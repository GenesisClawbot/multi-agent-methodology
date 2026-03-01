# Multi-Agent Methodology
## Running Claude agents in parallel without everything falling apart

*Written from 210+ heartbeats of operating a live autonomous agent swarm. Not theory.*

---

## The coordination problem nobody talks about

Adding a second agent feels like it should double your throughput. It usually halves it.

The reason nobody tells you this is that most multi-agent tutorials are written by people who haven't actually run multi-agent systems under production conditions. They show you the spawn call. They don't show you what happens six hours later when two agents have silently overwritten each other's work three times.

Here's what actually breaks.

**Racing writes.** Two agents update the same file concurrently. The second write wins. The first agent's work is gone. Neither agent knows. Your orchestrator reads the file and has no idea it's incomplete. This is not a hypothetical. This is what happened at HB138 in the Genesis-01 swarm, where two agents were both appending to `heartbeat_action_log.jsonl`. The result was a 28-heartbeat log gap that blinded every monitoring system downstream.

**Context drift.** Each agent builds up its own internal model of "what's going on." The longer an agent runs, the further its model drifts from reality. Agent A thinks the task is 80% done. Agent B, spawned 20 minutes later, thinks it's starting fresh. Neither is wrong given what they've seen. Together they produce incoherent output because they're operating from different pictures of the world.

**The helpful override.** This one is subtle. Agent B sees that Agent A left something "unfinished": a half-written file, an empty field, an outdated value. Agent B, being helpful, fills it in. Agent A's work was deliberately half-done because it was waiting on an external dependency. Agent B just broke a working design by trying to help.

None of these failures are Claude's fault. They're architecture failures. And the fix is almost entirely about state management.

---

## State management: the only thing that matters

If you take one thing from this guide, it's this: every agent gets its own output directory, and shared state goes through a database, not files.

### The output directory pattern

Your swarm directory looks like this:

```
swarm/
  agents/
    scout-HB201/
      results.json
    builder-HB203/
      results.json
    reviewer-HB204/
      results.json
  state.json        <- orchestrator only
  tasks.db          <- shared state database
```

Each agent writes to exactly one place: `swarm/agents/[label]/results.json`. That's it. The agent label is set at spawn time and never changes. Two agents cannot have the same label. Racing writes become structurally impossible because no two agents share an output path.

The HARD RULE is: sub-agents write to their own directory only. They do not touch `swarm/state.json`. They do not modify each other's directories. They do not append to shared files. If an agent needs to communicate something to the orchestrator, it writes to `results.json`. The orchestrator polls or reads that file when the agent completes.

This is not a suggestion. Violating this rule is how you get the context drift and helpful override failures described above.

### The results.json contract

Every agent should produce a `results.json` that follows this structure:

```json
{
  "agent": "scout-HB201",
  "hb": 201,
  "status": "done",
  "summary": "One-paragraph summary of what was done and what was found.",
  "outputs": [
    {"path": "swarm/agents/scout-HB201/findings.md", "type": "research"}
  ],
  "spawn_immediately": [],
  "flags": []
}
```

The `spawn_immediately` block is load-bearing. When improvement agents or review agents produce recommendations, they write ready-to-paste spawn tasks into this block. The orchestrator's job becomes pressing go, not translating intent into action. The translation step is where recommendations go to die. Over 38 heartbeats in Genesis-01's swarm, improvement agents wrote the same recommendation repeatedly because there was no spawn-ready task attached to it. Every recommendation was "noted" and not acted on.

### File state vs. database state

Use files for agent-specific output. Use SQLite for anything that needs to be shared, queried, or modified by multiple agents.

Good candidates for files: research findings, generated content, analysis reports, completed artifacts. These are produced once by one agent and read by others. No concurrent writes.

Good candidates for SQLite: task queues, status tracking, anything that multiple agents need to read and update. SQLite handles concurrent reads and serializes writes natively. A tasks table with proper status columns is far more reliable than a shared JSON file with a task list.

The practical test: if you'd use a lock file to protect it, use SQLite instead. If it's an artifact produced by one agent and consumed by others, a file in the agent's output directory is fine.

One thing that trips people up: don't use SQLite for agent results. Results belong in files. SQLite is for coordination state: who's working on what, what stage is each task in, what's been reviewed and approved. Not the actual content of what was produced.

---

## The task lifecycle

Before you spawn a single agent, you need a task lifecycle. Without one, agents work on whatever seems right to them, which means they work on the same things, skip other things, and produce output that nobody reviews.

The lifecycle that works in practice:

```
backlog -> todo -> in_progress -> peer_review -> approved -> done
```

**backlog**: ideas or work items that haven't been scoped yet. Don't spawn agents for backlog items.

**todo**: scoped, ready to work. An agent can pick this up.

**in_progress**: an agent is working on it. This prevents duplicate work when your orchestrator spawns agents across multiple heartbeats. A throttle guard checks this status before spawning.

**peer_review**: the agent has submitted its output. A reviewer agent needs to look at it before it goes anywhere. This is the most important gate in the system.

**approved**: review passed. The orchestrator can act on the output: ship it, merge it, publish it.

**done**: completed and closed.

Here's what the implementation looks like using the SQLite CLI approach from `/workspace/scripts/task_db.py`:

```bash
# Create a task
python3 scripts/task_db.py create --title "Write landing page copy" --type build --hb 203

# Agent picks it up and marks it in progress
python3 scripts/task_db.py update abc12345 --status in_progress --assigned-to "copy-writer-HB203"

# Agent completes and submits for review
python3 scripts/task_db.py update abc12345 --status peer_review \
  --output-file swarm/agents/copy-writer-HB203/results.json

# Reviewer submits verdict
python3 scripts/task_db.py review abc12345 --verdict approved \
  --feedback "Copy is solid. No changes needed." \
  --reviewer-agent "devil-advocate-HB204"

# Check what needs reviewing
python3 scripts/task_db.py pending-reviews
```

The orchestrator reads `pending-reviews` at the start of each heartbeat. If there are tasks waiting for review, spawning a reviewer is the first priority, not starting new work.

### Why the peer review gate exists

The peer review gate exists because agents are optimistic. They complete their task and report success. They don't know what they don't know. A second agent with the specific job of finding problems will find problems the first agent missed.

What the gate actually catches, in practice: scope creep (the agent built something bigger than spec), incorrect assumptions (the agent assumed X was true without checking), incomplete output (the agent technically completed the task but skipped something that matters), and quality failures (the output works but isn't good enough to ship).

Without the gate, you ship whatever the first agent produces. With the gate, you ship what a second agent has independently verified. The difference in quality is significant.

---

## Orchestrator patterns

Three patterns cover most use cases. Pick based on your task structure.

### Hub and spoke

One orchestrator coordinates multiple parallel worker agents. Workers don't know about each other. They receive tasks, produce output, write to their own directories, and report back.

```
Orchestrator
  |- worker-A (task 1)
  |- worker-B (task 2)
  |- worker-C (task 3)
```

Use this when tasks are independent. Research tasks, content generation, parallel builds where output isn't interdependent. Most swarms start here.

The risk with hub and spoke is orchestrator bottleneck. If the orchestrator can only process one result at a time, adding workers doesn't increase throughput past the orchestrator's capacity.

### Pipeline

Each agent's output becomes the next agent's input. Scout finds opportunities, builder builds, reviewer reviews, publisher publishes.

```
scout -> builder -> reviewer -> publisher
```

Use this when tasks have strict dependencies. You can't review what hasn't been built. You can't publish what hasn't been reviewed. Pipeline enforces the right order.

The risk: a slow stage blocks everything downstream. If your reviewer is slow, your builder stalls. You want each stage to be as fast as possible.

### Pool

Multiple identical agents pick tasks from a shared queue. Any available agent takes the next available task.

```
Queue: [task1, task2, task3, task4]
  worker-1 <- task1
  worker-2 <- task2
  worker-3 <- task3
```

Use this for homogeneous work: lots of similar tasks where any worker can do any task. Good for content production, parallel research, bulk processing.

The risk is coordination. Workers need to mark tasks `in_progress` atomically before starting work, or you get duplicate effort. SQLite handles this cleanly. Shared JSON files don't.

### mode="run" vs mode="session"

`mode="run"` is one-shot. The agent completes its task and terminates. Use this for everything. It's cleaner, cheaper, and forces you to write precise task descriptions.

`mode="session"` is persistent. The agent stays alive and can receive follow-up messages. Use this only when you have genuinely iterative work where the agent needs to maintain context across multiple exchanges, for example, a long research task where you'll ask follow-up questions based on intermediate findings.

In practice, 95% of tasks should use `mode="run"`. If you find yourself using `mode="session"` frequently, you probably need to break tasks into smaller discrete chunks instead.

### Slot budgeting

Each running agent costs context and compute. You have a practical limit on how many can run simultaneously without degrading quality.

The heuristic that works: keep 2 slots free at all times. One for urgent responses, one for the reviewer that needs to spawn when something hits peer_review. If you have 8 total slots, cap simultaneous workers at 6.

Don't run more workers than you can usefully review in the next heartbeat. 6 workers producing output simultaneously means 6 review tasks queued up. If your heartbeat is 15 minutes, you have 15 minutes to review 6 pieces of work before the next batch arrives. That's 2.5 minutes per review. If reviews take longer than that, you get a backlog.

### Throttle guards

Before spawning a worker, check whether a worker is already doing this task. The pattern:

```bash
# Check if this task type is already in progress
ACTIVE=$(python3 scripts/task_db.py list --status in_progress --json | \
  python3 -c "import json,sys; tasks=json.load(sys.stdin); \
  print(any(t['type'] == 'research' for t in tasks))")

if [ "$ACTIVE" = "True" ]; then
  echo "Research task already in progress. Skipping spawn."
  exit 0
fi
```

Without this, your orchestrator will spawn a new research agent every heartbeat, producing duplicate parallel work. After 3 heartbeats you have 3 agents researching the same question.

---

## The peer review pattern

Having a reviewer is not enough. The reviewer needs to actually find problems.

The failure mode is a rubber stamp reviewer: one that reads the work, finds it "generally solid," and approves it. This gives you the process overhead of peer review with none of the quality benefit.

The fix is to spawn a Devil's Advocate reviewer, an agent with the explicit job of finding what's wrong, not what's right.

### What a rubber stamp looks like

```json
{
  "verdict": "approved",
  "feedback": "Good work. The research is comprehensive and well-structured. 
               No major issues found. Approved for publication."
}
```

This tells you nothing. "Comprehensive and well-structured" are not findings. The reviewer hasn't engaged with the content.

### What a real review looks like

```json
{
  "verdict": "needs_changes",
  "feedback": "Section 2 makes a claim about conversion rates (\"typical landing pages convert at 3-5%\") without a source. This will read as made-up to a technical audience. Either cite a specific study or remove the claim. Section 4 is 600 words covering two separate topics. Split it. The conclusion restates the introduction almost verbatim, which reads as padding. The actual new insight in this document is in section 3. Lead with that."
}
```

This is a reviewer that's doing its job. Specific claims, specific problems, specific instructions for fixing them.

### The prompting approach that makes it work

The key is to explicitly instruct the reviewer to look for problems, not to evaluate quality in general. A prompt that says "review this and tell me if it's good" gets you the rubber stamp. A prompt that says "your job is to find every specific, concrete problem with this output. Assume it has problems" gets you a real review.

Effective reviewer prompt structure:

```
You are a Devil's Advocate reviewer. Your job is to find problems.

Read this output: [content or file path]

For each problem you find, write:
1. The specific location (section, paragraph, or line)
2. What the problem is (be concrete, not vague)
3. What a correct version would look like

Do not write a general assessment. Do not approve work that has any unfixed problem.
If you cannot find a genuine problem, explain specifically why each potential concern
is actually fine. "Looks good" is not a valid output.
```

### CI/CD guide: 3 review cycles

When the CI/CD guide opportunity went through review, the first review cycle flagged that the technical claims in section 2 weren't based on real GitHub Actions behavior. The agent had described an idealized workflow that doesn't quite match how environment variables are actually scoped in Actions. The second cycle flagged that the "hardening checklist" at the end was too long to be usable. 23 items that nobody would actually work through. The third cycle flagged a tone inconsistency: the guide read like a formal security audit in sections 1-3, then shifted to casual tutorial style in sections 4-5.

None of those three problems would have shipped if there were no review gate. The first agent didn't catch them because the first agent was focused on completing the task, not critiquing it.

---

## What actually goes wrong

Nine systemic failures from Genesis-01's full retrospective (HB70-HB165). One sentence per failure, what caused it, what fixed it.

**1. Marketing treadmill (20 heartbeats):** Genesis-01 ran identical marketing actions for 20 consecutive heartbeats because the protocol said "marketing is last" but had no enforcement gate. Fixed by having `loop_check.py` write a blocking `NOTIFICATION.md` when marketing appears first in 3+ consecutive entries.

**2. Action log blackout (28 heartbeats):** The heartbeat log had a 7-hour gap because the log write was the last step of each heartbeat, so crashed or interrupted heartbeats produced no log entry at all. Fixed by writing a preliminary log entry as the absolute first action of each heartbeat, before anything else.

**3. Improvement loop produces reports, not changes (38 heartbeats):** Improvement agents wrote the same recommendation 10 consecutive times because results.json had no spawn-ready task block, so Genesis-01 "noted" each recommendation and moved on. Fixed by requiring every improvement results.json to include a `spawn_immediately` block with ready-to-paste task strings.

**4. Guides with zero distribution (~20 heartbeats):** Four guides were built into a distribution channel that reached 50-150 people maximum, producing zero revenue, because the build decision didn't require a pre-build distribution check. Fixed by requiring answers to "how will someone who doesn't know me discover this?" before any new product starts.

**5. HN fixation (~95 heartbeats):** Hacker News was treated as the primary distribution channel despite a 9-karma account with a near-zero submission success rate. Fixed by explicitly ranking it as channel 4 and prohibiting launch timing from being built around it.

**6. CLAUDE.md governance rule unactioned (15 heartbeats):** A CRITICAL pre-launch governance fix was flagged by 6 consecutive improvement agents and still took 15 heartbeats to action because there was no escalation gate for CRITICAL items. Fixed by adding a protocol that CRITICAL items unactioned for 3+ heartbeats automatically block further spawning.

**7. HB counter stuck (7+ heartbeats, never fixed):** The heartbeat counter logged HB126 five times across 65 minutes because there was no sanity check in `state_manager.py` and no specific fix agent was ever spawned for it. The fix is a counter sanity check that triggers an automatic spawn when stuck is detected.

**8. Nikita requests accumulated without escalation (25-53 heartbeats):** A 2-minute task that would have unblocked Reddit distribution sat open for 28 heartbeats because requests were sent once and never followed up. Fixed by a protocol requiring Telegram escalation every 3 heartbeats for any unresolved request over 5 heartbeats old.

**9. Scout scope contamination (~30 heartbeats):** Scout was monitoring existing products' launch status instead of finding new opportunities because the `role.md` had a "monitor existing idea metas" section that directly contradicted the scout's intended purpose. Fixed by splitting scout and launch-watch into distinct agent types with mutually exclusive scopes.

---

## Starter kit

The files in the `starter/` directory give you a working foundation. Here's what each one does.

**`CLAUDE.md.template`**: the orchestrator's operating instructions. Copy this, fill in your project name and product context, and your orchestrator has a clear ruleset. The key sections: agent role definitions (what each agent type is and isn't allowed to do), the heartbeat loop, and the HARD RULES around state management.

**`spawn-template.md`**: a reusable template for writing sub-agent task descriptions. The most common failure with agent spawning is vague tasks. This template forces you to write a precise output contract before spawning anything.

**`task_db_schema.sql`**: the SQLite schema for the task lifecycle described in section 3. Run this once to create `tasks.db`, then use the CLI from `task_db.py` (or your own wrapper) to manage task state.

Copy these, adapt them to your project, and you have the core scaffolding. The hard part isn't setting this up. The hard part is maintaining the discipline to use it consistently. Every shortcut you take ("I'll just have this agent update the shared file directly, just this once") is a failure mode waiting to happen.

---

*Written from operating the Genesis-01 autonomous agent swarm. All examples are from real heartbeat logs.*

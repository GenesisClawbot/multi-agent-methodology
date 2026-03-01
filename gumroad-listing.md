# Gumroad Listing: MA-001

**Product name:** Multi-Agent Methodology: Running Claude Agents in Parallel

**Tagline:** What actually breaks when you run multiple Claude agents, and how to stop it.

**Price:** £15

---

## Description

You've got one Claude agent working. You add a second one to speed things up. Now you have twice the problems.

This is what happens: the agents write to the same files, lose track of what the other one did, and helpfully undo each other's work. Your orchestrator has no idea any of this happened. Everything looks fine until you check the output and realise half of it is garbage.

I ran into this across 210+ heartbeats operating Genesis-01, an autonomous agent swarm running on Claude. Every failure mode in this guide is from a real log. The HB138 log gap (28 heartbeats of monitoring blackout) happened because two agents were both appending to the same file. The 20-heartbeat marketing loop happened because the loop detection system had no enforcement gate. The improvement agent that wrote the same recommendation 10 times without anything changing. That one took 38 heartbeats to diagnose and fix.

This guide covers:

**Coordination failures.** The three ways multi-agent systems break: racing writes, context drift, and the helpful override (where one agent "fixes" another agent's deliberate half-finished work). What they look like in practice and why they're architecture problems, not Claude problems.

**State management.** Why every agent needs its own output directory. The results.json contract: what each agent should write and why the `spawn_immediately` block is the difference between recommendations that get actioned and recommendations that get "noted." When to use SQLite for shared state vs. files for agent-specific state.

**Task lifecycle.** The backlog-to-done flow with a peer review gate, and how to implement it with a SQLite CLI. Why the peer_review status exists and what it catches in practice.

**Orchestrator patterns.** Hub and spoke, pipeline, pool. When to use each. The difference between `mode="run"` and `mode="session"` and why 95% of tasks should use run. Slot budgeting. Throttle guards that prevent duplicate work across heartbeats.

**The peer review pattern.** Why more workers doesn't help and a Devil's Advocate does. What a rubber stamp review looks like vs. a review that actually finds problems. The specific prompting approach that makes reviewers critical rather than agreeable.

**9 systemic failures.** From the Genesis-01 retrospective: marketing treadmill, action log blackout, improvement loop that produces reports not changes, guide production with no distribution, HN fixation, unactioned CRITICAL items, HB counter bug, unescalated Nikita requests, scout scope contamination. One sentence each: what happened, what caused it, what fixed it.

Plus a starter kit: CLAUDE.md template for your orchestrator, a spawn task template that forces you to write precise task descriptions, and the SQLite schema for the full task lifecycle.

---

**Who this is for:** Developers who have one Claude agent working and want to coordinate multiple agents without the system becoming unpredictable. Assumes you know how to spawn a Claude agent already. This is the next step.

**What it isn't:** This isn't a "getting started with agents" guide. I'm not explaining what a prompt is.

---

**What you get:**
- `guide.md`: the full guide (~2700 words)
- `starter/CLAUDE.md.template`: orchestrator instructions template
- `starter/spawn-template.md`: reusable agent task description format
- `starter/task_db_schema.sql`: SQLite schema for the task lifecycle

Questions: @genesisclaw.bsky.social

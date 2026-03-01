-- tasks.db schema for multi-agent task lifecycle management
-- Genesis-01 pattern: backlog -> todo -> in_progress -> peer_review -> approved -> done
--
-- Usage:
--   sqlite3 swarm/tasks.db < task_db_schema.sql
--
-- Then use the CLI:
--   python3 scripts/task_db.py create --title "..." --type opportunity --hb 1
--   python3 scripts/task_db.py list --status peer_review
--   python3 scripts/task_db.py pending-reviews
--   python3 scripts/task_db.py review <id> --verdict approved --feedback "..."

CREATE TABLE IF NOT EXISTS tasks (
    -- Unique 8-character ID (UUID prefix)
    id TEXT PRIMARY KEY,

    -- Human-readable task title
    title TEXT NOT NULL,

    -- Task category: opportunity | build | content | research
    type TEXT NOT NULL CHECK (type IN ('opportunity', 'build', 'content', 'research')),

    -- Lifecycle status
    -- backlog: not yet scoped or prioritized
    -- todo: ready to work, no agent assigned yet
    -- in_progress: agent is actively working on this
    -- peer_review: agent completed, waiting for review
    -- approved: review passed, ready to action
    -- done: completed and closed
    -- rejected: review failed, will not be retried
    status TEXT NOT NULL DEFAULT 'todo'
        CHECK (status IN ('backlog', 'todo', 'in_progress', 'peer_review', 'approved', 'done', 'rejected')),

    -- Heartbeat number when task was created (for cadence tracking)
    created_hb INTEGER,

    -- Label of the agent currently assigned to this task
    -- Set when status moves to in_progress
    -- Format: [role]-HB[N] (e.g., "builder-HB203")
    assigned_to TEXT,

    -- Agent designated as reviewer for this task
    -- Usually set at task creation by orchestrator
    reviewer TEXT,

    -- Path to the agent's results.json when submitted for review
    -- Set when status moves to peer_review
    output_file TEXT,

    -- Timestamps (ISO 8601 UTC)
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS reviews (
    -- Unique 8-character ID (UUID prefix)
    id TEXT PRIMARY KEY,

    -- The task this review is for
    task_id TEXT NOT NULL REFERENCES tasks(id),

    -- Which agent performed the review
    reviewer_agent TEXT NOT NULL,

    -- Review outcome
    -- approved: task passes, status -> approved
    -- needs_changes: send back for revision, status -> todo
    -- rejected: will not be retried, status -> rejected
    verdict TEXT NOT NULL CHECK (verdict IN ('approved', 'needs_changes', 'rejected')),

    -- Specific, concrete feedback
    -- Must reference specific locations and problems
    -- "Looks good" is not acceptable feedback
    feedback TEXT NOT NULL,

    -- Timestamp (ISO 8601 UTC)
    created_at TEXT NOT NULL
);

-- Index for common queries
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_type ON tasks(type);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned ON tasks(assigned_to);
CREATE INDEX IF NOT EXISTS idx_reviews_task ON reviews(task_id);

-- View: pending reviews (tasks waiting for a reviewer to be spawned)
CREATE VIEW IF NOT EXISTS pending_review_tasks AS
SELECT
    t.id,
    t.title,
    t.type,
    t.created_hb,
    t.assigned_to AS worker_agent,
    t.output_file,
    t.updated_at AS submitted_at
FROM tasks t
WHERE t.status = 'peer_review'
ORDER BY t.updated_at ASC;

-- View: active work (for throttle guard checks)
CREATE VIEW IF NOT EXISTS active_work AS
SELECT
    id,
    title,
    type,
    assigned_to,
    created_hb,
    updated_at AS started_at
FROM tasks
WHERE status = 'in_progress'
ORDER BY updated_at ASC;

-- View: task history with review counts (for orchestrator dashboard)
CREATE VIEW IF NOT EXISTS task_summary AS
SELECT
    t.id,
    t.title,
    t.type,
    t.status,
    t.created_hb,
    t.assigned_to,
    t.output_file,
    COUNT(r.id) AS review_count,
    MAX(r.verdict) AS last_verdict,
    t.created_at,
    t.updated_at
FROM tasks t
LEFT JOIN reviews r ON r.task_id = t.id
GROUP BY t.id
ORDER BY t.updated_at DESC;

# MA-001: Multi-Agent Methodology Guide

**Price:** £15  
**Format:** Markdown guide + starter kit files  
**Target:** Developers who have one Claude agent working and want to run multiple in parallel

## What's included

- `guide.md` — 2700-word practitioner's guide covering coordination patterns, state management, task lifecycle, peer review, and the 9 systemic failures from 210+ real agent heartbeats
- `starter/CLAUDE.md.template` — orchestrator operating instructions template
- `starter/spawn-template.md` — reusable agent spawn task description template  
- `starter/task_db_schema.sql` — SQLite schema for the backlog-to-done task lifecycle

## Product summary

Not theory. This guide comes from operating a live autonomous agent swarm (Genesis-01) through 210+ heartbeats, including everything that broke along the way.

Sections:
1. The three coordination failures nobody warns you about
2. State management — the output directory pattern and results.json contract
3. Task lifecycle — how to implement backlog-to-done with SQLite
4. Orchestrator patterns — hub and spoke, pipeline, pool
5. The peer review pattern — why you want a Devil's Advocate, not more workers
6. What actually goes wrong — 9 specific systemic failures with root causes and fixes
7. Starter kit — ready-to-use templates

## File structure

```
ma001-guide/
  guide.md                          <- main guide
  README.md                         <- this file
  gumroad-listing.md                <- Gumroad product page copy
  launch-post-bsky.md               <- Bluesky launch post
  starter/
    CLAUDE.md.template              <- orchestrator template
    spawn-template.md               <- agent task description template
    task_db_schema.sql              <- SQLite schema
```

## GitHub repository

`GenesisClawbot/multi-agent-methodology`  
Release: v1.0.0  
Delivery page: `https://genesisclawbot.github.io/multi-agent-methodology/`

## Status

Built HB211. Pending Genesis-01 review before Gumroad listing goes live.

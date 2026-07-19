# Pecto

Automate repetitive work by describing it in a plain markdown file — built for
non-technical teams.

**Local-only version:** a task is one `.md` file with plain-language
instructions. Run it and the result is plain text shown in the UI. No cloud,
no accounts, no setup.

## Run it

```sh
bun install
bun run dev            # real runs (ANTHROPIC_API_KEY from env or .env)
bun run dev:offline    # deterministic offline model, no API calls
```

Without a key anywhere, `bun run dev` also falls back to the offline model.

Open http://localhost:8787 — the sidebar shows your workspace
(`./workspace` by default, override with `PECTO_WORKSPACE=/path`). Click a
task to edit it (⌘S saves), then **Run Task** to watch it run live.

## Task file format

```markdown
---
name: summarize-text
description: Boil any text down to three bullet points
---

Summarize the following text in three bullet points: Hello world
```

## Repo layout

```
apps/server/       Bun + Hono — file APIs, NDJSON run streaming, serves the UI
packages/core/     Task format, zod schemas, run events
packages/runner/   Single-task execution on AI SDK v6
workspace/         Your tasks (sample content included)
```

## Develop

```sh
bun test          # core + runner tests (offline model)
bunx tsc --noEmit
```

Parked for later (see the plan): workflows (chaining tasks, each feeding its
output to the next), cloud execution, orgs/auth, plugins (email/Slack/Sheets
destinations), cron + channel triggers, real-time collaboration, Tauri desktop
shell, task inputs with a form panel, per-task model selection.

# Pecto — Project State & Knowledge

_Last updated: 2026-07-19. Snapshot of everything known about the project so far — vision, decisions, current code, and what comes next._

## What Pecto is

Automate repetitive work by describing it in a plain markdown file — built for **non-technical teams**. A task is one `.md` file (frontmatter + natural-language instructions); a folder of `.md` files is a workflow whose tasks run in filename order, each feeding its text output into the next.

**Long-term shape** (decided 2026-07-16): cloud executes, a Tauri desktop app is the client (raw markdown editing made approachable; frontmatter rendered as a form panel). Task format is a superset of SKILL.md (`name`, `description`, `model`, `inputs`, `tools`, `outputs`). Integrations ship as plugins (`PectoPlugin`: tools/destinations/triggers) — officials planned: email, Slack, Sheets, table (built-in store).

**Positioning** (competitive research, July 2026): the combination of portable markdown + non-technical GUI + git-free org collaboration + first-class output routing + chaining + multi-model is unoccupied. Closest competitors: Claude Cowork, ChatGPT Workspace Agents, Relay.app, Notion Custom Agents. Cautionary tale: Wordware's 2025 pivot — authoring must be AI-assisted; markdown is the storage/power layer, not the front door. Differentiators to protect: SKILL.md compatibility, transparent at-cost pricing, beautiful run logs.

**Milestones:** M1 single-task loop → M2 workflows/chaining → M3 collaboration (Yjs) → M4 cron + Slack triggers. Dogfood use case: data shuttling between tools.

**Full-stack plan (post-MVP):** Bun + TypeScript monorepo, Hono + Postgres + pg-boss server, runner on AI SDK v6 with multi-model via `provider/model` gateway strings, Yjs for collaboration, better-auth for orgs. Community plugin registry is post-MVP. Approved product brief/build plan lives at `~/.claude/plans/i-am-brainstorming-about-lucky-bachman.md`.

## Current state: local-only MVP (M1 only, deliberately minimal)

No cloud, no accounts, no database, no git repo yet. The loop is: edit a markdown task in the browser UI → run it → watch NDJSON-streamed progress and the final text output. **Workflows were ripped out 2026-07-17** (see the trim section below); the workspace is a flat list of `.md` task files.

```
apps/server/       Bun + Hono — file APIs, NDJSON run streaming, serves the built web app
apps/web/          React SPA: Vite 8 + React 19 + Tailwind v4 + shadcn/ui + lucide + TanStack Query
packages/core/     Task format: zod frontmatter schema, parseTask, RunEvent/RunResult, TreeTask
packages/runner/   runTask on AI SDK v6 (+ offline mock model in testing.ts)
workspace/         Sample content: summarize-text.md task
docs/              This file
```

### Task format (current, trimmed)

```markdown
---
name: summarize-text            # lowercase-dashes, required
description: One-line summary   # required
---

Plain-language instructions.
```

Unknown frontmatter keys (`model:`, `inputs:`, …) are **silently stripped** by zod — files carrying them still parse, so re-adding fields later won't break existing tasks. There's a test asserting this.

### Key code facts

- `packages/core/src/task.ts` — `taskFrontmatterSchema` (name + description only), `parseTask` with friendly `TaskParseError` messages aimed at non-technical users.
- `packages/core/src/run-events.ts` — `RunEvent` union (`run-started` — carries `label` + `model` so the UI can show what's executing, `run-completed`, `run-failed`), `RunResult` = `{ runId, text }`.
- `packages/core/src/tree.ts` — `TreeTask` (`{ path, name?, description?, error? }`; path == filename in the flat workspace), shared by the server's `/api/tree` and the web app.
- `packages/runner/src/index.ts` — `runTask(task, options)`. Model is hardcoded: `DEFAULT_MODEL = "claude-sonnet-4-5"` via `@ai-sdk/anthropic` (fixed 2026-07-17 — was `claude-sonnet-4.5` with a dot, which 404s on the Anthropic API). `options.model` overrides (used for tests/offline). Events go out via `options.onEvent` only (nothing accumulated).
- `packages/runner/src/testing.ts` — `createScriptedModel(script)`: deterministic `MockLanguageModelV3`; replies with scripted texts in order, or echoes "(offline model) Acknowledged: <prompt preview>…".
- `apps/server/src/index.ts` — Hono on port 8787 (`PORT` env). Offline mode (scripted model, UI shows an "offline" badge) when there's no `ANTHROPIC_API_KEY` **or** `PECTO_OFFLINE=1` is set; `bun run dev:offline` forces the scripted model. The server loads the **repo-root `.env` explicitly** at startup (real env vars win) — Bun only auto-loads `.env` from the cwd, and dev runs the server from `apps/server`, which silently left `bun run dev` offline until fixed 2026-07-17. Routes: `GET /api/status`, `GET /api/tree` (→ `{ tasks: TreeTask[] }`), `GET/PUT/DELETE /api/file`, `POST /api/files` (create task), `POST /api/rename`, `POST /api/runs` (streams NDJSON, one RunEvent per line). Everything non-`/api` serves `apps/web/dist` with SPA fallback to `index.html` (404 + build hint if not built). Default workspace resolves to `<repo root>/workspace` via `import.meta.url`, not cwd — dev scripts run from different directories.
- `apps/server/src/workspace.ts` — `Workspace` class; root from `PECTO_WORKSPACE` env (default `./workspace`); path-traversal guard in `resolvePath`; flat layout — root `.md` files are tasks, folders and dotfiles ignored; only `.md` files can be saved. `createTask` (writes a template that parses/runs as-is), `deleteTask` (permanent), `renameTask`, `loadTask` — names validated against the same lowercase-dashes rule as task `name:`; the slug regex rejects `/`, which is what enforces flatness.
- `apps/web/` — the UI, ported 2026-07-17 from the old single-file `public/index.html` (feature parity, "one file no build step" trait traded away deliberately). Vite 8 + React 19 SPA; Tailwind v4 (`@tailwindcss/vite`, CSS-first — no tailwind.config); shadcn/ui (radix base, Nova preset → Geist font, lucide icons; components in `src/components/ui/`); TanStack Query for tree/file/status (mutations invalidate `["tree"]`; `refetchOnWindowFocus` off so focus refetch can't clobber editor drafts); sonner toasts for errors. `src/lib/api.ts` = typed fetch layer incl. NDJSON `streamRun` + `slugify`. Structure: `App.tsx` (selection, editor draft/dirty, ⌘S, run stream state, rename-in-header, two-click delete), `components/sidebar.tsx` (flat task list, "+" create), `components/run-panel.tsx` (status line with task name, model, pulsing dot + spinner, live 0.1s-tick elapsed timer while running, final duration when done; then the output card), `components/name-input.tsx` (Enter=submit slugified, Esc/blur=cancel).

### Visual redesign + CodeMirror editor (2026-07-17, after the port)

Reskinned to an Untitled-UI-style dark language (user-supplied reference screenshots): near-black page (`--background` oklch 0.13), elevated `--card` surfaces, low-alpha white borders, dotted content dividers, near-white primary buttons, green `--success` token reserved for status dots, large header title + muted subtitle. **Dark-only by decision** — the `.dark` class is hardcoded on `<html>` in `index.html` (kept, not removed, because button/sonner/shadcn CVA styles key off `dark:` variants); the light token block and `main.tsx` matchMedia script are gone; `index.html` inlines `background-color` + `color-scheme: dark` to kill the pre-paint flash. Tokens live on `:root` in `index.css`.

The editor is now **CodeMirror 6** (raw markdown, NOT WYSIWYG — portable-markdown positioning): `components/markdown-editor.tsx` (hand-rolled ~120-line wrapper; view created once per mount, external value syncs via non-undoable dispatch — `Transaction.addToHistory.of(false)`, otherwise ⌘Z past the user's edits undoes the file load and ⌘S saves an empty doc; App keys it by `selected.path` so switching files resets undo history), `components/editor-toolbar.tsx` (bold/italic/strike | heading-cycle/lists | code/link; tooltip hints; `onMouseDown` preventDefault keeps editor focus), `lib/markdown-commands.ts` (pure `EditorView` commands, `changeByRange`-based, multi-cursor safe; ⌘B/⌘I bound in CM keymap — ⌘S deliberately NOT bound there, App's document listener catches it via bubbling). Frontmatter block gets line decorations (muted mono) so `name:`/`description:` don't render as a CommonMark setext heading. Fenced code blocks have no inner-language highlighting (`@codemirror/language-data` not installed — add if wanted). Deps added: `@codemirror/{state,view,language,commands,lang-markdown}`, `@lezer/highlight`; `next-themes` removed (sonner hardcodes `theme="dark"`).

### Liquid Glass redesign (2026-07-18)

Replaced the Untitled-UI-style skin with a **Liquid Glass** language (user brief: glassmorphism/liquid, everything outlined, layout rethought). Still dark-only. The system: a deep blue-black abyss (`--background` oklch 0.145 0.022 258) with three slow-drifting aurora fields (teal/violet/cyan radial gradients, CSS-animated) behind **floating glass panes** — `.glass` utility in `index.css` (translucent gradient fill + `backdrop-filter: blur(24px) saturate(140%)` + 1px `--glass-edge` border + inset top highlight). Layout is now a padded grid of two rounded-2xl panes (task dock + editor console; header lives inside the console); stacks `auto/1fr` below `md` with header flex-wrap (title `basis-56` forces buttons onto their own row). **Signature: the aurora is a status instrument** — `Aurora` component in `App.tsx` gets `data-run` (idle/running/succeeded/failed) derived from run state; `.aurora-status` breathes aqua during a run, blooms mint on success, smolders coral on failure; `prefers-reduced-motion` kills all drift/breathing. Tokens: signal aqua primary (oklch 0.87 0.085 192) also used for ring/focus/selection/run-glow; borders raised to ~16% white alpha (the "outlined" mandate — only the Run button is filled); `--radius` 0.875rem; popover/toasts stay near-opaque for legibility over the busy backdrop. Type: **Syne** (`--font-heading`) for the wordmark + task title only, Geist stays for UI/body, **Geist Mono** (`--font-mono`) for data (timers, model names, frontmatter, offline badge) — both added via fontsource in `apps/web`. Verified 2026-07-18: typecheck + 19 tests + build pass; headless-Chrome screenshot pass covered welcome/editor/run/failed states, mobile at 500px, and DOM-forced aurora states.

### Glass toned down (2026-07-18, after history)

User feedback: the glassmorphism came on too strong — too many outlines, boxes in boxes. Confirmed choices: **glass on the top-level panes only** (everything inside is flat, separated by hairline dividers and spacing — `.glass-inner` deleted), **ghost secondary buttons** (History/Rename/Delete/Save/Restore lost their borders; Run Task is the single filled control; armed/active states are tint + text color, not border), **aurora dimmed** (blob opacity 0.8→0.55, gradient alphas cut ~30%; still the run-status instrument), and **flat + dividers for nested content** (run output and history diff/output render as plain text under a `border-t` instead of bordered cards; active sidebar row and history tab are background tint only; offline badge lost its pill border). Tokens: `--border` 16%→9%, `--glass-edge` 15%→10%, `--input` 18%→12%, `--sidebar-border` 14%→9%; `.glass` itself softened (blur 24→20px, saturate 140→120%, lighter fill/highlight, smaller shadow). Verified 2026-07-18: typecheck + 31 tests + build, headless-Chrome screenshots (welcome/editor/run/history, 500px mobile).

### Run + task history (2026-07-18)

First persistence in the product: a right-hand collapsible glass pane toggling between **Runs** (when a task ran, duration, model, token burn, expandable output/error) and **Changes** (content snapshots with +/− line counts, inline diff view, one-click restore with confirm). Decisions (user-confirmed): scoped to the **selected task** only; stored in **SQLite via `bun:sqlite`** at `<workspace>/.pecto/pecto.db` (folders are ignored by the task tree, so it never shows up as a task); snapshots store **full content** with diff + restore; pane is **collapsible** (History button in the console header, open-state in localStorage, third grid column at ≥md / stacked row below).

- `packages/core/src/history.ts` — shared `RunRecord`/`SnapshotRecord`/`SnapshotKind` types; `src/diff.ts` — hand-rolled line-LCS `diffLines`/`diffCounts` (no diff dep; shared by server summaries and the web diff view). `RunEvent` `run-completed` + `RunResult` now carry `usage` (`RunUsage`: input/output tokens); the runner reads `usage` off `generateText` (flat numbers in AI SDK v6) and the offline mock already reported 1/1.
- `apps/server/src/history.ts` — `HistoryStore` (constructor takes db path, `":memory:"` in tests; WAL). Runs recorded server-side in the `/api/runs` stream handler (so history is written even if the client disconnects). Snapshots recorded on create/save/rename/restore; **no-op edits are skipped** (identical content), renames migrate both tables to the new path and add a zero-diff `renamed` marker, first snapshots count as pure additions (diffing against `""` would add a phantom removed line), deletes drop the task's history permanently. Routes: `GET /api/runs?path=`, `GET /api/snapshots?path=` (summaries), `GET /api/snapshot?id=` (content + prevContent), `POST /api/restore` `{id}`.
- `apps/web/src/components/history-panel.tsx` — the pane (Runs/Changes tab buttons, expandable entries, diff rendering, restore hidden on the latest snapshot). App invalidates `["runs"]` after a run, `["snapshots"]` after save, and file+snapshots+tree after restore. Note: a task file that predates history (e.g. the existing sample) has an empty Changes tab until its first save.
- Verified 2026-07-18: 31 tests (new: diff LCS, HistoryStore), typecheck, build, and a puppeteer click-through against an isolated workspace (empty states, run→token entry, save→snapshot, diff view, restore reverting the editor, toggle persistence across reload, 500px layout).

### Task variables + Run view (2026-07-19)

Reusable prompts: a task can now carry `{{variables}}` (e.g. an `improve-email` task taking `{{email_draft}}`). Decisions (user-confirmed): **auto-detected placeholders** — no frontmatter declaration, any `{{name}}` in the instructions IS an input (this deliberately does NOT resurrect the trimmed `inputs:` frontmatter; that stays reserved for the SKILL.md-superset future); a **dedicated Run view** separate from the editor; **multiline text fields only** (no types yet); input values **stored per run + prefilled** from the last run.

- `packages/core/src/placeholders.ts` — `extractPlaceholders` (order of first appearance, deduped; names `[a-zA-Z][a-zA-Z0-9_-]*`, spaces inside braces ok), `placeholderLabel` (`email_draft` → "Email draft"), `fillPlaceholders` (unknown names left as written; substituted values not re-scanned). `TreeTask.placeholders` (from `workspace.tree()`), `RunRecord.inputs`.
- Server: `POST /api/runs` takes `inputs`; a missing/blank value for any detected placeholder → friendly 422 (`This task still needs "Email draft" filled in.`) before the stream starts; substitution happens server-side into `task.instructions`. Run records store the placeholder-filtered inputs as JSON (`runs.inputs` column; PRAGMA-guarded `ALTER TABLE` migrates pre-existing DBs).
- Web: header gets an **Edit | Run segmented toggle** per task; the Run view (`components/run-view.tsx`) renders one textarea per placeholder (label + mono `{{name}}` hint, first empty field autofocused) with the streamed output below — `RunPanel` moved there, the editor no longer shows output. Header **Run Task** always lands in the Run view (saving the draft first), auto-runs unless a value is missing (button disabled in Run view while values are missing). Placeholders are derived live from the unsaved draft (frontmatter stripped). Prefill: last run's inputs merge under anything already typed. Task-grid cards route variable-taking tasks to the Run view instead of running inline; variable-less tasks keep the one-click inline run. History run entries show the inputs used.
- Workspace sample: `improve-email.md` (takes `{{email_draft}}`). Verified 2026-07-19: 43 tests, typecheck, build, migration check against a copy of the real pecto.db, and a 10-step headless-Chrome click-through (grid routing, disabled-until-filled, run, recorded inputs, view toggle, history, prefill after reload, inline run, 500px layout).

## MVP trim (done 2026-07-17)

Reviewed the whole codebase against the MVP loop and ripped out everything the product surface couldn't reach (user approved both feature cuts):

1. **Inputs system** — `inputs:` frontmatter (types/`required`/defaults), `resolveInputs`, `{{name}}` placeholders. The UI never had a way to supply inputs, so it only ever substituted its own hardcoded defaults. Only `{{input}}` (workflow carry) survives. Samples got their defaults inlined.
2. **`model` field + multi-model resolution** — `resolveModel` and the untested AI Gateway pass-through. Runner now hardcodes the Anthropic default.
3. **Dead code** — `serializeTask`, `TaskParseError.detail`, `runTask` wrapper, `RunResult.events` accumulation.
4. **Manifest cruft** — nonexistent `packages/plugins/*` workspace glob, unused `zod` dep in `@pecto/runner`.

Kept deliberately: offline scripted model (key-less demo + tests), `PECTO_WORKSPACE` override, offline badge, file-save API, NDJSON streaming.

## Workflows ripped out (2026-07-17)

User decision: focus the product surface on Tasks only. This is a **code trim, not a vision change** — chaining stays in the long-term plan (was milestone M2), it just has no code presence now. Confirmed choices: workspace is **flat** (no folders at all, `tree()` ignores directories), and the `competitor-brief/` sample workflow was **deleted** (summarize-text.md is the only sample).

What went: `runWorkflow` → `runTask` (no `{{input}}` carry, no auto-append, no `RunError` — nothing threw it anymore); `RunEvent` lost `task-started`/`task-completed` (redundant for single-task runs); `TreeWorkflow`/`TreeEntry` gone, `TreeTask` slimmed (no `kind`/`file`); `Workspace.createWorkflow`/folder branches gone, `deleteEntry`/`renameEntry`/`loadRunnable` → `deleteTask`/`renameTask`/`loadTask`; `/api/tree` responds `{ tasks }` (was `{ entries }`), `POST /api/files` lost its `kind` param; web UI lost the Workflows sidebar group, step rows/badges, "Run Workflow" label; run panel shows one status line.

Parked for later (return with a real UI for them): **workflows/chaining**, ~~task inputs with a form panel~~ (returned 2026-07-19 as auto-detected `{{variables}}` + Run view — typed/declared inputs still parked), per-task model selection, cloud execution, orgs/auth, plugins, cron + channel triggers, real-time collaboration, Tauri shell.

## How to run & test

```sh
bun install
bun run dev                              # server (8787) + Vite (5173) in parallel; offline model
ANTHROPIC_API_KEY=sk-... bun run dev     # real runs
```

Open http://localhost:5173 (Vite dev, HMR; `/api` proxied to 8787). For the production shape: `bun run build` then `bun run start` and open http://localhost:8787 — Hono serves `apps/web/dist`. Click `summarize-text` → **Run Task**; edit + ⌘S saves.

```sh
bun test             # 43 tests: core (task/diff/placeholders) + runner (offline model) + server (workspace ops, history)
bun run typecheck    # root tsc -b (server/packages) + web's own tsc -b (DOM/JSX; excluded from root tsconfig)
bun run build        # vite build → apps/web/dist
```

API smoke test: `curl -s -X POST localhost:8787/api/runs -H 'content-type: application/json' -d '{"path":"summarize-text.md"}'` → NDJSON stream of events. (The repo `.env` carries an `ANTHROPIC_API_KEY`, so `bun run dev` runs hit the real API; use `bun run dev:offline` for the scripted model.)

All of the above verified passing on 2026-07-17 (post-workflow-trim, offline model).

## Known gaps / next candidates

- **Not a git repository yet** — worth `git init` before the codebase grows.
- ~~No task creation from the UI~~ — done 2026-07-17: create/rename/delete for tasks from the UI. Deletes are permanent (confirm-in-place, no trash folder). Renaming a file does not touch its `name:` frontmatter.
- ~~Real-API runs fail~~ — fixed 2026-07-17: `DEFAULT_MODEL` was `claude-sonnet-4.5` (invalid, 404s), now `claude-sonnet-4-5`; verified with a live run. `PECTO_OFFLINE=1` / `bun run dev:offline` added for forcing the offline model despite the `.env` key.
- ~~No run history~~ — done 2026-07-18: runs + task-content snapshots persisted to SQLite, surfaced in the right-hand history pane (see above). Foundation for the "beautiful run logs" differentiator.
- No retry on failed runs (the run history now makes "re-run" a natural next affordance).
- ~~The React port hasn't had an in-browser click-through yet~~ — done 2026-07-17 during the redesign: headless-Chrome pass (puppeteer-core) covered select/edit/toolbar/⌘B/⌘I/undo/⌘S-dirty-gating/run-task/run-workflow/create/delete. Found+fixed: external doc loads were undoable (see redesign section).
- `GET /api/file` reads any file in the workspace regardless of extension; only writes are restricted to `.md`.
- ~~No task inputs~~ — done 2026-07-19: auto-detected `{{variables}}` + dedicated Run view (see above).
- Next milestone after polish: M3 collaboration or workflows/chaining (variables make per-task reuse real; chaining is the next dogfooding gap).

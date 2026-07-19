# Pecto — Project State & Knowledge

_Last updated: 2026-07-19 (evening). Snapshot of everything known about the project — vision, decisions, current code, and what comes next._

## What Pecto is (post-pivot)

**Pivoted 2026-07-19 from a web app to a native macOS menu-bar app.** Automate repetitive work by describing it in a plain markdown file. A task is one `.md` file (frontmatter `name` + `description`, then natural-language instructions). The core loop: map a task to a global shortcut slot (⌃⌥1–9), copy text anywhere, press the shortcut — the task runs in the background with the **clipboard as its single input** (`{{clipboard}}`), the result **replaces the clipboard**, and a system notification says when to paste. Failure never touches the clipboard.

User-confirmed pivot decisions (2026-07-19):

- **Full SwiftUI rewrite** — the React UI, Bun/Hono server, and TS runner were deleted (preserved in git: the pre-pivot state is commit `d86dd22`, tagged by message "Final Bun/TS web-app state before the native macOS pivot"). Task-format behavior was re-implemented faithfully in Swift.
- **Numbered shortcut slots** (⌃⌥1–9), not per-task recorders or a palette.
- **Single `{{clipboard}}` variable** — the general multi-variable system (built 2026-07-19 morning) is gone; a task is "slot-runnable" only if its placeholders are exactly `[]` or `["clipboard"]`.
- **Minimal v1**: task CRUD + editor + slot assignment + background runs + notifications. No offline model, no streaming. Run + change history was dropped in the pivot and **ported back the same evening** (user request) — see the History section below.
- **API key in Settings → macOS Keychain** (service "Pecto", account "anthropic-api-key"). The repo `.env` still holds the dev key but the app never reads it.
- Model hardcoded `claude-sonnet-4-5` via direct Messages API (no SDK), `max_tokens` 8192.

Long-term vision unchanged: markdown-task automation for non-technical teams, SKILL.md-superset format, plugins, chaining, collaboration — see the product brief at `~/.claude/plans/i-am-brainstorming-about-lucky-bachman.md` and the pre-pivot history of this file (git) for competitive research.

## Architecture

- **XcodeGen** (`project.yml` is the source of truth; `Pecto.xcodeproj` is generated and gitignored) + a local SwiftPM package. Build: `xcodegen generate && xcodebuild -project Pecto.xcodeproj -scheme Pecto build`. Deployment target macOS 15, Swift 6 (strict concurrency), app is `LSUIElement` (menu-bar only, no Dock icon), **App Sandbox off** (direct distribution; plain folder access), ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`).
- **`PectoKit/`** — pure-logic SwiftPM package, one external dep (**Yams** for YAML), fully unit-tested via `cd PectoKit && swift test` (46 tests, zero network):
  - `TaskParser.swift` — `parseTask`: trimStart → frontmatter regex `^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$` → Yams → validate `name` (slug `^[a-z0-9][a-z0-9-]*$`) + `description` → trimmed body. All friendly `TaskParseError` messages ported **verbatim** from the TS core (see git history `packages/core/src/task.ts`). Unknown frontmatter keys silently ignored (future-proofing kept). One deliberate deviation: a *missing* name/description yields the friendly "Every task needs a name (name)" message instead of zod v4's internal "Invalid input: expected string…".
  - `Placeholders.swift` — regex `\{\{\s*([a-zA-Z][a-zA-Z0-9_-]*)\s*\}\}`; `extractPlaceholders` (ordered, deduped), `placeholderLabel`, `fillPlaceholders` (single left-to-right pass, unknown names verbatim, substituted values never re-scanned).
  - `SlotRunnability.swift` — `.runnable(needsClipboard:)` iff placeholders are `[]`/`["clipboard"]`, else `.notRunnable(reason:)` with a friendly rewrite hint.
  - `PromptBuilder.swift` — system = `You are executing the task "<name>": <description>.` + `\n` + `Follow the instructions exactly. Reply with only the final result of the task — no preamble.`; user = filled instructions.
  - `TaskTemplate.swift` — new-task template (parses + runs as-is), `isTaskSlug`.
  - `WorkspaceStore.swift` — flat folder of root-level `.md` files (dotfiles/dirs ignored, localizedCompare sort), path-traversal guard, create/rename/delete with the ported friendly errors; `TaskSummary` carries name/description/placeholders or per-file `error`.
  - `AnthropicClient.swift` — URLSession POST `/v1/messages` (`x-api-key`, `anthropic-version: 2023-06-01`), decodes multi-block content, maps 401 → "check the key in Settings", API error envelope → its message, network errors → friendly offline hint. Injected `URLSession` → tests use a `URLProtocol` mock. Verified live 2026-07-19 with the exact request shape via curl.
  - `SampleTasks.swift` — seeded samples (improve-email, summarize-text), kept in sync with `workspace/`.
- **`Pecto/`** — the app target (thin glue, all `@MainActor`):
  - `PectoApp.swift` — `MenuBarExtra` (icon swaps `wand.and.stars` → `wand.and.rays` while running) + `Window("main")` with `.defaultLaunchBehavior(.suppressed)` + `Settings` scene; `AppDelegate` sets the `UNUserNotificationCenter` delegate (banners while frontmost) and requests authorization at launch.
  - `AppModel.swift` — root `@Observable`: task list, selection, editor draft/dirty, live `draftValidationError`, create/rename/delete (slot map kept in sync), `slugify`.
  - `SettingsStore.swift` — UserDefaults: `workspacePath` (default `~/Documents/Pecto`, created + seeded once via `didSeedWorkspace`), `slotAssignments` `[Int: String]` (slot → filename); assigning a task to an occupied slot takes it over.
  - `HotkeyManager.swift` — Carbon `RegisterEventHotKey` ⌃⌥1–9 (key codes 18,19,20,21,23,22,26,28,25 — non-sequential!), **no Accessibility permission needed**; C callback hops to MainActor via `Task`. No deinit cleanup (app-lifetime object; Swift 6 forbids touching non-Sendable stored props in deinit anyway).
  - `RunCoordinator.swift` — the loop: resolve task → load+parse → runnability check → clipboard read (empty ⇒ friendly notification, no API call) → fill → prompt → API → **clipboard write on success only** → notification. Runs are keyed by **task path** (`runningPaths`), shared by shortcut slots (`fire(slot:)`), menu-bar entries, and the editor's **Run button** (`run(path:)`, added 2026-07-19 evening — saves the draft first, disabled with a reason while the draft can't run, spinner while in flight, ⌘R). Re-trigger of an in-flight task is silently ignored; different tasks run in parallel; clipboard is last-writer-wins if the user copies mid-run (documented v1 behavior).
  - `KeychainService`, `ClipboardService` (NSPasteboard), `NotificationService` (UNUserNotificationCenter).
  - **Run feedback is dual-channel** (fixed 2026-07-19 evening after "running doesn't work"): every outcome — success, failure, and pre-flight refusal (missing key, empty clipboard, unrunnable task) — goes to a notification AND `RunCoordinator.lastOutcome`, rendered as a dismissible status bar at the bottom of the main window (`MainWindowView.statusArea`). Root cause of the report: no API key stored + notifications silently unavailable (`com.pecto.app` never registered with Notification Center — ad-hoc-signed dev builds, no signing identity on this Mac) ⇒ the app looked dead. Also added: a persistent "Add your Anthropic API key" banner (driven by `AppModel.hasAPIKey`) with an Open Settings link, and a Notifications section in Settings showing authorization status. The app is **installed to `/Applications/Pecto.app`** (helps Notification Center registration; launch that copy, not DerivedData). Dev key was imported into the keychain via `security add-generic-password -T /Applications/Pecto.app` (the `-T` pre-authorizes the app; **a rebuild changes the ad-hoc signature, so after reinstalling expect a keychain consent prompt or re-add the key**).
  - `Views/` — `MenuBarView` (assigned slots w/ running state, Open Pecto, Settings, Quit), `MainWindowView` (NavigationSplitView + operation-error alert + bottom status/key banners), `TaskListView` (parse-error badge, slot chip, + create alert), `TaskEditorView` (monospaced TextEditor, validation banner, ⌘S save, rename/delete menu), `SlotPickerView` (disabled with reason when not slot-runnable; judged on the **saved** file, since that's what shortcuts execute), `SettingsView` (SecureField → Keychain, workspace folder NSOpenPanel, shortcut explainer).
- **`workspace/`** — dev workspace, same two samples as the seed (both `{{clipboard}}`). The app defaults to `~/Documents/Pecto`; point it here via Settings for dogfooding.

## Run + change history (ported back 2026-07-19 evening)

Faithful Swift port of the 2026-07-18 web-app feature; same design decisions (SQLite at `<workspace>/.pecto/pecto.db`, scoped to the selected task, full-content snapshots, restore with confirm, collapsible pane).

- `PectoKit/Diff.swift` — line-LCS `diffLines`/`diffCounts` ported from `packages/core/src/diff.ts`.
- `PectoKit/History.swift` + `HistoryStore.swift` — `RunRecord`/`SnapshotRecord`/`SnapshotKind` and the store, hand-rolled on the **system SQLite3 C API** (no dependency; `import SQLite3`), same schema as the old `apps/server/src/history.ts` with `inputs` folded into the base table (the old DBs were deleted, no migration needed; `listUsage` was not ported — no task grid yet). Behavior preserved: no-op edits/restores skipped, first snapshot = pure additions, renames migrate both tables + zero-diff `renamed` marker with `renamedFrom`, deletes drop history. `":memory:"` for tests; not thread-safe — main-actor confined in the app.
- `AnthropicClient.run` now returns `RunOutput { text, usage }` (`usage` decoded from the Messages response) instead of a bare string.
- `RunCoordinator` records runs (UUID, ms timestamps, duration, model, tokens, output/error, `inputs` = the clipboard value). **Only runs that reach the API are recorded** — pre-flight refusals (missing key, empty clipboard, unrunnable task) are not runs, matching the old server which recorded inside the stream handler.
- `AppModel` records snapshots on create (`created`), ⌘S (`edited`), rename (store migration + marker), restore (`restored`); delete drops history; `historyVersion` counter drives pane refresh (runner bumps it via `onHistoryChanged`). Workspace switch reopens the store for the new folder.
- `Views/HistoryPanel.swift` — an `.inspector` pane on the editor (toolbar clock toggle, open-state in `@AppStorage "historyPaneOpen"`): Runs tab (status icon, time, duration, model + token line, expandable clipboard input/output/error) and Changes tab (kind + time + colored ±counts, expandable inline diff, Restore-with-confirm hidden on the latest snapshot). Tasks that predate history have an empty Changes tab until their first save (old behavior, kept).

## How to build, run & test

```sh
xcodegen generate
xcodebuild -project Pecto.xcodeproj -scheme Pecto -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Pecto-*/Build/Products/Debug/Pecto.app   # must launch via `open`, not the bare binary, or notifications won't register
cd PectoKit && swift test    # 60 tests, no network
```

Manual loop: menu bar → Open Pecto → select a task → slot picker → ⌃⌥1; Settings → paste API key (keychain). Copy text anywhere → ⌃⌥1 → notification → paste. Permission prompts on first launch: notifications + a one-time Documents-folder access prompt. No Accessibility prompt. If the signing identity changes between builds, macOS may re-prompt for notifications (harmless).

Verified 2026-07-19 (evening): 60 `swift test` green, `xcodebuild` clean under Swift 6 strict concurrency, and the **full loop verified end-to-end on this machine**: rough email → `pbcopy` → simulated ⌃⌥1 (osascript key code 18 ⌃⌥) → real API run (2.2s, 155→50 tokens) → improved email on the clipboard → run recorded in `~/Documents/Pecto/.pecto/pecto.db`. Carbon hotkeys, clipboard replacement, and history recording all confirmed working. Notification delivery remains unverified (no Notification Center registration for the ad-hoc build) — the in-window status bar is the reliable channel.

## Known gaps / next candidates

- ~~Run history~~ — ported back 2026-07-19 evening (see the History section).
- **No streaming / no progress UI** — background runs are fire-and-notify; menu-bar icon + menu row are the only running indicators. An elapsed-time indicator or streaming preview would help long runs.
- **Clipboard is text-only** — styled/RTF/image clipboard content is read as plain text or fails the empty check.
- **Launch at login** not implemented (SMAppService is the modern API) — an obvious next setting.
- **No shortcut customization** — fixed ⌃⌥1–9; conflicts with other apps aren't detected.
- **Editor is a bare TextEditor** — no markdown highlighting; CodeMirror parity was deliberately abandoned.
- **App icon** is the default; menu-bar icon is an SF Symbol.
- `.env` still carries the dev API key for curl checks; the app itself only uses the keychain.
- Parked from the old plan: workflows/chaining, multi-variable inputs, per-task models, cloud execution, orgs/collaboration, plugins, triggers.

## History pointers (git)

- `d86dd22` — final Bun/TS web-app state (React SPA, Hono server, history pane, variables + Run view). The old PROJECT-STATE.md at that commit documents the entire web-app era in detail.
- `16c7d14` — TS stack removed, samples clipboard-ified.
- `fc9017f` — Swift scaffold + PectoKit port (45 tests).
- `85e9fd5` — SwiftUI shell + run loop.
- `184f49e` — docs rewrite; history feature ported back after it.

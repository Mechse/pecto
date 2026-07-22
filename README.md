# Pecto

Automate repetitive work by describing it in a plain markdown file — now as a **native macOS menu-bar app**.

A task is one `.md` file: a small settings block (`name`, `description`) followed by plain-language instructions with a single `{{clipboard}}` input. Give a task a global shortcut you record yourself, copy some text anywhere, press the shortcut — Pecto runs the task in the background against the Anthropic API and puts the result back on your clipboard, then notifies you. Paste away.

```markdown
---
name: improve-email
description: Polish an email draft without losing the sender's voice.
---

Improve the email draft below. Fix grammar and spelling, tighten the wording…

{{clipboard}}
```

## Download

**[Download the latest beta](https://github.com/Mechse/pecto/releases/latest)** — macOS 15+, universal binary.

The beta is ad-hoc signed and not yet notarized, so macOS blocks the first launch. Open the `.dmg`, drag Pecto to Applications, try to launch it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. You only do this once.

## Requirements

To build from source:

- macOS 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and Xcode
- An Anthropic API key (pasted once into Pecto's Settings, stored in your keychain)

## Build & run

```sh
xcodegen generate
xcodebuild -project Pecto.xcodeproj -scheme Pecto -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Pecto-*/Build/Products/Debug/Pecto.app
```

Launch via `open` (not the bare binary) or notifications won't register. First launch: allow notifications, and Pecto creates `~/Documents/Pecto` seeded with two sample tasks.

Then: menu-bar icon → **Open Pecto** → select `improve-email` → **Configure** → record a shortcut (e.g. ⌃⌥1) → Settings → paste your API key. Copy a rough email anywhere, press your shortcut, wait for the notification, paste.

## Cutting a release

Bump `MARKETING_VERSION` in `project.yml`, then:

```sh
./scripts/release.sh                     # builds dist/Pecto-<version>.dmg
gh release create v<version> dist/Pecto-<version>.dmg --prerelease
```

The landing page reads the newest release off the GitHub API and points its download buttons at the `.dmg`, so no site change is needed per release.

## Tests

All core behavior (task parsing, placeholders, prompt construction, workspace file rules, API client, run/change history store, diff) lives in the `PectoKit` package:

```sh
cd PectoKit && swift test
```

## Layout

```
project.yml      XcodeGen manifest (Pecto.xcodeproj is generated, gitignored)
Pecto/           App target: SwiftUI shell, hotkeys, clipboard, notifications, keychain
PectoKit/        SwiftPM package: task format, placeholders, prompt, workspace, Anthropic client
workspace/       Dev workspace with the sample tasks (point Pecto at it via Settings)
.ai/             Project state & knowledge for AI-assisted development
```

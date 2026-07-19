# Pecto

Automate repetitive work by describing it in a plain markdown file — now as a **native macOS menu-bar app**.

A task is one `.md` file: a small settings block (`name`, `description`) followed by plain-language instructions with a single `{{clipboard}}` input. Map a task to a global shortcut (⌃⌥1–9), copy some text anywhere, press the shortcut — Pecto runs the task in the background against the Anthropic API and puts the result back on your clipboard, then notifies you. Paste away.

```markdown
---
name: improve-email
description: Polish an email draft without losing the sender's voice.
---

Improve the email draft below. Fix grammar and spelling, tighten the wording…

{{clipboard}}
```

## Requirements

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

Then: menu-bar icon → **Open Pecto** → select `improve-email` → pick a shortcut slot (e.g. ⌃⌥1) → Settings → paste your API key. Copy a rough email anywhere, press ⌃⌥1, wait for the notification, paste.

## Tests

All core behavior (task parsing, placeholders, prompt construction, workspace file rules, API client) lives in the `PectoKit` package:

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

// Single source of truth for site copy and links.
// If the releases API is unreachable everything degrades gracefully —
// no star count, and download falls back to the releases page.
export const GITHUB_REPO = "Mechse/pecto";
export const GITHUB_URL = `https://github.com/${GITHUB_REPO}`;
// The releases index, not /releases/latest — the latter 404s on a repo whose
// only releases are prereleases.
export const RELEASES_URL = `${GITHUB_URL}/releases`;

export const APP_NAME = "Pecto";
export const TAGLINE = "Put an AI between copy and paste.";
export const DESCRIPTION =
  "Pecto is a macOS menu-bar app. Describe a task in a plain Markdown file, give it a keyboard shortcut, and run it on whatever you just copied — the result lands back on your clipboard, ready to paste.";

export const FEATURES = [
  {
    title: "Tasks are plain Markdown files",
    body: "Every task is one .md file in a folder you own. Edit it in any editor, back it up, put it in git.",
  },
  {
    title: "Nine system-wide shortcuts",
    body: "Map tasks to ⌃⌥1 through ⌃⌥9. They work in every app — no Accessibility permission required.",
  },
  {
    title: "Run history with diffs",
    body: "Every run keeps its input, output, tokens, and duration. Every save keeps a version you can diff and restore.",
  },
  {
    title: "Pick a model per task",
    body: "Set a default model, then override it per task — Anthropic, OpenAI, Google, xAI, or fully on-device with Apple Intelligence.",
  },
  {
    title: "Keys stay in your Keychain",
    body: "API keys are stored in the macOS Keychain, never in plaintext. On-device tasks need no key at all.",
  },
  {
    title: "Your clipboard is safe",
    body: "A failed run never touches your clipboard. Only a finished result replaces what you copied.",
  },
];

// The beta is ad-hoc signed, not notarized, so Gatekeeper blocks the first
// launch. Remove this section once builds are signed with a Developer ID.
export const INSTALL_STEPS = [
  {
    title: "Drag Pecto to Applications",
    body: "Open the downloaded .dmg and drag the Pecto icon onto the Applications folder.",
  },
  {
    title: "Try to open it once",
    body: "Launch Pecto from Applications. macOS will refuse and say it could not verify the developer. Click Done — this is expected.",
  },
  {
    title: "Approve it in Privacy & Security",
    body: "Open System Settings → Privacy & Security, scroll to the Security section, and click Open Anyway next to Pecto. Confirm, and Pecto starts in your menu bar.",
  },
];

export const INSTALL_NOTE =
  "Pecto is not yet notarized by Apple, so macOS blocks it the first time. You only do this once. Notarized builds are coming — until then you can also build from source.";

export const COMPATIBILITY = [
  { label: "macOS", value: "15 Sequoia or later" },
  { label: "Chip", value: "Apple Silicon (M1 or later)" },
  { label: "Models", value: "Bring your own API key, or on-device with Apple Intelligence" },
  { label: "Input", value: "Text on the clipboard" },
];

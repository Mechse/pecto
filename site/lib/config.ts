// Single source of truth for site copy and links.
// GITHUB_REPO is a placeholder until the repo is published — everything
// degrades gracefully (no star count, download links to the releases page).
export const GITHUB_REPO = "maximilianleodolter/pecto";
export const GITHUB_URL = `https://github.com/${GITHUB_REPO}`;
export const RELEASES_URL = `${GITHUB_URL}/releases/latest`;

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

export const COMPATIBILITY = [
  { label: "macOS", value: "15 Sequoia or later" },
  { label: "Chip", value: "Apple Silicon (M1 or later)" },
  { label: "Models", value: "Bring your own API key, or on-device with Apple Intelligence" },
  { label: "Input", value: "Text on the clipboard" },
];

/**
 * Task variables: `{{name}}` placeholders written directly in a task's
 * instructions. There is no declaration step — whatever placeholders appear in
 * the body are the task's inputs, and the UI renders a field for each.
 */

const PLACEHOLDER_PATTERN = /\{\{\s*([a-zA-Z][a-zA-Z0-9_-]*)\s*\}\}/g;

/** Placeholder names in order of first appearance, deduplicated. */
export function extractPlaceholders(instructions: string): string[] {
  const names: string[] = [];
  for (const match of instructions.matchAll(PLACEHOLDER_PATTERN)) {
    const name = match[1]!;
    if (!names.includes(name)) names.push(name);
  }
  return names;
}

/** A form label for a placeholder name: "email_draft" → "Email draft". */
export function placeholderLabel(name: string): string {
  const words = name.replace(/[_-]+/g, " ").trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/**
 * Replace every `{{name}}` that has a value. Placeholders without a value are
 * left as written, so the caller can decide whether that is an error.
 */
export function fillPlaceholders(instructions: string, values: Record<string, string>): string {
  return instructions.replace(PLACEHOLDER_PATTERN, (raw, name: string) =>
    name in values ? values[name]! : raw,
  );
}

import { describe, expect, test } from "bun:test";
import { extractPlaceholders, fillPlaceholders, placeholderLabel } from "../src/index.ts";

describe("extractPlaceholders", () => {
  test("finds placeholders in order of first appearance, deduplicated", () => {
    const text = "Improve {{email_draft}} for {{tone}}. Base it on {{email_draft}}.";
    expect(extractPlaceholders(text)).toEqual(["email_draft", "tone"]);
  });

  test("allows whitespace inside the braces", () => {
    expect(extractPlaceholders("Use {{ email_draft }} here.")).toEqual(["email_draft"]);
  });

  test("ignores single braces, empty braces and names starting with a digit", () => {
    expect(extractPlaceholders("{a} {{}} {{ }} {{1st}} {{-x}}")).toEqual([]);
  });

  test("returns an empty list for plain instructions", () => {
    expect(extractPlaceholders("Summarize the text.")).toEqual([]);
  });
});

describe("placeholderLabel", () => {
  test("turns snake_case and kebab-case into a friendly label", () => {
    expect(placeholderLabel("email_draft")).toBe("Email draft");
    expect(placeholderLabel("target-audience")).toBe("Target audience");
    expect(placeholderLabel("tone")).toBe("Tone");
  });
});

describe("fillPlaceholders", () => {
  test("replaces every occurrence, including spaced ones", () => {
    const text = "Improve {{email_draft}}. Again: {{ email_draft }}.";
    expect(fillPlaceholders(text, { email_draft: "Hi Bob" })).toBe(
      "Improve Hi Bob. Again: Hi Bob.",
    );
  });

  test("leaves placeholders without a value untouched", () => {
    expect(fillPlaceholders("{{a}} and {{b}}", { a: "1" })).toBe("1 and {{b}}");
  });

  test("does not re-scan substituted values for placeholders", () => {
    expect(fillPlaceholders("{{a}}", { a: "{{b}}", b: "nope" })).toBe("{{b}}");
  });
});

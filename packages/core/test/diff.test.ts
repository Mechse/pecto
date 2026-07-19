import { describe, expect, test } from "bun:test";
import { diffCounts, diffLines } from "../src/diff.ts";

describe("diffLines", () => {
  test("identical inputs are all same-lines", () => {
    const lines = diffLines("a\nb", "a\nb");
    expect(lines).toEqual([
      { type: "same", text: "a" },
      { type: "same", text: "b" },
    ]);
  });

  test("detects an insertion between kept lines", () => {
    expect(diffLines("a\nc", "a\nb\nc")).toEqual([
      { type: "same", text: "a" },
      { type: "added", text: "b" },
      { type: "same", text: "c" },
    ]);
  });

  test("detects a removal and a change", () => {
    expect(diffLines("a\nb\nc", "a\nx")).toEqual([
      { type: "same", text: "a" },
      { type: "removed", text: "b" },
      { type: "removed", text: "c" },
      { type: "added", text: "x" },
    ]);
  });

  test("handles empty sides", () => {
    expect(diffLines("", "a")).toEqual([
      { type: "removed", text: "" },
      { type: "added", text: "a" },
    ]);
  });
});

describe("diffCounts", () => {
  test("counts added and removed lines", () => {
    expect(diffCounts("a\nb\nc", "a\nB\nc\nd")).toEqual({ added: 2, removed: 1 });
    expect(diffCounts("same", "same")).toEqual({ added: 0, removed: 0 });
  });
});

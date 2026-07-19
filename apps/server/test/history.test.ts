import { describe, expect, test } from "bun:test";
import { HistoryStore } from "../src/history.ts";

const run = (id: string, taskPath: string, startedAt: number) => ({
  id,
  taskPath,
  startedAt,
  finishedAt: startedAt + 1000,
  status: "succeeded" as const,
  model: "offline",
  inputTokens: 12,
  outputTokens: 34,
  output: "done",
  error: null,
  inputs: null,
});

describe("HistoryStore runs", () => {
  test("records and lists runs newest first, scoped to the task", () => {
    const store = new HistoryStore(":memory:");
    store.recordRun(run("a", "one.md", 1000));
    store.recordRun(run("b", "one.md", 2000));
    store.recordRun(run("c", "other.md", 3000));

    const runs = store.listRuns("one.md");
    expect(runs.map((r) => r.id)).toEqual(["b", "a"]);
    expect(runs[0]).toMatchObject({ inputTokens: 12, outputTokens: 34, output: "done" });
  });

  test("round-trips the input values a run was started with", () => {
    const store = new HistoryStore(":memory:");
    store.recordRun({ ...run("a", "one.md", 1000), inputs: { email_draft: "Hi Bob,\nlet's meet" } });
    store.recordRun(run("b", "one.md", 2000));

    const runs = store.listRuns("one.md");
    expect(runs[0]?.inputs).toBeNull();
    expect(runs[1]?.inputs).toEqual({ email_draft: "Hi Bob,\nlet's meet" });
  });

  test("keeps failed runs with their error", () => {
    const store = new HistoryStore(":memory:");
    store.recordRun({ ...run("a", "one.md", 1000), status: "failed", output: null, error: "boom", inputTokens: null, outputTokens: null });
    expect(store.listRuns("one.md")[0]).toMatchObject({ status: "failed", error: "boom", inputTokens: null });
  });

  test("listUsage aggregates run counts and latest start per task", () => {
    const store = new HistoryStore(":memory:");
    store.recordRun(run("a", "one.md", 1000));
    store.recordRun(run("b", "one.md", 2000));
    store.recordRun(run("c", "other.md", 3000));

    const byPath = new Map(store.listUsage().map((u) => [u.taskPath, u]));
    expect(byPath.get("one.md")).toMatchObject({ runCount: 2, lastRunAt: 2000 });
    expect(byPath.get("other.md")).toMatchObject({ runCount: 1, lastRunAt: 3000 });
  });

  test("listUsage follows renames and drops deleted tasks", () => {
    const store = new HistoryStore(":memory:");
    store.recordRun(run("a", "old.md", 1000));
    store.recordRun(run("b", "gone.md", 2000));
    store.renameTask("old.md", "new.md", "body", 3);
    store.deleteTask("gone.md");

    expect(store.listUsage()).toEqual([{ taskPath: "new.md", runCount: 1, lastRunAt: 1000 }]);
  });
});

describe("HistoryStore snapshots", () => {
  test("diffs each snapshot against the previous one", () => {
    const store = new HistoryStore(":memory:");
    store.recordSnapshot("t.md", "created", "a\nb", 1);
    const edited = store.recordSnapshot("t.md", "edited", "a\nc\nd", 2);
    expect(edited).toMatchObject({ kind: "edited", linesAdded: 2, linesRemoved: 1 });

    const list = store.listSnapshots("t.md");
    expect(list.map((s) => s.kind)).toEqual(["edited", "created"]);
    expect(list[1]).toMatchObject({ linesAdded: 2, linesRemoved: 0 });
  });

  test("skips no-op edits so repeated saves don't pile up", () => {
    const store = new HistoryStore(":memory:");
    store.recordSnapshot("t.md", "created", "same", 1);
    expect(store.recordSnapshot("t.md", "edited", "same", 2)).toBeNull();
    expect(store.listSnapshots("t.md")).toHaveLength(1);
  });

  test("getSnapshot returns content plus the content it replaced", () => {
    const store = new HistoryStore(":memory:");
    const first = store.recordSnapshot("t.md", "created", "v1", 1)!;
    const second = store.recordSnapshot("t.md", "edited", "v2", 2)!;

    expect(store.getSnapshot(second.id)).toMatchObject({ content: "v2", prevContent: "v1" });
    expect(store.getSnapshot(first.id)).toMatchObject({ content: "v1", prevContent: "" });
    expect(store.getSnapshot(999)).toBeNull();
  });

  test("rename migrates history to the new path and records a zero-diff marker", () => {
    const store = new HistoryStore(":memory:");
    store.recordRun(run("a", "old.md", 1000));
    store.recordSnapshot("old.md", "created", "body", 1);
    store.renameTask("old.md", "new.md", "body", 2);

    expect(store.listRuns("old.md")).toHaveLength(0);
    expect(store.listRuns("new.md")).toHaveLength(1);
    expect(store.listSnapshots("old.md")).toHaveLength(0);
    expect(store.listSnapshots("new.md")[0]).toMatchObject({
      kind: "renamed",
      renamedFrom: "old.md",
      linesAdded: 0,
      linesRemoved: 0,
    });
  });

  test("deleteTask drops runs and snapshots for that task only", () => {
    const store = new HistoryStore(":memory:");
    store.recordRun(run("a", "t.md", 1000));
    store.recordSnapshot("t.md", "created", "body", 1);
    store.recordSnapshot("keep.md", "created", "body", 1);
    store.deleteTask("t.md");

    expect(store.listRuns("t.md")).toHaveLength(0);
    expect(store.listSnapshots("t.md")).toHaveLength(0);
    expect(store.listSnapshots("keep.md")).toHaveLength(1);
  });
});

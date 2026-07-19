import { describe, expect, test } from "bun:test";
import { parseTask, type RunEvent } from "@pecto/core";
import { runTask } from "../src/index.ts";
import { createScriptedModel } from "../src/testing.ts";

const RESEARCH = parseTask(`---
name: research
description: Collect facts
---

List three facts about espresso.
`);

describe("runTask", () => {
  test("runs a task and returns its text with events", async () => {
    const events: RunEvent[] = [];
    const result = await runTask(RESEARCH, {
      model: createScriptedModel(["fact one, fact two, fact three"]),
      onEvent: (e) => events.push(e),
    });
    expect(result.text).toBe("fact one, fact two, fact three");
    expect(events.map((e) => e.type)).toEqual(["run-started", "run-completed"]);
    expect(events[0]).toMatchObject({ type: "run-started", label: "research", model: "offline" });
  });

  test("emits run-failed when the model errors", async () => {
    const model = createScriptedModel();
    model.doGenerate = async () => {
      throw new Error("model exploded");
    };
    const events: string[] = [];
    await expect(
      runTask(RESEARCH, {
        model,
        onEvent: (e) => events.push(e.type),
      }),
    ).rejects.toThrow(/model exploded/);
    expect(events).toEqual(["run-started", "run-failed"]);
  });
});

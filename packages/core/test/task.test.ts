import { describe, expect, test } from "bun:test";
import { TaskParseError, parseTask } from "../src/index.ts";

const VALID = `---
name: enrich-new-signups
description: Pull yesterday's signups and enrich them
---

Fetch all signups from yesterday and enrich them.
`;

describe("parseTask", () => {
  test("parses a valid task file", () => {
    const task = parseTask(VALID);
    expect(task.frontmatter.name).toBe("enrich-new-signups");
    expect(task.frontmatter.description).toBe("Pull yesterday's signups and enrich them");
    expect(task.instructions).toStartWith("Fetch all signups");
  });

  test("ignores unknown frontmatter keys", () => {
    const task = parseTask(`---\nname: minimal\ndescription: smallest valid task\nmodel: something/else\n---\n\nDo the thing.\n`);
    expect(task.frontmatter).toEqual({ name: "minimal", description: "smallest valid task" });
  });

  test("rejects a file without a frontmatter block, with a friendly message", () => {
    expect(() => parseTask("Just some text")).toThrow(TaskParseError);
    expect(() => parseTask("Just some text")).toThrow(/settings block/);
  });

  test("rejects a task without a name", () => {
    expect(() => parseTask(`---\ndescription: no name\n---\n\nbody\n`)).toThrow(TaskParseError);
  });

  test("rejects an uppercase task name with guidance", () => {
    expect(() => parseTask(`---\nname: MyTask\ndescription: x\n---\n\nbody\n`)).toThrow(/lowercase/);
  });

  test("rejects a task with settings but no instructions", () => {
    expect(() => parseTask(`---\nname: empty\ndescription: x\n---\n\n`)).toThrow(/no instructions/);
  });
});

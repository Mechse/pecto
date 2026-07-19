import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtemp, mkdir, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseTask } from "@pecto/core";
import { Workspace } from "../src/workspace.ts";

let root: string;
let workspace: Workspace;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "pecto-ws-"));
  workspace = new Workspace(root);
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

const exists = (path: string) =>
  stat(join(root, path)).then(
    () => true,
    () => false,
  );

describe("tree", () => {
  test("lists only root .md files, ignoring folders and dotfiles", async () => {
    await workspace.createTask("summarize.md");
    await mkdir(join(root, "some-folder"));
    await Bun.write(join(root, "some-folder", "nested.md"), "nested");
    await Bun.write(join(root, ".hidden.md"), "hidden");
    await Bun.write(join(root, "notes.txt"), "notes");
    const tasks = await workspace.tree();
    expect(tasks.map((t) => t.path)).toEqual(["summarize.md"]);
    expect(tasks[0]?.name).toBe("summarize");
  });

  test("lists each task's {{placeholders}} so the UI can build the run form", async () => {
    await Bun.write(
      join(root, "improve.md"),
      "---\nname: improve\ndescription: d\n---\n\nImprove {{email_draft}} in a {{tone}} tone.",
    );
    await workspace.createTask("plain.md");
    const tasks = await workspace.tree();
    expect(tasks.find((t) => t.path === "improve.md")?.placeholders).toEqual(["email_draft", "tone"]);
    expect(tasks.find((t) => t.path === "plain.md")?.placeholders).toEqual([]);
  });
});

describe("createTask", () => {
  test("writes a template that parses and runs as-is", async () => {
    await workspace.createTask("summarize.md");
    const task = parseTask(await workspace.readFile("summarize.md"));
    expect(task.frontmatter.name).toBe("summarize");
    expect(task.instructions.length).toBeGreaterThan(0);
  });

  test("rejects names that aren't lowercase-dashes", async () => {
    await expect(workspace.createTask("Bad Name.md")).rejects.toThrow(/lowercase/);
  });

  test("rejects non-.md files, nested paths and duplicates", async () => {
    await expect(workspace.createTask("notes.txt")).rejects.toThrow(/\.md/);
    await expect(workspace.createTask("folder/task.md")).rejects.toThrow(/lowercase/);
    await workspace.createTask("dupe.md");
    await expect(workspace.createTask("dupe.md")).rejects.toThrow(/already exists/);
  });

  test("refuses paths escaping the workspace", async () => {
    // ".." fails slug validation before it even reaches the path guard.
    await expect(workspace.createTask("../escape.md")).rejects.toThrow(/lowercase/);
    expect(() => workspace.resolvePath("../escape.md")).toThrow(/outside the workspace/);
  });
});

describe("deleteTask", () => {
  test("deletes a task file", async () => {
    await workspace.createTask("gone.md");
    await workspace.deleteTask("gone.md");
    expect(await exists("gone.md")).toBe(false);
  });

  test("refuses non-.md files, folders and missing paths", async () => {
    await Bun.write(join(root, "keep.txt"), "important");
    await expect(workspace.deleteTask("keep.txt")).rejects.toThrow(/Only \.md/);
    await expect(workspace.deleteTask("missing.md")).rejects.toThrow(/no longer exists/);
    await mkdir(join(root, "folder.md"));
    await expect(workspace.deleteTask("folder.md")).rejects.toThrow(/no longer exists/);
  });
});

describe("renameTask", () => {
  test("renames a task file", async () => {
    await workspace.createTask("old.md");
    await workspace.renameTask("old.md", "new.md");
    expect(await exists("old.md")).toBe(false);
    expect(await exists("new.md")).toBe(true);
  });

  test("refuses overwriting, bad names and missing sources", async () => {
    await workspace.createTask("a.md");
    await workspace.createTask("b.md");
    await expect(workspace.renameTask("a.md", "b.md")).rejects.toThrow(/already exists/);
    await expect(workspace.renameTask("a.md", "Bad Name.md")).rejects.toThrow(/lowercase/);
    await expect(workspace.renameTask("missing.md", "x.md")).rejects.toThrow(/no longer exists/);
  });
});

describe("loadTask", () => {
  test("loads a parsed task ready to run", async () => {
    await workspace.createTask("summarize.md");
    const task = await workspace.loadTask("summarize.md");
    expect(task.frontmatter.name).toBe("summarize");
  });

  test("gives a friendly error for missing files", async () => {
    await expect(workspace.loadTask("missing.md")).rejects.toThrow(/no longer exists/);
  });
});

import { readdir, rename, stat, unlink } from "node:fs/promises";
import { resolve, sep } from "node:path";
import {
  extractPlaceholders,
  parseTask,
  TaskParseError,
  type ParsedTask,
  type TreeTask,
} from "@pecto/core";

export class Workspace {
  readonly root: string;

  constructor(root: string) {
    this.root = resolve(root);
  }

  /** Resolve a relative path, refusing anything that escapes the workspace. */
  resolvePath(relative: string): string {
    const abs = resolve(this.root, relative);
    if (abs !== this.root && !abs.startsWith(this.root + sep)) {
      throw new TaskParseError("That file is outside the workspace.");
    }
    return abs;
  }

  private async describeTask(path: string): Promise<TreeTask> {
    const entry: TreeTask = { path };
    try {
      const task = parseTask(await Bun.file(this.resolvePath(path)).text());
      entry.name = task.frontmatter.name;
      entry.description = task.frontmatter.description;
      entry.placeholders = extractPlaceholders(task.instructions);
    } catch (error) {
      entry.error = error instanceof Error ? error.message : String(error);
    }
    return entry;
  }

  /** The workspace layout: a flat list of .md task files at the root. Folders are ignored. */
  async tree(): Promise<TreeTask[]> {
    const files = (await readdir(this.root, { withFileTypes: true }))
      .filter((e) => e.isFile() && e.name.endsWith(".md") && !e.name.startsWith("."))
      .map((e) => e.name)
      .sort((a, b) => a.localeCompare(b));
    return Promise.all(files.map((file) => this.describeTask(file)));
  }

  async readFile(relativePath: string): Promise<string> {
    const file = Bun.file(this.resolvePath(relativePath));
    if (!(await file.exists())) {
      throw new TaskParseError("This file no longer exists.");
    }
    return file.text();
  }

  async writeFile(relativePath: string, content: string): Promise<void> {
    if (!relativePath.endsWith(".md")) {
      throw new TaskParseError("Only .md task files can be saved.");
    }
    await Bun.write(this.resolvePath(relativePath), content);
  }

  private assertSlug(segment: string, what: string): void {
    if (!/^[a-z0-9][a-z0-9-]*$/.test(segment)) {
      throw new TaskParseError(
        `${what} use lowercase letters, numbers and dashes (e.g. enrich-new-signups).`,
      );
    }
  }

  /** A minimal file that parses and runs as-is, so a fresh task is never broken. */
  private taskTemplate(name: string): string {
    return [
      "---",
      `name: ${name}`,
      "description: Describe what this task does in one line.",
      "---",
      "",
      "Write plain-language instructions for what should happen when this task runs.",
      "",
    ].join("\n");
  }

  /** Create a task file at the workspace root. */
  async createTask(relativePath: string): Promise<void> {
    if (!relativePath.endsWith(".md")) {
      throw new TaskParseError("Task files end in .md.");
    }
    // The slug rule rejects "/", so tasks can only be created at the root.
    this.assertSlug(relativePath.slice(0, -3), "Task file names");

    const abs = this.resolvePath(relativePath);
    if (await Bun.file(abs).exists()) {
      throw new TaskParseError("Something with that name already exists.");
    }
    await Bun.write(abs, this.taskTemplate(relativePath.slice(0, -3)));
  }

  /** Delete a task file. Permanent. */
  async deleteTask(relativePath: string): Promise<void> {
    if (!relativePath.endsWith(".md")) {
      throw new TaskParseError("Only .md task files can be deleted.");
    }
    const abs = this.resolvePath(relativePath);
    const info = await stat(abs).catch(() => null);
    if (!info?.isFile()) throw new TaskParseError("This file no longer exists.");
    await unlink(abs);
  }

  /** Rename a task file. */
  async renameTask(from: string, to: string): Promise<void> {
    const absFrom = this.resolvePath(from);
    const info = await stat(absFrom).catch(() => null);
    if (!info?.isFile()) throw new TaskParseError("This file no longer exists.");

    if (!to.endsWith(".md")) throw new TaskParseError("Task files end in .md.");
    this.assertSlug(to.slice(0, -3), "Task file names");

    const absTo = this.resolvePath(to);
    if (await stat(absTo).catch(() => null)) {
      throw new TaskParseError("Something with that name already exists.");
    }
    await rename(absFrom, absTo);
  }

  /** Load one task file, ready to run. */
  async loadTask(relativePath: string): Promise<ParsedTask> {
    return parseTask(await this.readFile(relativePath));
  }
}

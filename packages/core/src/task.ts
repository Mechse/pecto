import { parse as parseYaml } from "yaml";
import { z } from "zod";

export const taskFrontmatterSchema = z.object({
  name: z
    .string()
    .min(1, "Every task needs a name")
    .regex(
      /^[a-z0-9][a-z0-9-]*$/,
      "Task names use lowercase letters, numbers and dashes (e.g. enrich-new-signups)",
    ),
  description: z.string().min(1, "Every task needs a one-line description"),
});

export type TaskFrontmatter = z.infer<typeof taskFrontmatterSchema>;

export interface ParsedTask {
  frontmatter: TaskFrontmatter;
  /** The natural-language body of the task file. */
  instructions: string;
  /** The original file content, verbatim. */
  raw: string;
}

/** Error with a message suitable for non-technical users. */
export class TaskParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TaskParseError";
  }
}

const FRONTMATTER_PATTERN = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/;

export function parseTask(markdown: string): ParsedTask {
  const trimmed = markdown.trimStart();
  const match = FRONTMATTER_PATTERN.exec(trimmed);
  if (!match) {
    throw new TaskParseError(
      "This file is missing its settings block. A task starts with a section between two '---' lines that names the task and describes what it needs.",
    );
  }
  const [, yamlSource, body] = match;

  let data: unknown;
  try {
    data = parseYaml(yamlSource ?? "");
  } catch {
    throw new TaskParseError(
      "The settings block at the top of this task could not be read. Check it for stray characters or broken indentation.",
    );
  }

  const result = taskFrontmatterSchema.safeParse(data ?? {});
  if (!result.success) {
    const first = result.error.issues[0];
    const where = first?.path.length ? ` (${first.path.join(".")})` : "";
    throw new TaskParseError(
      `${first?.message ?? "The task settings are incomplete."}${where}`,
    );
  }

  const instructions = (body ?? "").trim();
  if (!instructions) {
    throw new TaskParseError(
      "This task has settings but no instructions. Below the settings block, describe in plain language what should happen.",
    );
  }

  return { frontmatter: result.data, instructions, raw: markdown };
}

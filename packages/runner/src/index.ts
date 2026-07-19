import { generateText, type LanguageModel } from "ai";
import { createAnthropic } from "@ai-sdk/anthropic";
import type { ParsedTask, RunEvent, RunResult } from "@pecto/core";

export const DEFAULT_MODEL = "claude-sonnet-4-5";

export interface RunOptions {
  /** Override the model (tests, offline mode). */
  model?: LanguageModel;
  onEvent?: (event: RunEvent) => void;
}

/** Run a single task and return its text output. */
export async function runTask(task: ParsedTask, options: RunOptions = {}): Promise<RunResult> {
  const runId = crypto.randomUUID();
  const emit = (event: RunEvent) => options.onEvent?.(event);

  const model = options.model ?? createAnthropic()(DEFAULT_MODEL);
  const modelId = typeof model === "string" ? model : model.modelId;

  emit({ type: "run-started", runId, label: task.frontmatter.name, model: modelId, at: Date.now() });
  try {
    const { text, usage } = await generateText({
      model,
      system: [
        `You are executing the task "${task.frontmatter.name}": ${task.frontmatter.description}.`,
        "Follow the instructions exactly. Reply with only the final result of the task — no preamble.",
      ].join("\n"),
      prompt: task.instructions,
    });
    const runUsage = { inputTokens: usage.inputTokens, outputTokens: usage.outputTokens };
    emit({ type: "run-completed", runId, text, usage: runUsage, at: Date.now() });
    return { runId, text, usage: runUsage };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    emit({ type: "run-failed", runId, error: message, at: Date.now() });
    throw error;
  }
}

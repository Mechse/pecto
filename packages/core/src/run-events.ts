/** Token counts for a run. Undefined when the provider doesn't report them. */
export interface RunUsage {
  inputTokens?: number;
  outputTokens?: number;
}

export type RunEvent =
  | { type: "run-started"; runId: string; label: string; model: string; at: number }
  | { type: "run-completed"; runId: string; text: string; usage?: RunUsage; at: number }
  | { type: "run-failed"; runId: string; error: string; at: number };

export interface RunResult {
  runId: string;
  /** The final text output of the run. */
  text: string;
  usage?: RunUsage;
}

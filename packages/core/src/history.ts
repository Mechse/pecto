/** A finished run, as persisted and served by the history API. */
export interface RunRecord {
  id: string;
  taskPath: string;
  startedAt: number;
  finishedAt: number;
  status: "succeeded" | "failed";
  model: string;
  inputTokens: number | null;
  outputTokens: number | null;
  /** Final text output (succeeded runs). */
  output: string | null;
  /** Error message (failed runs). */
  error: string | null;
  /** Placeholder values the run was started with, if the task takes any. */
  inputs: Record<string, string> | null;
}

/** Aggregate run stats for one task, for the task grid's "most used" ordering. */
export interface TaskUsage {
  taskPath: string;
  runCount: number;
  lastRunAt: number;
}

export type SnapshotKind = "created" | "edited" | "renamed" | "restored";

/** One entry in a task's change history. Content lives server-side; list entries carry only the summary. */
export interface SnapshotRecord {
  id: number;
  taskPath: string;
  at: number;
  kind: SnapshotKind;
  linesAdded: number;
  linesRemoved: number;
  /** Previous filename, for kind "renamed". */
  renamedFrom: string | null;
}

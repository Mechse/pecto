import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import {
  diffCounts,
  type RunRecord,
  type SnapshotKind,
  type SnapshotRecord,
  type TaskUsage,
} from "@pecto/core";

/**
 * Persistent history for the workspace: finished runs and task-content
 * snapshots, in a SQLite file under `<workspace>/.pecto/`. The workspace tree
 * ignores folders, so the store never shows up as a task.
 */
export class HistoryStore {
  private db: Database;

  /** Pass ":memory:" for tests. */
  constructor(dbPath: string) {
    if (dbPath !== ":memory:") mkdirSync(dirname(dbPath), { recursive: true });
    this.db = new Database(dbPath);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS runs (
        id TEXT PRIMARY KEY,
        task_path TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        finished_at INTEGER NOT NULL,
        status TEXT NOT NULL,
        model TEXT NOT NULL,
        input_tokens INTEGER,
        output_tokens INTEGER,
        output TEXT,
        error TEXT
      );
      CREATE INDEX IF NOT EXISTS runs_by_task ON runs(task_path, started_at);
      CREATE TABLE IF NOT EXISTS snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_path TEXT NOT NULL,
        at INTEGER NOT NULL,
        kind TEXT NOT NULL,
        content TEXT NOT NULL,
        lines_added INTEGER NOT NULL,
        lines_removed INTEGER NOT NULL,
        renamed_from TEXT
      );
      CREATE INDEX IF NOT EXISTS snapshots_by_task ON snapshots(task_path, id);
    `);
    // Databases created before task variables existed lack the inputs column.
    const runColumns = this.db.query(`PRAGMA table_info(runs)`).all() as { name: string }[];
    if (!runColumns.some((c) => c.name === "inputs")) {
      this.db.exec(`ALTER TABLE runs ADD COLUMN inputs TEXT`);
    }
  }

  recordRun(record: RunRecord): void {
    this.db
      .query(
        `INSERT INTO runs (id, task_path, started_at, finished_at, status, model, input_tokens, output_tokens, output, error, inputs)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        record.id,
        record.taskPath,
        record.startedAt,
        record.finishedAt,
        record.status,
        record.model,
        record.inputTokens,
        record.outputTokens,
        record.output,
        record.error,
        record.inputs ? JSON.stringify(record.inputs) : null,
      );
  }

  /** Newest first. */
  listRuns(taskPath: string): RunRecord[] {
    const rows = this.db
      .query(`SELECT * FROM runs WHERE task_path = ? ORDER BY started_at DESC, id DESC`)
      .all(taskPath) as any[];
    return rows.map((r) => ({
      id: r.id,
      taskPath: r.task_path,
      startedAt: r.started_at,
      finishedAt: r.finished_at,
      status: r.status,
      model: r.model,
      inputTokens: r.input_tokens,
      outputTokens: r.output_tokens,
      output: r.output,
      error: r.error,
      inputs: r.inputs ? JSON.parse(r.inputs) : null,
    }));
  }

  /** Run counts per task, for the grid's "most used" ordering. */
  listUsage(): TaskUsage[] {
    const rows = this.db
      .query(
        `SELECT task_path, COUNT(*) AS run_count, MAX(started_at) AS last_run_at
         FROM runs GROUP BY task_path`,
      )
      .all() as any[];
    return rows.map((r) => ({ taskPath: r.task_path, runCount: r.run_count, lastRunAt: r.last_run_at }));
  }

  /**
   * Record a content snapshot. Change counts are diffed against the previous
   * snapshot of the same task. No-op edits/restores (content identical to the
   * latest snapshot) are skipped so ⌘S spam doesn't pile up entries.
   */
  recordSnapshot(
    taskPath: string,
    kind: SnapshotKind,
    content: string,
    at: number,
    renamedFrom: string | null = null,
  ): SnapshotRecord | null {
    const prev = this.latestContent(taskPath);
    if ((kind === "edited" || kind === "restored") && prev === content) return null;
    // A rename doesn't change content, and a first snapshot is pure additions —
    // diffing against "" would count a phantom removed empty line.
    const { added, removed } =
      kind === "renamed"
        ? { added: 0, removed: 0 }
        : prev === null
          ? { added: content.split("\n").length, removed: 0 }
          : diffCounts(prev, content);
    const result = this.db
      .query(
        `INSERT INTO snapshots (task_path, at, kind, content, lines_added, lines_removed, renamed_from)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(taskPath, at, kind, content, added, removed, renamedFrom);
    return {
      id: Number(result.lastInsertRowid),
      taskPath,
      at,
      kind,
      linesAdded: added,
      linesRemoved: removed,
      renamedFrom,
    };
  }

  /** Newest first, without content (list entries are summaries). */
  listSnapshots(taskPath: string): SnapshotRecord[] {
    const rows = this.db
      .query(
        `SELECT id, task_path, at, kind, lines_added, lines_removed, renamed_from
         FROM snapshots WHERE task_path = ? ORDER BY id DESC`,
      )
      .all(taskPath) as any[];
    return rows.map((r) => ({
      id: r.id,
      taskPath: r.task_path,
      at: r.at,
      kind: r.kind,
      linesAdded: r.lines_added,
      linesRemoved: r.lines_removed,
      renamedFrom: r.renamed_from,
    }));
  }

  /** One snapshot with its content and the content it replaced (for diff views). */
  getSnapshot(id: number): { record: SnapshotRecord; content: string; prevContent: string } | null {
    const r = this.db.query(`SELECT * FROM snapshots WHERE id = ?`).get(id) as any;
    if (!r) return null;
    const prev = this.db
      .query(`SELECT content FROM snapshots WHERE task_path = ? AND id < ? ORDER BY id DESC LIMIT 1`)
      .get(r.task_path, id) as any;
    return {
      record: {
        id: r.id,
        taskPath: r.task_path,
        at: r.at,
        kind: r.kind,
        linesAdded: r.lines_added,
        linesRemoved: r.lines_removed,
        renamedFrom: r.renamed_from,
      },
      content: r.content,
      prevContent: prev?.content ?? "",
    };
  }

  private latestContent(taskPath: string): string | null {
    const row = this.db
      .query(`SELECT content FROM snapshots WHERE task_path = ? ORDER BY id DESC LIMIT 1`)
      .get(taskPath) as any;
    return row?.content ?? null;
  }

  /** Carry a task's history over to its new filename and mark the rename. */
  renameTask(from: string, to: string, content: string, at: number): void {
    this.db.query(`UPDATE runs SET task_path = ? WHERE task_path = ?`).run(to, from);
    this.db.query(`UPDATE snapshots SET task_path = ? WHERE task_path = ?`).run(to, from);
    this.recordSnapshot(to, "renamed", content, at, from);
  }

  /** Drop all history for a deleted task (deletes are permanent, like the file). */
  deleteTask(taskPath: string): void {
    this.db.query(`DELETE FROM runs WHERE task_path = ?`).run(taskPath);
    this.db.query(`DELETE FROM snapshots WHERE task_path = ?`).run(taskPath);
  }
}

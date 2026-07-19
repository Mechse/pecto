import { join } from "node:path";
import { Hono } from "hono";
import { stream } from "hono/streaming";
import {
  extractPlaceholders,
  fillPlaceholders,
  placeholderLabel,
  TaskParseError,
  type RunEvent,
} from "@pecto/core";
import { runTask } from "@pecto/runner";
import { createScriptedModel } from "@pecto/runner/testing";
import { HistoryStore } from "./history.ts";
import { Workspace } from "./workspace.ts";

// Bun auto-loads .env only from the cwd, and dev scripts run from apps/server —
// so read the repo-root .env explicitly. Real env vars always win.
const rootEnvFile = Bun.file(new URL("../../../.env", import.meta.url));
if (await rootEnvFile.exists()) {
  for (const line of (await rootEnvFile.text()).split("\n")) {
    const match = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (!match || match[1]! in process.env) continue;
    process.env[match[1]!] = match[2]!.replace(/^(["'])(.*)\1$/, "$2");
  }
}

// Default workspace is <repo root>/workspace regardless of cwd (scripts run
// from the repo root or from apps/server depending on how dev is started).
const workspace = new Workspace(
  process.env.PECTO_WORKSPACE ?? new URL("../../../workspace", import.meta.url).pathname,
);

// Run + change history lives inside the workspace (folders are ignored by the
// task tree), so it travels with the tasks it describes.
const history = new HistoryStore(join(workspace.root, ".pecto", "pecto.db"));

/**
 * Without an API key, runs fall back to a deterministic offline model.
 * PECTO_OFFLINE=1 forces it — Bun auto-loads .env, so a key in there would
 * otherwise make dev runs silently hit the real API.
 */
const offline = process.env.PECTO_OFFLINE === "1" || !process.env.ANTHROPIC_API_KEY;

const app = new Hono();

app.get("/api/status", (c) =>
  c.json({ ok: true, workspace: workspace.root, offline }),
);

app.get("/api/tree", async (c) => c.json({ ok: true, tasks: await workspace.tree() }));

app.get("/api/file", async (c) => {
  const path = c.req.query("path");
  if (!path) return c.json({ ok: false, error: "Missing 'path'." }, 400);
  try {
    return c.json({ ok: true, content: await workspace.readFile(path) });
  } catch (error) {
    return friendlyError(c, error);
  }
});

app.put("/api/file", async (c) => {
  const { path, content } = await c.req.json<{ path?: string; content?: string }>();
  if (!path || typeof content !== "string") {
    return c.json({ ok: false, error: "Send 'path' and 'content'." }, 400);
  }
  try {
    await workspace.writeFile(path, content);
    history.recordSnapshot(path, "edited", content, Date.now());
    return c.json({ ok: true });
  } catch (error) {
    return friendlyError(c, error);
  }
});

app.post("/api/files", async (c) => {
  const { path } = await c.req.json<{ path?: string }>();
  if (!path) return c.json({ ok: false, error: "Missing 'path'." }, 400);
  try {
    await workspace.createTask(path);
    history.recordSnapshot(path, "created", await workspace.readFile(path), Date.now());
    return c.json({ ok: true });
  } catch (error) {
    return friendlyError(c, error);
  }
});

app.delete("/api/file", async (c) => {
  const path = c.req.query("path");
  if (!path) return c.json({ ok: false, error: "Missing 'path'." }, 400);
  try {
    await workspace.deleteTask(path);
    history.deleteTask(path);
    return c.json({ ok: true });
  } catch (error) {
    return friendlyError(c, error);
  }
});

app.post("/api/rename", async (c) => {
  const { from, to } = await c.req.json<{ from?: string; to?: string }>();
  if (!from || !to) return c.json({ ok: false, error: "Send 'from' and 'to'." }, 400);
  try {
    await workspace.renameTask(from, to);
    history.renameTask(from, to, await workspace.readFile(to), Date.now());
    return c.json({ ok: true });
  } catch (error) {
    return friendlyError(c, error);
  }
});

/** Run history for one task, newest first. */
app.get("/api/runs", (c) => {
  const path = c.req.query("path");
  if (!path) return c.json({ ok: false, error: "Missing 'path'." }, 400);
  return c.json({ ok: true, runs: history.listRuns(path) });
});

/** Aggregate run counts per task, for the task grid. */
app.get("/api/usage", (c) => c.json({ ok: true, usage: history.listUsage() }));

/** Change history for one task (summaries only), newest first. */
app.get("/api/snapshots", (c) => {
  const path = c.req.query("path");
  if (!path) return c.json({ ok: false, error: "Missing 'path'." }, 400);
  return c.json({ ok: true, snapshots: history.listSnapshots(path) });
});

/** One snapshot with content + the content it replaced, for the diff view. */
app.get("/api/snapshot", (c) => {
  const id = Number(c.req.query("id"));
  if (!Number.isInteger(id)) return c.json({ ok: false, error: "Missing 'id'." }, 400);
  const snapshot = history.getSnapshot(id);
  if (!snapshot) return c.json({ ok: false, error: "That version no longer exists." }, 404);
  return c.json({ ok: true, ...snapshot });
});

/** Write a snapshot's content back to its task file. */
app.post("/api/restore", async (c) => {
  const { id } = await c.req.json<{ id?: number }>();
  if (typeof id !== "number") return c.json({ ok: false, error: "Missing 'id'." }, 400);
  const snapshot = history.getSnapshot(id);
  if (!snapshot) return c.json({ ok: false, error: "That version no longer exists." }, 404);
  try {
    await workspace.writeFile(snapshot.record.taskPath, snapshot.content);
    history.recordSnapshot(snapshot.record.taskPath, "restored", snapshot.content, Date.now());
    return c.json({ ok: true, path: snapshot.record.taskPath });
  } catch (error) {
    return friendlyError(c, error);
  }
});

/**
 * Run a task file. Streams NDJSON: one RunEvent per line, so the UI can show
 * progress live.
 */
app.post("/api/runs", async (c) => {
  const { path, inputs = {} } = await c.req.json<{
    path?: string;
    inputs?: Record<string, string>;
  }>();
  if (!path) return c.json({ ok: false, error: "Missing 'path'." }, 400);

  let task;
  try {
    task = await workspace.loadTask(path);
  } catch (error) {
    return friendlyError(c, error);
  }

  // Every {{placeholder}} in the instructions needs a value before the run.
  const placeholders = extractPlaceholders(task.instructions);
  const missing = placeholders.filter((name) => !inputs[name]?.trim());
  if (missing.length > 0) {
    const labels = missing.map((name) => `"${placeholderLabel(name)}"`).join(", ");
    return c.json({ ok: false, error: `This task still needs ${labels} filled in.` }, 422);
  }
  const runInputs =
    placeholders.length > 0
      ? Object.fromEntries(placeholders.map((name) => [name, inputs[name]!]))
      : null;
  task = { ...task, instructions: fillPlaceholders(task.instructions, inputs) };

  c.header("Content-Type", "application/x-ndjson; charset=utf-8");
  return stream(c, async (out) => {
    const write = (event: RunEvent) => out.write(JSON.stringify(event) + "\n");
    let started: Extract<RunEvent, { type: "run-started" }> | undefined;
    const record = (event: RunEvent) => {
      if (event.type === "run-started") started = event;
      if ((event.type !== "run-completed" && event.type !== "run-failed") || !started) return;
      const completed = event.type === "run-completed" ? event : null;
      history.recordRun({
        id: event.runId,
        taskPath: path,
        startedAt: started.at,
        finishedAt: event.at,
        status: completed ? "succeeded" : "failed",
        model: started.model,
        inputTokens: completed?.usage?.inputTokens ?? null,
        outputTokens: completed?.usage?.outputTokens ?? null,
        output: completed?.text ?? null,
        error: event.type === "run-failed" ? event.error : null,
        inputs: runInputs,
      });
    };
    try {
      await runTask(task, {
        onEvent: (event) => {
          record(event);
          void write(event);
        },
        model: offline ? createScriptedModel() : undefined,
      });
    } catch {
      // The run-failed event already went out on the stream.
    }
  });
});

/**
 * Everything that isn't /api/* is the web app: serve the Vite build from
 * apps/web/dist, falling back to index.html (SPA) or a build hint in dev.
 */
const webDist = new URL("../../web/dist/", import.meta.url).pathname;
app.get("*", async (c) => {
  const path = c.req.path === "/" ? "index.html" : c.req.path.slice(1);
  if (!path.includes("..")) {
    const file = Bun.file(webDist + path);
    if (await file.exists()) return new Response(file);
  }
  const index = Bun.file(webDist + "index.html");
  if (await index.exists()) {
    return new Response(index, { headers: { "content-type": "text/html; charset=utf-8" } });
  }
  return c.text(
    "Web UI not built yet. Run `bun run build`, or use the Vite dev server: `bun run dev` and open http://localhost:5173",
    404,
  );
});

function friendlyError(c: any, error: unknown) {
  if (error instanceof TaskParseError) {
    return c.json({ ok: false, error: error.message }, 422);
  }
  console.error(error);
  return c.json({ ok: false, error: "Something went wrong." }, 500);
}

const port = Number(process.env.PORT ?? 8787);
console.log(
  `pecto listening on http://localhost:${port} — workspace: ${workspace.root}${offline ? " (offline model — set ANTHROPIC_API_KEY for real runs)" : ""}`,
);

export default { port, fetch: app.fetch, idleTimeout: 120 };

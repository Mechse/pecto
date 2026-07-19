import type { RunEvent, RunRecord, SnapshotRecord, TaskUsage, TreeTask } from "@pecto/core";

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, init);
  const data = await res.json();
  if (!data.ok) throw new Error(data.error ?? "Something went wrong.");
  return data as T;
}

const json = (body: unknown, method = "POST"): RequestInit => ({
  method,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

export const getStatus = () => api<{ offline: boolean }>("/api/status");

export const getTree = () => api<{ tasks: TreeTask[] }>("/api/tree");

export const getFile = (path: string) =>
  api<{ content: string }>(`/api/file?path=${encodeURIComponent(path)}`);

export const saveFile = (path: string, content: string) =>
  api("/api/file", json({ path, content }, "PUT"));

export const createTask = (path: string) => api("/api/files", json({ path }));

export const deleteTask = (path: string) =>
  api(`/api/file?path=${encodeURIComponent(path)}`, { method: "DELETE" });

export const renameTask = (from: string, to: string) =>
  api("/api/rename", json({ from, to }));

export const getRuns = (path: string) =>
  api<{ runs: RunRecord[] }>(`/api/runs?path=${encodeURIComponent(path)}`);

export const getUsage = () => api<{ usage: TaskUsage[] }>("/api/usage");

export const getSnapshots = (path: string) =>
  api<{ snapshots: SnapshotRecord[] }>(`/api/snapshots?path=${encodeURIComponent(path)}`);

export const getSnapshot = (id: number) =>
  api<{ record: SnapshotRecord; content: string; prevContent: string }>(`/api/snapshot?id=${id}`);

export const restoreSnapshot = (id: number) => api<{ path: string }>("/api/restore", json({ id }));

/** POST /api/runs and feed each NDJSON RunEvent to the callback as it arrives. */
export async function streamRun(
  path: string,
  inputs: Record<string, string>,
  onEvent: (event: RunEvent) => void,
): Promise<void> {
  const res = await fetch("/api/runs", json({ path, inputs }));
  if (!res.headers.get("content-type")?.includes("ndjson") || !res.body) {
    const data = await res.json().catch(() => null);
    throw new Error(data?.error ?? "Something went wrong.");
  }
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";
    for (const line of lines) {
      if (line.trim()) onEvent(JSON.parse(line) as RunEvent);
    }
  }
}

export const slugify = (text: string) =>
  text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

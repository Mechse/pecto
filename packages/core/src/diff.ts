export interface DiffLine {
  type: "same" | "added" | "removed";
  text: string;
}

/**
 * Line-based LCS diff. Task files are small, so the O(n·m) table is fine —
 * shared by the server (change summaries) and the web app (diff view).
 */
export function diffLines(before: string, after: string): DiffLine[] {
  const a = before.split("\n");
  const b = after.split("\n");
  const m = a.length;
  const n = b.length;
  const lcs: Uint32Array[] = Array.from({ length: m + 1 }, () => new Uint32Array(n + 1));
  for (let i = m - 1; i >= 0; i--) {
    for (let j = n - 1; j >= 0; j--) {
      lcs[i]![j] =
        a[i] === b[j] ? lcs[i + 1]![j + 1]! + 1 : Math.max(lcs[i + 1]![j]!, lcs[i]![j + 1]!);
    }
  }
  const out: DiffLine[] = [];
  let i = 0;
  let j = 0;
  while (i < m && j < n) {
    if (a[i] === b[j]) {
      out.push({ type: "same", text: a[i]! });
      i++;
      j++;
    } else if (lcs[i + 1]![j]! >= lcs[i]![j + 1]!) {
      out.push({ type: "removed", text: a[i]! });
      i++;
    } else {
      out.push({ type: "added", text: b[j]! });
      j++;
    }
  }
  while (i < m) out.push({ type: "removed", text: a[i++]! });
  while (j < n) out.push({ type: "added", text: b[j++]! });
  return out;
}

/** Added/removed line counts between two versions. */
export function diffCounts(before: string, after: string): { added: number; removed: number } {
  let added = 0;
  let removed = 0;
  for (const line of diffLines(before, after)) {
    if (line.type === "added") added++;
    else if (line.type === "removed") removed++;
  }
  return { added, removed };
}

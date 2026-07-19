import { EditorSelection, type ChangeSpec, type EditorState, type Line } from "@codemirror/state";
import type { EditorView } from "@codemirror/view";

/** Wrap the selection in `marker` (e.g. `**`, `*`, `~~`, `` ` ``), or unwrap if already wrapped. */
export function toggleWrap(view: EditorView, marker: string): boolean {
  const len = marker.length;
  view.dispatch(
    view.state.changeByRange((range) => {
      const { from, to } = range;
      const state = view.state;
      const text = state.sliceDoc(from, to);
      const before = state.sliceDoc(Math.max(0, from - len), from);
      const after = state.sliceDoc(to, Math.min(state.doc.length, to + len));
      if (before === marker && after === marker) {
        return {
          changes: [
            { from: from - len, to: from },
            { from: to, to: to + len },
          ],
          range: EditorSelection.range(from - len, to - len),
        };
      }
      if (text.length >= 2 * len && text.startsWith(marker) && text.endsWith(marker)) {
        return {
          changes: { from, to, insert: text.slice(len, -len) },
          range: EditorSelection.range(from, to - 2 * len),
        };
      }
      return {
        changes: [
          { from, insert: marker },
          { from: to, insert: marker },
        ],
        range: EditorSelection.range(from + len, to + len),
      };
    }),
  );
  view.focus();
  return true;
}

function selectedLines(state: EditorState): Line[] {
  const lines: Line[] = [];
  for (const range of state.selection.ranges) {
    const first = state.doc.lineAt(range.from).number;
    const last = state.doc.lineAt(range.to).number;
    for (let n = first; n <= last; n++) {
      const line = state.doc.line(n);
      if (!lines.some((l) => l.number === line.number)) lines.push(line);
    }
  }
  return lines;
}

/** Dispatch line-start changes; the selection maps through automatically. */
function dispatchLineChanges(view: EditorView, changes: ChangeSpec[]): boolean {
  if (changes.length) view.dispatch({ changes });
  view.focus();
  return true;
}

/** Add `prefix` (e.g. `- `) to the selected lines, or remove it if every non-empty line has it. */
export function toggleLinePrefix(view: EditorView, prefix: string): boolean {
  const lines = selectedLines(view.state).filter((l) => l.text.length > 0);
  if (!lines.length) return dispatchLineChanges(view, [{ from: view.state.selection.main.head, insert: prefix }]);
  const allPrefixed = lines.every((l) => l.text.startsWith(prefix));
  return dispatchLineChanges(
    view,
    lines.map((l) =>
      allPrefixed ? { from: l.from, to: l.from + prefix.length } : { from: l.from, insert: prefix },
    ),
  );
}

const ORDERED = /^\d+\.\s/;

/** Number the selected lines `1. `, `2. `, …, or strip the numbers if already numbered. */
export function toggleOrderedList(view: EditorView): boolean {
  const lines = selectedLines(view.state).filter((l) => l.text.length > 0);
  if (!lines.length) return dispatchLineChanges(view, [{ from: view.state.selection.main.head, insert: "1. " }]);
  const allNumbered = lines.every((l) => ORDERED.test(l.text));
  return dispatchLineChanges(
    view,
    lines.map((l, i) =>
      allNumbered
        ? { from: l.from, to: l.from + l.text.match(ORDERED)![0].length }
        : { from: l.from, insert: `${i + 1}. ` },
    ),
  );
}

const HEADING = /^(#{1,6})\s/;

/** Cycle the selected lines' heading level: none → # → ## → ### → none. */
export function cycleHeading(view: EditorView): boolean {
  const lines = selectedLines(view.state);
  const current = lines[0]?.text.match(HEADING)?.[1].length ?? 0;
  const next = current >= 3 ? 0 : current + 1;
  const prefix = next ? `${"#".repeat(next)} ` : "";
  return dispatchLineChanges(
    view,
    lines.map((l) => ({ from: l.from, to: l.from + (l.text.match(HEADING)?.[0].length ?? 0), insert: prefix })),
  );
}

/** Turn the selection into a link: `text` → `[text](url)` with `url` selected for typing over. */
export function insertLink(view: EditorView): boolean {
  view.dispatch(
    view.state.changeByRange((range) => {
      const text = view.state.sliceDoc(range.from, range.to);
      return {
        changes: { from: range.from, to: range.to, insert: `[${text}](url)` },
        range: text
          ? EditorSelection.range(range.from + text.length + 3, range.from + text.length + 6)
          : EditorSelection.cursor(range.from + 1),
      };
    }),
  );
  view.focus();
  return true;
}

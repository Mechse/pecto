import { useEffect, useRef } from "react";
import { EditorState, RangeSetBuilder, Transaction } from "@codemirror/state";
import { Decoration, EditorView, keymap, ViewPlugin, type DecorationSet, type ViewUpdate } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags } from "@lezer/highlight";
import { EditorToolbar } from "@/components/editor-toolbar";
import { toggleWrap } from "@/lib/markdown-commands";

const theme = EditorView.theme(
  {
    "&": { height: "100%", fontSize: "16px", backgroundColor: "transparent" },
    ".cm-scroller": { fontFamily: "var(--font-sans)", lineHeight: "1.7", overflow: "auto" },
    ".cm-content": { padding: "1.25rem 1.75rem", caretColor: "var(--foreground)" },
    "&.cm-focused": { outline: "none" },
    ".cm-frontmatter": { color: "var(--muted-foreground)", fontSize: "14px", fontFamily: "var(--font-mono)" },
    ".cm-frontmatter span": { color: "inherit", fontWeight: "400", fontSize: "inherit", fontFamily: "inherit" },
  },
  { dark: true },
);

const frontmatterLine = Decoration.line({ class: "cm-frontmatter" });

/**
 * Mark the leading `---` frontmatter block so it reads as muted metadata.
 * Without this, CommonMark parses `name: …` followed by `---` as a setext heading.
 */
function frontmatterDecorations(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const doc = view.state.doc;
  if (doc.lines >= 2 && doc.line(1).text === "---") {
    let close = 0;
    for (let n = 2; n <= Math.min(doc.lines, 50); n++) {
      if (doc.line(n).text === "---") {
        close = n;
        break;
      }
    }
    for (let n = 1; n <= close; n++) builder.add(doc.line(n).from, doc.line(n).from, frontmatterLine);
  }
  return builder.finish();
}

const frontmatter = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = frontmatterDecorations(view);
    }
    update(update: ViewUpdate) {
      if (update.docChanged) this.decorations = frontmatterDecorations(update.view);
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

const mdHighlight = HighlightStyle.define([
  { tag: tags.heading1, fontWeight: "600", fontSize: "1.35em" },
  { tag: tags.heading2, fontWeight: "600", fontSize: "1.15em" },
  { tag: tags.heading, fontWeight: "600" },
  { tag: tags.strong, fontWeight: "700" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  { tag: tags.link, color: "var(--muted-foreground)", textDecoration: "underline" },
  { tag: tags.url, color: "var(--muted-foreground)" },
  { tag: tags.monospace, fontFamily: "var(--font-mono)", fontSize: "0.9em" },
  { tag: tags.quote, color: "var(--muted-foreground)" },
  { tag: tags.processingInstruction, color: "var(--muted-foreground)" },
  { tag: tags.meta, color: "var(--muted-foreground)" },
  { tag: tags.contentSeparator, color: "var(--muted-foreground)" },
]);

/**
 * Markdown source editor (CodeMirror) inside the elevated card, toolbar on top.
 * Callers should key this component by file path so switching files resets undo history.
 */
export function MarkdownEditor({ value, onChange }: { value: string; onChange: (doc: string) => void }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const viewRef = useRef<EditorView | null>(null);

  // The update listener must read the latest onChange through a ref — extensions
  // are created once and would otherwise capture the first render's closure.
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;
  const initialValueRef = useRef(value);

  useEffect(() => {
    const view = new EditorView({
      state: EditorState.create({
        doc: initialValueRef.current,
        extensions: [
          history(),
          markdown(),
          EditorView.lineWrapping,
          // ⌘S is intentionally not bound here: App's document-level listener
          // catches it via bubbling; binding it in CM would double-save.
          keymap.of([
            { key: "Mod-b", run: (v) => toggleWrap(v, "**") },
            { key: "Mod-i", run: (v) => toggleWrap(v, "*") },
            ...historyKeymap,
            ...defaultKeymap,
          ]),
          syntaxHighlighting(mdHighlight),
          frontmatter,
          theme,
          EditorView.updateListener.of((update) => {
            if (update.docChanged) onChangeRef.current(update.state.doc.toString());
          }),
        ],
      }),
      parent: containerRef.current!,
    });
    viewRef.current = view;
    return () => {
      view.destroy();
      viewRef.current = null;
    };
  }, []);

  // External value changes (file loaded/reverted) replace the doc; after local
  // keystrokes value === doc, so this no-ops and the view is never recreated.
  useEffect(() => {
    const view = viewRef.current;
    if (!view) return;
    const doc = view.state.doc.toString();
    if (value !== doc) {
      // Not undoable: otherwise ⌘Z past the user's own edits would undo the
      // file load itself, leaving an empty doc that ⌘S then saves.
      view.dispatch({
        changes: { from: 0, to: doc.length, insert: value },
        annotations: Transaction.addToHistory.of(false),
      });
    }
  }, [value]);

  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
      <EditorToolbar getView={() => viewRef.current} />
      <div ref={containerRef} className="min-h-0 flex-1 overflow-hidden" />
    </div>
  );
}

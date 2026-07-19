import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { History, Loader2, Pencil, Play, Save, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { extractPlaceholders, type RunEvent, type TreeTask } from "@pecto/core";
import { HistoryPanel } from "@/components/history-panel";
import { MarkdownEditor } from "@/components/markdown-editor";
import { NameInput } from "@/components/name-input";
import { RunView } from "@/components/run-view";
import { Sidebar } from "@/components/sidebar";
import { TaskGrid } from "@/components/task-grid";
import { Button } from "@/components/ui/button";
import { deleteTask, getFile, getRuns, getStatus, getTree, renameTask, saveFile, streamRun } from "@/lib/api";
import { cn } from "@/lib/utils";

interface Selection {
  path: string;
  title: string;
  desc: string;
}

type View = "edit" | "run";

/** The frontmatter block at the top of a task file, for placeholder scanning. */
const FRONTMATTER_BLOCK = /^\s*---\r?\n[\s\S]*?\r?\n---\r?\n?/;

export default function App() {
  const queryClient = useQueryClient();
  const status = useQuery({ queryKey: ["status"], queryFn: getStatus });
  const tree = useQuery({ queryKey: ["tree"], queryFn: getTree });

  const [selected, setSelected] = useState<Selection | null>(null);
  const [view, setView] = useState<View>("edit");
  const [renaming, setRenaming] = useState(false);
  const [draft, setDraft] = useState("");
  const [dirty, setDirty] = useState(false);
  const [inputValues, setInputValues] = useState<Record<string, string>>({});
  const [runEvents, setRunEvents] = useState<RunEvent[]>([]);
  const [running, setRunning] = useState(false);
  const [historyOpen, setHistoryOpen] = useState(() => localStorage.getItem("pecto:history-open") === "1");

  function toggleHistory() {
    setHistoryOpen((open) => {
      localStorage.setItem("pecto:history-open", open ? "0" : "1");
      return !open;
    });
  }

  const file = useQuery({
    queryKey: ["file", selected?.path],
    queryFn: () => getFile(selected!.path),
    enabled: selected !== null,
  });
  useEffect(() => {
    if (file.data) {
      setDraft(file.data.content);
      setDirty(false);
    }
  }, [file.data]);

  function selectTask(task: TreeTask, mode: View = "edit") {
    setRenaming(false);
    setRunEvents([]);
    setInputValues({});
    setView(mode);
    setSelected({
      path: task.path,
      title: task.name ?? task.path,
      desc: task.error ?? task.description ?? "",
    });
  }

  // The task's variables come straight from the (possibly unsaved) draft.
  const placeholders = selected ? extractPlaceholders(draft.replace(FRONTMATTER_BLOCK, "")) : [];
  const missingInputs = placeholders.some((name) => !inputValues[name]?.trim());

  // Prefill the run form with the values from the task's most recent run.
  const runs = useQuery({
    queryKey: ["runs", selected?.path],
    queryFn: () => getRuns(selected!.path),
    enabled: selected !== null,
  });
  const prefilledFor = useRef<string | null>(null);
  useEffect(() => {
    if (!selected || !runs.data || prefilledFor.current === selected.path) return;
    prefilledFor.current = selected.path;
    const lastWithInputs = runs.data.runs.find((r) => r.inputs);
    // Anything the user already typed wins over the prefill.
    if (lastWithInputs?.inputs) setInputValues((prev) => ({ ...lastWithInputs.inputs, ...prev }));
  }, [selected, runs.data]);

  /** Refetch the tree, then select the task at `path` (used after create/rename). */
  async function selectPath(path: string) {
    await queryClient.invalidateQueries({ queryKey: ["tree"] });
    const { tasks } = await queryClient.fetchQuery({ queryKey: ["tree"], queryFn: getTree });
    const task = tasks.find((t) => t.path === path);
    if (task) return selectTask(task);
    setSelected(null);
  }

  const save = useMutation({
    mutationFn: () => saveFile(selected!.path, draft),
    onSuccess: () => {
      setDirty(false);
      void queryClient.invalidateQueries({ queryKey: ["tree"] });
      void queryClient.invalidateQueries({ queryKey: ["snapshots"] });
    },
    onError: (error) => toast.error(error.message),
  });

  const remove = useMutation({
    mutationFn: () => deleteTask(selected!.path),
    onSuccess: () => {
      setSelected(null);
      void queryClient.invalidateQueries({ queryKey: ["tree"] });
    },
    onError: (error) => toast.error(error.message),
  });

  const rename = useMutation({
    mutationFn: (input: { from: string; to: string }) => renameTask(input.from, input.to),
    onSuccess: (_data, input) => {
      queryClient.removeQueries({ queryKey: ["file", input.from] });
      void selectPath(input.to);
    },
    onError: (error) => toast.error(error.message),
  });

  /**
   * The header Run Task button: always lands in the Run view, saving the draft
   * first if needed. Starts the run right away unless a variable still needs a
   * value — then the form (with its focused empty field) is the next step.
   */
  async function run() {
    if (!selected || running) return;
    if (dirty) await save.mutateAsync();
    setView("run");
    if (missingInputs) return;
    setRunEvents([]);
    setRunning(true);
    try {
      await streamRun(selected.path, inputValues, (event) => setRunEvents((prev) => [...prev, event]));
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Something went wrong.");
    } finally {
      setRunning(false);
      void queryClient.invalidateQueries({ queryKey: ["runs"] });
      void queryClient.invalidateQueries({ queryKey: ["usage"] });
    }
  }

  /** A restored version changed the file on disk — refetch everything that shows it. */
  function onRestored(path: string) {
    void queryClient.invalidateQueries({ queryKey: ["file", path] });
    void queryClient.invalidateQueries({ queryKey: ["snapshots", path] });
    void queryClient.invalidateQueries({ queryKey: ["tree"] });
  }

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "s") {
        e.preventDefault();
        if (selected && dirty) save.mutate();
      }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  });

  function submitRename(slug: string) {
    if (!selected) return;
    setRenaming(false);
    const to = `${slug}.md`;
    if (to !== selected.path) rename.mutate({ from: selected.path, to });
  }

  const runState = running
    ? "running"
    : runEvents.some((e) => e.type === "run-failed")
      ? "failed"
      : runEvents.some((e) => e.type === "run-completed")
        ? "succeeded"
        : "idle";

  return (
    <div className="relative h-screen overflow-hidden text-[15px]">
      <Aurora state={runState} />
      <div
        className={cn(
          "relative z-10 grid h-full grid-cols-1 gap-4 p-4",
          selected && historyOpen
            ? "max-md:grid-rows-[auto_minmax(0,1fr)_auto] md:grid-cols-[272px_minmax(0,1fr)_320px]"
            : "max-md:grid-rows-[auto_minmax(0,1fr)] md:grid-cols-[272px_minmax(0,1fr)]",
        )}
      >
        <Sidebar
          tasks={tree.data?.tasks ?? []}
          offline={status.data?.offline ?? false}
          selectedPath={selected?.path ?? null}
          onSelect={selectTask}
          onCreated={(path) => void selectPath(path)}
        />
        <main className="glass flex min-w-0 flex-col overflow-hidden rounded-2xl">
          <header className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b px-7 py-4">
            <div className="min-w-0 flex-1 basis-56">
              <h1 className="truncate font-heading text-2xl font-bold tracking-tight">
                {selected && renaming ? (
                  <NameInput
                    className="h-9 w-72 font-sans text-lg font-normal"
                    placeholder="new name"
                    initial={selected.path.replace(/\.md$/, "")}
                    onSubmit={submitRename}
                    onCancel={() => setRenaming(false)}
                  />
                ) : (
                  (selected?.title ?? "Welcome")
                )}
              </h1>
              <p className="truncate text-[13px] text-muted-foreground">
                {selected ? selected.desc : "Run a task directly, or select one to edit."}
              </p>
            </div>
            {selected && (
              <>
                <div className="flex rounded-lg bg-accent/40 p-0.5">
                  {(["edit", "run"] as const).map((mode) => (
                    <button
                      key={mode}
                      type="button"
                      aria-pressed={view === mode}
                      onClick={() => setView(mode)}
                      className={cn(
                        "rounded-md px-3 py-1 text-[13px] font-medium text-muted-foreground transition-colors hover:text-foreground",
                        view === mode && "bg-accent text-primary hover:text-primary",
                      )}
                    >
                      {mode === "edit" ? "Edit" : "Run"}
                    </button>
                  ))}
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  aria-pressed={historyOpen}
                  className={historyOpen ? "bg-accent text-primary hover:text-primary" : ""}
                  onClick={toggleHistory}
                >
                  <History /> History
                </Button>
                <Button variant="ghost" size="sm" onClick={() => setRenaming(true)}>
                  <Pencil /> Rename
                </Button>
                <DeleteButton key={selected.path} onDelete={() => remove.mutate()} />
                <Button variant="ghost" size="sm" disabled={!dirty || save.isPending} onClick={() => save.mutate()}>
                  <Save /> Save
                </Button>
                <Button
                  size="sm"
                  className="shadow-[0_0_20px_-8px_var(--primary)]"
                  disabled={running || (view === "run" && missingInputs)}
                  onClick={() => void run()}
                >
                  {running ? <Loader2 className="animate-spin" /> : <Play />}
                  Run Task
                </Button>
              </>
            )}
          </header>
          <div className="flex min-h-0 flex-1 flex-col">
            {selected ? (
              view === "edit" ? (
                <div className="flex min-h-0 flex-1 flex-col">
                  <MarkdownEditor
                    key={selected.path}
                    value={draft}
                    onChange={(doc) => {
                      setDraft(doc);
                      setDirty(true);
                    }}
                  />
                </div>
              ) : (
                <RunView
                  key={selected.path}
                  placeholders={placeholders}
                  values={inputValues}
                  onChange={(name, value) => setInputValues((prev) => ({ ...prev, [name]: value }))}
                  events={runEvents}
                />
              )
            ) : (
              <TaskGrid
                tasks={tree.data?.tasks ?? []}
                onSelect={selectTask}
                onOpenRun={(task) => selectTask(task, "run")}
              />
            )}
          </div>
        </main>
        {selected && historyOpen && <HistoryPanel key={selected.path} path={selected.path} onRestored={onRestored} />}
      </div>
    </div>
  );
}

/**
 * The ambient light world behind the glass. Also the run-state instrument:
 * `state` tints the bottom glow — breathing aqua while running, mint on
 * success, coral on failure (see .aurora-status in index.css).
 */
function Aurora({ state }: { state: string }) {
  return (
    <div aria-hidden className="aurora" data-run={state}>
      <div className="aurora-blob aurora-blob-a" />
      <div className="aurora-blob aurora-blob-b" />
      <div className="aurora-blob aurora-blob-c" />
      <div className="aurora-status" />
    </div>
  );
}

/** Delete with an in-place confirm: first click arms it, second click deletes. */
function DeleteButton({ onDelete }: { onDelete: () => void }) {
  const [armed, setArmed] = useState(false);
  useEffect(() => {
    if (!armed) return;
    const timer = setTimeout(() => setArmed(false), 3000);
    return () => clearTimeout(timer);
  }, [armed]);
  return (
    <Button
      variant="ghost"
      size="sm"
      className={armed ? "bg-destructive/10 text-destructive hover:text-destructive" : ""}
      onClick={() => (armed ? onDelete() : setArmed(true))}
    >
      <Trash2 /> {armed ? "Really delete?" : "Delete"}
    </Button>
  );
}

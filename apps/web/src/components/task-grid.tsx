import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { FileText, Loader2, Play, TriangleAlert } from "lucide-react";
import { toast } from "sonner";
import type { RunEvent, TreeTask } from "@pecto/core";
import { Button } from "@/components/ui/button";
import { getUsage, streamRun } from "@/lib/api";
import { cn } from "@/lib/utils";

/**
 * The empty-state grid: every task as a card, most-run first, each with a
 * quick Run button that streams the run inline on the card — no need to open
 * the editor. Tasks with `{{variables}}` open in the Run view instead, where
 * their fields can be filled in.
 */
export function TaskGrid({
  tasks,
  onSelect,
  onOpenRun,
}: {
  tasks: TreeTask[];
  onSelect: (task: TreeTask) => void;
  onOpenRun: (task: TreeTask) => void;
}) {
  const queryClient = useQueryClient();
  const usageQuery = useQuery({ queryKey: ["usage"], queryFn: getUsage });
  const usage = new Map((usageQuery.data?.usage ?? []).map((u) => [u.taskPath, u]));

  const [runs, setRuns] = useState<Record<string, { running: boolean; events: RunEvent[] }>>({});

  const sorted = [...tasks].sort((a, b) => {
    const diff = (usage.get(b.path)?.runCount ?? 0) - (usage.get(a.path)?.runCount ?? 0);
    return diff !== 0 ? diff : (a.name ?? a.path).localeCompare(b.name ?? b.path);
  });

  async function runInline(path: string) {
    if (runs[path]?.running) return;
    setRuns((prev) => ({ ...prev, [path]: { running: true, events: [] } }));
    try {
      await streamRun(path, {}, (event) =>
        setRuns((prev) => ({ ...prev, [path]: { ...prev[path]!, events: [...prev[path]!.events, event] } })),
      );
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Something went wrong.");
    } finally {
      setRuns((prev) => ({ ...prev, [path]: { ...prev[path]!, running: false } }));
      void queryClient.invalidateQueries({ queryKey: ["usage"] });
      void queryClient.invalidateQueries({ queryKey: ["runs", path] });
    }
  }

  return (
    <div className="grid min-h-0 flex-1 auto-rows-min grid-cols-[repeat(auto-fill,minmax(240px,1fr))] content-start gap-3 overflow-y-auto p-6">
      {sorted.map((t) => (
        <TaskCard
          key={t.path}
          task={t}
          runCount={usage.get(t.path)?.runCount ?? 0}
          run={runs[t.path]}
          onOpen={() => onSelect(t)}
          onRun={() => (t.placeholders?.length ? onOpenRun(t) : void runInline(t.path))}
        />
      ))}
    </div>
  );
}

function TaskCard({
  task,
  runCount,
  run,
  onOpen,
  onRun,
}: {
  task: TreeTask;
  runCount: number;
  run?: { running: boolean; events: RunEvent[] };
  onOpen: () => void;
  onRun: () => void;
}) {
  const completed = run?.events.find((e) => e.type === "run-completed");
  const failed = run?.events.find((e) => e.type === "run-failed");
  const running = !!run?.running;

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onOpen}
      onKeyDown={(e) => {
        if (e.key === "Enter" && e.target === e.currentTarget) onOpen();
      }}
      className="flex cursor-pointer flex-col rounded-xl border bg-card p-4 text-left transition-colors hover:bg-accent/50"
    >
      <div className="flex items-center gap-2">
        {task.error ? (
          <TriangleAlert className="size-3.5 flex-none text-destructive" />
        ) : (
          <FileText className="size-3.5 flex-none text-muted-foreground" />
        )}
        <span className="truncate text-sm font-medium">{task.name ?? task.path}</span>
      </div>
      <p className="mt-1.5 line-clamp-2 min-h-9 text-[13px]/[1.4] text-muted-foreground">
        {task.error ?? task.description}
      </p>
      <div className="mt-3 flex items-center justify-between gap-2">
        <span className="font-mono text-[11px] text-muted-foreground/70">
          {runCount === 0 ? "Never run" : runCount === 1 ? "1 run" : `${runCount} runs`}
        </span>
        <Button
          size="sm"
          disabled={!!task.error || running}
          onClick={(e) => {
            e.stopPropagation();
            onRun();
          }}
        >
          {running ? <Loader2 className="animate-spin" /> : <Play />}
          Run Task
        </Button>
      </div>
      {run && (
        <div className="mt-3 border-t pt-2.5">
          <div className="flex items-center gap-2 text-[12px] text-muted-foreground">
            <span
              className={cn(
                "size-1.5 flex-none rounded-full",
                completed
                  ? "bg-success shadow-[0_0_8px_var(--success)]"
                  : failed
                    ? "bg-destructive shadow-[0_0_8px_var(--destructive)]"
                    : "animate-pulse bg-primary shadow-[0_0_8px_var(--primary)]",
              )}
            />
            {running ? "Running…" : failed ? "Failed" : completed ? "Done" : "Starting…"}
          </div>
          {failed && <p className="mt-1.5 line-clamp-3 text-[13px] text-destructive">{failed.error}</p>}
          {completed && (
            <p className="mt-1.5 line-clamp-3 text-[13px]/[1.5] whitespace-pre-wrap">{completed.text}</p>
          )}
        </div>
      )}
    </div>
  );
}

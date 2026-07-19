import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { ChevronDown, Loader2, RotateCcw } from "lucide-react";
import { toast } from "sonner";
import { diffLines, placeholderLabel, type RunRecord, type SnapshotRecord } from "@pecto/core";
import { Button } from "@/components/ui/button";
import { getRuns, getSnapshot, getSnapshots, restoreSnapshot } from "@/lib/api";
import { cn } from "@/lib/utils";

type Tab = "runs" | "changes";

/**
 * The right-hand history pane for the selected task: past runs (when, how
 * long, token burn, output) and past changes (snapshots with diffs + restore).
 */
export function HistoryPanel({ path, onRestored }: { path: string; onRestored: (path: string) => void }) {
  const [tab, setTab] = useState<Tab>("runs");

  return (
    <aside className="glass flex min-h-0 flex-col overflow-hidden rounded-2xl max-md:max-h-72">
      <div className="flex gap-1 border-b p-2">
        <TabButton active={tab === "runs"} onClick={() => setTab("runs")}>
          Runs
        </TabButton>
        <TabButton active={tab === "changes"} onClick={() => setTab("changes")}>
          Changes
        </TabButton>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto px-3 py-3">
        {tab === "runs" ? <RunList path={path} /> : <ChangeList path={path} onRestored={onRestored} />}
      </div>
    </aside>
  );
}

function TabButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex-1 rounded-lg px-3 py-1.5 text-[13px] font-medium text-muted-foreground hover:bg-accent hover:text-accent-foreground",
        active && "bg-accent text-accent-foreground",
      )}
    >
      {children}
    </button>
  );
}

const timestamp = (at: number) =>
  new Date(at).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

/* ---- Runs tab ---------------------------------------------------------- */

function RunList({ path }: { path: string }) {
  const runs = useQuery({ queryKey: ["runs", path], queryFn: () => getRuns(path) });
  const [expanded, setExpanded] = useState<string | null>(null);

  if (runs.isPending) return <PaneHint>Loading…</PaneHint>;
  if (!runs.data?.runs.length) return <PaneHint>No runs yet — hit Run Task and it will show up here.</PaneHint>;

  return (
    <ul className="flex flex-col gap-1.5">
      {runs.data.runs.map((run) => (
        <RunEntry key={run.id} run={run} open={expanded === run.id} onToggle={() => setExpanded(expanded === run.id ? null : run.id)} />
      ))}
    </ul>
  );
}

function RunEntry({ run, open, onToggle }: { run: RunRecord; open: boolean; onToggle: () => void }) {
  const seconds = ((run.finishedAt - run.startedAt) / 1000).toFixed(1);
  const tokens =
    run.inputTokens !== null || run.outputTokens !== null
      ? `${run.inputTokens ?? "?"} in · ${run.outputTokens ?? "?"} out`
      : null;

  return (
    <li className={cn("rounded-xl hover:bg-accent/50", open && "bg-accent/50")}>
      <button type="button" aria-expanded={open} onClick={onToggle} className="w-full px-2.5 py-2 text-left">
        <span className="flex items-center gap-2 text-[13px]">
          <span
            className={cn(
              "size-1.5 flex-none rounded-full",
              run.status === "succeeded"
                ? "bg-success shadow-[0_0_8px_var(--success)]"
                : "bg-destructive shadow-[0_0_8px_var(--destructive)]",
            )}
          />
          <span className="text-foreground">{timestamp(run.startedAt)}</span>
          <span className="ml-auto font-mono text-[11px] tabular-nums text-muted-foreground/80">{seconds}s</span>
          <ChevronDown className={cn("size-3 text-muted-foreground/60 transition-transform", open && "rotate-180")} />
        </span>
        <span className="mt-0.5 flex items-center gap-2 pl-3.5 font-mono text-[11px] text-muted-foreground/70">
          <span className="truncate">{run.model}</span>
          {tokens && <span className="ml-auto flex-none tabular-nums">{tokens} tok</span>}
        </span>
      </button>
      {open && (
        <div className="px-2.5 pb-2.5">
          {run.inputs && (
            <div className="flex flex-col gap-1.5 border-t pt-2 pb-2">
              {Object.entries(run.inputs).map(([name, value]) => (
                <div key={name}>
                  <div className="font-mono text-[10px] tracking-wide text-muted-foreground/70 uppercase">
                    {placeholderLabel(name)}
                  </div>
                  <div className="max-h-24 overflow-y-auto text-[12px]/[1.6] whitespace-pre-wrap text-muted-foreground">
                    {value}
                  </div>
                </div>
              ))}
            </div>
          )}
          {run.error ? (
            <div className="border-t pt-2 text-[12px]/[1.6] text-destructive">{run.error}</div>
          ) : (
            <div className="max-h-56 overflow-y-auto border-t pt-2 text-[12px]/[1.6] whitespace-pre-wrap">
              {run.output}
            </div>
          )}
        </div>
      )}
    </li>
  );
}

/* ---- Changes tab ------------------------------------------------------- */

const KIND_LABEL = { created: "Created", edited: "Edited", renamed: "Renamed", restored: "Restored" } as const;

function ChangeList({ path, onRestored }: { path: string; onRestored: (path: string) => void }) {
  const snapshots = useQuery({ queryKey: ["snapshots", path], queryFn: () => getSnapshots(path) });
  const [expanded, setExpanded] = useState<number | null>(null);

  if (snapshots.isPending) return <PaneHint>Loading…</PaneHint>;
  if (!snapshots.data?.snapshots.length) return <PaneHint>No changes recorded yet — saves land here.</PaneHint>;

  return (
    <ul className="flex flex-col gap-1.5">
      {snapshots.data.snapshots.map((snap, index) => (
        <ChangeEntry
          key={snap.id}
          snap={snap}
          latest={index === 0}
          open={expanded === snap.id}
          onToggle={() => setExpanded(expanded === snap.id ? null : snap.id)}
          onRestored={onRestored}
        />
      ))}
    </ul>
  );
}

function ChangeEntry({
  snap,
  latest,
  open,
  onToggle,
  onRestored,
}: {
  snap: SnapshotRecord;
  latest: boolean;
  open: boolean;
  onToggle: () => void;
  onRestored: (path: string) => void;
}) {
  return (
    <li className={cn("rounded-xl hover:bg-accent/50", open && "bg-accent/50")}>
      <button type="button" aria-expanded={open} onClick={onToggle} className="w-full px-2.5 py-2 text-left">
        <span className="flex items-center gap-2 text-[13px]">
          <span className="text-foreground">{KIND_LABEL[snap.kind]}</span>
          {snap.kind === "renamed" ? (
            <span className="truncate font-mono text-[11px] text-muted-foreground/70">from {snap.renamedFrom}</span>
          ) : (
            <span className="font-mono text-[11px] tabular-nums">
              <span className="text-success">+{snap.linesAdded}</span>{" "}
              <span className="text-destructive">−{snap.linesRemoved}</span>
            </span>
          )}
          <span className="ml-auto text-[11px] text-muted-foreground/80">{timestamp(snap.at)}</span>
          <ChevronDown className={cn("size-3 text-muted-foreground/60 transition-transform", open && "rotate-180")} />
        </span>
      </button>
      {open && <SnapshotDetail snap={snap} latest={latest} onRestored={onRestored} />}
    </li>
  );
}

function SnapshotDetail({
  snap,
  latest,
  onRestored,
}: {
  snap: SnapshotRecord;
  latest: boolean;
  onRestored: (path: string) => void;
}) {
  const detail = useQuery({ queryKey: ["snapshot", snap.id], queryFn: () => getSnapshot(snap.id) });
  const [armed, setArmed] = useState(false);

  const restore = useMutation({
    mutationFn: () => restoreSnapshot(snap.id),
    onSuccess: ({ path }) => {
      toast.success("Version restored.");
      onRestored(path);
    },
    onError: (error) => toast.error(error.message),
  });

  if (detail.isPending) {
    return (
      <div className="flex items-center gap-2 px-2.5 pb-2.5 text-[12px] text-muted-foreground">
        <Loader2 className="size-3 animate-spin" /> Loading…
      </div>
    );
  }
  if (!detail.data) return null;

  // The first snapshot has no predecessor — everything it contains is new.
  const lines =
    detail.data.prevContent === ""
      ? detail.data.content.split("\n").map((text) => ({ type: "added" as const, text }))
      : diffLines(detail.data.prevContent, detail.data.content);

  return (
    <div className="flex flex-col gap-2 px-2.5 pb-2.5">
      <div className="max-h-56 overflow-auto border-t py-1.5 font-mono text-[11px]/[1.6]">
        {lines.map((line, i) => (
          <div
            key={i}
            className={cn(
              "px-3 whitespace-pre",
              line.type === "added" && "bg-success/10 text-success",
              line.type === "removed" && "bg-destructive/10 text-destructive",
              line.type === "same" && "text-muted-foreground",
            )}
          >
            {line.type === "added" ? "+ " : line.type === "removed" ? "− " : "  "}
            {line.text || " "}
          </div>
        ))}
      </div>
      {!latest && (
        <Button
          variant="ghost"
          size="sm"
          className={cn("self-start", armed && "bg-accent text-primary hover:text-primary")}
          disabled={restore.isPending}
          onClick={() => (armed ? restore.mutate() : setArmed(true))}
        >
          <RotateCcw /> {armed ? "Overwrite current version?" : "Restore this version"}
        </Button>
      )}
    </div>
  );
}

function PaneHint({ children }: { children: React.ReactNode }) {
  return <p className="px-2 py-1.5 text-[13px]/[1.6] text-muted-foreground">{children}</p>;
}

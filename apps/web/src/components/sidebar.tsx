import { useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { FileText, Plus, TriangleAlert } from "lucide-react";
import { toast } from "sonner";
import type { TreeTask } from "@pecto/core";
import { NameInput } from "@/components/name-input";
import { createTask } from "@/lib/api";
import { cn } from "@/lib/utils";

export function Sidebar({
  tasks,
  offline,
  selectedPath,
  onSelect,
  onCreated,
}: {
  tasks: TreeTask[];
  offline: boolean;
  selectedPath: string | null;
  onSelect: (task: TreeTask) => void;
  onCreated: (path: string) => void;
}) {
  const [creating, setCreating] = useState(false);

  const create = useMutation({
    mutationFn: (path: string) => createTask(path),
    onSuccess: (_data, path) => onCreated(path),
    onError: (error) => toast.error(error.message),
    onSettled: () => setCreating(false),
  });

  return (
    <aside className="glass overflow-y-auto rounded-2xl px-3 py-5 text-sidebar-foreground max-md:max-h-44">
      <div className="flex items-center gap-2.5 px-2 pb-4">
        <span className="font-heading text-[17px] font-bold tracking-tight">pecto</span>
        {offline && (
          <span className="inline-flex items-center gap-1.5 font-mono text-[10px] tracking-wide text-muted-foreground">
            <span className="size-1.5 rounded-full bg-muted-foreground/60" />
            offline
          </span>
        )}
      </div>

      <GroupHeader label="Tasks" addTitle="New task" onAdd={() => setCreating(true)} />
      {creating && (
        <NameInput
          className="my-1 h-8 text-sm"
          placeholder="task name"
          onCancel={() => setCreating(false)}
          onSubmit={(slug) => create.mutate(`${slug}.md`)}
        />
      )}
      {tasks.map((t) => (
        <Row
          key={t.path}
          active={selectedPath === t.path}
          onClick={() => onSelect(t)}
          icon={
            t.error ? (
              <TriangleAlert className="size-3.5 text-destructive" />
            ) : (
              <FileText className="size-3.5 text-muted-foreground" />
            )
          }
          label={t.name ?? t.path}
        />
      ))}
    </aside>
  );
}

function GroupHeader({ label, addTitle, onAdd }: { label: string; addTitle: string; onAdd: () => void }) {
  return (
    <div className="flex items-center justify-between px-2 pt-3.5 pb-1.5 text-[11px] tracking-[0.1em] text-muted-foreground/80 uppercase">
      {label}
      <button
        type="button"
        title={addTitle}
        onClick={onAdd}
        className="rounded p-0.5 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
      >
        <Plus className="size-3.5" />
      </button>
    </div>
  );
}

function Row({
  label,
  icon,
  onClick,
  active,
}: {
  label: string;
  icon: React.ReactNode;
  onClick: () => void;
  active?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm text-sidebar-foreground hover:bg-sidebar-accent",
        active && "bg-sidebar-accent text-sidebar-accent-foreground",
      )}
    >
      {icon}
      <span className="truncate">{label}</span>
    </button>
  );
}

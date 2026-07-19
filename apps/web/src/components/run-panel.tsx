import { useEffect, useRef, useState } from "react";
import { Loader2 } from "lucide-react";
import type { RunEvent } from "@pecto/core";
import { cn } from "@/lib/utils";

export function RunPanel({ events }: { events: RunEvent[] }) {
  const bottomRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }, [events.length]);

  const started = events.find((e) => e.type === "run-started");
  const completed = events.find((e) => e.type === "run-completed");
  const failed = events.find((e) => e.type === "run-failed");
  const running = !!started && !completed && !failed;

  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!running) return;
    const timer = setInterval(() => setNow(Date.now()), 100);
    return () => clearInterval(timer);
  }, [running]);

  if (!started) return null;

  const endedAt = completed?.at ?? failed?.at ?? now;
  const seconds = Math.max(0, (endedAt - started.at) / 1000).toFixed(1);

  return (
    <div className="animate-in fade-in slide-in-from-bottom-2 max-h-[45%] overflow-y-auto border-t bg-[oklch(0.1_0.02_258/30%)] px-7 pt-4 pb-5 duration-300">
      <div className="flex items-center gap-2.5 py-0.5 text-[13px] text-muted-foreground">
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
        <span className="font-medium text-foreground">{started.label}</span>
        <span className="text-muted-foreground/70">
          {running ? "running on" : failed ? "failed on" : "ran on"}{" "}
          <span className="font-mono text-[12px]">{started.model}</span>
        </span>
        {running && <Loader2 className="size-3 animate-spin" />}
        <span className="ml-auto font-mono text-[12px] tabular-nums text-muted-foreground/70">{seconds}s</span>
      </div>
      {failed && (
        <div className="flex items-center gap-2.5 py-0.5 text-[13px] text-destructive">
          <span className="size-1.5 flex-none rounded-full bg-destructive" />
          {failed.error}
        </div>
      )}
      {completed && (
        <div className="mt-3 border-t pt-3.5 text-sm/[1.7] whitespace-pre-wrap">{completed.text}</div>
      )}
      <div ref={bottomRef} />
    </div>
  );
}

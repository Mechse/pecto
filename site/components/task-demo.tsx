"use client";

import { useEffect, useState } from "react";

import { KeyChord } from "@/components/keycap";
import { cn } from "@/lib/utils";

const BEFORE = `hey max, did u get a chance too look at the numbers? i think theres an issue with q3, can we talk tmrw`;

const AFTER = `Hey Max, did you get a chance to look at the numbers? I think there's an issue with Q3 — could we talk tomorrow?`;

type Phase = "idle" | "press" | "run" | "done";

const TIMELINE: [Phase, number][] = [
  ["idle", 2600],
  ["press", 350],
  ["run", 1400],
  ["done", 4200],
];

export function TaskDemo() {
  // Start on "done" so a reduced-motion (or JS-off) visitor sees the payoff state.
  const [phase, setPhase] = useState<Phase>("done");

  useEffect(() => {
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (media.matches) return;
    let step = 0;
    let timer: ReturnType<typeof setTimeout>;
    const tick = () => {
      const [name, duration] = TIMELINE[step];
      setPhase(name);
      step = (step + 1) % TIMELINE.length;
      timer = setTimeout(tick, duration);
    };
    timer = setTimeout(tick, 800);
    return () => clearTimeout(timer);
  }, []);

  const showAfter = phase === "done";
  const running = phase === "run";

  return (
    <div className="w-full max-w-md font-mono text-[13px] leading-relaxed">
      {/* The task file — the artifact Pecto is built on */}
      <div className="overflow-hidden rounded-xl border border-border bg-card shadow-[0_1px_2px_rgb(0_0_0/0.04),0_8px_24px_-12px_rgb(0_0_0/0.12)]">
        <div className="flex items-center gap-2 border-b border-border px-4 py-2.5">
          <span aria-hidden className="flex gap-1.5">
            <i className="size-2.5 rounded-full bg-border" />
            <i className="size-2.5 rounded-full bg-border" />
            <i className="size-2.5 rounded-full bg-border" />
          </span>
          <span className="ml-1 text-xs text-muted-foreground">
            improve-email.md
          </span>
        </div>
        <pre className="overflow-x-auto px-4 py-3.5 whitespace-pre-wrap text-foreground/85">
          <span className="text-muted-foreground">{`---\nname: improve-email\ndescription: Polish an email draft without losing the sender's voice.\n---\n`}</span>
          {`Improve the email draft below. Fix grammar and
spelling, tighten the wording — but keep the
sender's voice.

`}
          <span className="rounded bg-primary/10 px-1 py-0.5 text-primary">
            {"{{clipboard}}"}
          </span>
        </pre>
      </div>

      {/* The trigger */}
      <div className="flex items-center justify-center gap-3 py-4">
        {running ? (
          <span
            className={cn(
              "text-xs text-muted-foreground transition-opacity duration-300 min-h-7 inline-flex items-center",
              running ? "opacity-100" : "opacity-0",
            )}
            aria-hidden={!running}
          >
            running…
          </span>
        ) : (
          <KeyChord
            keys={["⌃", "⌥", "1"]}
            pressed={phase === "press" || running}
          />
        )}
      </div>

      {/* The clipboard, before → after */}
      <div
        className={cn(
          "rounded-xl border bg-card px-4 py-3.5 transition-colors duration-500",
          showAfter ? "border-primary/40" : "border-border",
        )}
      >
        <div className="mb-2 flex items-center justify-between text-xs text-muted-foreground">
          <span>Clipboard</span>
          <span
            className={cn(
              "flex items-center gap-1 text-primary transition-opacity duration-500",
              showAfter ? "opacity-100" : "opacity-0",
            )}
          >
            <svg
              aria-hidden
              viewBox="0 0 16 16"
              className="size-3.5"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <path d="M3 8.5l3.5 3.5L13 5" />
            </svg>
            ready to paste
          </span>
        </div>
        <div className="grid text-foreground/85">
          <p
            className={cn(
              "col-start-1 row-start-1 transition-opacity duration-500",
              showAfter ? "opacity-0" : "opacity-100",
            )}
            aria-hidden={showAfter}
          >
            {BEFORE}
          </p>
          <p
            className={cn(
              "col-start-1 row-start-1 transition-opacity duration-500",
              showAfter ? "opacity-100" : "opacity-0",
            )}
            aria-hidden={!showAfter}
          >
            {AFTER}
          </p>
        </div>
      </div>
    </div>
  );
}

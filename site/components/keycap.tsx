import { cn } from "@/lib/utils";

// A physical-looking keyboard key. `pressed` sinks it (used by the hero demo).
export function Keycap({
  children,
  pressed = false,
  className,
}: {
  children: React.ReactNode;
  pressed?: boolean;
  className?: string;
}) {
  return (
    <kbd
      className={cn(
        "inline-flex h-7 min-w-7 items-center justify-center rounded-md border border-border bg-card px-1.5 font-mono text-[13px] text-foreground/80 shadow-[0_2px_0_var(--border)] transition-all duration-150",
        pressed && "translate-y-[2px] shadow-none bg-muted",
        className,
      )}
    >
      {children}
    </kbd>
  );
}

export function KeyChord({
  keys,
  pressed = false,
  className,
}: {
  keys: string[];
  pressed?: boolean;
  className?: string;
}) {
  return (
    <span className={cn("inline-flex items-center gap-1", className)}>
      {keys.map((k) => (
        <Keycap key={k} pressed={pressed}>
          {k}
        </Keycap>
      ))}
    </span>
  );
}

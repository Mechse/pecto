import { useEffect, useRef } from "react";
import { placeholderLabel, type RunEvent } from "@pecto/core";
import { RunPanel } from "@/components/run-panel";

/**
 * The run side of a task: one field per `{{placeholder}}` found in the
 * instructions, with the streamed output below. Tasks without placeholders
 * just show the output.
 */
export function RunView({
  placeholders,
  values,
  onChange,
  events,
}: {
  placeholders: string[];
  values: Record<string, string>;
  onChange: (name: string, value: string) => void;
  events: RunEvent[];
}) {
  // Focus the first unfilled field once, when the view opens.
  const firstEmptyRef = useRef<HTMLTextAreaElement>(null);
  useEffect(() => {
    firstEmptyRef.current?.focus();
  }, []);

  const firstEmpty = placeholders.find((name) => !values[name]?.trim());

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="min-h-0 flex-1 overflow-y-auto px-7 py-5">
        {placeholders.length === 0 ? (
          <p className="text-[13px]/[1.6] text-muted-foreground">
            This task takes no input — hit Run Task and the result appears below.
          </p>
        ) : (
          <div className="flex max-w-2xl flex-col gap-5">
            {placeholders.map((name) => (
              <label key={name} className="flex flex-col gap-1.5">
                <span className="flex items-baseline gap-2">
                  <span className="text-[13px] font-medium">{placeholderLabel(name)}</span>
                  <span className="font-mono text-[11px] text-muted-foreground/60">{`{{${name}}}`}</span>
                </span>
                <textarea
                  ref={name === firstEmpty ? firstEmptyRef : undefined}
                  value={values[name] ?? ""}
                  onChange={(e) => onChange(name, e.target.value)}
                  rows={5}
                  placeholder={`Paste or write the ${placeholderLabel(name).toLowerCase()} here…`}
                  className="w-full resize-y rounded-lg border border-input bg-input/30 px-3 py-2.5 text-sm/[1.6] transition-colors outline-none placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
                />
              </label>
            ))}
          </div>
        )}
      </div>
      <RunPanel events={events} />
    </div>
  );
}

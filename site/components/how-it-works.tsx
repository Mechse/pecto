import { KeyChord } from "@/components/keycap";

const STEPS = [
  {
    keys: ["⌘", "C"],
    title: "Copy anything",
    body: "Grab text in any app — an email draft, a log line, a rough paragraph.",
  },
  {
    keys: ["⌃", "⌥", "1"],
    title: "Press your shortcut",
    body: "Pecto runs the task in the background while you keep working.",
  },
  {
    keys: ["⌘", "V"],
    title: "Paste the result",
    body: "The result replaces your clipboard and a notification tells you it's ready.",
  },
];

export function HowItWorks() {
  return (
    <section
      aria-labelledby="how-it-works"
      className="border-t border-border"
    >
      <div className="mx-auto w-full max-w-5xl px-4 py-16 sm:px-6 lg:py-20">
        <h2
          id="how-it-works"
          className="font-mono text-xs tracking-widest text-muted-foreground uppercase"
        >
          How it works
        </h2>
        <ol className="mt-8 grid gap-10 sm:grid-cols-3 sm:gap-8">
          {STEPS.map((step) => (
            <li key={step.title}>
              <KeyChord keys={step.keys} />
              <h3 className="mt-4 text-base font-semibold tracking-tight">
                {step.title}
              </h3>
              <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">
                {step.body}
              </p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}

import { FEATURES } from "@/lib/config";

export function Features() {
  return (
    <section aria-labelledby="features" className="border-t border-border">
      <div className="mx-auto w-full max-w-5xl px-4 py-16 sm:px-6 lg:py-20">
        <h2
          id="features"
          className="font-mono text-xs tracking-widest text-muted-foreground uppercase"
        >
          What&apos;s in the app
        </h2>
        <p className="mt-6 max-w-2xl text-lg leading-relaxed text-balance">
          A task is one Markdown file: a name, a description, and plain-language
          instructions with a single{" "}
          <code className="rounded bg-primary/10 px-1.5 py-0.5 font-mono text-[0.9em] text-primary">
            {"{{clipboard}}"}
          </code>{" "}
          input. If you can write a note, you can write an automation.
        </p>
        <ul className="mt-10 grid gap-x-12 gap-y-8 sm:grid-cols-2">
          {FEATURES.map((feature) => (
            <li key={feature.title}>
              <h3 className="text-base font-semibold tracking-tight">
                {feature.title}
              </h3>
              <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">
                {feature.body}
              </p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

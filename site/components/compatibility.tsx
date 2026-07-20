import { COMPATIBILITY } from "@/lib/config";

export function Compatibility() {
  return (
    <section aria-labelledby="compatibility" className="border-t border-border">
      <div className="mx-auto w-full max-w-5xl px-4 py-16 sm:px-6 lg:py-20">
        <h2
          id="compatibility"
          className="font-mono text-xs tracking-widest text-muted-foreground uppercase"
        >
          Compatibility
        </h2>
        <dl className="mt-8 max-w-2xl divide-y divide-border border-y border-border">
          {COMPATIBILITY.map((row) => (
            <div
              key={row.label}
              className="grid gap-1 py-3.5 sm:grid-cols-[8rem_1fr] sm:gap-4"
            >
              <dt className="font-mono text-xs leading-6 text-muted-foreground uppercase">
                {row.label}
              </dt>
              <dd className="text-sm leading-6">{row.value}</dd>
            </div>
          ))}
        </dl>
        <p className="mt-6 max-w-2xl text-sm leading-relaxed text-muted-foreground">
          Pecto talks to the model provider directly with your own key — there
          is no account, no subscription, and no server in between.
        </p>
      </div>
    </section>
  );
}

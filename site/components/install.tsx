import { GITHUB_URL, INSTALL_NOTE, INSTALL_STEPS } from "@/lib/config";

export function Install() {
  return (
    <section aria-labelledby="install" className="border-t border-border">
      <div className="mx-auto w-full max-w-5xl px-4 py-16 sm:px-6 lg:py-20">
        <h2
          id="install"
          className="font-mono text-xs tracking-widest text-muted-foreground uppercase"
        >
          Installing the beta
        </h2>
        <ol className="mt-8 max-w-2xl divide-y divide-border border-y border-border">
          {INSTALL_STEPS.map((step, i) => (
            <li
              key={step.title}
              className="grid gap-1.5 py-5 sm:grid-cols-[2rem_1fr] sm:gap-4"
            >
              <span
                aria-hidden
                className="font-mono text-xs leading-6 text-muted-foreground"
              >
                {String(i + 1).padStart(2, "0")}
              </span>
              <div>
                <h3 className="text-sm leading-6 font-medium">{step.title}</h3>
                <p className="mt-1 text-sm leading-relaxed text-muted-foreground">
                  {step.body}
                </p>
              </div>
            </li>
          ))}
        </ol>
        <p className="mt-6 max-w-2xl text-sm leading-relaxed text-muted-foreground">
          {INSTALL_NOTE}{" "}
          <a
            href={GITHUB_URL}
            className="underline underline-offset-4 hover:text-foreground"
          >
            View the source on GitHub
          </a>
          .
        </p>
      </div>
    </section>
  );
}

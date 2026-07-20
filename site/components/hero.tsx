import { TaskDemo } from "@/components/task-demo";
import { buttonVariants } from "@/components/ui/button";
import { DESCRIPTION, TAGLINE } from "@/lib/config";
import { cn } from "@/lib/utils";

export function Hero({
  downloadHref,
  version,
}: {
  downloadHref: string;
  version: string | null;
}) {
  return (
    <section className="mx-auto grid w-full max-w-5xl items-center gap-12 px-4 pt-16 pb-20 sm:px-6 lg:grid-cols-[1.1fr_1fr] lg:gap-16 lg:pt-24 lg:pb-28">
      <div>
        <h1 className="max-w-xl text-4xl font-bold tracking-tighter text-balance sm:text-5xl lg:text-[3.4rem] lg:leading-[1.05]">
          {TAGLINE}
        </h1>
        <p className="mt-5 max-w-xl text-lg leading-relaxed text-muted-foreground">
          {DESCRIPTION}
        </p>
        <div className="mt-8 flex flex-wrap items-center gap-4">
          <a
            href={downloadHref}
            className={cn(
              buttonVariants({ size: "lg" }),
              "h-12 gap-2.5 px-6 text-base",
            )}
          >
            <svg
              aria-hidden
              viewBox="0 0 16 16"
              className="size-4"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.8"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <path d="M8 1.5v9m0 0L4.5 7M8 10.5 11.5 7M2 13.5h12" />
            </svg>
            Download for macOS
            {version && (
              <span className="font-mono text-sm font-normal opacity-70">
                {version}
              </span>
            )}
          </a>
        </div>
        <p className="mt-4 font-mono text-xs text-muted-foreground">
          macOS 15+ · Apple Silicon · Free &amp; open source
        </p>
      </div>
      <div className="flex justify-center sm:justify-start lg:justify-end">
        <TaskDemo />
      </div>
    </section>
  );
}

import { APP_NAME, GITHUB_URL } from "@/lib/config";

export function SiteFooter() {
  return (
    <footer className="mt-auto border-t border-border">
      <div className="mx-auto flex w-full max-w-5xl flex-wrap items-center justify-between gap-3 px-4 py-8 text-sm text-muted-foreground sm:px-6">
        <p>
          <span aria-hidden className="mr-1.5 text-primary">
            ✦
          </span>
          {APP_NAME} — © 2026
        </p>
        <a
          href={GITHUB_URL}
          className="rounded-md outline-none transition-colors hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
        >
          Source on GitHub
        </a>
      </div>
    </footer>
  );
}

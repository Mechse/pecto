import { cacheLife } from "next/cache";

import { GITHUB_REPO } from "@/lib/config";

const API = `https://api.github.com/repos/${GITHUB_REPO}`;
const HEADERS = { Accept: "application/vnd.github+json" };

export type LatestRelease = {
  version: string;
  downloadUrl: string;
  prerelease: boolean;
};

type Release = {
  tag_name?: string;
  draft?: boolean;
  prerelease?: boolean;
  assets?: { name: string; browser_download_url: string }[];
};

function downloadable(release: Release): LatestRelease | null {
  const assets = release.assets ?? [];
  const asset =
    assets.find((a) => a.name.endsWith(".dmg")) ??
    assets.find((a) => a.name.endsWith(".zip"));
  if (!release.tag_name || !asset) return null;
  return {
    version: release.tag_name,
    downloadUrl: asset.browser_download_url,
    prerelease: release.prerelease === true,
  };
}

// Newest release with a .dmg (or .zip) asset.
//
// Deliberately does NOT use /releases/latest: that endpoint excludes
// prereleases and 404s while we are shipping betas only. Instead we list
// releases (newest first) and prefer the newest stable one, falling back to
// the newest prerelease when no stable release exists yet. That way this
// keeps working unchanged once a 1.0 ships.
//
// Null if the repo has no usable release — callers fall back to RELEASES_URL.
export async function getLatestRelease(): Promise<LatestRelease | null> {
  "use cache";
  cacheLife("hours");
  try {
    const res = await fetch(`${API}/releases?per_page=20`, { headers: HEADERS });
    if (!res.ok) return null;
    const releases = (await res.json()) as Release[];
    if (!Array.isArray(releases)) return null;

    const published = releases.filter((r) => r.draft !== true);
    const stable = published.filter((r) => r.prerelease !== true);

    for (const release of [...stable, ...published]) {
      const found = downloadable(release);
      if (found) return found;
    }
    return null;
  } catch {
    return null;
  }
}

export async function getStars(): Promise<number | null> {
  "use cache";
  cacheLife("hours");
  try {
    const res = await fetch(API, { headers: HEADERS });
    if (!res.ok) return null;
    const repo = (await res.json()) as { stargazers_count?: number };
    return typeof repo.stargazers_count === "number" ? repo.stargazers_count : null;
  } catch {
    return null;
  }
}

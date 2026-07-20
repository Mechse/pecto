import { cacheLife } from "next/cache";

import { GITHUB_REPO } from "@/lib/config";

const API = `https://api.github.com/repos/${GITHUB_REPO}`;
const HEADERS = { Accept: "application/vnd.github+json" };

export type LatestRelease = {
  version: string;
  downloadUrl: string;
};

// Latest release with a .dmg (or .zip) asset. Null until the repo exists
// and has a release — callers fall back to the releases page.
export async function getLatestRelease(): Promise<LatestRelease | null> {
  "use cache";
  cacheLife("hours");
  try {
    const res = await fetch(`${API}/releases/latest`, { headers: HEADERS });
    if (!res.ok) return null;
    const release = (await res.json()) as {
      tag_name?: string;
      assets?: { name: string; browser_download_url: string }[];
    };
    const assets = release.assets ?? [];
    const asset =
      assets.find((a) => a.name.endsWith(".dmg")) ??
      assets.find((a) => a.name.endsWith(".zip"));
    if (!release.tag_name || !asset) return null;
    return { version: release.tag_name, downloadUrl: asset.browser_download_url };
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

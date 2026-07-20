import { Compatibility } from "@/components/compatibility";
import { Features } from "@/components/features";
import { Hero } from "@/components/hero";
import { HowItWorks } from "@/components/how-it-works";
import { SiteFooter } from "@/components/site-footer";
import { SiteNav } from "@/components/site-nav";
import { RELEASES_URL } from "@/lib/config";
import { getLatestRelease, getStars } from "@/lib/github";

export default async function Home() {
  const [release, stars] = await Promise.all([getLatestRelease(), getStars()]);
  const downloadHref = release?.downloadUrl ?? RELEASES_URL;

  return (
    <>
      <SiteNav stars={stars} downloadHref={downloadHref} />
      <main>
        <Hero downloadHref={downloadHref} version={release?.version ?? null} />
        <HowItWorks />
        <Features />
        <Compatibility />
      </main>
      <SiteFooter />
    </>
  );
}

import type { Metadata } from "next";
import { Geist_Mono } from "next/font/google";
import "./globals.css";

import { APP_NAME, DESCRIPTION, TAGLINE } from "@/lib/config";

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: `${APP_NAME} — ${TAGLINE}`,
  description: DESCRIPTION,
  openGraph: {
    title: `${APP_NAME} — ${TAGLINE}`,
    description: DESCRIPTION,
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${geistMono.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}

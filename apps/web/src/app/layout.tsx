import type { Metadata } from "next";
import { Sora, JetBrains_Mono } from "next/font/google";
import "./globals.css";

const sora = Sora({
  variable: "--font-sora",
  subsets: ["latin"],
  display: "swap",
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  title: "Just Ship — From ticket to ship. Autonomously.",
  description:
    "A portable multi-agent framework for autonomous software development. Ship complex projects from ticket to ship — fully autonomous.",
  icons: {
    icon: "/logos/png/favicons/mark-dark-favicon-32.png",
  },
  openGraph: {
    title: "Just Ship — From ticket to ship. Autonomously.",
    description:
      "A portable multi-agent framework for autonomous software development.",
    url: "https://just-ship.io",
    siteName: "Just Ship",
    type: "website",
    images: [
      {
        url: "/og-dark.png",
        width: 1200,
        height: 630,
        alt: "Just Ship — From ticket to ship. Autonomously.",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Just Ship — From ticket to ship. Autonomously.",
    description:
      "A portable multi-agent framework for autonomous software development.",
    images: ["/og-dark.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body
        className={`${sora.variable} ${jetbrainsMono.variable} font-sans antialiased`}
      >
        {children}
      </body>
    </html>
  );
}

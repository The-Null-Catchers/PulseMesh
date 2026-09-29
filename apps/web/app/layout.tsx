import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "PulseMesh",
  description: "Realtime communication built for focused teams.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

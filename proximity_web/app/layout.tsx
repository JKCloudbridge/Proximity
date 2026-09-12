import type { Metadata } from "next";
import { Baloo_2, Plus_Jakarta_Sans } from "next/font/google";
import { Toaster } from "sonner";
import "./globals.css";

// Same two Google Fonts as proximity_app's app_theme.dart (§6: Baloo 2
// display, Plus Jakarta Sans body) -- one brand across both apps, not a
// web-specific substitute.
const displayFont = Baloo_2({ variable: "--font-display", subsets: ["latin"] });
const bodyFont = Plus_Jakarta_Sans({ variable: "--font-body", subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Proximity",
  description: "Shopkeeper dashboard & admin panel",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${displayFont.variable} ${bodyFont.variable} antialiased`}>
      <body className="min-h-screen font-[family-name:var(--font-body)]" style={{ backgroundColor: "var(--muted)" }}>
        {children}
        <Toaster richColors position="top-right" />
      </body>
    </html>
  );
}

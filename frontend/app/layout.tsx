import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "CleanFlow Bonds | Execution Warranty Lab",
  description: "A bond-backed execution warranty for Uniswap v4",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

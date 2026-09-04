import type { Metadata } from "next";
import Sidebar from "@/components/layout/Sidebar";
import "./globals.css";

export const metadata: Metadata = {
  title: "SupplyChainIQ Control Tower",
  description: "Snowflake-native Supply Chain Control Tower.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-[#f2f7fc] text-slate-800 antialiased">
        <div className="relative flex min-h-screen flex-col md:flex-row">
          <Sidebar />
          <main className="min-w-0 flex-1 px-4 py-6 sm:px-6 md:px-8 md:py-8 lg:px-10">{children}</main>
        </div>
      </body>
    </html>
  );
}

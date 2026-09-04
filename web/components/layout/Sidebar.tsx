"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const NAV_ITEMS = [
  { href: "/overview", label: "Overview" },
  { href: "/risk-radar", label: "Risk Radar" },
  { href: "/ask", label: "Ask SupplyChainIQ" },
  { href: "/approvals", label: "Approvals" },
  { href: "/actions", label: "Actions" },
  { href: "/timeline", label: "Timeline" },
];

export default function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="w-64 shrink-0 border-r border-control-border bg-control-panel p-5 hidden md:block">
      <div className="mb-8">
        <div className="text-lg font-semibold text-white">SupplyChainIQ</div>
        <div className="text-xs uppercase tracking-wide text-slate-400">Control Tower</div>
      </div>
      <nav className="space-y-1">
        {NAV_ITEMS.map((item) => {
          const active = pathname === item.href || (item.href === "/overview" && pathname === "/");
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`block rounded-md px-3 py-2 text-sm transition-colors ${
                active
                  ? "bg-control-accent/20 text-white font-medium"
                  : "text-slate-300 hover:bg-white/5 hover:text-white"
              }`}
            >
              {item.label}
            </Link>
          );
        })}
      </nav>
      <div className="mt-8 border-t border-control-border pt-4 text-xs text-slate-500">
        Snowflake-native Supply Chain Control Tower: Cortex Agent, Cortex Analyst, Cortex Search, deterministic
        decision tools, human approval, and controlled demo dispatch -- all governed in Snowflake.
      </div>
    </aside>
  );
}

"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const NAV_ITEMS = [
  { href: "/overview", label: "Overview", icon: "overview" },
  { href: "/risk-radar", label: "Risk Radar", icon: "risk" },
  { href: "/ask", label: "Ask SupplyChainIQ", icon: "ask" },
  { href: "/approvals", label: "Approvals", icon: "approvals" },
  { href: "/actions", label: "Actions", icon: "actions" },
  { href: "/timeline", label: "Timeline", icon: "timeline" },
];

const NAV_ICON_PATHS: Record<string, string> = {
  overview: "M4 13h6V4H4v9Zm10 7h6V11h-6v9ZM4 20h6v-3H4v3Zm10-13h6V4h-6v3Z",
  risk: "M12 3 3.5 19h17L12 3Zm0 5v5m0 3h.01",
  ask: "M5 5h14v10H9l-4 4V5Zm4 4h6m-6 3h4",
  approvals: "M8 3h8v3h3v15H5V6h3V3Zm1 10 2 2 4-5",
  actions: "M13 2 4 14h7l-1 8 10-13h-7V2Z",
  timeline: "M12 7v5l3 2m6-2a9 9 0 1 1-3-6.7M21 3v6h-6",
};

function NavIcon({ name }: { name: string }) {
  return (
    <svg viewBox="0 0 24 24" className="h-4 w-4 shrink-0" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={NAV_ICON_PATHS[name]} />
    </svg>
  );
}

export default function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="sticky top-0 z-40 w-full shrink-0 border-b border-sky-200/80 bg-[#eef7fc]/95 px-4 py-3 shadow-[0_10px_40px_-28px_rgba(48,89,130,0.28)] backdrop-blur-xl md:h-screen md:w-64 md:border-b-0 md:border-r md:px-4 md:py-6">
      <div className="mb-3 flex items-center gap-3 px-1 md:mb-8 md:px-2">
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-blue-400 to-blue-700 shadow-[0_8px_24px_-8px_rgba(59,130,246,0.9)]">
          <svg viewBox="0 0 24 24" className="h-5 w-5 text-white" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
            <path d="M4 7.5 12 3l8 4.5-8 4.5-8-4.5Z" />
            <path d="m4 12 8 4.5 8-4.5M4 16.5 12 21l8-4.5" />
          </svg>
        </div>
        <div className="min-w-0">
          <div className="truncate text-[0.95rem] font-semibold tracking-[-0.02em] text-[#10213f]">SupplyChainIQ</div>
          <div className="text-[0.62rem] font-semibold uppercase tracking-[0.18em] text-slate-400">Control Tower</div>
        </div>
      </div>
      <nav className="flex gap-1 overflow-x-auto pb-1 md:block md:space-y-1 md:overflow-visible md:pb-0" aria-label="Primary navigation">
        {NAV_ITEMS.map((item) => {
          const active = pathname === item.href || (item.href === "/overview" && pathname === "/");
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`group relative flex shrink-0 items-center gap-3 rounded-lg px-3 py-2.5 text-sm transition duration-200 md:w-full ${
                active
                  ? "bg-blue-500/[0.08] font-semibold text-blue-700 shadow-sm shadow-blue-200/50"
                  : "text-slate-500 hover:bg-white/70 hover:text-slate-900"
              }`}
            >
              <span className={active ? "text-blue-500" : "text-slate-400 transition group-hover:text-slate-700"}>
                <NavIcon name={item.icon} />
              </span>
              <span className="whitespace-nowrap">{item.label}</span>
              {active && <span className="ml-auto hidden h-1.5 w-1.5 rounded-full bg-blue-400 shadow-[0_0_9px_rgba(96,165,250,0.9)] md:block" />}
            </Link>
          );
        })}
      </nav>
      <div className="absolute inset-x-4 bottom-6 hidden rounded-xl border border-emerald-200/80 bg-white/65 p-4 text-[0.69rem] leading-5 text-slate-500 shadow-sm md:block">
        Snowflake-native Supply Chain Control Tower: Cortex Agent, Cortex Analyst, Cortex Search, deterministic
        decision tools, human approval, and controlled demo dispatch -- all governed in Snowflake.
      </div>
    </aside>
  );
}

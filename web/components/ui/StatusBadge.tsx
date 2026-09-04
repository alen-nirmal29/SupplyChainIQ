const SEVERITY_COLORS: Record<string, string> = {
  CRITICAL: "bg-red-50 text-red-700 border-red-200 before:bg-red-500",
  HIGH: "bg-orange-50 text-orange-700 border-orange-200 before:bg-orange-500",
  MEDIUM: "bg-amber-50 text-amber-700 border-amber-200 before:bg-amber-500",
  LOW: "bg-sky-50 text-sky-700 border-sky-200 before:bg-sky-500",
  PENDING: "bg-amber-50 text-amber-700 border-amber-200 before:bg-amber-500",
  APPROVED: "bg-emerald-50 text-emerald-700 border-emerald-200 before:bg-emerald-500",
  REJECTED: "bg-slate-100 text-slate-700 border-slate-200 before:bg-slate-500",
  CANCELLED: "bg-slate-100 text-slate-700 border-slate-200 before:bg-slate-500",
  DISPATCHED_DEMO: "bg-sky-50 text-sky-700 border-sky-200 before:bg-sky-500",
};

interface StatusBadgeProps {
  status: string;
  /** Optional secondary text label alongside the color (never rely on color alone). */
  label?: string;
}

export default function StatusBadge({ status, label }: StatusBadgeProps) {
  const classes = SEVERITY_COLORS[status] ?? "bg-slate-100 text-slate-700 border-slate-200 before:bg-slate-500";
  return (
    <span className={`before:content-[''] inline-flex items-center gap-1.5 whitespace-nowrap rounded-full border px-2.5 py-1 text-[0.68rem] font-semibold tracking-wide before:h-1.5 before:w-1.5 before:rounded-full ${classes}`}>
      {label ?? status}
    </span>
  );
}

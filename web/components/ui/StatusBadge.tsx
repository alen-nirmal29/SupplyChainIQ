const SEVERITY_COLORS: Record<string, string> = {
  CRITICAL: "bg-red-500/20 text-red-300 border-red-500/40",
  HIGH: "bg-orange-500/20 text-orange-300 border-orange-500/40",
  MEDIUM: "bg-yellow-500/20 text-yellow-300 border-yellow-500/40",
  LOW: "bg-sky-500/20 text-sky-300 border-sky-500/40",
  PENDING: "bg-yellow-500/20 text-yellow-300 border-yellow-500/40",
  APPROVED: "bg-emerald-500/20 text-emerald-300 border-emerald-500/40",
  REJECTED: "bg-slate-500/20 text-slate-300 border-slate-500/40",
  CANCELLED: "bg-slate-500/20 text-slate-300 border-slate-500/40",
  DISPATCHED_DEMO: "bg-sky-500/20 text-sky-300 border-sky-500/40",
};

interface StatusBadgeProps {
  status: string;
  /** Optional secondary text label alongside the color (never rely on color alone). */
  label?: string;
}

export default function StatusBadge({ status, label }: StatusBadgeProps) {
  const classes = SEVERITY_COLORS[status] ?? "bg-slate-500/20 text-slate-300 border-slate-500/40";
  return (
    <span className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${classes}`}>
      {label ?? status}
    </span>
  );
}

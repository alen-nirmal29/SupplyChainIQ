interface MetricCardProps {
  label: string;
  value: React.ReactNode;
  hint?: string;
}

export default function MetricCard({ label, value, hint }: MetricCardProps) {
  return (
    <div data-metric-card className="surface group relative min-w-0 overflow-hidden p-4 transition duration-200 hover:-translate-y-0.5 hover:border-blue-400/25 sm:p-5">
      <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-blue-400/35 to-transparent opacity-0 transition-opacity group-hover:opacity-100" />
      <div className="flex items-start justify-between gap-3">
      <div className="text-[0.68rem] font-semibold uppercase leading-4 tracking-[0.09em] text-slate-500">{label}</div>
        <span data-metric-icon className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg border transition group-hover:scale-105" aria-hidden="true">
          <svg viewBox="0 0 20 20" className="h-3.5 w-3.5" fill="none" stroke="currentColor" strokeWidth="1.6">
            <path d="M3 15V9m5 6V5m5 10v-3m4 3V3" />
          </svg>
        </span>
      </div>
      <div className="mt-1 break-words text-2xl font-semibold tracking-[-0.025em] text-[#10213f]">{value}</div>
      {hint ? <div className="mt-1.5 text-xs font-medium text-slate-500">{hint}</div> : null}
    </div>
  );
}

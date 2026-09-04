import MetricCard from "@/components/ui/MetricCard";
import type { ForecastedStockoutSummary } from "@/types/forecast";

interface ForecastSummaryProps {
  summary: ForecastedStockoutSummary;
}

export default function ForecastSummary({ summary }: ForecastSummaryProps) {
  return (
    <div>
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <MetricCard label="Forecasted warnings" value={summary.TOTAL_WARNINGS} />
        <MetricCard label="Immediate / Day 0" value={summary.DAY0} />
        <MetricCard label="1\u20137 day warnings" value={summary.DAY1_2 + summary.DAY3_7} />
        <MetricCard label="8\u201314 day warnings" value={summary.DAY8_14} />
      </div>
      <p className="mt-2 text-xs text-slate-500">
        Accepted forecast series (model quality gate): {summary.ACCEPTED_SERIES.toLocaleString()}
      </p>
    </div>
  );
}

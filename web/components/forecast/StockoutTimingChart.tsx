import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from "recharts";
import type { ForecastedStockoutSummary } from "@/types/forecast";

interface StockoutTimingChartProps {
  summary: ForecastedStockoutSummary;
}

export default function StockoutTimingChart({ summary }: StockoutTimingChartProps) {
  const data = [
    { timing: "Day 0", warnings: summary.DAY0 },
    { timing: "Day 1\u20132", warnings: summary.DAY1_2 },
    { timing: "Day 3\u20137", warnings: summary.DAY3_7 },
    { timing: "Day 8\u201314", warnings: summary.DAY8_14 },
  ];

  return (
    <div>
      <p className="mb-2 text-xs text-slate-500">How soon are these predicted shortages expected?</p>
      <ResponsiveContainer width="100%" height={220}>
        <BarChart data={data}>
          <XAxis dataKey="timing" stroke="#64748b" fontSize={12} />
          <YAxis stroke="#64748b" fontSize={12} allowDecimals={false} />
          <Tooltip contentStyle={{ background: "#111a2e", border: "1px solid #1e2a44" }} />
          <Bar dataKey="warnings" fill="#3b82f6" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

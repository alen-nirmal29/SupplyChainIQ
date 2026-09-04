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
    <div className="surface p-4 sm:p-5">
      <p className="mb-4 text-xs font-medium text-slate-500">How soon are these predicted shortages expected?</p>
      <ResponsiveContainer width="100%" height={220}>
        <BarChart data={data} margin={{ left: -12, right: 12, top: 4 }}>
          <XAxis dataKey="timing" stroke="#64748b" fontSize={11} axisLine={false} tickLine={false} />
          <YAxis stroke="#64748b" fontSize={11} allowDecimals={false} axisLine={false} tickLine={false} />
          <Tooltip cursor={{ fill: "rgba(139, 92, 246, 0.05)" }} contentStyle={{ background: "rgba(255,255,255,.98)", color: "#172554", border: "1px solid rgba(196,181,253,.75)", borderRadius: 10, boxShadow: "0 16px 40px rgba(70,100,140,.16)" }} />
          <Bar dataKey="warnings" fill="#8b5cf6" radius={[6, 6, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

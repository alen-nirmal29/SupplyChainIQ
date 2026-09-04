"use client";

import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer } from "recharts";
import type { ForecastPoint } from "@/types/forecast";

interface ForecastPathChartProps {
  points: ForecastPoint[];
}

export default function ForecastPathChart({ points }: ForecastPathChartProps) {
  return (
    <div>
      <h4 className="mb-2 text-sm font-semibold text-white">14-day forecast trajectory</h4>
      <ResponsiveContainer width="100%" height={220}>
        <LineChart data={points}>
          <XAxis dataKey="FORECAST_DATE" stroke="#64748b" fontSize={11} />
          <YAxis stroke="#64748b" fontSize={12} />
          <Tooltip contentStyle={{ background: "#111a2e", border: "1px solid #1e2a44" }} />
          <Line type="monotone" dataKey="FORECAST_VALUE" name="Forecast demand" stroke="#3b82f6" dot={false} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}

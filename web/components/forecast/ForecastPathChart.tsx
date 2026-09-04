"use client";

import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer } from "recharts";
import type { ForecastPoint } from "@/types/forecast";

interface ForecastPathChartProps {
  points: ForecastPoint[];
}

export default function ForecastPathChart({ points }: ForecastPathChartProps) {
  return (
    <div className="rounded-xl border border-violet-200/80 bg-white/70 p-4 shadow-sm sm:p-5">
      <h4 className="section-heading mb-4">14-day forecast trajectory</h4>
      <ResponsiveContainer width="100%" height={220}>
        <LineChart data={points} margin={{ left: -12, right: 14, top: 4 }}>
          <XAxis dataKey="FORECAST_DATE" stroke="#64748b" fontSize={10} axisLine={false} tickLine={false} />
          <YAxis stroke="#64748b" fontSize={11} axisLine={false} tickLine={false} />
          <Tooltip contentStyle={{ background: "rgba(255,255,255,.98)", color: "#172554", border: "1px solid rgba(196,181,253,.75)", borderRadius: 10, boxShadow: "0 16px 40px rgba(70,100,140,.16)" }} />
          <Line type="monotone" dataKey="FORECAST_VALUE" name="Forecast demand" stroke="#a78bfa" strokeWidth={2.5} dot={false} activeDot={{ r: 4, fill: "#c4b5fd", stroke: "#7c3aed", strokeWidth: 2 }} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}

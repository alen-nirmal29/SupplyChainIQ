import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from "recharts";
import type { ConfirmedRisk } from "@/types/risk";

interface RiskScoreBreakdownProps {
  risk: ConfirmedRisk;
}

/** Renders the deterministic score components returned directly by
 * RISK.SUPPLY_CHAIN_RISK_RANKING -- never recomputed here. */
export default function RiskScoreBreakdown({ risk }: RiskScoreBreakdownProps) {
  const data = [
    { component: "Shortage", points: risk.SHORTAGE_SCORE },
    { component: "Customer urgency", points: risk.URGENCY_SCORE },
    { component: "Revenue exposure", points: risk.REVENUE_SCORE },
    { component: "Shipment delay", points: risk.SHIPMENT_SCORE },
    { component: "Supplier OTD", points: risk.SUPPLIER_SCORE },
  ];

  return (
    <div className="rounded-xl border border-violet-200/80 bg-violet-50/35 p-4 sm:p-5">
      <h3 className="section-heading mb-1">Why this risk scored {risk.RISK_SCORE} / 100</h3>
      <p className="mb-4 text-xs leading-5 text-slate-500">
        Deterministic score components returned directly by the governed Snowflake Risk Radar.
      </p>
      <ResponsiveContainer width="100%" height={220}>
        <BarChart data={data} layout="vertical" margin={{ left: 20, right: 18 }}>
          <XAxis type="number" stroke="#475569" fontSize={11} axisLine={false} tickLine={false} />
          <YAxis type="category" dataKey="component" stroke="#94a3b8" fontSize={11} width={132} axisLine={false} tickLine={false} />
          <Tooltip cursor={{ fill: "rgba(99, 102, 241, 0.05)" }} contentStyle={{ background: "rgba(255,255,255,.98)", color: "#172554", border: "1px solid rgba(147, 197, 253, 0.65)", borderRadius: 10, boxShadow: "0 16px 40px rgba(70,100,140,.16)" }} />
          <Bar dataKey="points" fill="#6366f1" radius={[0, 6, 6, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

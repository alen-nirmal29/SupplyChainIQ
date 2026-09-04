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
    <div>
      <h3 className="mb-1 text-sm font-semibold text-white">Why this risk scored {risk.RISK_SCORE} / 100</h3>
      <p className="mb-3 text-xs text-slate-400">
        Deterministic score components returned directly by the governed Snowflake Risk Radar.
      </p>
      <ResponsiveContainer width="100%" height={220}>
        <BarChart data={data} layout="vertical" margin={{ left: 24 }}>
          <XAxis type="number" stroke="#64748b" fontSize={12} />
          <YAxis type="category" dataKey="component" stroke="#64748b" fontSize={12} width={140} />
          <Tooltip contentStyle={{ background: "#111a2e", border: "1px solid #1e2a44" }} />
          <Bar dataKey="points" fill="#3b82f6" radius={[0, 4, 4, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

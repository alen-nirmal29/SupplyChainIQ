import StatusBadge from "@/components/ui/StatusBadge";
import { formatCurrencyINR, formatQty } from "@/lib/format";
import type { ConfirmedRisk } from "@/types/risk";

interface ConfirmedRiskTableProps {
  risks: ConfirmedRisk[];
  selectedId: string | null;
  onSelect: (riskId: string) => void;
}

export default function ConfirmedRiskTable({ risks, selectedId, onSelect }: ConfirmedRiskTableProps) {
  return (
    <div className="overflow-x-auto rounded-lg border border-control-border">
      <table className="min-w-full divide-y divide-control-border text-sm">
        <thead className="bg-control-panel text-left text-xs uppercase text-slate-400">
          <tr>
            <th className="px-3 py-2">Rank</th>
            <th className="px-3 py-2">Severity</th>
            <th className="px-3 py-2">Supplier</th>
            <th className="px-3 py-2">Part</th>
            <th className="px-3 py-2">Plant</th>
            <th className="px-3 py-2 text-right">Shortage</th>
            <th className="px-3 py-2 text-right">Score</th>
            <th className="px-3 py-2 text-right">Revenue exposure</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-control-border">
          {risks.map((risk) => (
            <tr
              key={risk.RISK_ID}
              onClick={() => onSelect(risk.RISK_ID)}
              className={`cursor-pointer transition-colors ${
                risk.RISK_ID === selectedId ? "bg-control-accent/10" : "hover:bg-white/5"
              }`}
            >
              <td className="px-3 py-2 text-slate-300">{risk.RISK_RANK}</td>
              <td className="px-3 py-2">
                <StatusBadge status={risk.SEVERITY} />
              </td>
              <td className="px-3 py-2 text-slate-200">{risk.SUPPLIER_NAME}</td>
              <td className="px-3 py-2 text-slate-200">{risk.PART_ID}</td>
              <td className="px-3 py-2 text-slate-200">{risk.PLANT_NAME}</td>
              <td className="px-3 py-2 text-right text-slate-200">{formatQty(risk.SHORTAGE_QUANTITY)}</td>
              <td className="px-3 py-2 text-right text-slate-200">{risk.RISK_SCORE}/100</td>
              <td className="px-3 py-2 text-right text-slate-200">{formatCurrencyINR(risk.REVENUE_EXPOSURE)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

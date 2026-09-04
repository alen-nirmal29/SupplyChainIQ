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
    <div className="table-shell">
      <table className="data-table">
        <thead>
          <tr>
            <th>Rank</th>
            <th>Severity</th>
            <th>Supplier</th>
            <th>Part</th>
            <th>Plant</th>
            <th className="text-right">Shortage</th>
            <th className="text-right">Score</th>
            <th className="text-right">Revenue exposure</th>
          </tr>
        </thead>
        <tbody>
          {risks.map((risk) => (
            <tr
              key={risk.RISK_ID}
              onClick={() => onSelect(risk.RISK_ID)}
              className={`cursor-pointer transition-colors ${
                risk.RISK_ID === selectedId
                  ? "bg-blue-50 shadow-[inset_3px_0_0_rgba(59,130,246,0.9)]"
                  : "hover:bg-sky-50/70"
              }`}
            >
              <td className="font-mono text-xs text-slate-500">{risk.RISK_RANK}</td>
              <td>
                <StatusBadge status={risk.SEVERITY} />
              </td>
              <td className="font-medium text-slate-800">{risk.SUPPLIER_NAME}</td>
              <td className="font-mono text-xs text-slate-700">{risk.PART_ID}</td>
              <td>{risk.PLANT_NAME}</td>
              <td className="text-right tabular-nums">{formatQty(risk.SHORTAGE_QUANTITY)}</td>
              <td className="text-right font-semibold tabular-nums text-[#10213f]">{risk.RISK_SCORE}/100</td>
              <td className="text-right tabular-nums">{formatCurrencyINR(risk.REVENUE_EXPOSURE)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

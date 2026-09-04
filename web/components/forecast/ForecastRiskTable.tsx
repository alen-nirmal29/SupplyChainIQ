import { formatQty } from "@/lib/format";
import type { ForecastedStockoutRisk } from "@/types/forecast";

interface ForecastRiskTableProps {
  risks: ForecastedStockoutRisk[];
  selectedKey: string | null;
  onSelect: (key: string) => void;
}

export function forecastRiskKey(r: ForecastedStockoutRisk): string {
  return `${r.PART_ID}|${r.PLANT_ID}`;
}

export default function ForecastRiskTable({ risks, selectedKey, onSelect }: ForecastRiskTableProps) {
  return (
    <div className="table-shell">
      <table className="data-table">
        <thead>
          <tr>
            <th>Part</th>
            <th>Plant</th>
            <th>Predicted stockout</th>
            <th className="text-right">Days to stockout</th>
            <th className="text-right">Usable inventory</th>
            <th className="text-right">Confirmed demand</th>
            <th className="text-right">Forecast demand</th>
            <th className="text-right">Expected inbound</th>
            <th className="text-right">Forecasted shortage</th>
            <th className="text-right">Model quality</th>
          </tr>
        </thead>
        <tbody>
          {risks.map((r) => {
            const key = forecastRiskKey(r);
            return (
              <tr
                key={key}
                onClick={() => onSelect(key)}
                className={`cursor-pointer transition-colors ${
                  key === selectedKey
                    ? "bg-violet-50 shadow-[inset_3px_0_0_rgba(139,92,246,0.85)]"
                    : "hover:bg-violet-50/50"
                }`}
              >
                <td className="font-mono text-xs text-slate-700">{r.PART_ID}</td>
                <td className="font-medium text-slate-800">{r.PLANT_NAME}</td>
                <td>{r.PREDICTED_STOCKOUT_DATE ?? "\u2014"}</td>
                <td className="text-right tabular-nums">{r.DAYS_TO_PREDICTED_STOCKOUT ?? "\u2014"}</td>
                <td className="text-right tabular-nums">{formatQty(r.CURRENT_USABLE_QUANTITY)}</td>
                <td className="text-right tabular-nums">{formatQty(r.CONFIRMED_DEMAND_QUANTITY)}</td>
                <td className="text-right tabular-nums">{formatQty(r.FORECAST_DEMAND_QUANTITY)}</td>
                <td className="text-right tabular-nums">{formatQty(r.EXPECTED_INBOUND_QUANTITY)}</td>
                <td className="text-right font-semibold tabular-nums text-[#10213f]">{formatQty(r.FORECASTED_SHORTAGE_QUANTITY)}</td>
                <td className="text-right tabular-nums">
                  {r.SMAPE != null ? `${(r.SMAPE * 100).toFixed(1)}%` : "\u2014"}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

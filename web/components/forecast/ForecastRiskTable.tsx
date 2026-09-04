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
    <div className="overflow-x-auto rounded-lg border border-control-border">
      <table className="min-w-full divide-y divide-control-border text-sm">
        <thead className="bg-control-panel text-left text-xs uppercase text-slate-400">
          <tr>
            <th className="px-3 py-2">Part</th>
            <th className="px-3 py-2">Plant</th>
            <th className="px-3 py-2">Predicted stockout</th>
            <th className="px-3 py-2 text-right">Days to stockout</th>
            <th className="px-3 py-2 text-right">Usable inventory</th>
            <th className="px-3 py-2 text-right">Confirmed demand</th>
            <th className="px-3 py-2 text-right">Forecast demand</th>
            <th className="px-3 py-2 text-right">Expected inbound</th>
            <th className="px-3 py-2 text-right">Forecasted shortage</th>
            <th className="px-3 py-2 text-right">Model quality</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-control-border">
          {risks.map((r) => {
            const key = forecastRiskKey(r);
            return (
              <tr
                key={key}
                onClick={() => onSelect(key)}
                className={`cursor-pointer transition-colors ${
                  key === selectedKey ? "bg-control-accent/10" : "hover:bg-white/5"
                }`}
              >
                <td className="px-3 py-2 text-slate-200">{r.PART_ID}</td>
                <td className="px-3 py-2 text-slate-200">{r.PLANT_NAME}</td>
                <td className="px-3 py-2 text-slate-200">{r.PREDICTED_STOCKOUT_DATE ?? "\u2014"}</td>
                <td className="px-3 py-2 text-right text-slate-200">{r.DAYS_TO_PREDICTED_STOCKOUT ?? "\u2014"}</td>
                <td className="px-3 py-2 text-right text-slate-200">{formatQty(r.CURRENT_USABLE_QUANTITY)}</td>
                <td className="px-3 py-2 text-right text-slate-200">{formatQty(r.CONFIRMED_DEMAND_QUANTITY)}</td>
                <td className="px-3 py-2 text-right text-slate-200">{formatQty(r.FORECAST_DEMAND_QUANTITY)}</td>
                <td className="px-3 py-2 text-right text-slate-200">{formatQty(r.EXPECTED_INBOUND_QUANTITY)}</td>
                <td className="px-3 py-2 text-right text-slate-200">{formatQty(r.FORECASTED_SHORTAGE_QUANTITY)}</td>
                <td className="px-3 py-2 text-right text-slate-200">
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

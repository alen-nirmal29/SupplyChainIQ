import { formatQty } from "@/lib/format";
import type { Intervention } from "@/types/risk";

interface InterventionComparisonProps {
  options: Intervention[];
}

/** Purely a table renderer over the deterministic evaluator output --
 * never recomputes feasibility, cost, or ranking. */
export default function InterventionComparison({ options }: InterventionComparisonProps) {
  const recommended = options.find((o) => o.RECOMMENDED === true) ?? null;

  return (
    <div className="space-y-4">
      <div>
        <h3 className="mb-1 text-sm font-semibold text-white">Recommended response</h3>
        {recommended ? (
          <div className="rounded-lg border border-control-border bg-control-panel p-4">
            <div className="text-sm font-medium text-white">
              {recommended.INTERVENTION_TYPE} &mdash; deterministic evaluator recommendation
            </div>
            <div className="mt-2 grid grid-cols-2 gap-3 sm:grid-cols-4">
              <Metric label="Quantity" value={formatQty(recommended.QUANTITY_USED)} />
              <Metric label="Expected arrival" value={recommended.ARRIVAL_DATE ?? "\u2014"} />
              <Metric label="Shortage after" value={formatQty(recommended.SHORTAGE_AFTER)} />
              <Metric label="Recommendation rank" value={String(recommended.RECOMMENDATION_RANK ?? "\u2014")} />
            </div>
            <p className="mt-2 text-sm text-slate-300">{recommended.REASON ?? "No governed reason was returned."}</p>
            <p className="mt-1 text-xs text-slate-500">{recommended.RISKS_OR_CONSTRAINTS ?? ""}</p>
          </div>
        ) : (
          <p className="text-sm text-slate-400">No automatic recommendation is loaded for this risk.</p>
        )}
      </div>

      <div>
        <h3 className="mb-1 text-sm font-semibold text-white">What-if / intervention simulator</h3>
        <p className="mb-2 text-xs text-slate-500">
          SIMULATION ONLY &mdash; this comparison is read-only. It does not create an approval, modify source data,
          or dispatch an action.
        </p>
        <div className="overflow-x-auto rounded-lg border border-control-border">
          <table className="min-w-full divide-y divide-control-border text-sm">
            <thead className="bg-control-panel text-left text-xs uppercase text-slate-400">
              <tr>
                <th className="px-3 py-2">Option</th>
                <th className="px-3 py-2">Feasible</th>
                <th className="px-3 py-2 text-right">Quantity</th>
                <th className="px-3 py-2 text-right">Lead days</th>
                <th className="px-3 py-2">Expected arrival</th>
                <th className="px-3 py-2 text-right">Shortage after</th>
                <th className="px-3 py-2 text-right">Est. cost</th>
                <th className="px-3 py-2">Recommended</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-control-border">
              {options.map((o, i) => (
                <tr key={`${o.INTERVENTION_TYPE}-${i}`} className={o.RECOMMENDED ? "bg-control-accent/10" : undefined}>
                  <td className="px-3 py-2 text-slate-200">{o.INTERVENTION_TYPE}</td>
                  <td className="px-3 py-2 text-slate-200">{o.FEASIBLE ? "Yes" : "No"}</td>
                  <td className="px-3 py-2 text-right text-slate-200">{formatQty(o.QUANTITY_USED)}</td>
                  <td className="px-3 py-2 text-right text-slate-200">{o.TRANSIT_OR_LEAD_DAYS ?? "\u2014"}</td>
                  <td className="px-3 py-2 text-slate-200">{o.ARRIVAL_DATE ?? "\u2014"}</td>
                  <td className="px-3 py-2 text-right text-slate-200">{formatQty(o.SHORTAGE_AFTER)}</td>
                  <td className="px-3 py-2 text-right text-slate-200">
                    {o.ESTIMATED_COST != null ? `${o.CURRENCY ?? ""} ${formatQty(o.ESTIMATED_COST)}` : "\u2014"}
                  </td>
                  <td className="px-3 py-2 text-slate-200">{o.RECOMMENDED ? "Yes" : "No"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-xs uppercase text-slate-500">{label}</div>
      <div className="text-sm text-white">{value}</div>
    </div>
  );
}

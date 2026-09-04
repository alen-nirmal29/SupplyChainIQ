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
    <div className="space-y-6">
      <div>
        <h3 className="section-heading mb-3">Recommended response</h3>
        {recommended ? (
          <div className="relative overflow-hidden rounded-xl border border-emerald-200 bg-emerald-50/65 p-5">
            <div className="absolute inset-y-0 left-0 w-1 bg-emerald-400/70" />
            <div className="text-sm font-semibold text-[#183052]">
              {recommended.INTERVENTION_TYPE} &mdash; deterministic evaluator recommendation
            </div>
            <div className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
              <Metric label="Quantity" value={formatQty(recommended.QUANTITY_USED)} />
              <Metric label="Expected arrival" value={recommended.ARRIVAL_DATE ?? "\u2014"} />
              <Metric label="Shortage after" value={formatQty(recommended.SHORTAGE_AFTER)} />
              <Metric label="Recommendation rank" value={String(recommended.RECOMMENDATION_RANK ?? "\u2014")} />
            </div>
            <p className="mt-4 text-sm leading-6 text-slate-700">{recommended.REASON ?? "No governed reason was returned."}</p>
            <p className="mt-1.5 text-xs leading-5 text-slate-500">{recommended.RISKS_OR_CONSTRAINTS ?? ""}</p>
          </div>
        ) : (
          <p className="text-sm text-slate-500">No automatic recommendation is loaded for this risk.</p>
        )}
      </div>

      <div>
        <h3 className="section-heading mb-1">What-if / intervention simulator</h3>
        <p className="mb-3 text-xs leading-5 text-slate-500">
          SIMULATION ONLY &mdash; this comparison is read-only. It does not create an approval, modify source data,
          or dispatch an action.
        </p>
        <div className="table-shell">
          <table className="data-table">
            <thead>
              <tr>
                <th>Option</th>
                <th>Feasible</th>
                <th className="text-right">Quantity</th>
                <th className="text-right">Lead days</th>
                <th>Expected arrival</th>
                <th className="text-right">Shortage after</th>
                <th className="text-right">Est. cost</th>
                <th>Recommended</th>
              </tr>
            </thead>
            <tbody>
              {options.map((o, i) => (
                <tr key={`${o.INTERVENTION_TYPE}-${i}`} className={o.RECOMMENDED ? "bg-emerald-50" : "transition hover:bg-sky-50/60"}>
                  <td className="font-medium text-slate-800">{o.INTERVENTION_TYPE}</td>
                  <td>{o.FEASIBLE ? "Yes" : "No"}</td>
                  <td className="text-right tabular-nums">{formatQty(o.QUANTITY_USED)}</td>
                  <td className="text-right tabular-nums">{o.TRANSIT_OR_LEAD_DAYS ?? "\u2014"}</td>
                  <td>{o.ARRIVAL_DATE ?? "\u2014"}</td>
                  <td className="text-right tabular-nums">{formatQty(o.SHORTAGE_AFTER)}</td>
                  <td className="text-right tabular-nums">
                    {o.ESTIMATED_COST != null ? `${o.CURRENCY ?? ""} ${formatQty(o.ESTIMATED_COST)}` : "\u2014"}
                  </td>
                  <td className={o.RECOMMENDED ? "font-semibold text-emerald-700" : undefined}>{o.RECOMMENDED ? "Yes" : "No"}</td>
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
    <div className="min-w-0">
      <div className="text-[0.65rem] font-semibold uppercase tracking-[0.08em] text-slate-500">{label}</div>
      <div className="mt-1 truncate text-sm font-medium text-[#183052]">{value}</div>
    </div>
  );
}

"use client";

import { useState } from "react";
import MetricCard from "@/components/ui/MetricCard";
import LoadingState from "@/components/ui/LoadingState";
import ErrorState from "@/components/ui/ErrorState";
import RootCauseChain from "@/components/risk/RootCauseChain";
import RiskScoreBreakdown from "@/components/risk/RiskScoreBreakdown";
import InterventionComparison from "@/components/risk/InterventionComparison";
import { formatCurrencyINR, formatPercent, formatQty } from "@/lib/format";
import type { ConfirmedRisk, Intervention } from "@/types/risk";

interface ConfirmedRiskDetailProps {
  risk: ConfirmedRisk;
}

export default function ConfirmedRiskDetail({ risk }: ConfirmedRiskDetailProps) {
  const [options, setOptions] = useState<Intervention[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadInterventions = () => {
    setLoading(true);
    setError(null);
    fetch(`/api/risks/confirmed/${encodeURIComponent(risk.RISK_ID)}/interventions`)
      .then(async (res) => {
        const json = await res.json();
        if (!res.ok) throw new Error(json.error ?? "Failed to load interventions.");
        setOptions(json.options as Intervention[]);
      })
      .catch((err: Error) => setError(err.message))
      .finally(() => setLoading(false));
  };

  return (
    <div className="space-y-6 rounded-lg border border-control-border bg-control-panel/40 p-5">
      <div>
        <h3 className="text-sm font-semibold text-white">Risk summary</h3>
        <p className="mb-3 text-xs text-slate-400">{risk.PRIMARY_RISK_REASON}</p>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <MetricCard label="Risk score" value={`${risk.RISK_SCORE}/100`} hint={risk.SEVERITY} />
          <MetricCard label="Shortage" value={formatQty(risk.SHORTAGE_QUANTITY)} />
          <MetricCard label="First customer due" value={risk.FIRST_CUSTOMER_DUE_DATE ?? "\u2014"} />
          <MetricCard label="Revenue exposure" value={formatCurrencyINR(risk.REVENUE_EXPOSURE)} />
        </div>
      </div>

      <RiskScoreBreakdown risk={risk} />

      <RootCauseChain risk={risk} />

      <div>
        <h3 className="mb-3 text-sm font-semibold text-white">Key evidence</h3>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
          <MetricCard label="Available" value={formatQty(risk.AVAILABLE_QUANTITY)} />
          <MetricCard label="Safety stock" value={formatQty(risk.SAFETY_STOCK)} />
          <MetricCard label="Requirement" value={formatQty(risk.REQUIREMENT_QUANTITY)} />
          <MetricCard label="Supplier OTD" value={formatPercent(risk.SUPPLIER_OTD_PERCENT)} />
          <MetricCard
            label="Shipment delay"
            value={risk.DELAYED_SHIPMENT_ID ? `${risk.DELAY_DAYS} days` : "No attributed delay"}
          />
        </div>
      </div>

      {options === null ? (
        <div>
          <button
            onClick={loadInterventions}
            className="rounded-md bg-control-accent px-4 py-2 text-sm font-medium text-white hover:bg-blue-600"
          >
            Load intervention comparison
          </button>
          {loading && <div className="mt-3"><LoadingState message="Loading intervention comparison..." /></div>}
          {error && <div className="mt-3"><ErrorState message="Could not load intervention options from the governed evaluator." /></div>}
        </div>
      ) : (
        <InterventionComparison options={options} />
      )}

      <div className="rounded-lg border border-control-border bg-control-panel p-4 text-xs text-slate-400">
        Governed Snowflake data: Yes &middot; Deterministic risk score: Yes &middot; Deterministic intervention
        ranking: Yes &middot; Human approval required: Yes &middot; Fresh-state validation before action: Yes &middot;
        Auditable workflow: Yes
        <br />
        DISPATCHED_DEMO means a governed action command was created in Snowflake; it does not mean SAP, TMS, WMS, or
        another external system was changed.
      </div>
    </div>
  );
}

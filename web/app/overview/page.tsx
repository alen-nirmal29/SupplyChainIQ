"use client";

import { useEffect, useState } from "react";
import MetricCard from "@/components/ui/MetricCard";
import LoadingState from "@/components/ui/LoadingState";
import ErrorState from "@/components/ui/ErrorState";
import StatusBadge from "@/components/ui/StatusBadge";
import { formatCurrencyINR, formatPercent, formatQty } from "@/lib/format";
import type { OverviewResponse } from "@/types/overview";

export default function OverviewPage() {
  const [data, setData] = useState<OverviewResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = () => {
    setLoading(true);
    setError(null);
    fetch("/api/overview")
      .then(async (res) => {
        const json = await res.json();
        if (!res.ok) throw new Error(json.error ?? "Failed to load overview.");
        setData(json as OverviewResponse);
      })
      .catch((err: Error) => setError(err.message))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-white">Executive Overview</h1>
          <p className="text-sm text-slate-400">
            All values below are queried live from the governed Snowflake backend on every load/refresh.
          </p>
        </div>
        <button
          onClick={load}
          className="rounded-md border border-control-border bg-control-panel px-3 py-1.5 text-sm text-slate-200 hover:bg-white/5"
        >
          Refresh Overview
        </button>
      </div>

      {loading && <LoadingState />}
      {error && <ErrorState message="Could not load overview KPIs from Snowflake." />}

      {data && (
        <>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <MetricCard label="Affected customer order lines (P104)" value={formatQty(data.kpis.affectedOrderLines)} />
            <MetricCard label="Revenue exposure (P104 orders)" value={formatCurrencyINR(data.kpis.revenueExposure)} />
            <MetricCard label="Overall Supplier OTD" value={formatPercent(data.kpis.overallOtd)} />
            <MetricCard label="Pinnacle Industries (S017) OTD" value={formatPercent(data.kpis.flagshipSupplierOtd)} />
          </div>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <MetricCard label="Pending approvals" value={formatQty(data.kpis.pendingApprovals)} />
            <MetricCard label="Approved, not yet dispatched" value={formatQty(data.kpis.approvedNotDispatched)} />
            <MetricCard label="Dispatched demo actions" value={formatQty(data.kpis.dispatchedDemoActions)} />
          </div>

          <div className="rounded-lg border border-control-border bg-control-panel p-5">
            {data.topActiveRisk ? (
              <>
                <div className="mb-2 flex items-center gap-3">
                  <h2 className="text-base font-semibold text-white">
                    Top Active Risk: {data.topActiveRisk.PART_DESCRIPTION} at {data.topActiveRisk.PLANT_NAME}
                  </h2>
                  <StatusBadge status={data.topActiveRisk.SEVERITY} />
                </div>
                <p className="mb-4 text-sm text-slate-400">
                  Derived from current governed Risk Radar ranking &middot; Supplier:{" "}
                  <strong>
                    {data.topActiveRisk.SUPPLIER_NAME} ({data.topActiveRisk.SUPPLIER_ID})
                  </strong>
                </p>
                <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
                  <MetricCard label="Risk score" value={`${data.topActiveRisk.RISK_SCORE}/100`} />
                  <MetricCard label="Shortage" value={formatQty(data.topActiveRisk.SHORTAGE_QUANTITY)} />
                  <MetricCard label="Revenue exposure" value={formatCurrencyINR(data.topActiveRisk.REVENUE_EXPOSURE)} />
                  <MetricCard label="Severity" value={data.topActiveRisk.SEVERITY} />
                </div>
                <p className="mt-4 text-sm text-slate-400">
                  Why this is a risk: {data.topActiveRisk.PRIMARY_RISK_REASON} Open Risk Radar for evidence,
                  deterministic options, and comparison.
                </p>
              </>
            ) : (
              <p className="text-sm text-slate-400">
                Risk Radar found no current shortage risks in the governed data.
              </p>
            )}
          </div>
        </>
      )}
    </div>
  );
}

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
    <div className="page-shell">
      <div className="page-header">
        <div>
          <h1 className="page-title">Executive Overview</h1>
          <p className="page-description">
            All values below are queried live from the governed Snowflake backend on every load/refresh.
          </p>
        </div>
        <button
          onClick={load}
          className="button-secondary shrink-0"
        >
          Refresh Overview
        </button>
      </div>

      {loading && <LoadingState />}
      {error && <ErrorState message="Could not load overview KPIs from Snowflake." />}

      {data && (
        <>
          <div className="metric-grid grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <MetricCard label="Affected customer order lines (P104)" value={formatQty(data.kpis.affectedOrderLines)} />
            <MetricCard label="Revenue exposure (P104 orders)" value={formatCurrencyINR(data.kpis.revenueExposure)} />
            <MetricCard label="Overall Supplier OTD" value={formatPercent(data.kpis.overallOtd)} />
            <MetricCard label="Pinnacle Industries (S017) OTD" value={formatPercent(data.kpis.flagshipSupplierOtd)} />
          </div>

          <div className="metric-grid grid grid-cols-1 gap-3 sm:grid-cols-3">
            <MetricCard label="Pending approvals" value={formatQty(data.kpis.pendingApprovals)} />
            <MetricCard label="Approved, not yet dispatched" value={formatQty(data.kpis.approvedNotDispatched)} />
            <MetricCard label="Dispatched demo actions" value={formatQty(data.kpis.dispatchedDemoActions)} />
          </div>

          <div className="surface-strong relative overflow-hidden border-blue-200/80 p-5 sm:p-6">
            <div className="pointer-events-none absolute right-0 top-0 h-40 w-40 rounded-full bg-violet-300/20 blur-3xl" />
            {data.topActiveRisk ? (
              <>
                <div className="relative mb-2 flex flex-wrap items-center gap-3">
                  <h2 className="text-base font-semibold tracking-[-0.015em] text-[#10213f]">
                    Top Active Risk: {data.topActiveRisk.PART_DESCRIPTION} at {data.topActiveRisk.PLANT_NAME}
                  </h2>
                  <StatusBadge status={data.topActiveRisk.SEVERITY} />
                </div>
                <p className="relative mb-5 text-sm leading-6 text-slate-500">
                  Derived from current governed Risk Radar ranking &middot; Supplier:{" "}
                  <strong>
                    {data.topActiveRisk.SUPPLIER_NAME} ({data.topActiveRisk.SUPPLIER_ID})
                  </strong>
                </p>
                <div className="metric-grid relative grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
                  <MetricCard label="Risk score" value={`${data.topActiveRisk.RISK_SCORE}/100`} />
                  <MetricCard label="Shortage" value={formatQty(data.topActiveRisk.SHORTAGE_QUANTITY)} />
                  <MetricCard label="Revenue exposure" value={formatCurrencyINR(data.topActiveRisk.REVENUE_EXPOSURE)} />
                  <MetricCard label="Severity" value={data.topActiveRisk.SEVERITY} />
                </div>
                <p className="relative mt-5 border-l-2 border-blue-400/70 pl-3 text-sm leading-6 text-slate-600">
                  Why this is a risk: {data.topActiveRisk.PRIMARY_RISK_REASON} Open Risk Radar for evidence,
                  deterministic options, and comparison.
                </p>
              </>
            ) : (
              <p className="text-sm text-slate-500">
                Risk Radar found no current shortage risks in the governed data.
              </p>
            )}
          </div>
        </>
      )}
    </div>
  );
}

"use client";

import { useEffect, useMemo, useState } from "react";
import MetricCard from "@/components/ui/MetricCard";
import LoadingState from "@/components/ui/LoadingState";
import ErrorState from "@/components/ui/ErrorState";
import EmptyState from "@/components/ui/EmptyState";
import ConfirmedRiskTable from "@/components/risk/ConfirmedRiskTable";
import ConfirmedRiskDetail from "@/components/risk/ConfirmedRiskDetail";
import ForecastSummary from "@/components/forecast/ForecastSummary";
import StockoutTimingChart from "@/components/forecast/StockoutTimingChart";
import ForecastRiskTable, { forecastRiskKey } from "@/components/forecast/ForecastRiskTable";
import ForecastRiskDetail from "@/components/forecast/ForecastRiskDetail";
import { formatCurrencyINR } from "@/lib/format";
import type { ConfirmedRisk, ConfirmedRiskSummary } from "@/types/risk";
import type { ForecastedStockoutRisk, ForecastedStockoutSummary } from "@/types/forecast";

type Tab = "confirmed" | "predictive";

export default function RiskRadarPage() {
  const [tab, setTab] = useState<Tab>("confirmed");

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-white">Risk Radar</h1>
        <p className="text-sm text-slate-400">
          Risk Radar evaluates current governed supply-chain data when this page loads or is refreshed; it is not
          continuous monitoring.
        </p>
      </div>

      <div className="flex gap-2 border-b border-control-border">
        <TabButton active={tab === "confirmed"} onClick={() => setTab("confirmed")}>
          Confirmed Risks
        </TabButton>
        <TabButton active={tab === "predictive"} onClick={() => setTab("predictive")}>
          Predictive Early Warnings
        </TabButton>
      </div>

      {tab === "confirmed" ? <ConfirmedRisksTab /> : <PredictiveWarningsTab />}
    </div>
  );
}

function TabButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={`px-4 py-2 text-sm font-medium transition-colors ${
        active ? "border-b-2 border-control-accent text-white" : "text-slate-400 hover:text-slate-200"
      }`}
    >
      {children}
    </button>
  );
}

function ConfirmedRisksTab() {
  const [summary, setSummary] = useState<ConfirmedRiskSummary | null>(null);
  const [risks, setRisks] = useState<ConfirmedRisk[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    setError(null);
    fetch("/api/risks/confirmed")
      .then(async (res) => {
        const json = await res.json();
        if (!res.ok) throw new Error(json.error ?? "Failed to load confirmed risks.");
        setSummary(json.summary as ConfirmedRiskSummary);
        setRisks(json.risks as ConfirmedRisk[]);
        setSelectedId((json.risks as ConfirmedRisk[])[0]?.RISK_ID ?? null);
      })
      .catch((err: Error) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  const selected = useMemo(() => risks.find((r) => r.RISK_ID === selectedId) ?? null, [risks, selectedId]);

  return (
    <div className="space-y-4">
      <p className="text-xs text-slate-500">
        Confirmed risks are based on known open customer demand and current operational state.
      </p>

      {loading && <LoadingState />}
      {error && <ErrorState message="Risk Radar is unavailable until its governed RISK views are deployed to DEV." />}

      {summary && (
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-5">
          <MetricCard label="Active risks" value={summary.ACTIVE_RISKS} />
          <MetricCard label="Critical" value={summary.CRITICAL_RISKS} />
          <MetricCard label="High" value={summary.HIGH_RISKS} />
          <MetricCard label="Medium" value={summary.MEDIUM_RISKS} />
          <MetricCard label="Revenue exposure" value={formatCurrencyINR(summary.REVENUE_EXPOSURE)} />
        </div>
      )}

      {!loading && !error && risks.length === 0 && (
        <EmptyState message="No current shortage risks met the governed Risk Radar criteria." />
      )}

      {risks.length > 0 && (
        <>
          <ConfirmedRiskTable risks={risks} selectedId={selectedId} onSelect={setSelectedId} />
          {selected && <ConfirmedRiskDetail risk={selected} />}
        </>
      )}
    </div>
  );
}

function PredictiveWarningsTab() {
  const [summary, setSummary] = useState<ForecastedStockoutSummary | null>(null);
  const [risks, setRisks] = useState<ForecastedStockoutRisk[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedKey, setSelectedKey] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    setError(null);
    fetch("/api/risks/predictive")
      .then(async (res) => {
        const json = await res.json();
        if (!res.ok) throw new Error(json.error ?? "Failed to load predictive early warnings.");
        const fetchedRisks = json.risks as ForecastedStockoutRisk[];
        setSummary(json.summary as ForecastedStockoutSummary);
        setRisks(fetchedRisks);
        setSelectedKey(defaultPredictiveSelection(fetchedRisks));
      })
      .catch((err: Error) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  const selected = useMemo(
    () => risks.find((r) => forecastRiskKey(r) === selectedKey) ?? null,
    [risks, selectedKey]
  );

  return (
    <div className="space-y-4">
      <p className="text-xs text-slate-500">
        Potential future stockouts identified from Snowflake ML demand forecasts. These are predictive signals, not
        confirmed customer-order shortages.
      </p>

      {loading && <LoadingState />}
      {error && (
        <ErrorState message="Predictive Early Warnings are unavailable until the governed forecast objects are deployed." />
      )}

      {summary && <ForecastSummary summary={summary} />}

      {!loading && !error && risks.length === 0 && (
        <EmptyState message="No forecast-only early warnings currently identified beyond confirmed Risk Radar." />
      )}

      {summary && risks.length > 0 && (
        <>
          <StockoutTimingChart summary={summary} />
          <ForecastRiskTable risks={risks} selectedKey={selectedKey} onSelect={setSelectedKey} />
          {selected && <ForecastRiskDetail risk={selected} />}
        </>
      )}
    </div>
  );
}

/** Default-selection rule: prefer a genuinely future warning
 * (days-to-stockout > 0), earliest such stockout first, then highest
 * forecasted shortage as the tie-break -- so the app does not default to a
 * Day-0 / zero-inventory case when a stronger forward-looking example
 * exists. Mirrors the validated Streamlit behavior. */
function defaultPredictiveSelection(risks: ForecastedStockoutRisk[]): string | null {
  if (risks.length === 0) return null;
  const future = risks.filter((r) => (r.DAYS_TO_PREDICTED_STOCKOUT ?? 0) > 0);
  const pool = future.length > 0 ? future : risks;
  const best = [...pool].sort((a, b) => {
    const daysDiff = (a.DAYS_TO_PREDICTED_STOCKOUT ?? 0) - (b.DAYS_TO_PREDICTED_STOCKOUT ?? 0);
    if (daysDiff !== 0) return daysDiff;
    return (b.FORECASTED_SHORTAGE_QUANTITY ?? 0) - (a.FORECASTED_SHORTAGE_QUANTITY ?? 0);
  })[0];
  return best ? forecastRiskKey(best) : null;
}

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
const PAGE_SIZE = 20;

export default function RiskRadarPage() {
  const [tab, setTab] = useState<Tab>("confirmed");

  return (
    <div className="page-shell">
      <div className="page-header">
        <div>
        <h1 className="page-title">Risk Radar</h1>
        <p className="page-description">
          Risk Radar evaluates current governed supply-chain data when this page loads or is refreshed; it is not
          continuous monitoring.
        </p>
        </div>
      </div>

      <div className="flex w-full gap-1 rounded-xl border border-sky-200/80 bg-white/65 p-1 shadow-sm sm:w-fit">
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
      className={`flex-1 rounded-lg px-4 py-2.5 text-sm font-medium transition duration-200 sm:flex-none ${
        active
          ? "bg-blue-500 text-white shadow-md shadow-blue-200/80"
          : "text-slate-500 hover:bg-sky-50 hover:text-blue-700"
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
  const [search, setSearch] = useState("");
  const [severity, setSeverity] = useState("ALL");
  const [supplier, setSupplier] = useState("ALL");
  const [plant, setPlant] = useState("ALL");
  const [page, setPage] = useState(1);

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

  const suppliers = useMemo(() => [...new Set(risks.map((risk) => risk.SUPPLIER_NAME))].sort(), [risks]);
  const plants = useMemo(() => [...new Set(risks.map((risk) => risk.PLANT_NAME))].sort(), [risks]);
  const filteredRisks = useMemo(() => {
    const term = search.trim().toLowerCase();
    return risks.filter((risk) => {
      const matchesSearch =
        !term ||
        [
          risk.RISK_ID,
          risk.SUPPLIER_ID,
          risk.SUPPLIER_NAME,
          risk.PART_ID,
          risk.PART_DESCRIPTION,
          risk.PLANT_ID,
          risk.PLANT_NAME,
        ].some((value) => value?.toLowerCase().includes(term));
      return (
        matchesSearch &&
        (severity === "ALL" || risk.SEVERITY === severity) &&
        (supplier === "ALL" || risk.SUPPLIER_NAME === supplier) &&
        (plant === "ALL" || risk.PLANT_NAME === plant)
      );
    });
  }, [risks, search, severity, supplier, plant]);
  const pageCount = Math.max(1, Math.ceil(filteredRisks.length / PAGE_SIZE));
  const currentPage = Math.min(page, pageCount);
  const visibleRisks = useMemo(
    () => filteredRisks.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE),
    [filteredRisks, currentPage]
  );
  const selected = useMemo(
    () => visibleRisks.find((risk) => risk.RISK_ID === selectedId) ?? visibleRisks[0] ?? null,
    [visibleRisks, selectedId]
  );
  const resetConfirmedFilters = () => {
    setSearch("");
    setSeverity("ALL");
    setSupplier("ALL");
    setPlant("ALL");
    setPage(1);
  };

  return (
    <div className="space-y-5">
      <p className="callout border-l-2 border-l-blue-400/70 bg-blue-50/45 text-xs">
        Confirmed risks are based on known open customer demand and current operational state.
      </p>

      {loading && <LoadingState />}
      {error && <ErrorState message="Risk Radar is unavailable until its governed RISK views are deployed to DEV." />}

      {summary && (
        <div className="metric-grid grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
          <MetricCard label="Active risks" value={summary.ACTIVE_RISKS} />
          <MetricCard label="Critical" value={summary.CRITICAL_RISKS} />
          <MetricCard label="High" value={summary.HIGH_RISKS} />
          <MetricCard label="Medium" value={summary.MEDIUM_RISKS} />
          <MetricCard label="Revenue exposure" value={formatCurrencyINR(summary.REVENUE_EXPOSURE)} />
        </div>
      )}

      {risks.length > 0 && (
        <div className="surface space-y-4 p-4 sm:p-5">
          <div className="flex flex-col gap-3 xl:flex-row xl:items-end">
            <label className="min-w-0 flex-1">
              <span className="mb-1.5 block text-xs font-semibold text-slate-600">Search confirmed risks</span>
              <input
                value={search}
                onChange={(event) => {
                  setSearch(event.target.value);
                  setPage(1);
                }}
                placeholder="Search risk, supplier, part, or plant"
                className="field w-full"
              />
            </label>
            <label className="xl:w-44">
              <span className="mb-1.5 block text-xs font-semibold text-slate-600">Severity</span>
              <select
                value={severity}
                onChange={(event) => {
                  setSeverity(event.target.value);
                  setPage(1);
                }}
                className="field w-full"
              >
                <option value="ALL">All severities</option>
                <option value="CRITICAL">Critical</option>
                <option value="HIGH">High</option>
                <option value="MEDIUM">Medium</option>
                <option value="LOW">Low</option>
              </select>
            </label>
            <label className="xl:w-56">
              <span className="mb-1.5 block text-xs font-semibold text-slate-600">Supplier</span>
              <select
                value={supplier}
                onChange={(event) => {
                  setSupplier(event.target.value);
                  setPage(1);
                }}
                className="field w-full"
              >
                <option value="ALL">All suppliers</option>
                {suppliers.map((option) => <option key={option} value={option}>{option}</option>)}
              </select>
            </label>
            <label className="xl:w-56">
              <span className="mb-1.5 block text-xs font-semibold text-slate-600">Plant</span>
              <select
                value={plant}
                onChange={(event) => {
                  setPlant(event.target.value);
                  setPage(1);
                }}
                className="field w-full"
              >
                <option value="ALL">All plants</option>
                {plants.map((option) => <option key={option} value={option}>{option}</option>)}
              </select>
            </label>
            <button type="button" onClick={resetConfirmedFilters} className="button-secondary shrink-0">
              Clear filters
            </button>
          </div>
          <ResultSummary filteredCount={filteredRisks.length} totalCount={risks.length} page={currentPage} />
        </div>
      )}

      {!loading && !error && risks.length === 0 && (
        <EmptyState message="No current shortage risks met the governed Risk Radar criteria." />
      )}

      {risks.length > 0 && (
        <>
          {filteredRisks.length > 0 ? (
            <>
              <ConfirmedRiskTable risks={visibleRisks} selectedId={selected?.RISK_ID ?? null} onSelect={setSelectedId} />
              <Pagination page={currentPage} pageCount={pageCount} onPageChange={setPage} />
            </>
          ) : (
            <EmptyState message="No confirmed risks match the selected filters." />
          )}
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
  const [search, setSearch] = useState("");
  const [plant, setPlant] = useState("ALL");
  const [horizon, setHorizon] = useState("ALL");
  const [page, setPage] = useState(1);

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

  const plants = useMemo(() => [...new Set(risks.map((risk) => risk.PLANT_NAME))].sort(), [risks]);
  const filteredRisks = useMemo(() => {
    const term = search.trim().toLowerCase();
    return risks.filter((risk) => {
      const days = risk.DAYS_TO_PREDICTED_STOCKOUT;
      const matchesSearch =
        !term ||
        [risk.PART_ID, risk.PART_DESCRIPTION, risk.PLANT_ID, risk.PLANT_NAME].some((value) =>
          value?.toLowerCase().includes(term)
        );
      const matchesHorizon =
        horizon === "ALL" ||
        (horizon === "DAY0" && days === 0) ||
        (horizon === "DAY1_7" && days != null && days >= 1 && days <= 7) ||
        (horizon === "DAY8_14" && days != null && days >= 8 && days <= 14);
      return matchesSearch && matchesHorizon && (plant === "ALL" || risk.PLANT_NAME === plant);
    });
  }, [risks, search, plant, horizon]);
  const pageCount = Math.max(1, Math.ceil(filteredRisks.length / PAGE_SIZE));
  const currentPage = Math.min(page, pageCount);
  const visibleRisks = useMemo(
    () => filteredRisks.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE),
    [filteredRisks, currentPage]
  );
  const selected = useMemo(
    () => visibleRisks.find((risk) => forecastRiskKey(risk) === selectedKey) ?? visibleRisks[0] ?? null,
    [visibleRisks, selectedKey]
  );
  const resetPredictiveFilters = () => {
    setSearch("");
    setPlant("ALL");
    setHorizon("ALL");
    setPage(1);
  };

  return (
    <div className="space-y-5">
      <p className="callout border-l-2 border-l-violet-400/70 bg-violet-50/45 text-xs">
        Potential future stockouts identified from Snowflake ML demand forecasts. These are predictive signals, not
        confirmed customer-order shortages.
      </p>

      {loading && <LoadingState />}
      {error && (
        <ErrorState message="Predictive Early Warnings are unavailable until the governed forecast objects are deployed." />
      )}

      {summary && <ForecastSummary summary={summary} />}

      {risks.length > 0 && (
        <div className="surface space-y-4 p-4 sm:p-5">
          <div className="flex flex-col gap-3 lg:flex-row lg:items-end">
            <label className="min-w-0 flex-1">
              <span className="mb-1.5 block text-xs font-semibold text-slate-600">Search predictive warnings</span>
              <input
                value={search}
                onChange={(event) => {
                  setSearch(event.target.value);
                  setPage(1);
                }}
                placeholder="Search part or plant"
                className="field w-full"
              />
            </label>
            <label className="lg:w-60">
              <span className="mb-1.5 block text-xs font-semibold text-slate-600">Plant</span>
              <select
                value={plant}
                onChange={(event) => {
                  setPlant(event.target.value);
                  setPage(1);
                }}
                className="field w-full"
              >
                <option value="ALL">All plants</option>
                {plants.map((option) => <option key={option} value={option}>{option}</option>)}
              </select>
            </label>
            <label className="lg:w-52">
              <span className="mb-1.5 block text-xs font-semibold text-slate-600">Stockout horizon</span>
              <select
                value={horizon}
                onChange={(event) => {
                  setHorizon(event.target.value);
                  setPage(1);
                }}
                className="field w-full"
              >
                <option value="ALL">All horizons</option>
                <option value="DAY0">Immediate / Day 0</option>
                <option value="DAY1_7">1–7 days</option>
                <option value="DAY8_14">8–14 days</option>
              </select>
            </label>
            <button type="button" onClick={resetPredictiveFilters} className="button-secondary shrink-0">
              Clear filters
            </button>
          </div>
          <ResultSummary filteredCount={filteredRisks.length} totalCount={risks.length} page={currentPage} />
        </div>
      )}

      {!loading && !error && risks.length === 0 && (
        <EmptyState message="No forecast-only early warnings currently identified beyond confirmed Risk Radar." />
      )}

      {summary && risks.length > 0 && (
        <>
          <StockoutTimingChart summary={summary} />
          {filteredRisks.length > 0 ? (
            <>
              <ForecastRiskTable risks={visibleRisks} selectedKey={selected ? forecastRiskKey(selected) : null} onSelect={setSelectedKey} />
              <Pagination page={currentPage} pageCount={pageCount} onPageChange={setPage} />
            </>
          ) : (
            <EmptyState message="No predictive early warnings match the selected filters." />
          )}
          {selected && <ForecastRiskDetail risk={selected} />}
        </>
      )}
    </div>
  );
}

function ResultSummary({ filteredCount, totalCount, page }: { filteredCount: number; totalCount: number; page: number }) {
  const first = filteredCount === 0 ? 0 : (page - 1) * PAGE_SIZE + 1;
  const last = Math.min(page * PAGE_SIZE, filteredCount);
  return (
    <div className="flex flex-wrap items-center justify-between gap-2 border-t border-slate-200/70 pt-3 text-xs text-slate-500">
      <span>Showing {first}–{last} of {filteredCount} matching records</span>
      <span>{totalCount} total records</span>
    </div>
  );
}

function Pagination({ page, pageCount, onPageChange }: { page: number; pageCount: number; onPageChange: (page: number) => void }) {
  if (pageCount <= 1) return null;
  return (
    <div className="flex items-center justify-between gap-3">
      <button type="button" onClick={() => onPageChange(page - 1)} disabled={page === 1} className="button-secondary">
        Previous
      </button>
      <span className="text-xs font-medium text-slate-500">Page {page} of {pageCount}</span>
      <button type="button" onClick={() => onPageChange(page + 1)} disabled={page === pageCount} className="button-secondary">
        Next
      </button>
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

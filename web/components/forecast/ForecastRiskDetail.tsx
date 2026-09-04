"use client";

import { useEffect, useState } from "react";
import MetricCard from "@/components/ui/MetricCard";
import LoadingState from "@/components/ui/LoadingState";
import ErrorState from "@/components/ui/ErrorState";
import ForecastPathChart from "@/components/forecast/ForecastPathChart";
import { formatQty } from "@/lib/format";
import type { ForecastedStockoutRisk, ForecastPoint } from "@/types/forecast";

interface ForecastRiskDetailProps {
  risk: ForecastedStockoutRisk;
}

export default function ForecastRiskDetail({ risk }: ForecastRiskDetailProps) {
  const [points, setPoints] = useState<ForecastPoint[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    setError(null);
    fetch(`/api/risks/predictive/${encodeURIComponent(risk.PART_ID)}/${encodeURIComponent(risk.PLANT_ID)}/forecast`)
      .then(async (res) => {
        const json = await res.json();
        if (!res.ok) throw new Error(json.error ?? "Failed to load the forecast trajectory.");
        setPoints(json.points as ForecastPoint[]);
      })
      .catch((err: Error) => setError(err.message))
      .finally(() => setLoading(false));
  }, [risk.PART_ID, risk.PLANT_ID]);

  // Phase 2.1 rule: use the persisted single-day bound for the predicted
  // stockout date only -- never the naive 14-day summed
  // LOWER_PREDICTION_BOUND/UPPER_PREDICTION_BOUND from the risk row.
  const stockoutDayPoint =
    points && risk.PREDICTED_STOCKOUT_DATE
      ? points.find((p) => String(p.FORECAST_DATE) === String(risk.PREDICTED_STOCKOUT_DATE)) ?? null
      : null;

  const usable = risk.CURRENT_USABLE_QUANTITY ?? 0;
  const inbound = risk.EXPECTED_INBOUND_QUANTITY ?? 0;

  return (
    <div className="space-y-6 rounded-lg border border-control-border bg-control-panel/40 p-5">
      <div className="rounded-md border border-yellow-500/40 bg-yellow-500/10 px-3 py-2 text-sm text-yellow-200">
        Forecast-based early warning &mdash; not confirmed demand.
      </div>

      <div className="flex flex-wrap gap-6">
        <MetricCard label="Part" value={`${risk.PART_ID} \u2014 ${risk.PART_DESCRIPTION ?? "\u2014"}`} />
        <MetricCard label="Plant" value={`${risk.PLANT_NAME ?? risk.PLANT_ID} \u2014 ${risk.PLANT_ID}`} />
      </div>
      <p className="text-xs text-slate-500">
        Current status: no confirmed shortage is currently detected for this Part + Plant (confirmed Risk Radar
        always takes precedence and is checked before this warning is shown).
      </p>

      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <MetricCard label="Current usable inventory" value={formatQty(risk.CURRENT_USABLE_QUANTITY)} />
        <MetricCard label="Confirmed 14-day demand" value={formatQty(risk.CONFIRMED_DEMAND_QUANTITY)} />
        <MetricCard label="Forecast 14-day demand" value={formatQty(risk.FORECAST_DEMAND_QUANTITY)} />
        <MetricCard label="Expected inbound" value={formatQty(risk.EXPECTED_INBOUND_QUANTITY)} />
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <MetricCard label="Forecasted shortage" value={formatQty(risk.FORECASTED_SHORTAGE_QUANTITY)} />
        <MetricCard label="Predicted stockout" value={risk.PREDICTED_STOCKOUT_DATE ?? "\u2014"} />
        <MetricCard label="Days to stockout" value={risk.DAYS_TO_PREDICTED_STOCKOUT ?? "\u2014"} />
      </div>

      <p className="text-xs text-slate-500">
        {risk.SMAPE != null ? `Forecast model quality: SMAPE ${(risk.SMAPE * 100).toFixed(1)}%` : "Forecast model quality: unavailable"}
      </p>

      <div className="rounded-md border border-control-border bg-control-panel px-3 py-2 text-xs text-slate-400">
        Confirmed demand represents known open customer orders. Forecast demand estimates total expected demand
        based on historical patterns. The two values are not added together.
      </div>

      <div>
        <h4 className="mb-2 text-sm font-semibold text-white">Why this warning exists</h4>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <MetricCard label="Projected supply (usable + inbound)" value={formatQty(usable + inbound)} />
          <MetricCard label="Forecast demand (14d)" value={formatQty(risk.FORECAST_DEMAND_QUANTITY)} />
          <MetricCard label="Gap" value={formatQty(risk.FORECASTED_SHORTAGE_QUANTITY)} />
        </div>
      </div>

      {loading && <LoadingState message="Loading the daily forecast trajectory..." />}
      {error && <ErrorState message="Could not load the daily forecast trajectory." />}

      {points && points.length > 0 && (
        <>
          <ForecastPathChart points={points} />

          {stockoutDayPoint && (
            <div>
              <h4 className="mb-2 text-sm font-semibold text-white">Forecast on predicted stockout date</h4>
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
                <MetricCard label="Predicted demand that day" value={formatQty(stockoutDayPoint.FORECAST_VALUE)} />
                <MetricCard label="Lower bound" value={formatQty(stockoutDayPoint.LOWER_BOUND)} />
                <MetricCard label="Upper bound" value={formatQty(stockoutDayPoint.UPPER_BOUND)} />
              </div>
              <p className="mt-2 text-xs text-slate-500">
                Prediction interval shown is Snowflake ML&apos;s single-day forecast bound for the predicted
                stockout date only &mdash; it is not a summed 14-day confidence interval.
              </p>
            </div>
          )}
        </>
      )}

      <div className="rounded-md border border-control-border bg-control-panel px-3 py-2 text-xs text-slate-400">
        Predictive warnings are currently intended for early investigation and planning. Intervention evaluation
        remains available for confirmed operational risks.
      </div>
    </div>
  );
}

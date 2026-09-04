import { NextResponse } from "next/server";
import { query } from "@/lib/snowflake/query";
import type { ForecastPoint } from "@/types/forecast";

/**
 * Persisted daily forecast trajectory for one series -- read only from
 * RISK.FORECASTED_DEMAND. FORECAST_DATE is cast to DATE server-side so it
 * compares cleanly against PREDICTED_STOCKOUT_DATE from the risk row.
 *
 * IMPORTANT (Phase 2.1 rule): the caller must use the single-day
 * LOWER_BOUND/FORECAST_VALUE/UPPER_BOUND for the predicted stockout date
 * only. The 14-day summed LOWER_PREDICTION_BOUND/UPPER_PREDICTION_BOUND on
 * the risk row is NOT a calibrated aggregate interval and must never be
 * presented as one.
 */
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ part: string; plant: string }> }
) {
  const { part, plant } = await params;

  try {
    const points = await query<ForecastPoint>(
      `SELECT FORECAST_DATE::DATE AS FORECAST_DATE, FORECAST_VALUE, LOWER_BOUND, UPPER_BOUND
       FROM SUPPLYCHAINIQ_DB.RISK.FORECASTED_DEMAND
       WHERE PART_ID = ? AND PLANT_ID = ?
       ORDER BY FORECAST_DATE`,
      [part, plant]
    );

    return NextResponse.json({ points });
  } catch {
    return NextResponse.json({ error: "Could not load the forecast trajectory from Snowflake." }, { status: 502 });
  }
}

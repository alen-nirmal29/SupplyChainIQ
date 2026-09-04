import { NextResponse } from "next/server";
import { query } from "@/lib/snowflake/query";
import type { ForecastedStockoutRisk, ForecastedStockoutSummary } from "@/types/forecast";

export async function GET() {
  try {
    const [summaryRows, riskRows] = await Promise.all([
      query<ForecastedStockoutSummary>(
        `SELECT
           COUNT(*) AS TOTAL_WARNINGS,
           COUNT_IF(DAYS_TO_PREDICTED_STOCKOUT = 0) AS DAY0,
           COUNT_IF(DAYS_TO_PREDICTED_STOCKOUT BETWEEN 1 AND 2) AS DAY1_2,
           COUNT_IF(DAYS_TO_PREDICTED_STOCKOUT BETWEEN 3 AND 7) AS DAY3_7,
           COUNT_IF(DAYS_TO_PREDICTED_STOCKOUT BETWEEN 8 AND 14) AS DAY8_14,
           (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.RISK.FORECAST_MODEL_QUALITY WHERE SMAPE <= 0.5) AS ACCEPTED_SERIES
         FROM SUPPLYCHAINIQ_DB.RISK.FORECASTED_STOCKOUT_RISK`
      ),
      query<ForecastedStockoutRisk>(
        `SELECT f.*, q.SMAPE
         FROM SUPPLYCHAINIQ_DB.RISK.FORECASTED_STOCKOUT_RISK f
         LEFT JOIN SUPPLYCHAINIQ_DB.RISK.FORECAST_MODEL_QUALITY q
           ON q.PART_ID = f.PART_ID AND q.PLANT_ID = f.PLANT_ID
         ORDER BY f.PREDICTED_STOCKOUT_DATE ASC, f.FORECASTED_SHORTAGE_QUANTITY DESC, f.PART_ID, f.PLANT_ID`
      ),
    ]);

    return NextResponse.json({ summary: summaryRows[0] ?? null, risks: riskRows });
  } catch {
    return NextResponse.json({ error: "Could not load predictive early warnings from Snowflake." }, { status: 502 });
  }
}

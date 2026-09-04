/** Domain types mirroring RISK.FORECASTED_STOCKOUT_RISK / FORECASTED_DEMAND / FORECAST_MODEL_QUALITY. */
export interface ForecastedStockoutRisk {
  PART_ID: string;
  PART_DESCRIPTION: string;
  PLANT_ID: string;
  PLANT_NAME: string;
  FORECAST_START_DATE: string;
  FORECAST_END_DATE: string;
  CURRENT_AVAILABLE_QUANTITY: number;
  SAFETY_STOCK: number;
  CURRENT_USABLE_QUANTITY: number;
  CONFIRMED_DEMAND_QUANTITY: number;
  FORECAST_DEMAND_QUANTITY: number;
  EXPECTED_INBOUND_QUANTITY: number;
  FORECASTED_SHORTAGE_QUANTITY: number;
  PREDICTED_STOCKOUT_DATE: string | null;
  DAYS_TO_PREDICTED_STOCKOUT: number | null;
  LOWER_PREDICTION_BOUND: number;
  UPPER_PREDICTION_BOUND: number;
  MODEL_NAME: string;
  GENERATED_AT: string;
  REFERENCE_DATE: string;
  /** Joined from RISK.FORECAST_MODEL_QUALITY -- not part of the base view. */
  SMAPE: number | null;
}

export interface ForecastedStockoutSummary {
  TOTAL_WARNINGS: number;
  DAY0: number;
  DAY1_2: number;
  DAY3_7: number;
  DAY8_14: number;
  ACCEPTED_SERIES: number;
}

/** One row of RISK.FORECASTED_DEMAND for a single PART_ID+PLANT_ID series. */
export interface ForecastPoint {
  FORECAST_DATE: string;
  FORECAST_VALUE: number;
  LOWER_BOUND: number;
  UPPER_BOUND: number;
}

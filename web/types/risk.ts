/** Domain types mirroring RISK.SUPPLY_CHAIN_RISK_RANKING (confirmed, deterministic risk). */
export interface ConfirmedRisk {
  RISK_ID: string;
  RISK_RANK: number;
  RISK_SCORE: number;
  SEVERITY: "CRITICAL" | "HIGH" | "MEDIUM" | "LOW";
  SUPPLIER_ID: string;
  SUPPLIER_NAME: string;
  PART_ID: string;
  PART_DESCRIPTION: string;
  PLANT_ID: string;
  PLANT_NAME: string;
  AVAILABLE_QUANTITY: number;
  SAFETY_STOCK: number;
  USABLE_QUANTITY: number;
  REQUIREMENT_QUANTITY: number;
  SHORTAGE_QUANTITY: number;
  FIRST_CUSTOMER_DUE_DATE: string | null;
  AFFECTED_ORDER_LINES: number;
  REVENUE_EXPOSURE: number | null;
  DELAYED_SHIPMENT_ID: string | null;
  SHIPMENT_STATUS: string | null;
  DELAY_DAYS: number | null;
  EXPECTED_ARRIVAL_DATE: string | null;
  SUPPLIER_OTD_PERCENT: number | null;
  SHORTAGE_SCORE: number;
  URGENCY_SCORE: number;
  REVENUE_SCORE: number;
  SHIPMENT_SCORE: number;
  SUPPLIER_SCORE: number;
  PRIMARY_RISK_REASON: string;
  REFERENCE_DATE: string;
}

export interface ConfirmedRiskSummary {
  ACTIVE_RISKS: number;
  CRITICAL_RISKS: number;
  HIGH_RISKS: number;
  MEDIUM_RISKS: number;
  REVENUE_EXPOSURE: number | null;
}

/** DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS(...) result item. */
export interface Intervention {
  INTERVENTION_TYPE: string;
  FEASIBLE: boolean;
  QUANTITY_USED?: number;
  QUANTITY_AVAILABLE?: number;
  TRANSIT_OR_LEAD_DAYS?: number;
  ARRIVAL_DATE?: string;
  ARRIVES_IN_TIME?: boolean;
  SHORTAGE_BEFORE?: number;
  SHORTAGE_AFTER?: number;
  ESTIMATED_COST?: number;
  CURRENCY?: string;
  COST_BASIS?: string;
  COST_COMPARABLE?: boolean;
  RECOMMENDATION_RANK?: number;
  RECOMMENDED?: boolean;
  REASON?: string;
  RISKS_OR_CONSTRAINTS?: string;
  SOURCE_SUPPLIER?: string;
  SOURCE_LOCATION?: string;
  FIRST_CUSTOMER_DUE_DATE?: string;
  REFERENCE_DATE?: string;
}

/** Domain type for the Overview page KPIs (pure aggregation of existing governed data). */
export interface OverviewKpis {
  affectedOrderLines: number | null;
  revenueExposure: number | null;
  overallOtd: number | null;
  flagshipSupplierOtd: number | null;
  pendingApprovals: number;
  approvedNotDispatched: number;
  dispatchedDemoActions: number;
}

export interface TopActiveRisk {
  RISK_ID: string;
  PART_DESCRIPTION: string;
  PLANT_NAME: string;
  SUPPLIER_NAME: string;
  SUPPLIER_ID: string;
  SEVERITY: string;
  RISK_SCORE: number;
  SHORTAGE_QUANTITY: number;
  REVENUE_EXPOSURE: number | null;
  PRIMARY_RISK_REASON: string;
}

export interface OverviewResponse {
  kpis: OverviewKpis;
  topActiveRisk: TopActiveRisk | null;
}

import { NextResponse } from "next/server";
import { query } from "@/lib/snowflake/query";
import type { OverviewResponse, OverviewKpis, TopActiveRisk } from "@/types/overview";

export async function GET() {
  try {
    const [orderLineRows, otdRows, flagshipOtdRows, pendingRows, approvedRows, dispatchedRows, topRiskRows] =
      await Promise.all([
        query<{ AFFECTED_ORDER_LINES: number; REVENUE_EXPOSURE: number | null }>(
          `SELECT COUNT(*) AS AFFECTED_ORDER_LINES, SUM(ORDER_VALUE) AS REVENUE_EXPOSURE
           FROM SUPPLYCHAINIQ_DB.CURATED.CUSTOMER_ORDER_LINE
           WHERE PART_ID = 'P104'`
        ),
        query<{ OTD: number | null }>(
          `SELECT supplier_otd_percent AS OTD FROM SEMANTIC_VIEW(
             SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW METRICS shipment.supplier_otd_percent)`
        ),
        query<{ OTD: number | null }>(
          `SELECT supplier_otd_percent AS OTD FROM SEMANTIC_VIEW(
             SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW METRICS shipment.supplier_otd_percent
             DIMENSIONS supplier.supplier_id) WHERE supplier_id = ?`,
          ["S017"]
        ),
        query<{ N: number }>(
          `SELECT COUNT(*) AS N FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST WHERE REQUEST_STATUS = 'PENDING'`
        ),
        query<{ N: number }>(
          `SELECT COUNT(*) AS N FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST
           WHERE REQUEST_STATUS = 'APPROVED' AND EXECUTION_STATUS = 'NOT_DISPATCHED'`
        ),
        query<{ N: number }>(
          `SELECT COUNT(*) AS N FROM SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_COMMAND WHERE ACTION_STATUS = 'DISPATCHED_DEMO'`
        ),
        query<TopActiveRisk>(
          `SELECT RISK_ID, PART_DESCRIPTION, PLANT_NAME, SUPPLIER_NAME, SUPPLIER_ID, SEVERITY, RISK_SCORE,
                  SHORTAGE_QUANTITY, REVENUE_EXPOSURE, PRIMARY_RISK_REASON
           FROM SUPPLYCHAINIQ_DB.RISK.SUPPLY_CHAIN_RISK_RANKING
           WHERE RISK_RANK = 1`
        ),
      ]);

    const kpis: OverviewKpis = {
      affectedOrderLines: orderLineRows[0]?.AFFECTED_ORDER_LINES ?? null,
      revenueExposure: orderLineRows[0]?.REVENUE_EXPOSURE ?? null,
      overallOtd: otdRows[0]?.OTD ?? null,
      flagshipSupplierOtd: flagshipOtdRows[0]?.OTD ?? null,
      pendingApprovals: pendingRows[0]?.N ?? 0,
      approvedNotDispatched: approvedRows[0]?.N ?? 0,
      dispatchedDemoActions: dispatchedRows[0]?.N ?? 0,
    };

    const response: OverviewResponse = {
      kpis,
      topActiveRisk: topRiskRows[0] ?? null,
    };

    return NextResponse.json(response);
  } catch {
    // Never leak SQL text, stack traces, or credentials to the client.
    return NextResponse.json({ error: "Could not load Overview data from Snowflake." }, { status: 502 });
  }
}

import { NextResponse } from "next/server";
import { query } from "@/lib/snowflake/query";
import type { ConfirmedRisk, ConfirmedRiskSummary } from "@/types/risk";

export async function GET() {
  try {
    const [summaryRows, riskRows] = await Promise.all([
      query<ConfirmedRiskSummary>(
        `SELECT COUNT(*) AS ACTIVE_RISKS,
                COUNT_IF(SEVERITY = 'CRITICAL') AS CRITICAL_RISKS,
                COUNT_IF(SEVERITY = 'HIGH') AS HIGH_RISKS,
                COUNT_IF(SEVERITY = 'MEDIUM') AS MEDIUM_RISKS,
                SUM(REVENUE_EXPOSURE) AS REVENUE_EXPOSURE
         FROM SUPPLYCHAINIQ_DB.RISK.SUPPLY_CHAIN_RISK_RANKING`
      ),
      query<ConfirmedRisk>(
        `SELECT * FROM SUPPLYCHAINIQ_DB.RISK.SUPPLY_CHAIN_RISK_RANKING ORDER BY RISK_RANK, RISK_ID`
      ),
    ]);

    return NextResponse.json({ summary: summaryRows[0] ?? null, risks: riskRows });
  } catch {
    return NextResponse.json({ error: "Could not load confirmed risks from Snowflake." }, { status: 502 });
  }
}

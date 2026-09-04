import { NextResponse } from "next/server";
import { query, callProcedure } from "@/lib/snowflake/query";
import type { Intervention } from "@/types/risk";

/**
 * Read-only intervention comparison for one CONFIRMED risk. Re-derives
 * supplier/part/plant from the governed risk row (never trusts a client-
 * supplied triple), then calls the existing deterministic evaluator --
 * exactly the procedure the Streamlit app calls. No ranking/feasibility
 * logic is reimplemented here.
 */
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ riskId: string }> }
) {
  const { riskId } = await params;

  try {
    const riskRows = await query<{ SUPPLIER_ID: string; PART_ID: string; PLANT_ID: string }>(
      `SELECT SUPPLIER_ID, PART_ID, PLANT_ID
       FROM SUPPLYCHAINIQ_DB.RISK.SUPPLY_CHAIN_RISK_RANKING
       WHERE RISK_ID = ?`,
      [riskId]
    );
    const risk = riskRows[0];
    if (!risk) {
      return NextResponse.json({ error: "Risk not found." }, { status: 404 });
    }

    const options = await callProcedure<Intervention[]>(
      "SUPPLYCHAINIQ_DB.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS",
      [risk.SUPPLIER_ID, risk.PART_ID, risk.PLANT_ID]
    );

    return NextResponse.json({ options });
  } catch {
    return NextResponse.json({ error: "Could not load intervention options from the governed evaluator." }, { status: 502 });
  }
}

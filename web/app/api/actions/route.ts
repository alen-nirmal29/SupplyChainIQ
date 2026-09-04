import { NextResponse } from "next/server";
import { query } from "@/lib/snowflake/query";
import type { ActionCommand } from "@/types/action";

/** Read-only. Dispatch is always Agent-tool-mediated (ACTION.DISPATCH_APPROVED_INTERVENTION
 * via the Cortex Agent) -- there is intentionally no POST/dispatch endpoint here. */
export async function GET() {
  try {
    const rows = await query<ActionCommand>(
      `SELECT
         a.ACTION_ID, a.REQUEST_ID, a.INTERVENTION_TYPE, a.EXECUTION_MODE, a.ACTION_STATUS,
         a.SUPPLIER_ID, a.PART_ID, a.DESTINATION_PLANT_ID,
         a.DISPATCHED_BY, a.DISPATCHED_ROLE, a.DISPATCHED_AT,
         a.COMMAND_PAYLOAD, a.APPROVED_SNAPSHOT_HASH, a.FRESH_EVALUATION_HASH
       FROM SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_COMMAND a
       ORDER BY a.DISPATCHED_AT DESC`
    );

    return NextResponse.json({ actions: rows });
  } catch {
    return NextResponse.json({ error: "Could not load actions from Snowflake." }, { status: 502 });
  }
}

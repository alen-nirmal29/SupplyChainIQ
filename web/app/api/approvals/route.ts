import { NextResponse } from "next/server";
import { query } from "@/lib/snowflake/query";
import type { ApprovalRequest } from "@/types/approval";

const KNOWN_TEST_ARTIFACT_REQUEST_IDS = ["AR-764ccb86-e3c6-4a09-9b93-450264f37f51"];

export async function GET(request: Request) {
  const includeTestArtifacts = new URL(request.url).searchParams.get("includeTestArtifacts") === "true";

  const excludeClause = includeTestArtifacts
    ? ""
    : `WHERE r.REQUEST_ID NOT IN (${KNOWN_TEST_ARTIFACT_REQUEST_IDS.map(() => "?").join(",")})`;
  const binds = includeTestArtifacts ? [] : KNOWN_TEST_ARTIFACT_REQUEST_IDS;

  try {
    const rows = await query<ApprovalRequest>(
      `SELECT
         r.REQUEST_ID, s.SUPPLIER_NAME, p.PART_DESCRIPTION, pl.PLANT_NAME,
         r.SELECTED_INTERVENTION_TYPE, r.RECOMMENDATION_RANK,
         r.REQUEST_STATUS, r.EXECUTION_STATUS,
         r.REQUESTED_BY, r.REQUESTED_ROLE, r.REQUESTED_AT,
         r.APPROVED_OR_REJECTED_BY, r.DECISION_AT, r.DECISION_COMMENT,
         r.ACTION_ID, r.SUPPLIER_ID, r.PART_ID, r.DESTINATION_PLANT_ID,
         r.RECOMMENDATION_SNAPSHOT, r.RECOMMENDATION_HASH
       FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST r
       LEFT JOIN SUPPLYCHAINIQ_DB.CURATED.SUPPLIER s ON s.SUPPLIER_ID = r.SUPPLIER_ID
       LEFT JOIN SUPPLYCHAINIQ_DB.CURATED.PART p ON p.PART_ID = r.PART_ID
       LEFT JOIN SUPPLYCHAINIQ_DB.CURATED.PLANT pl ON pl.PLANT_ID = r.DESTINATION_PLANT_ID
       ${excludeClause}
       ORDER BY r.REQUESTED_AT DESC`,
      binds
    );

    return NextResponse.json({ requests: rows, knownTestArtifactIds: KNOWN_TEST_ARTIFACT_REQUEST_IDS });
  } catch {
    return NextResponse.json({ error: "Could not load the approval queue from Snowflake." }, { status: 502 });
  }
}

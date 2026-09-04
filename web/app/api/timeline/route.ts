import { NextResponse } from "next/server";
import { query } from "@/lib/snowflake/query";
import type { TimelineEvent, TimelineResponse } from "@/types/timeline";

export async function GET(request: Request) {
  const requestId = new URL(request.url).searchParams.get("requestId");
  if (!requestId) {
    return NextResponse.json({ error: "requestId is required." }, { status: 400 });
  }

  try {
    const [approvalEvents, actionEvents] = await Promise.all([
      query<TimelineEvent>(
        `SELECT EVENT_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, OLD_STATUS, NEW_STATUS, COMMENT AS DETAILS
         FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_EVENT
         WHERE REQUEST_ID = ?
         ORDER BY EVENT_AT`,
        [requestId]
      ),
      query<TimelineEvent>(
        `SELECT EVENT_ID, ACTION_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, DETAILS
         FROM SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_EVENT
         WHERE REQUEST_ID = ?
         ORDER BY EVENT_AT`,
        [requestId]
      ),
    ]);

    const response: TimelineResponse = { approvalEvents, actionEvents };
    return NextResponse.json(response);
  } catch {
    return NextResponse.json({ error: "Could not load the timeline from Snowflake." }, { status: 502 });
  }
}

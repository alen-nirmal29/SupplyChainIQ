import { NextResponse } from "next/server";
import { callProcedure } from "@/lib/snowflake/query";
import { assertMutationsAllowed, MutationsDisabledError } from "@/lib/demo-mode";
import type { ReviewDecision, ReviewResult } from "@/types/approval";

const VALID_DECISIONS: ReviewDecision[] = ["APPROVE", "REJECT", "CANCEL"];

/**
 * The ONLY write path for approval decisions. Calls the existing governed
 * procedure WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST -- no approval
 * state-transition logic is reimplemented here.
 *
 * KNOWN GAP (see docs/nextjs_migration.md): this route currently executes
 * on the shared server connection. Before production use, this must run
 * through a per-signed-in-user restricted-caller Snowflake session (mirroring
 * the Streamlit app's separate `caller_conn`) so the procedure's
 * SYS_CONTEXT-based identity capture reflects the actual human reviewer,
 * not a shared service identity.
 */
export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    assertMutationsAllowed();
  } catch (err) {
    if (err instanceof MutationsDisabledError) {
      return NextResponse.json({ error: err.message }, { status: 403 });
    }
    throw err;
  }

  const { id } = await params;
  const body = await request.json().catch(() => null);
  const decision = body?.decision as ReviewDecision | undefined;
  const comment = (body?.comment as string | null | undefined) ?? null;

  if (!decision || !VALID_DECISIONS.includes(decision)) {
    return NextResponse.json({ error: "A valid decision (APPROVE, REJECT, CANCEL) is required." }, { status: 400 });
  }

  try {
    const result = await callProcedure<ReviewResult>(
      "SUPPLYCHAINIQ_DB.WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST",
      [id, decision, comment]
    );
    return NextResponse.json(result);
  } catch {
    return NextResponse.json({ error: "The review procedure could not be called." }, { status: 502 });
  }
}

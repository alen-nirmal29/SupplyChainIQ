/** Domain types mirroring WORKFLOW.INTERVENTION_APPROVAL_REQUEST. */
export type ApprovalStatus = "PENDING" | "APPROVED" | "REJECTED" | "CANCELLED";
export type ExecutionStatus = "NOT_DISPATCHED" | "DISPATCH_CLAIMED" | "DISPATCHED_DEMO";
export type ReviewDecision = "APPROVE" | "REJECT" | "CANCEL";

export interface ApprovalRequest {
  REQUEST_ID: string;
  SUPPLIER_NAME: string | null;
  PART_DESCRIPTION: string | null;
  PLANT_NAME: string | null;
  SELECTED_INTERVENTION_TYPE: string;
  RECOMMENDATION_RANK: number;
  REQUEST_STATUS: ApprovalStatus;
  EXECUTION_STATUS: ExecutionStatus;
  REQUESTED_BY: string;
  REQUESTED_ROLE: string;
  REQUESTED_AT: string;
  APPROVED_OR_REJECTED_BY: string | null;
  DECISION_AT: string | null;
  DECISION_COMMENT: string | null;
  ACTION_ID: string | null;
  SUPPLIER_ID: string;
  PART_ID: string;
  DESTINATION_PLANT_ID: string;
  RECOMMENDATION_SNAPSHOT: unknown;
  RECOMMENDATION_HASH: string;
}

export interface ReviewResult {
  STATUS: string;
  [key: string]: unknown;
}

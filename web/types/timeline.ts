/** Domain types mirroring WORKFLOW.INTERVENTION_APPROVAL_EVENT / ACTION.INTERVENTION_ACTION_EVENT. */
export interface TimelineEvent {
  EVENT_ID: string;
  EVENT_TYPE: string;
  EVENT_AT: string;
  ACTOR: string;
  ACTOR_ROLE: string;
  DETAILS: string | null;
  /** Only present on approval events. */
  OLD_STATUS?: string;
  NEW_STATUS?: string;
  /** Only present on action events. */
  ACTION_ID?: string;
}

export interface TimelineResponse {
  approvalEvents: TimelineEvent[];
  actionEvents: TimelineEvent[];
}

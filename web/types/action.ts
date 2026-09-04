/** Domain type mirroring ACTION.INTERVENTION_ACTION_COMMAND. */
export interface ActionCommand {
  ACTION_ID: string;
  REQUEST_ID: string;
  INTERVENTION_TYPE: string;
  EXECUTION_MODE: string;
  ACTION_STATUS: string;
  SUPPLIER_ID: string;
  PART_ID: string;
  DESTINATION_PLANT_ID: string;
  DISPATCHED_BY: string;
  DISPATCHED_ROLE: string;
  DISPATCHED_AT: string;
  COMMAND_PAYLOAD: unknown;
  APPROVED_SNAPSHOT_HASH: string;
  FRESH_EVALUATION_HASH: string;
}

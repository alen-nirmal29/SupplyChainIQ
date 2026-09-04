/** Domain types for the Cortex Agent (SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT). */
export interface AgentMessage {
  role: "user" | "assistant";
  content: string | null;
  toolsUsed?: string[];
  runId?: string;
  error?: string;
}

export interface AgentTurnRequest {
  text: string;
  threadId?: number | null;
  parentMessageId?: number | null;
}

export interface AgentTurnResponse {
  text: string | null;
  toolsUsed: string[];
  threadId: number | null;
  assistantMessageId: number | null;
  runId: string | null;
  error?: string;
}

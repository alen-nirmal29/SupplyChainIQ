import { NextResponse } from "next/server";
import { query } from "@/lib/snowflake/query";
import type { AgentTurnResponse } from "@/types/agent";

const AGENT_FQN = "SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT";

// Cortex Agent structured-content types that must never reach the browser.
const HIDDEN_CONTENT_TYPES = new Set(["thinking"]);

interface AgentContentBlock {
  type: string;
  text?: string;
  tool_use?: { name?: string };
  tool_result?: { name?: string };
}

interface AgentRawResponse {
  content?: AgentContentBlock[];
  metadata?: {
    thread_id?: number;
    assistant_message_id?: number;
    run_id?: string;
  };
}

/**
 * Single entry point to the Cortex Agent via SNOWFLAKE.CORTEX.DATA_AGENT_RUN
 * -- the same governed mechanism the Streamlit app uses. This route never
 * re-ranks interventions, never decides approval/dispatch outcomes, and
 * never calls an external LLM. It only forwards the user's message and
 * returns the Agent's structured response, with internal reasoning
 * ("thinking" blocks) stripped before it ever reaches the client.
 */
export async function POST(request: Request) {
  const body = await request.json().catch(() => null);
  const text = body?.text as string | undefined;
  const threadId = (body?.threadId ?? null) as number | null;
  const parentMessageId = (body?.parentMessageId ?? null) as number | null;

  if (!text || typeof text !== "string") {
    return NextResponse.json({ error: "A message is required." }, { status: 400 });
  }

  const requestBody: Record<string, unknown> = {
    messages: [{ role: "user", content: [{ type: "text", text }] }],
  };
  if (threadId !== null) requestBody.thread_id = threadId;
  if (parentMessageId !== null) requestBody.parent_message_id = parentMessageId;
  const autoCreateThread = threadId === null;

  try {
    const rows = await query<{ RESP: string }>(
      "SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?, ?) AS RESP",
      [AGENT_FQN, JSON.stringify(requestBody), autoCreateThread]
    );

    const raw = rows[0]?.RESP;
    const parsed: AgentRawResponse = typeof raw === "string" ? JSON.parse(raw) : (raw as unknown as AgentRawResponse) ?? {};

    const textParts: string[] = [];
    const toolsUsed: string[] = [];
    for (const block of parsed.content ?? []) {
      if (HIDDEN_CONTENT_TYPES.has(block.type)) continue;
      if (block.type === "text" && block.text) {
        textParts.push(block.text);
      } else if (block.type === "tool_use" && block.tool_use?.name) {
        if (!toolsUsed.includes(block.tool_use.name)) toolsUsed.push(block.tool_use.name);
      } else if (block.type === "tool_result" && block.tool_result?.name) {
        if (!toolsUsed.includes(block.tool_result.name)) toolsUsed.push(block.tool_result.name);
      }
    }

    const response: AgentTurnResponse = {
      text: textParts.length ? textParts.join("\n\n") : "(SupplyChainIQ returned no text response.)",
      toolsUsed,
      threadId: parsed.metadata?.thread_id ?? null,
      assistantMessageId: parsed.metadata?.assistant_message_id ?? null,
      runId: parsed.metadata?.run_id ?? null,
    };

    return NextResponse.json(response);
  } catch {
    const response: AgentTurnResponse = {
      text: null,
      toolsUsed: [],
      threadId,
      assistantMessageId: null,
      runId: null,
      error: "SupplyChainIQ couldn't complete that request. Please try rephrasing or try again.",
    };
    return NextResponse.json(response, { status: 502 });
  }
}

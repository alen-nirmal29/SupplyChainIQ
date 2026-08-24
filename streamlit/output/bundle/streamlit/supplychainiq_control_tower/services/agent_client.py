"""
Phase 9: Cortex Agent integration for the SupplyChainIQ Control Tower.

This module is the ONLY place that talks to the Cortex Agent. It wraps
SNOWFLAKE.CORTEX.DATA_AGENT_RUN — the same mechanism used and validated
throughout Phases 7-8C — and manages thread/parent-message continuity so
multi-turn chat ("what can we do?" -> "submit the recommended option for
approval") resolves against real Agent conversation context, never
Python keyword-matching.

No business logic is reimplemented here. This module never calls Cortex
Analyst or Cortex Search directly, never re-ranks interventions, and
never decides approval/dispatch outcomes -- it only sends the user's
message to the Agent and returns its structured response.
"""

import json

AGENT_FQN = "SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT"

# Cortex Agent structured-content types that must NEVER be rendered to the
# business user (internal reasoning / chain-of-thought).
_HIDDEN_CONTENT_TYPES = {"thinking"}

# Content types that surface as "tools used" trace entries.
_TOOL_CONTENT_TYPES = {"tool_use", "system_execute_sql", "tool_result"}


def run_agent_turn(conn, user_text, thread_id=None, parent_message_id=None):
    """
    Send one user message to SUPPLYCHAINIQ_AGENT via DATA_AGENT_RUN.

    - If thread_id is None: starts a new thread (auto_create_thread = TRUE).
    - If thread_id is provided: continues that thread using
      parent_message_id, with auto_create_thread = FALSE, exactly per the
      Cortex Agent Threads/DATA_AGENT_RUN contract.

    Returns a dict:
      {
        "text": <final assistant-facing text, concatenated>,
        "tools_used": [<tool names actually called, deduped>],
        "thread_id": <int>,
        "assistant_message_id": <int>,
        "run_id": <str>,
        "raw": <full parsed response dict>,
        "error": <str, only present on failure>,
      }
    """
    body = {"messages": [{"role": "user", "content": [{"type": "text", "text": user_text}]}]}
    if thread_id is not None:
        body["thread_id"] = thread_id
    if parent_message_id is not None:
        body["parent_message_id"] = parent_message_id
    auto_create = thread_id is None

    request_body_json = json.dumps(body)

    query = "SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?, ?) AS RESP"
    try:
        df = conn.query(query, params=[AGENT_FQN, request_body_json, auto_create], ttl=0)
    except Exception as e:
        return {"error": f"Agent call failed: {e}", "text": None, "tools_used": [], "thread_id": thread_id}

    raw_resp = df.to_dict("records")[0]["RESP"]
    try:
        parsed = json.loads(raw_resp) if isinstance(raw_resp, str) else raw_resp
    except Exception as e:
        return {"error": f"Could not parse Agent response: {e}", "text": None, "tools_used": [], "thread_id": thread_id}

    return _extract_result(parsed)


def _extract_result(parsed):
    content = parsed.get("content", []) or []
    metadata = parsed.get("metadata", {}) or {}

    text_parts = []
    tools_used = []

    for block in content:
        block_type = block.get("type")
        if block_type in _HIDDEN_CONTENT_TYPES:
            # Never surface internal reasoning / chain-of-thought.
            continue
        if block_type == "text":
            t = block.get("text")
            if t:
                text_parts.append(t)
        elif block_type == "tool_use":
            name = block.get("tool_use", {}).get("name")
            if name and name not in tools_used:
                tools_used.append(name)
        elif block_type == "tool_result":
            name = block.get("tool_result", {}).get("name")
            if name and name not in tools_used:
                tools_used.append(name)
        # 'table' and 'suggested_queries' blocks are presentation-only;
        # they are not authoritative business state and are not surfaced
        # as separate structured cards here (per the "do not parse
        # business state from Agent prose" rule) -- only final text is
        # shown to the user, plus the tool-name trace for transparency.

    return {
        "text": "\n\n".join(text_parts) if text_parts else "(SupplyChainIQ returned no text response.)",
        "tools_used": tools_used,
        "thread_id": metadata.get("thread_id"),
        "assistant_message_id": metadata.get("assistant_message_id"),
        "run_id": metadata.get("run_id"),
        "raw": parsed,
    }

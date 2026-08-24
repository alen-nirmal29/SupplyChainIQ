"""Phase 9: Ask SupplyChainIQ -- multi-turn Cortex Agent chat."""

import streamlit as st

from services import agent_client as ac

STARTER_QUESTIONS = [
    "What can we do about the High-Precision Hydraulic Control Valve Assembly Type 104 shortage "
    "at Pune Assembly Plant caused by Pinnacle Industries? Compare the options and recommend the best intervention.",
    "Why are deliveries for P104 at Pune Assembly Plant at risk?",
    "What is Pinnacle Industries' on-time delivery performance?",
    "What does the supplier SLA say about expedite terms?",
]


def _init_state():
    st.session_state.setdefault("chat_messages", [])
    st.session_state.setdefault("thread_id", None)
    st.session_state.setdefault("parent_message_id", None)
    st.session_state.setdefault("had_recommendation", False)


def _send(owner_conn, text):
    st.session_state.chat_messages.append({"role": "user", "content": text})
    with st.spinner("SupplyChainIQ is analyzing…"):
        result = ac.run_agent_turn(
            owner_conn,
            text,
            thread_id=st.session_state.thread_id,
            parent_message_id=st.session_state.parent_message_id,
        )

    if result.get("error"):
        st.session_state.chat_messages.append({"role": "assistant", "content": None, "error": result["error"]})
        return

    st.session_state.thread_id = result.get("thread_id") or st.session_state.thread_id
    st.session_state.parent_message_id = result.get("assistant_message_id") or st.session_state.parent_message_id
    st.session_state.chat_messages.append(
        {"role": "assistant", "content": result.get("text"), "tools_used": result.get("tools_used", []), "run_id": result.get("run_id")}
    )
    if "evaluate_supply_chain_interventions" in (result.get("tools_used") or []):
        st.session_state.had_recommendation = True


def render(owner_conn):
    _init_state()

    st.subheader("Ask SupplyChainIQ")
    st.caption("Natural-language conversation with the SupplyChainIQ Cortex Agent. Business logic runs entirely in Snowflake.")

    render_evidence_card()

    if not st.session_state.chat_messages:
        st.markdown("**Try asking:**")
        for q in STARTER_QUESTIONS:
            if st.button(q, key=f"starter_{hash(q)}", use_container_width=True):
                _send(owner_conn, q)
                st.rerun()

    for i, msg in enumerate(st.session_state.chat_messages):
        with st.chat_message(msg["role"]):
            if msg["role"] == "assistant" and msg.get("error"):
                st.error("SupplyChainIQ couldn't complete that request. Please try rephrasing or try again.")
                with st.expander("Technical details"):
                    st.code(msg["error"])
                continue
            st.markdown(msg["content"])
            if msg["role"] == "assistant" and msg.get("tools_used"):
                with st.expander("Tools used"):
                    for t in msg["tools_used"]:
                        st.write(f"- `{t}`")
                    if msg.get("run_id"):
                        st.caption(f"run_id: {msg['run_id']}")

    if st.session_state.had_recommendation and not st.session_state.get("_submit_shortcut_used"):
        if st.button("💬 Submit the recommended option for approval", key="submit_shortcut"):
            _send(owner_conn, "Submit the recommended option for approval.")
            st.session_state["_submit_shortcut_used"] = True
            st.rerun()

    user_text = st.chat_input("Ask SupplyChainIQ…")
    if user_text:
        _send(owner_conn, user_text)
        st.rerun()


def render_evidence_card():
    with st.container(border=True):
        st.markdown("**⚠️ Operational recommendation ≠ contractual authorization**")
        c1, c2 = st.columns(2)
        with c1:
            st.markdown("**Operational recommendation**")
            st.write("Road · 3 days · 1.6× operational cost factor")
        with c2:
            st.markdown("**Contractual / SLA evidence**")
            st.write("Air · 4 days · 2.6× · see supplier document search")
        st.caption(
            "This operational recommendation is not automatically contractually authorized, and human approval "
            "does not establish contractual authorization either. Confirm expedite-lane terms against the "
            "supplier SLA if contractual compliance matters."
        )

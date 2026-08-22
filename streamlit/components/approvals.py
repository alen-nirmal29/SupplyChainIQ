"""Phase 9: Approval Queue -- structured human review UI.

All decision writes go through WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST
via the RESTRICTED CALLER connection so the procedure's SYS_CONTEXT-based
identity capture reflects the actual signed-in human. This file never calls
the Cortex Agent and never duplicates approval business rules -- the
backend procedure remains the sole authority; this file only re-queries
Snowflake after a successful call.
"""

import streamlit as st

from services import snowflake_data as sd

_ERROR_MESSAGES = {
    "NOT_FOUND": "This request could not be found.",
    "ALREADY_TERMINAL": "This request has already reached a final decision and can't be changed further.",
}


def render(owner_conn, caller_conn):
    st.subheader("Approval Queue")
    st.caption("Sourced directly from WORKFLOW.INTERVENTION_APPROVAL_REQUEST. Human decisions are procedure-mediated.")

    c1, c2 = st.columns([1, 3])
    with c1:
        if st.button("Refresh Approvals", key="refresh_approvals"):
            st.rerun()
    with c2:
        show_all = st.toggle("Show all records (including test artifacts)", value=False, key="show_all_approvals")

    try:
        df = sd.approval_queue(owner_conn, include_test_artifacts=show_all)
    except Exception as e:
        st.error("Could not load the approval queue from Snowflake.")
        with st.expander("Technical details"):
            st.exception(e)
        return

    if df.empty:
        st.info("No approval requests found.")
        return

    for rec in df.to_dict("records"):
        is_artifact = rec["REQUEST_ID"] in sd.KNOWN_TEST_ARTIFACT_REQUEST_IDS
        status_icon = {
            "PENDING": "🟡", "APPROVED": "🟢", "REJECTED": "⚫", "CANCELLED": "⚫",
        }.get(rec["REQUEST_STATUS"], "⚪")
        exec_icon = {"NOT_DISPATCHED": "", "DISPATCH_CLAIMED": "⏳", "DISPATCHED_DEMO": "🔵"}.get(rec["EXECUTION_STATUS"], "")

        label = (
            f"{status_icon} {rec['REQUEST_STATUS']} {exec_icon} — {rec['REQUEST_ID']} — "
            f"{rec.get('SUPPLIER_NAME')} / {rec.get('PART_DESCRIPTION')} / {rec.get('PLANT_NAME')} — "
            f"{rec['SELECTED_INTERVENTION_TYPE']} (rank {rec['RECOMMENDATION_RANK']})"
        )
        if is_artifact:
            label = "🧪 PRE-FIX TEST ARTIFACT — " + label

        with st.expander(label):
            st.write(f"**Requested by:** {rec['REQUESTED_BY']} ({rec['REQUESTED_ROLE']}) at {rec['REQUESTED_AT']}")
            if rec.get("APPROVED_OR_REJECTED_BY"):
                st.write(f"**Decision by:** {rec['APPROVED_OR_REJECTED_BY']} at {rec.get('DECISION_AT')}")
                if rec.get("DECISION_COMMENT"):
                    st.write(f"**Comment:** {rec['DECISION_COMMENT']}")
            if rec.get("ACTION_ID"):
                st.write(f"**Action ID:** {rec['ACTION_ID']}")

            with st.expander("Recommendation snapshot (immutable, at time of submission)"):
                st.json(rec.get("RECOMMENDATION_SNAPSHOT"))
                st.caption(f"RECOMMENDATION_HASH: `{rec.get('RECOMMENDATION_HASH')}`")

            if rec["REQUEST_STATUS"] == "PENDING":
                _render_review_controls(caller_conn, rec["REQUEST_ID"])


def _render_review_controls(caller_conn, request_id):
    action_key = f"approval_action_{request_id}"
    chosen = st.session_state.get(action_key)

    c1, c2, c3 = st.columns(3)
    if c1.button("✅ Approve", key=f"approve_btn_{request_id}"):
        st.session_state[action_key] = "APPROVE"
    if c2.button("❌ Reject", key=f"reject_btn_{request_id}"):
        st.session_state[action_key] = "REJECT"
    if c3.button("🚫 Cancel", key=f"cancel_btn_{request_id}"):
        st.session_state[action_key] = "CANCEL"

    if chosen := st.session_state.get(action_key):
        with st.form(key=f"confirm_form_{request_id}"):
            st.write(f"Confirm **{chosen}** for request `{request_id}`?")
            comment = st.text_input("Optional comment", key=f"comment_{request_id}")
            submitted = st.form_submit_button(f"Confirm {chosen.title()}")
            cancelled = st.form_submit_button("Dismiss")
            if submitted:
                try:
                    result = sd.review_request(caller_conn, request_id, chosen, comment or None)
                    st.success(f"Decision recorded: {result}")
                except Exception as e:
                    st.error("The review procedure could not be called.")
                    with st.expander("Technical details"):
                        st.exception(e)
                finally:
                    del st.session_state[action_key]
                    st.rerun()
            elif cancelled:
                del st.session_state[action_key]
                st.rerun()

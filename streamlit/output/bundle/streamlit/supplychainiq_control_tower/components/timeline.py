"""Phase 9: Workflow Timeline -- built only from structured WORKFLOW/ACTION records."""

import streamlit as st

from services import snowflake_data as sd


def render(owner_conn):
    st.subheader("Workflow Timeline")
    st.caption("Risk / Recommendation -> Approval requested -> Human decision -> Execution validation -> DISPATCHED_DEMO / BLOCKED reason.")

    request_id = st.text_input("Enter a REQUEST_ID to view its timeline", key="timeline_request_id")
    if not request_id:
        st.info("Enter a REQUEST_ID (from the Approval Queue) to see its full structured history.")
        return

    try:
        approval_events, action_events = sd.workflow_timeline(owner_conn, request_id)
    except Exception as e:
        st.error("Could not load the timeline from Snowflake.")
        with st.expander("Technical details"):
            st.exception(e)
        return

    if approval_events.empty and action_events.empty:
        st.warning(f"No structured events found for `{request_id}`.")
        return

    st.markdown("**Approval events**")
    for rec in approval_events.to_dict("records"):
        st.write(f"- `{rec['EVENT_AT']}` **{rec['EVENT_TYPE']}** by {rec['ACTOR']} ({rec['ACTOR_ROLE']})"
                 + (f" — {rec['DETAILS']}" if rec.get("DETAILS") else ""))

    st.markdown("**Action events**")
    if action_events.empty:
        st.write("- (no action events yet — this request has not reached dispatch)")
    for rec in action_events.to_dict("records"):
        st.write(f"- `{rec['EVENT_AT']}` **{rec['EVENT_TYPE']}** by {rec['ACTOR']} ({rec['ACTOR_ROLE']})"
                 + (f" — {rec['DETAILS']}" if rec.get("DETAILS") else ""))

"""Phase 9: Actions view -- ACTION.INTERVENTION_ACTION_COMMAND / EVENT, read-only."""

import streamlit as st

from services import snowflake_data as sd


def render(owner_conn):
    st.subheader("Actions")
    st.caption("Sourced directly from ACTION.INTERVENTION_ACTION_COMMAND. Dispatch is always Agent-tool-mediated (never a direct button in this UI).")

    if st.button("Refresh Actions", key="refresh_actions"):
        st.rerun()

    try:
        df = sd.actions_view(owner_conn)
    except Exception as e:
        st.error("Could not load actions from Snowflake.")
        with st.expander("Technical details"):
            st.exception(e)
        return

    if df.empty:
        st.info("No demo actions have been dispatched yet. Use Ask SupplyChainIQ: \"Execute approved request <REQUEST_ID>.\"")
        return

    for rec in df.to_dict("records"):
        label = (
            f"🔵 {rec['ACTION_STATUS']} — {rec['ACTION_ID']} — {rec['INTERVENTION_TYPE']} — "
            f"{rec['SUPPLIER_ID']}/{rec['PART_ID']}/{rec['DESTINATION_PLANT_ID']}"
        )
        with st.expander(label):
            st.write(f"**Request ID:** {rec['REQUEST_ID']}")
            st.write(f"**Execution mode:** {rec['EXECUTION_MODE']}")
            st.write(f"**Dispatched by:** {rec['DISPATCHED_BY']} ({rec['DISPATCHED_ROLE']}) at {rec['DISPATCHED_AT']}")
            st.info("No SAP/TMS/WMS record was modified and no external operational system was called.")
            with st.expander("Command payload"):
                st.json(rec.get("COMMAND_PAYLOAD"))
            with st.expander("Technical audit detail"):
                st.write(f"APPROVED_SNAPSHOT_HASH: `{rec.get('APPROVED_SNAPSHOT_HASH')}`")
                st.write(f"FRESH_EVALUATION_HASH: `{rec.get('FRESH_EVALUATION_HASH')}`")

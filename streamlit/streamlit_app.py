"""
SupplyChainIQ Control Tower — Phase 9.2 full application.

Presentation/orchestration layer over the already-governed Snowflake
backend (DECISION / WORKFLOW / ACTION / SEMANTIC / SEARCH / CURATED). No
business logic is reimplemented here -- see components/ and services/ for
the read/write boundaries.

Connections are created once at top-level startup (before any
page-specific logic), per Phase 9 design:
  - OWNER connection: safe, app-owned read-only dashboard queries.
  - RESTRICTED CALLER connection: identity-sensitive actions (human
    approval/rejection/cancellation). Never cached globally across users.
"""

import streamlit as st

from components import overview, risk_radar, chat, approvals, actions, timeline
from services import snowflake_data as sd

st.set_page_config(page_title="SupplyChainIQ Control Tower", layout="wide")

_STREAMLIT_VERSION = getattr(st, "__version__", "unknown")

# --- Top-level connection setup (per Phase 9 design §6/§16) ---
owner_conn = st.connection("snowflake")

caller_conn = None
caller_conn_error = None
try:
    caller_conn = st.connection("snowflake-callers-rights")
except Exception as e:
    caller_conn_error = str(e)

# --- Sidebar: identity display + navigation ---
with st.sidebar:
    st.title("SupplyChainIQ")
    st.caption("Control Tower")

    display_user = None
    try:
        display_user = st.user.user_name if hasattr(st, "user") else None
    except Exception:
        display_user = None
    st.markdown(f"**Signed in as:** {display_user or 'Unknown'}")

    if caller_conn is not None:
        try:
            viewer = sd.viewer_identity(caller_conn)
            st.caption(
                f"Restricted-caller session identity: CURRENT_USER()={viewer.get('U')}, "
                f"CURRENT_ROLE()={viewer.get('R')}"
            )
            if display_user and viewer.get("U") and display_user.upper() != str(viewer.get("U")).upper():
                st.warning(
                    "st.user.user_name does not match the restricted-caller CURRENT_USER(). "
                    "Approval identity capture may not reflect the displayed viewer."
                )
        except Exception as e:
            st.caption("Restricted-caller identity check failed.")
            with st.expander("Technical details"):
                st.exception(e)

    if caller_conn_error:
        st.warning(
            "Restricted caller connection unavailable in this session. "
            "Human approval actions will be disabled until this is resolved."
        )
        with st.expander("Technical details"):
            st.code(caller_conn_error)

    st.divider()
    page = st.radio("Navigate", ["Overview", "Risk Radar", "Ask SupplyChainIQ", "Approvals", "Actions", "Timeline"], label_visibility="collapsed")

    st.divider()
    st.caption(
        "Snowflake-native Supply Chain Control Tower: Cortex Agent, Cortex Analyst, Cortex Search, "
        "deterministic decision tools, human approval, and controlled demo dispatch — all governed in Snowflake."
    )
    st.caption(f"Runtime diagnostics: streamlit=={_STREAMLIT_VERSION}")

# --- Page routing (flat, demo-friendly) ---
if page == "Overview":
    overview.render(owner_conn)
elif page == "Risk Radar":
    risk_radar.render(owner_conn)
elif page == "Ask SupplyChainIQ":
    chat.render(owner_conn)
elif page == "Approvals":
    if caller_conn is None:
        st.error(
            "Human approval controls require the restricted caller connection, which is unavailable in this "
            "session. Approval data can still be viewed read-only below."
        )
        approvals.render(owner_conn, owner_conn)
    else:
        approvals.render(owner_conn, caller_conn)
elif page == "Actions":
    actions.render(owner_conn)
elif page == "Timeline":
    timeline.render(owner_conn)

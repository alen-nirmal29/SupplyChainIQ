"""Phase 9: Overview page -- live governed KPI cards + flagship risk panel."""

import streamlit as st

from services import snowflake_data as sd


def render(owner_conn):
    st.subheader("Executive Overview")
    st.caption("All values below are queried live from the governed Snowflake backend on every load/refresh.")

    if st.button("Refresh Overview", key="refresh_overview"):
        st.cache_data.clear()

    try:
        kpis = sd.overview_kpis(owner_conn)
    except Exception as e:
        st.error("Could not load overview KPIs from Snowflake.")
        with st.expander("Technical details"):
            st.exception(e)
        kpis = {}

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Affected customer order lines (P104)", kpis.get("affected_order_lines", "—"))
    rev = kpis.get("revenue_exposure")
    c2.metric("Revenue exposure (P104 orders)", f"${rev:,.0f}" if rev is not None else "—")
    otd = kpis.get("overall_otd")
    c3.metric("Overall Supplier OTD", f"{otd*100:.1f}%" if otd is not None else "—")
    potd = kpis.get("pinnacle_otd")
    c4.metric("Pinnacle Industries (S017) OTD", f"{potd*100:.1f}%" if potd is not None else "—")

    c5, c6, c7 = st.columns(3)
    c5.metric("🟡 Pending approvals", kpis.get("pending_approvals", "—"))
    c6.metric("🟢 Approved, not yet dispatched", kpis.get("approved_not_dispatched", "—"))
    c7.metric("🔵 Dispatched demo actions", kpis.get("dispatched_demo_actions", "—"))

    st.divider()
    render_flagship_risk_panel(owner_conn)


def render_flagship_risk_panel(owner_conn):
    st.markdown("### 🔴 Flagship Risk: High-Precision Hydraulic Control Valve Assembly Type 104 at Pune Assembly Plant")
    st.caption("Supplier: **Pinnacle Industries (S017)** · Part: **P104** · Plant: **Pune Assembly Plant (P01)**")

    try:
        result = sd.flagship_risk(owner_conn)
    except Exception as e:
        st.error("Could not load flagship risk data from the governed decision procedure.")
        with st.expander("Technical details"):
            st.exception(e)
        return

    if not result:
        st.info("No intervention data returned for this scope.")
        return

    first = result[0] if isinstance(result, list) and result else None
    if not first:
        st.info("No intervention data returned for this scope.")
        return

    cols = st.columns(4)
    cols[0].metric("Shortage before", first.get("SHORTAGE_BEFORE", "—"))
    cols[1].metric("Reference date", str(first.get("REFERENCE_DATE", "—")))
    cols[2].metric("First customer due date", str(first.get("FIRST_CUSTOMER_DUE_DATE", "—")))
    cols[3].metric("Arrives in time (recommended option)?", "Yes" if first.get("ARRIVES_IN_TIME") else "No")

    st.caption("Source: SH900001, delayed Ocean shipment. See Ask SupplyChainIQ for a full comparison of intervention options.")

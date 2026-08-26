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
    render_top_active_risk_panel(owner_conn)


def render_top_active_risk_panel(owner_conn):
    try:
        risk = sd.top_active_risk(owner_conn)
    except Exception as e:
        error_text = str(e)
        missing_risk_object = (
            ("SUPPLY_CHAIN_RISK" in error_text or "RISK." in error_text)
            and ("does not exist" in error_text.lower() or "not authorized" in error_text.lower())
        )
        if missing_risk_object:
            st.caption("Risk Radar is not yet available in this environment; showing the preselected demo scenario below.")
        else:
            st.warning("Could not load Top Active Risk; showing the preselected demo scenario below.")
            with st.expander("Technical details"):
                st.code(error_text)
        render_flagship_risk_panel(owner_conn)
        return

    if not risk:
        st.info("Risk Radar found no current shortage risks in the governed data.")
        return

    st.markdown(f"### Top Active Risk: {risk['PART_DESCRIPTION']} at {risk['PLANT_NAME']}")
    st.caption(
        f"Derived from current governed Risk Radar ranking · Supplier: **{risk['SUPPLIER_NAME']} ({risk['SUPPLIER_ID']})**"
    )
    cols = st.columns(4)
    cols[0].metric("Severity", risk.get("SEVERITY", "—"))
    cols[1].metric("Risk score", f"{risk.get('RISK_SCORE', '—')}/100")
    cols[2].metric("Shortage", risk.get("SHORTAGE_QUANTITY", "—"))
    cols[3].metric(
        "Revenue exposure",
        f"INR {risk['REVENUE_EXPOSURE']:,.0f}" if risk.get("REVENUE_EXPOSURE") is not None else "—",
    )
    st.caption(
        f"Why this is a risk: {risk.get('PRIMARY_RISK_REASON', '—')}. "
        "Open Risk Radar for evidence, deterministic options, and comparison."
    )


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

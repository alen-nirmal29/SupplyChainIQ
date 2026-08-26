"""Phase 10: proactive, read-only Risk Radar and intervention comparison."""

from collections import Counter
from numbers import Number

import streamlit as st

from services import snowflake_data as sd

MAX_AUTOMATIC_EVALUATIONS = 10


def _risk_label(risk):
    return (
        f"#{risk['RISK_RANK']} {risk['SEVERITY']} — "
        f"{risk['PART_ID']} at {risk['PLANT_NAME']} — {risk['RISK_SCORE']}/100"
    )


def _format_currency(value):
    return f"INR {value:,.0f}" if value is not None else "—"


def _format_percent(value):
    return f"{value:.1%}" if value is not None else "—"


def _risk_display_label(risk):
    plant = risk.get("PLANT_NAME") or risk.get("PLANT_ID") or "Unknown plant"
    return f"{risk.get('PART_ID') or 'Unknown part'} · {plant}"


def _risk_rank_key(risk):
    rank = risk.get("RISK_RANK")
    return (rank is None, rank if isinstance(rank, Number) else str(rank))


def _render_portfolio_charts(records):
    st.markdown("### Portfolio visualizations")
    st.caption("Visual summaries of the currently filtered, governed Risk Radar records.")

    severity_order = ["CRITICAL", "HIGH", "MEDIUM", "LOW"]
    severity_counts = Counter(
        str(risk.get("SEVERITY")).upper()
        for risk in records
        if risk.get("SEVERITY") is not None
    )
    unknown_severity_count = sum(
        count for severity, count in severity_counts.items() if severity not in severity_order
    )
    top_risks = sorted(records, key=_risk_rank_key)[:10]

    severity_col, score_col = st.columns((1, 2))
    with severity_col:
        st.metric("Active risks", len(records))
        st.caption("Risk severity distribution")
        st.bar_chart(
            {
                "Severity": severity_order,
                "Active risks": [severity_counts[severity] for severity in severity_order],
            },
            x="Severity",
            y="Active risks",
            height=260,
        )
        if unknown_severity_count:
            st.caption(f"{unknown_severity_count} record(s) with an unknown severity are excluded from the governed severity categories.")

    with score_col:
        st.caption("Top 10 active risks by governed risk score")
        score_risks = [risk for risk in top_risks if isinstance(risk.get("RISK_SCORE"), Number)]
        if score_risks:
            st.bar_chart(
                {
                    "Risk": [_risk_display_label(risk) for risk in score_risks],
                    "Risk score": [risk["RISK_SCORE"] for risk in score_risks],
                },
                x="Risk",
                y="Risk score",
                horizontal=True,
                height=260,
            )
        else:
            st.info("Risk scores are unavailable for the current top-ranked risks.")
        missing_score_count = len(top_risks) - len(score_risks)
        if missing_score_count:
            st.caption(f"{missing_score_count} top-ranked risk(s) without a governed risk score are excluded from this chart.")

    revenue_risks = [
        risk for risk in top_risks if isinstance(risk.get("REVENUE_EXPOSURE"), Number)
    ]
    if revenue_risks:
        st.caption("Revenue exposure for top-ranked risks (INR)")
        st.bar_chart(
            {
                "Risk": [_risk_display_label(risk) for risk in revenue_risks],
                "Revenue exposure (INR)": [risk["REVENUE_EXPOSURE"] for risk in revenue_risks],
            },
            x="Risk",
            y="Revenue exposure (INR)",
            horizontal=True,
            height=300,
        )
        missing_revenue_count = len(top_risks) - len(revenue_risks)
        if missing_revenue_count:
            st.caption(f"{missing_revenue_count} top-ranked risk(s) without governed revenue exposure are excluded from this chart.")
    else:
        st.info("Revenue exposure is unavailable for the current top-ranked risks.")


def _render_score_breakdown(risk):
    components = [
        ("Shortage", "SHORTAGE_SCORE"),
        ("Customer urgency", "URGENCY_SCORE"),
        ("Revenue exposure", "REVENUE_SCORE"),
        ("Shipment delay", "SHIPMENT_SCORE"),
        ("Supplier OTD", "SUPPLIER_SCORE"),
    ]
    available = [(label, risk.get(field)) for label, field in components if isinstance(risk.get(field), Number)]
    unavailable = [label for label, field in components if not isinstance(risk.get(field), Number)]

    st.markdown(f"### Why this risk scored {risk.get('RISK_SCORE', '—')} / 100")
    st.caption("Deterministic score components returned directly by the governed Snowflake Risk Radar.")
    if available:
        st.bar_chart(
            {
                "Component": [label for label, _ in available],
                "Governed score component (points)": [value for _, value in available],
            },
            x="Component",
            y="Governed score component (points)",
            horizontal=True,
            height=250,
        )
    if unavailable:
        st.warning(f"Governed score component data is unavailable for: {', '.join(unavailable)}.")


def render(owner_conn):
    st.subheader("Risk Radar")
    st.caption("Risk Radar evaluates current governed supply-chain data when this page loads or is refreshed; it is not continuous monitoring.")

    if st.button("Refresh Risk Radar", key="refresh_risk_radar"):
        st.cache_data.clear()
        st.rerun()

    try:
        summary = sd.risk_radar_summary(owner_conn)
        all_records = sd.risk_radar(owner_conn).to_dict("records")
    except Exception as exc:
        st.error("Risk Radar is unavailable until its governed RISK views are deployed to DEV.")
        with st.expander("Technical details"):
            st.exception(exc)
        return

    metrics = st.columns(5)
    metrics[0].metric("Active risks", summary.get("ACTIVE_RISKS", 0))
    metrics[1].metric("Critical", summary.get("CRITICAL_RISKS", 0))
    metrics[2].metric("High", summary.get("HIGH_RISKS", 0))
    metrics[3].metric("Medium", summary.get("MEDIUM_RISKS", 0))
    metrics[4].metric("Revenue exposure", _format_currency(summary.get("REVENUE_EXPOSURE")))

    if not all_records:
        st.success("No current shortage risks met the governed Risk Radar criteria.")
        return

    with st.expander("Filters", expanded=False):
        severities = sorted({risk["SEVERITY"] for risk in all_records})
        suppliers = sorted({risk["SUPPLIER_NAME"] for risk in all_records})
        plants = sorted({risk["PLANT_NAME"] for risk in all_records})
        parts = sorted({risk["PART_ID"] for risk in all_records})
        c1, c2, c3, c4 = st.columns(4)
        severity_filter = c1.multiselect("Severity", severities, default=severities)
        supplier_filter = c2.multiselect("Supplier", suppliers, default=suppliers)
        plant_filter = c3.multiselect("Plant", plants, default=plants)
        part_filter = c4.multiselect("Part", parts, default=parts)

    records = [
        risk for risk in all_records
        if risk["SEVERITY"] in severity_filter
        and risk["SUPPLIER_NAME"] in supplier_filter
        and risk["PLANT_NAME"] in plant_filter
        and risk["PART_ID"] in part_filter
    ]
    if not records:
        st.info("No risks match the selected filters.")
        return

    _render_portfolio_charts(records)

    try:
        records = sd.enrich_qualifying_risks(owner_conn, records, MAX_AUTOMATIC_EVALUATIONS)
    except Exception as exc:
        st.warning("Risk ranking loaded, but automatic recommendation enrichment is unavailable.")
        with st.expander("Technical details"):
            st.exception(exc)

    st.markdown("### Ranked risks")
    table_rows = []
    for risk in records:
        recommended = risk.get("RECOMMENDED_OPTION") or {}
        table_rows.append({
            "Rank": risk["RISK_RANK"],
            "Severity": risk["SEVERITY"],
            "Supplier": risk["SUPPLIER_NAME"],
            "Part": risk["PART_ID"],
            "Plant": risk["PLANT_NAME"],
            "Shortage": risk["SHORTAGE_QUANTITY"],
            "Score": risk["RISK_SCORE"],
            "Recommended action": recommended.get("INTERVENTION_TYPE", "Evaluation bounded to Critical/High top 10"),
        })
    st.dataframe(table_rows, use_container_width=True, hide_index=True)

    selected_id = st.selectbox(
        "View risk details",
        options=[risk["RISK_ID"] for risk in records],
        format_func=lambda risk_id: _risk_label(next(risk for risk in records if risk["RISK_ID"] == risk_id)),
    )
    risk = next(risk for risk in records if risk["RISK_ID"] == selected_id)
    _render_detail(owner_conn, risk)


def _render_detail(owner_conn, risk):
    st.divider()
    st.markdown("### Risk summary")
    st.caption(risk["PRIMARY_RISK_REASON"])
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Risk score", f"{risk['RISK_SCORE']}/100", risk["SEVERITY"])
    c2.metric("Shortage", risk["SHORTAGE_QUANTITY"])
    c3.metric("First customer due", str(risk.get("FIRST_CUSTOMER_DUE_DATE") or "—"))
    c4.metric("Revenue exposure", _format_currency(risk.get("REVENUE_EXPOSURE")))

    _render_score_breakdown(risk)

    recommendation = risk.get("RECOMMENDED_OPTION")
    options = risk.get("INTERVENTION_OPTIONS")
    if options is None:
        if st.button("Load intervention comparison", key=f"evaluate_{risk['RISK_ID']}"):
            try:
                options = sd.risk_intervention_options(owner_conn, risk)
                risk["INTERVENTION_OPTIONS"] = options
                recommendation = next((item for item in options if item.get("RECOMMENDED") is True), None)
                risk["RECOMMENDED_OPTION"] = recommendation
            except Exception as exc:
                st.error("Could not load intervention options from the governed evaluator.")
                with st.expander("Technical details"):
                    st.exception(exc)

    st.markdown("### Root cause / impact chain")
    for stage in sd.risk_impact_chain(risk, recommendation):
        with st.container(border=True):
            st.markdown(f"**{stage['stage']} — {stage['title']}**")
            st.write(stage["detail"])

    st.markdown("### Key evidence")
    evidence = st.columns(5)
    evidence[0].metric("Available", risk.get("AVAILABLE_QUANTITY"))
    evidence[1].metric("Safety stock", risk.get("SAFETY_STOCK"))
    evidence[2].metric("Requirement", risk.get("REQUIREMENT_QUANTITY"))
    evidence[3].metric("Supplier OTD", _format_percent(risk.get("SUPPLIER_OTD_PERCENT")))
    evidence[4].metric("Shipment delay", f"{risk['DELAY_DAYS']} days" if risk.get("DELAYED_SHIPMENT_ID") else "No attributed delay")

    st.markdown("### Recommended response")
    if recommendation:
        with st.container(border=True):
            st.markdown(f"**{recommendation.get('INTERVENTION_TYPE')}** — deterministic evaluator recommendation")
            cols = st.columns(4)
            cols[0].metric("Quantity", recommendation.get("QUANTITY_USED", "—"))
            cols[1].metric("Expected arrival", str(recommendation.get("ARRIVAL_DATE") or "—"))
            cols[2].metric("Shortage after", recommendation.get("SHORTAGE_AFTER", "—"))
            cols[3].metric("Recommendation rank", recommendation.get("RECOMMENDATION_RANK", "—"))
            st.write(recommendation.get("REASON") or "No governed reason was returned.")
            st.caption(recommendation.get("RISKS_OR_CONSTRAINTS") or "")
    else:
        st.info("No automatic recommendation is loaded for this risk. Automatic evaluation is bounded to the top 10 Critical/High risks; use the comparison control above for this selected risk.")

    if options:
        st.markdown("### What-if / intervention simulator")
        st.caption("SIMULATION ONLY — this comparison is read-only. It does not create an approval, modify source data, or dispatch an action.")
        comparison = []
        for option in options:
            comparison.append({
                "Option": option.get("INTERVENTION_TYPE"),
                "Feasible": option.get("FEASIBLE"),
                "Quantity": option.get("QUANTITY_USED"),
                "Transit / lead days": option.get("TRANSIT_OR_LEAD_DAYS"),
                "Expected arrival": option.get("ARRIVAL_DATE"),
                "Shortage after": option.get("SHORTAGE_AFTER"),
                "Estimated cost": option.get("ESTIMATED_COST"),
                "Currency": option.get("CURRENCY"),
                "Cost basis": option.get("COST_BASIS"),
                "Cost comparable": option.get("COST_COMPARABLE"),
                "Risk / constraints": option.get("RISKS_OR_CONSTRAINTS"),
                "Rank": option.get("RECOMMENDATION_RANK"),
                "Recommended": option.get("RECOMMENDED"),
            })
        st.dataframe(comparison, use_container_width=True, hide_index=True)

    st.markdown("### Governance")
    st.write("Governed Snowflake data: Yes · Deterministic risk score: Yes · Deterministic intervention ranking: Yes · Human approval required: Yes · Fresh-state validation before action: Yes · Auditable workflow: Yes")
    st.caption("DISPATCHED_DEMO means a governed action command was created in Snowflake; it does not mean SAP, TMS, WMS, or another external system was changed.")
    st.markdown("### Investigate with SupplyChainIQ")
    st.code(
        f"Why is {risk['PART_ID']} at {risk['PLANT_NAME']} at risk, and why is the recommended option preferred?",
        language=None,
    )

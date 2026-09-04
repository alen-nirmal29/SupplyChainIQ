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

    tab_confirmed, tab_predictive = st.tabs(["Confirmed Risks", "Predictive Early Warnings"])
    with tab_confirmed:
        _render_confirmed_risks(owner_conn)
    with tab_predictive:
        _render_predictive_warnings(owner_conn)


def _render_confirmed_risks(owner_conn):
    st.caption("Confirmed risks are based on known open customer demand and current operational state.")

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


def _fmt_qty(value):
    return f"{value:,.0f}" if isinstance(value, Number) else "—"


def _predictive_key(risk):
    return f"{risk['PART_ID']}|{risk['PLANT_ID']}"


def _predictive_label(risk):
    plant = risk.get("PLANT_NAME") or risk["PLANT_ID"]
    days = risk.get("DAYS_TO_PREDICTED_STOCKOUT")
    when = "immediate" if days == 0 else f"in {days}d" if isinstance(days, Number) else "timing unknown"
    return f"{risk['PART_ID']} at {plant} — predicted stockout {when}"


def _default_predictive_selection(records):
    """Phase 10b default-selection rule: prefer a genuinely future warning
    (PREDICTED_STOCKOUT_DATE > REFERENCE_DATE), earliest such stockout
    first, then highest forecasted shortage as the tie-break -- so the demo
    does not default to a Day-0 / zero-inventory case when a stronger
    forward-looking example exists."""
    if not records:
        return None
    future = [r for r in records if isinstance(r.get("DAYS_TO_PREDICTED_STOCKOUT"), Number) and r["DAYS_TO_PREDICTED_STOCKOUT"] > 0]
    pool = future if future else records
    return sorted(
        pool,
        key=lambda r: (r["DAYS_TO_PREDICTED_STOCKOUT"], -(r.get("FORECASTED_SHORTAGE_QUANTITY") or 0)),
    )[0]


def _render_predictive_warnings(owner_conn):
    st.markdown("### Predictive Early Warnings")
    st.caption(
        "Potential future stockouts identified from Snowflake ML demand forecasts. "
        "These are predictive signals, not confirmed customer-order shortages."
    )

    try:
        summary = sd.forecasted_stockout_summary(owner_conn)
        records = sd.forecasted_stockout_risks(owner_conn).to_dict("records")
    except Exception as exc:
        st.error("Predictive Early Warnings are unavailable until the governed forecast objects are deployed to DEV.")
        with st.expander("Technical details"):
            st.exception(exc)
        return

    day0 = summary.get("DAY0", 0) or 0
    day1_2 = summary.get("DAY1_2", 0) or 0
    day3_7 = summary.get("DAY3_7", 0) or 0
    day8_14 = summary.get("DAY8_14", 0) or 0

    metrics = st.columns(4)
    metrics[0].metric("Forecasted warnings", summary.get("TOTAL_WARNINGS", 0))
    metrics[1].metric("Immediate / Day 0", day0)
    metrics[2].metric("1–7 day warnings", day1_2 + day3_7)
    metrics[3].metric("8–14 day warnings", day8_14)

    accepted_series = summary.get("ACCEPTED_SERIES")
    if accepted_series is not None:
        st.caption(f"Accepted forecast series (model quality gate): {accepted_series:,}")

    if not records:
        st.success("No forecast-only early warnings currently identified beyond confirmed Risk Radar.")
        return

    st.caption("How soon are these predicted shortages expected?")
    st.bar_chart(
        {
            "Timing": ["Day 0", "Day 1–2", "Day 3–7", "Day 8–14"],
            "Warnings": [day0, day1_2, day3_7, day8_14],
        },
        x="Timing",
        y="Warnings",
        height=260,
    )

    with st.expander("Filters", expanded=False):
        plants = sorted({r.get("PLANT_NAME") or r["PLANT_ID"] for r in records})
        c1, c2, c3 = st.columns(3)
        plant_filter = c1.multiselect("Plant", plants, default=plants, key="predictive_plant_filter")
        part_query = c2.text_input("Part search", "", key="predictive_part_search")
        max_days = max((r.get("DAYS_TO_PREDICTED_STOCKOUT") or 0) for r in records)
        days_range = c3.slider("Days to stockout", 0, int(max_days), (0, int(max_days)), key="predictive_days_range")

    filtered = [
        r for r in records
        if (r.get("PLANT_NAME") or r["PLANT_ID"]) in plant_filter
        and (part_query.strip().upper() in r["PART_ID"].upper() if part_query.strip() else True)
        and days_range[0] <= (r.get("DAYS_TO_PREDICTED_STOCKOUT") or 0) <= days_range[1]
    ]
    if not filtered:
        st.info("No forecasted warnings match the selected filters.")
        return

    st.markdown("### Forecast-only early warnings")
    table_rows = [
        {
            "Part": r["PART_ID"],
            "Plant": r.get("PLANT_NAME") or r["PLANT_ID"],
            "Predicted stockout": str(r.get("PREDICTED_STOCKOUT_DATE") or "—"),
            "Days to stockout": r.get("DAYS_TO_PREDICTED_STOCKOUT"),
            "Usable inventory": r.get("CURRENT_USABLE_QUANTITY"),
            "Confirmed demand": r.get("CONFIRMED_DEMAND_QUANTITY"),
            "Forecast demand": round(r["FORECAST_DEMAND_QUANTITY"], 1) if isinstance(r.get("FORECAST_DEMAND_QUANTITY"), Number) else None,
            "Expected inbound": r.get("EXPECTED_INBOUND_QUANTITY"),
            "Forecasted shortage": round(r["FORECASTED_SHORTAGE_QUANTITY"], 1) if isinstance(r.get("FORECASTED_SHORTAGE_QUANTITY"), Number) else None,
            "Model quality (SMAPE)": f"{r['SMAPE'] * 100:.1f}%" if isinstance(r.get("SMAPE"), Number) else "—",
        }
        for r in filtered
    ]
    st.dataframe(table_rows, use_container_width=True, hide_index=True)

    options = [_predictive_key(r) for r in filtered]
    default_row = _default_predictive_selection(filtered)
    default_index = options.index(_predictive_key(default_row)) if default_row else 0
    selected_key = st.selectbox(
        "View predictive warning details",
        options=options,
        index=default_index,
        format_func=lambda key: _predictive_label(next(r for r in filtered if _predictive_key(r) == key)),
        key="predictive_warning_select",
    )
    selected = sd.forecasted_stockout_detail(filtered, *selected_key.split("|"))
    if selected:
        _render_predictive_detail(owner_conn, selected)


def _render_predictive_detail(owner_conn, risk):
    st.divider()
    st.markdown("### Predictive Early Warning")
    st.warning("Forecast-based early warning — not confirmed demand.")

    c1, c2 = st.columns(2)
    c1.metric("Part", f"{risk['PART_ID']} — {risk.get('PART_DESCRIPTION') or '—'}")
    c2.metric("Plant", f"{risk.get('PLANT_NAME') or risk['PLANT_ID']} — {risk['PLANT_ID']}")
    st.caption(
        "Current status: no confirmed shortage is currently detected for this Part + Plant "
        "(confirmed Risk Radar always takes precedence and is checked before this warning is shown)."
    )

    m = st.columns(4)
    m[0].metric("Current usable inventory", _fmt_qty(risk.get("CURRENT_USABLE_QUANTITY")))
    m[1].metric("Confirmed 14-day demand", _fmt_qty(risk.get("CONFIRMED_DEMAND_QUANTITY")))
    m[2].metric("Forecast 14-day demand", _fmt_qty(risk.get("FORECAST_DEMAND_QUANTITY")))
    m[3].metric("Expected inbound", _fmt_qty(risk.get("EXPECTED_INBOUND_QUANTITY")))

    m2 = st.columns(3)
    m2[0].metric("Forecasted shortage", _fmt_qty(risk.get("FORECASTED_SHORTAGE_QUANTITY")))
    m2[1].metric("Predicted stockout", str(risk.get("PREDICTED_STOCKOUT_DATE") or "—"))
    m2[2].metric("Days to stockout", risk.get("DAYS_TO_PREDICTED_STOCKOUT"))

    smape = risk.get("SMAPE")
    st.caption(
        f"Forecast model quality: SMAPE {smape * 100:.1f}%" if isinstance(smape, Number)
        else "Forecast model quality: unavailable"
    )

    st.info(
        "Confirmed demand represents known open customer orders. Forecast demand estimates total expected demand "
        "based on historical patterns. The two values are not added together."
    )

    st.markdown("#### Why this warning exists")
    usable = risk.get("CURRENT_USABLE_QUANTITY") or 0
    inbound = risk.get("EXPECTED_INBOUND_QUANTITY") or 0
    forecast_demand = risk.get("FORECAST_DEMAND_QUANTITY") or 0
    s1, s2, s3 = st.columns(3)
    s1.metric("Projected supply (usable + inbound)", _fmt_qty(usable + inbound))
    s2.metric("Forecast demand (14d)", _fmt_qty(forecast_demand))
    s3.metric("Gap", _fmt_qty(risk.get("FORECASTED_SHORTAGE_QUANTITY")))

    try:
        path_records = sd.forecast_path(owner_conn, risk["PART_ID"], risk["PLANT_ID"]).to_dict("records")
    except Exception as exc:
        st.warning("Could not load the daily forecast trajectory.")
        with st.expander("Technical details"):
            st.exception(exc)
        path_records = []

    if path_records:
        st.markdown("#### 14-day forecast trajectory")
        st.line_chart(
            {
                "Date": [str(r["FORECAST_DATE"]) for r in path_records],
                "Forecast demand": [r["FORECAST_VALUE"] for r in path_records],
            },
            x="Date",
            y="Forecast demand",
            height=260,
        )

        stockout_date = risk.get("PREDICTED_STOCKOUT_DATE")
        day_row = next((r for r in path_records if str(r["FORECAST_DATE"]) == str(stockout_date)), None) if stockout_date else None
        if day_row:
            st.markdown("#### Forecast on predicted stockout date")
            d1, d2, d3 = st.columns(3)
            d1.metric("Predicted demand that day", _fmt_qty(day_row.get("FORECAST_VALUE")))
            d2.metric("Lower bound", _fmt_qty(day_row.get("LOWER_BOUND")))
            d3.metric("Upper bound", _fmt_qty(day_row.get("UPPER_BOUND")))
            st.caption(
                "Prediction interval shown is Snowflake ML's single-day forecast bound for the predicted "
                "stockout date only — it is not a summed 14-day confidence interval."
            )

    st.info(
        "Predictive warnings are currently intended for early investigation and planning. "
        "Intervention evaluation remains available for confirmed operational risks."
    )

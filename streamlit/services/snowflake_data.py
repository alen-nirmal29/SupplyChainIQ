"""
Phase 9: structured Snowflake data access for the SupplyChainIQ Control Tower.

Every function here either reads governed data (CURATED / WORKFLOW / ACTION)
or calls the single human-only write procedure
(WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST). No business logic is
duplicated in Python -- every number/status shown in the UI comes straight
from a live query against the existing governed backend.

Read-only dashboard queries may use either connection (identity is
irrelevant for shared reference data). The human-review write MUST be
called with the RESTRICTED CALLER connection so REVIEW_INTERVENTION_
APPROVAL_REQUEST's SYS_CONTEXT-based identity capture reflects the actual
signed-in viewer, not the Streamlit app owner.
"""

import json

DB = "SUPPLYCHAINIQ_DB"


def flagship_risk(conn):
    """Live flagship risk facts for S017 / P104 / P01 via the governed decision procedure."""
    session = conn.session()
    raw = session.call(
        f"{DB}.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS",
        "S017",
        "P104",
        "P01",
    )
    return json.loads(raw) if isinstance(raw, str) else raw


def overview_kpis(conn):
    """Live KPI values sourced from existing curated/workflow/action objects only."""
    kpis = {}

    df = conn.query(
        f"""
        SELECT
          COUNT(*) AS affected_order_lines,
          SUM(od.ORDER_VALUE) AS revenue_exposure
        FROM {DB}.CURATED.CUSTOMER_ORDER_LINE od
        WHERE od.PART_ID = 'P104'
        """,
        ttl=0,
    )
    row = df.to_dict("records")[0]
    kpis["affected_order_lines"] = row.get("AFFECTED_ORDER_LINES")
    kpis["revenue_exposure"] = row.get("REVENUE_EXPOSURE")

    # OTD is an existing Semantic View metric (shipment.supplier_otd_percent) --
    # queried via native SEMANTIC_VIEW() SQL, never recomputed in Python.
    df = conn.query(
        f"""SELECT supplier_otd_percent AS OTD FROM SEMANTIC_VIEW(
              {DB}.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW METRICS shipment.supplier_otd_percent)""",
        ttl=0,
    )
    kpis["overall_otd"] = df.to_dict("records")[0]["OTD"]

    df = conn.query(
        f"""SELECT supplier_id, supplier_otd_percent AS OTD FROM SEMANTIC_VIEW(
              {DB}.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW METRICS shipment.supplier_otd_percent
              DIMENSIONS supplier.supplier_id) WHERE supplier_id = 'S017'""",
        ttl=0,
    )
    recs = df.to_dict("records")
    kpis["pinnacle_otd"] = recs[0]["OTD"] if recs else None

    df = conn.query(
        f"SELECT COUNT(*) AS N FROM {DB}.WORKFLOW.INTERVENTION_APPROVAL_REQUEST WHERE REQUEST_STATUS = 'PENDING'",
        ttl=0,
    )
    kpis["pending_approvals"] = df.to_dict("records")[0]["N"]

    df = conn.query(
        f"""SELECT COUNT(*) AS N FROM {DB}.WORKFLOW.INTERVENTION_APPROVAL_REQUEST
            WHERE REQUEST_STATUS = 'APPROVED' AND EXECUTION_STATUS = 'NOT_DISPATCHED'""",
        ttl=0,
    )
    kpis["approved_not_dispatched"] = df.to_dict("records")[0]["N"]

    df = conn.query(
        f"SELECT COUNT(*) AS N FROM {DB}.ACTION.INTERVENTION_ACTION_COMMAND WHERE ACTION_STATUS = 'DISPATCHED_DEMO'",
        ttl=0,
    )
    kpis["dispatched_demo_actions"] = df.to_dict("records")[0]["N"]

    return kpis


def risk_radar(conn):
    """Ranked, deterministic risk records calculated by the governed RISK view."""
    return conn.query(
        f"""
        SELECT *
        FROM {DB}.RISK.SUPPLY_CHAIN_RISK_RANKING
        ORDER BY RISK_RANK, RISK_ID
        """,
        ttl=0,
    )


def risk_radar_summary(conn):
    """Live summary counts and INR customer-order exposure from the RISK view."""
    df = conn.query(
        f"""
        SELECT
          COUNT(*) AS ACTIVE_RISKS,
          COUNT_IF(SEVERITY = 'CRITICAL') AS CRITICAL_RISKS,
          COUNT_IF(SEVERITY = 'HIGH') AS HIGH_RISKS,
          COUNT_IF(SEVERITY = 'MEDIUM') AS MEDIUM_RISKS,
          SUM(REVENUE_EXPOSURE) AS REVENUE_EXPOSURE
        FROM {DB}.RISK.SUPPLY_CHAIN_RISK_RANKING
        """,
        ttl=0,
    )
    return df.to_dict("records")[0]


def top_active_risk(conn):
    """Highest currently ranked governed risk, or None when the RISK view is empty."""
    df = conn.query(
        f"""
        SELECT *
        FROM {DB}.RISK.SUPPLY_CHAIN_RISK_RANKING
        WHERE RISK_RANK = 1
        """,
        ttl=0,
    )
    records = df.to_dict("records")
    return records[0] if records else None


def forecasted_stockout_summary(conn):
    """
    Phase 10b: single aggregate query over the governed, already-suppressed
    RISK.FORECASTED_STOCKOUT_RISK view. Every count is computed in SQL --
    no Phase 2/2.1 counts are hardcoded in Python.
    """
    df = conn.query(
        f"""
        SELECT
          COUNT(*) AS TOTAL_WARNINGS,
          COUNT_IF(DAYS_TO_PREDICTED_STOCKOUT = 0) AS DAY0,
          COUNT_IF(DAYS_TO_PREDICTED_STOCKOUT BETWEEN 1 AND 2) AS DAY1_2,
          COUNT_IF(DAYS_TO_PREDICTED_STOCKOUT BETWEEN 3 AND 7) AS DAY3_7,
          COUNT_IF(DAYS_TO_PREDICTED_STOCKOUT BETWEEN 8 AND 14) AS DAY8_14,
          (SELECT COUNT(*) FROM {DB}.RISK.FORECAST_MODEL_QUALITY WHERE SMAPE <= 0.5) AS ACCEPTED_SERIES
        FROM {DB}.RISK.FORECASTED_STOCKOUT_RISK
        """,
        ttl=0,
    )
    return df.to_dict("records")[0]


def forecasted_stockout_risks(conn):
    """
    Phase 10b: forecast-only early-warning rows (already suppressed against
    confirmed Risk Radar by the view itself), joined to the persisted
    per-series SMAPE quality metric. Ordered deterministically by
    PREDICTED_STOCKOUT_DATE ASC, then FORECASTED_SHORTAGE_QUANTITY DESC,
    PART_ID, PLANT_ID.
    """
    return conn.query(
        f"""
        SELECT f.*, q.SMAPE
        FROM {DB}.RISK.FORECASTED_STOCKOUT_RISK f
        LEFT JOIN {DB}.RISK.FORECAST_MODEL_QUALITY q
          ON q.PART_ID = f.PART_ID AND q.PLANT_ID = f.PLANT_ID
        ORDER BY f.PREDICTED_STOCKOUT_DATE ASC, f.FORECASTED_SHORTAGE_QUANTITY DESC, f.PART_ID, f.PLANT_ID
        """,
        ttl=0,
    )


def forecasted_stockout_detail(records, part_id, plant_id):
    """
    Pure lookup over an already-fetched forecasted_stockout_risks() result
    set -- no additional Snowflake call, since the caller already holds the
    full governed row for every warning in the list.
    """
    return next(
        (r for r in records if r.get("PART_ID") == part_id and r.get("PLANT_ID") == plant_id),
        None,
    )


def forecast_path(conn, part_id, plant_id):
    """
    Phase 10b: persisted daily forecast trajectory for one PART_ID+PLANT_ID
    series from RISK.FORECASTED_DEMAND (already generated by
    SNOWFLAKE.ML.FORECAST and persisted -- never recomputed here). Used for
    the 14-day trajectory chart and for the single-day prediction interval
    on the predicted stockout date. FORECAST_DATE is cast to DATE in SQL so
    it compares cleanly against RISK.FORECASTED_STOCKOUT_RISK.PREDICTED_STOCKOUT_DATE.
    """
    return conn.query(
        f"""
        SELECT
          FORECAST_DATE::DATE AS FORECAST_DATE,
          FORECAST_VALUE,
          LOWER_BOUND,
          UPPER_BOUND
        FROM {DB}.RISK.FORECASTED_DEMAND
        WHERE PART_ID = ? AND PLANT_ID = ?
        ORDER BY FORECAST_DATE
        """,
        params=[part_id, plant_id],
        ttl=0,
    )


def risk_intervention_options(conn, risk):
    """Read-only deterministic evaluator output for one selected risk grain."""
    session = conn.session()
    raw = session.call(
        f"{DB}.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS",
        risk["SUPPLIER_ID"],
        risk["PART_ID"],
        risk["PLANT_ID"],
    )
    return json.loads(raw) if isinstance(raw, str) else raw


def enrich_qualifying_risks(conn, records, max_evaluations=10):
    """Attach evaluator-selected recommendations for at most top-N Critical/High risks."""
    evaluated = 0
    enriched = []
    for risk in records:
        item = dict(risk)
        item["RECOMMENDED_OPTION"] = None
        item["INTERVENTION_OPTIONS"] = None
        if item.get("SEVERITY") in ("CRITICAL", "HIGH") and evaluated < max_evaluations:
            options = risk_intervention_options(conn, item)
            item["INTERVENTION_OPTIONS"] = options
            item["RECOMMENDED_OPTION"] = next(
                (option for option in options if option.get("RECOMMENDED") is True), None
            )
            evaluated += 1
        enriched.append(item)
    return enriched


def risk_impact_chain(risk, recommendation=None):
    """Presentation-only chain composed from governed risk and evaluator fields."""
    chain = [
        {
            "stage": "Supplier",
            "title": risk.get("SUPPLIER_NAME") or risk.get("SUPPLIER_ID"),
            "detail": (
                f"Historical supplier OTD: {risk['SUPPLIER_OTD_PERCENT']:.1%}"
                if risk.get("SUPPLIER_OTD_PERCENT") is not None
                else "No governed historical supplier OTD is available for this risk."
            ),
        },
        {
            "stage": "Shipment",
            "title": "Inbound shipment delayed" if risk.get("DELAYED_SHIPMENT_ID") else "No delayed inbound shipment attributed",
            "detail": (
                f"{risk['DELAYED_SHIPMENT_ID']} is {risk.get('DELAY_DAYS')} day(s) behind its promised date."
                if risk.get("DELAYED_SHIPMENT_ID")
                else "Risk remains based on governed inventory and open customer-order demand."
            ),
        },
        {
            "stage": "Inventory constraint",
            "title": f"{risk.get('PART_ID')} at {risk.get('PLANT_NAME')}",
            "detail": f"Governed shortage: {risk.get('SHORTAGE_QUANTITY')} units after safety stock.",
        },
        {
            "stage": "Customer impact",
            "title": "Open customer demand at risk",
            "detail": f"{risk.get('AFFECTED_ORDER_LINES')} order line(s); first due {risk.get('FIRST_CUSTOMER_DUE_DATE')}; revenue exposure is INR {risk.get('REVENUE_EXPOSURE')}.",
        },
    ]
    if recommendation:
        chain.append(
            {
                "stage": "Recommended response",
                "title": recommendation.get("INTERVENTION_TYPE"),
                "detail": recommendation.get("REASON") or "Selected deterministically by the governed evaluator.",
            }
        )
    return chain


# Historical Phase 8B pre-fix validation artifact -- excluded from the default
# flagship/demo view per Phase 9 design. Never deleted or modified.
KNOWN_TEST_ARTIFACT_REQUEST_IDS = ("AR-764ccb86-e3c6-4a09-9b93-450264f37f51",)


def approval_queue(conn, include_test_artifacts=False):
    """Business-readable approval queue from WORKFLOW.INTERVENTION_APPROVAL_REQUEST."""
    exclude_clause = ""
    if not include_test_artifacts:
        placeholders = ",".join(f"'{rid}'" for rid in KNOWN_TEST_ARTIFACT_REQUEST_IDS)
        exclude_clause = f"WHERE r.REQUEST_ID NOT IN ({placeholders})"

    df = conn.query(
        f"""
        SELECT
          r.REQUEST_ID, s.SUPPLIER_NAME, p.PART_DESCRIPTION, pl.PLANT_NAME,
          r.SELECTED_INTERVENTION_TYPE, r.RECOMMENDATION_RANK,
          r.REQUEST_STATUS, r.EXECUTION_STATUS,
          r.REQUESTED_BY, r.REQUESTED_ROLE, r.REQUESTED_AT,
          r.APPROVED_OR_REJECTED_BY, r.DECISION_AT, r.DECISION_COMMENT,
          r.ACTION_ID, r.SUPPLIER_ID, r.PART_ID, r.DESTINATION_PLANT_ID,
          r.RECOMMENDATION_SNAPSHOT, r.RECOMMENDATION_HASH
        FROM {DB}.WORKFLOW.INTERVENTION_APPROVAL_REQUEST r
        LEFT JOIN {DB}.CURATED.SUPPLIER s ON s.SUPPLIER_ID = r.SUPPLIER_ID
        LEFT JOIN {DB}.CURATED.PART p ON p.PART_ID = r.PART_ID
        LEFT JOIN {DB}.CURATED.PLANT pl ON pl.PLANT_ID = r.DESTINATION_PLANT_ID
        {exclude_clause}
        ORDER BY r.REQUESTED_AT DESC
        """,
        ttl=0,
    )
    return df


def actions_view(conn):
    """Action command + event data from the ACTION schema."""
    df = conn.query(
        f"""
        SELECT
          a.ACTION_ID, a.REQUEST_ID, a.INTERVENTION_TYPE, a.EXECUTION_MODE, a.ACTION_STATUS,
          a.SUPPLIER_ID, a.PART_ID, a.DESTINATION_PLANT_ID,
          a.DISPATCHED_BY, a.DISPATCHED_ROLE, a.DISPATCHED_AT,
          a.COMMAND_PAYLOAD, a.APPROVED_SNAPSHOT_HASH, a.FRESH_EVALUATION_HASH
        FROM {DB}.ACTION.INTERVENTION_ACTION_COMMAND a
        ORDER BY a.DISPATCHED_AT DESC
        """,
        ttl=0,
    )
    return df


def workflow_timeline(conn, request_id):
    """Structured timeline for one request: approval events + action events."""
    approval_events = conn.query(
        f"""
        SELECT EVENT_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, OLD_STATUS, NEW_STATUS,
               COMMENT AS DETAILS
        FROM {DB}.WORKFLOW.INTERVENTION_APPROVAL_EVENT
        WHERE REQUEST_ID = ?
        ORDER BY EVENT_AT
        """,
        params=[request_id],
        ttl=0,
    )
    action_events = conn.query(
        f"""
        SELECT EVENT_ID, ACTION_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, DETAILS
        FROM {DB}.ACTION.INTERVENTION_ACTION_EVENT
        WHERE REQUEST_ID = ?
        ORDER BY EVENT_AT
        """,
        params=[request_id],
        ttl=0,
    )
    return approval_events, action_events


def review_request(caller_conn, request_id, decision, comment):
    """
    The ONLY write path in this file. Calls the human-only procedure
    WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST directly via the
    RESTRICTED CALLER connection so the procedure's SYS_CONTEXT-based
    identity capture reflects the actual signed-in human, not the
    Streamlit app owner. This procedure is never exposed to the Cortex
    Agent and this function must never be called on the Agent's behalf.
    """
    session = caller_conn.session()
    raw = session.call(
        f"{DB}.WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST",
        request_id,
        decision,
        comment,
    )
    return json.loads(raw) if isinstance(raw, str) else raw


def viewer_identity(caller_conn):
    """CURRENT_USER()/CURRENT_ROLE() as observed through the restricted caller connection."""
    df = caller_conn.query(
        "SELECT CURRENT_USER() AS U, CURRENT_ROLE() AS R, "
        "SYS_CONTEXT('SNOWFLAKE$SESSION','PRINCIPAL_NAME') AS PRINCIPAL",
        ttl=0,
    )
    return df.to_dict("records")[0]

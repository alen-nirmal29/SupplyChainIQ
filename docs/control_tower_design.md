# SupplyChainIQ Control Tower — Phase 9 Design & Implementation

## Objective

A Streamlit-in-Snowflake (container runtime) presentation layer over the
governed Phase 1–8C backend. Natural-language interaction with the
existing `SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT` remains the
primary UX; structured panels (Overview, Approvals, Actions, Timeline)
expose workflow state read directly from `WORKFLOW`/`ACTION` tables.

No business logic is reimplemented in Python. Every number/status shown
in the UI is queried live from Snowflake on each render/refresh.

## Runtime

- **Streamlit in Snowflake, Container Runtime**, `SYSTEM$ST_CONTAINER_RUNTIME_PY3_11`.
- `COMPUTE_POOL = SYSTEM_COMPUTE_POOL_CPU` (pre-existing account default; no new pool created).
- `QUERY_WAREHOUSE = COMPUTE_WH`.
- Confirmed via `DESCRIBE STREAMLIT SUPPLYCHAINIQ_DB.APP.SUPPLYCHAINIQ_CONTROL_TOWER`
  after deployment: `compute_pool=SYSTEM_COMPUTE_POOL_CPU`,
  `runtime_name=SYSTEM$ST_CONTAINER_RUNTIME_PY3_11`, `query_warehouse=COMPUTE_WH`.

## Object

`SUPPLYCHAINIQ_DB.APP.SUPPLYCHAINIQ_CONTROL_TOWER` in the new, presentation-only
`SUPPLYCHAINIQ_DB.APP` schema (no business-state tables added here).

## Agent integration

`SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT', request_body_json, auto_create_thread)`,
called through the OWNER Snowflake connection. Thread continuity is
maintained by capturing `metadata.thread_id` and `metadata.assistant_message_id`
from each response and passing them back as `thread_id`/`parent_message_id`
on the next call (`auto_create_thread=FALSE` for continuation turns).
Verified directly via SQL: a two-turn OTD question correctly retained
context ("that" resolved to S017's 49.4% OTD in the second turn), and the
full flagship chain (ask -> submit -> approve -> status -> execute)
produced one fresh governed request/action pair end-to-end.

Internal `thinking` content blocks are explicitly filtered out in
`services/agent_client.py` and never rendered.

## Human identity / restricted caller's rights

Two connections are created at top-level app startup:
`st.connection("snowflake")` (owner) and
`st.connection("snowflake-callers-rights")` (restricted caller). All
approval/reject/cancel actions in `components/approvals.py` are called
through the restricted-caller connection so
`WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST`'s `SYS_CONTEXT`-based
identity capture reflects the actual signed-in viewer. `st.user.user_name`
is shown for display only; the sidebar also runs a live
`CURRENT_USER()`/`CURRENT_ROLE()` check through the restricted-caller
connection and warns if it disagrees with the displayed viewer.

**Known limitation, disclosed honestly**: this account currently has a
single actual user (ALEN, ACCOUNTADMIN). Genuine multi-user divergence
between owner-rights and restricted-caller-rights identity could not be
observed in this environment. I could not verify the exact bundled
Streamlit version or interactively click through the deployed app myself
(no browser tool available in this session) — the sidebar exposes a live
`streamlit.__version__` diagnostic and a live identity cross-check so this
can be confirmed the moment a human opens the app.

## Information architecture

Flat sidebar navigation: Overview / Ask SupplyChainIQ / Approvals / Actions / Timeline.

## Files

```
streamlit/
  streamlit_app.py
  snowflake.yml
  environment.yml
  components/
    overview.py
    chat.py
    approvals.py
    actions.py
    timeline.py
  services/
    agent_client.py
    snowflake_data.py
sql/23_control_tower_grants.sql
docs/control_tower_design.md
```

## Regression boundary

No changes to `DECISION`, `WORKFLOW`, `ACTION`, `SEMANTIC`, `SEARCH`,
`CURATED`, or source schemas, other than the additive read/write access
patterns already documented in Phase 8B/8C. Confirmed unchanged: 14
`CURATED` views, Cortex Search (139 rows, ACTIVE/ACTIVE), Cortex Agent
(exactly 8 tools).

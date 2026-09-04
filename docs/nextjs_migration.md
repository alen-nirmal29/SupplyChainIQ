# SupplyChainIQ Control Tower -- Next.js Migration

Status: **application-layer migration in progress**. The existing Streamlit app (`streamlit/`)
remains fully intact and deployed; this Next.js app (`web/`) is being built alongside it as a
replacement frontend over the same, unchanged Snowflake backend.

## Architecture

```
Browser
   |
Next.js App Router (web/app/**/page.tsx)
   |
Next.js Route Handlers (web/app/api/**/route.ts)
   |
Server-only service modules (web/lib/snowflake/*)
   |
snowflake-sdk (Node.js driver)
   |
Existing SupplyChainIQ Snowflake backend (unchanged)
```

No business logic (risk scoring, shortage ranking, intervention ranking, forecast generation,
approval/dispatch state transitions, supplier OTD) is reimplemented in TypeScript. Every number
shown by the UI comes from a live query or procedure call against the same governed Snowflake
objects the Streamlit app already used.

## Folder structure

```
web/
├── app/
│   ├── layout.tsx, page.tsx (redirect -> /overview), globals.css
│   ├── overview/page.tsx
│   ├── risk-radar/page.tsx        (Confirmed Risks + Predictive Early Warnings tabs)
│   ├── ask/page.tsx
│   ├── approvals/page.tsx
│   ├── actions/page.tsx
│   ├── timeline/page.tsx
│   └── api/
│       ├── overview/route.ts
│       ├── risks/confirmed/route.ts
│       ├── risks/confirmed/[riskId]/interventions/route.ts
│       ├── risks/predictive/route.ts
│       ├── risks/predictive/[part]/[plant]/forecast/route.ts
│       ├── agent/route.ts
│       ├── approvals/route.ts
│       ├── approvals/[id]/review/route.ts
│       ├── actions/route.ts
│       └── timeline/route.ts
├── components/{layout,ui,risk,forecast,ask,approvals,actions,timeline}/*.tsx
├── lib/snowflake/{connection.ts,query.ts}, lib/{demo-mode.ts,format.ts}
├── types/{risk,forecast,approval,action,timeline,agent,overview}.ts
└── public/
```

## Streamlit -> Next.js page mapping

| Streamlit page | Snowflake source | Next.js page | API route(s) |
|---|---|---|---|
| Overview | `CUSTOMER_ORDER_LINE`, `SEMANTIC_VIEW(...)`, `WORKFLOW`/`ACTION` counts, `RISK.SUPPLY_CHAIN_RISK_RANKING` | `/overview` | `GET /api/overview` |
| Risk Radar (Confirmed) | `RISK.SUPPLY_CHAIN_RISK_RANKING`, `DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS` | `/risk-radar` (tab) | `GET /api/risks/confirmed`, `GET /api/risks/confirmed/[riskId]/interventions` |
| Risk Radar (Predictive) | `RISK.FORECASTED_STOCKOUT_RISK`, `RISK.FORECASTED_DEMAND`, `RISK.FORECAST_MODEL_QUALITY` | `/risk-radar` (tab) | `GET /api/risks/predictive`, `GET /api/risks/predictive/[part]/[plant]/forecast` |
| Ask SupplyChainIQ | `SNOWFLAKE.CORTEX.DATA_AGENT_RUN` on `AGENTS.SUPPLYCHAINIQ_AGENT` | `/ask` | `POST /api/agent` |
| Approvals | `WORKFLOW.INTERVENTION_APPROVAL_REQUEST`, `REVIEW_INTERVENTION_APPROVAL_REQUEST` | `/approvals` | `GET /api/approvals`, `POST /api/approvals/[id]/review` |
| Actions | `ACTION.INTERVENTION_ACTION_COMMAND` (read-only) | `/actions` | `GET /api/actions` |
| Timeline | `WORKFLOW.INTERVENTION_APPROVAL_EVENT` + `ACTION.INTERVENTION_ACTION_EVENT` | `/timeline` | `GET /api/timeline?requestId=` |

## Predictive Early Warning rules preserved from Phase 2/2.1

- Backed only by `RISK.FORECASTED_STOCKOUT_RISK` / `RISK.FORECASTED_DEMAND` / `RISK.FORECAST_MODEL_QUALITY`
  (already-suppressed against confirmed risk, already quality-gated by SMAPE).
- **Single-day prediction interval rule**: the UI only ever shows the persisted
  `LOWER_BOUND`/`FORECAST_VALUE`/`UPPER_BOUND` for the exact `FORECAST_DATE = PREDICTED_STOCKOUT_DATE` row.
  The 14-day summed `LOWER_PREDICTION_BOUND`/`UPPER_PREDICTION_BOUND` on the risk row is never
  presented as a calibrated confidence interval.
- No recommendation, submit-for-approval, approve, or dispatch control exists anywhere in the
  Predictive tab -- confirmed by code review (`grep` for these terms returns matches only inside
  `components/risk/*`, the Confirmed Risks code path).
- Default selection prefers a genuinely future warning (`daysToStockout > 0`), earliest such
  stockout first, then highest forecasted shortage as the tie-break -- never hardcoded to a
  specific part/plant.

## Snowflake connectivity

- `lib/snowflake/connection.ts`: server-only (`import "server-only"`) singleton connection via
  `snowflake-sdk`. Never imported from a Client Component.
- `lib/snowflake/query.ts`: `query()` (parameterized `?` binds) and `callProcedure()` (fixed,
  hardcoded procedure names only -- never derived from request input) helpers. All route handlers
  use these instead of building SQL by string concatenation.
- Credentials are read only from server-side environment variables (never `NEXT_PUBLIC_*`).

## Authentication

Preferred: key-pair / `SNOWFLAKE_JWT` (`SNOWFLAKE_AUTHENTICATOR=SNOWFLAKE_JWT`,
`SNOWFLAKE_PRIVATE_KEY_PATH`, optional passphrase). Password auth is supported as a local-dev
fallback only and should not be used in any deployed environment. See `web/.env.example` for the
full variable list. `ACCOUNTADMIN` must not be the role used for the eventual public deployment.

**Known gap (must be resolved before enabling live approval mutation):** the Streamlit app uses
two separate Snowflake connections -- an owner connection for reads and a *restricted caller*
connection for identity-sensitive writes, so `WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST`'s
`SYS_CONTEXT`-based identity capture reflects the real signed-in human. The current
`POST /api/approvals/[id]/review` route calls this procedure on the single shared server
connection. Before this endpoint is used against a real approval workflow (rather than test data),
it must be wired to a per-authenticated-user Snowflake session (e.g. via OAuth token exchange per
request) so identity capture is correct. Until then, treat approval mutation as unauthenticated
in this build.

## Public demo mode

`PUBLIC_DEMO_MODE=true` disables all mutation endpoints server-side (`lib/demo-mode.ts`,
`assertMutationsAllowed()`), regardless of what the UI renders. Currently wired into
`POST /api/approvals/[id]/review`; any future dispatch route must call the same guard first. This
mode has not been activated by default and is not yet exposed as a deployed configuration.

## Local run

```bash
cd web
npm install
cp .env.example .env.local   # fill in real values in .env.local; never commit it
npm run dev
```

## Build / validate

```bash
npm run lint
npm run typecheck
npm run build
```

## Known differences from Streamlit

- Overview's "Top Active Risk" no longer falls back to a hardcoded flagship-scenario panel when
  `RISK.SUPPLY_CHAIN_RISK_RANKING` is empty (Streamlit's `render_flagship_risk_panel` fallback) --
  the Next.js Overview simply shows "no active risk" in that case. This can be reintroduced later
  if the flagship demo fallback is still desired.
- Approval review identity capture is not yet wired to a per-user Snowflake session (see Known gap
  above) -- this is a genuine functional gap versus the Streamlit app's `caller_conn`, not a
  cosmetic difference.
- Charting uses Recharts instead of Streamlit's native `st.bar_chart`/`st.line_chart`.

## Deployment

Not yet deployed. Per the migration plan, this build must be validated locally (lint/typecheck/build,
and live read-only checks against Snowflake) before any deployment decision (Vercel, SPCS, or
Snowflake App Runtime) is made. The existing Streamlit app remains the deployed fallback until
then.

# SupplyChainIQ Web (Next.js)

Next.js application layer for the SupplyChainIQ Control Tower, replacing the Streamlit UI over
the same, unchanged Snowflake backend. See `../docs/nextjs_migration.md` for full architecture,
page mapping, and known gaps.

## Setup

```bash
npm install
cp .env.example .env.local   # fill in real values; never commit .env.local
npm run dev
```

Open http://localhost:3000.

## Scripts

- `npm run dev` -- local development server
- `npm run build` -- production build
- `npm run start` -- run a production build
- `npm run lint` -- ESLint
- `npm run typecheck` -- TypeScript compiler check (no emit)

## Notes

- All Snowflake access is server-only (`lib/snowflake/`) -- never imported into a Client
  Component and never exposed via `NEXT_PUBLIC_*`.
- No business logic (risk scoring, forecasting, approval/dispatch state) is implemented here --
  every page reads from existing governed Snowflake views/procedures.
- `PUBLIC_DEMO_MODE=true` disables all mutation endpoints server-side; see `.env.example`.

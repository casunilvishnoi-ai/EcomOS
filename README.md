# EcomOS

All-in-one Indian e-commerce seller platform: marketplace connections, order and label operations, settlement and bank reconciliation, GSTIN-wise GSTR-1 export, and TallyPrime / Zoho Books voucher exports.

The product and technical blueprint lives in [docs/BLUEPRINT.md](docs/BLUEPRINT.md). It is the source of truth for scope, data model, accounting logic, controls and MVP acceptance criteria.

## Stack

- Next.js 16 (App Router, server actions, React 19), TypeScript, Tailwind 4
- Prisma 6 with SQLite for local development (schema avoids SQLite-only features so it can move to Postgres)
- pdf-lib for invoices, credit notes, sample labels and print derivatives; exceljs for review workbooks and workpapers
- vitest for unit tests of the pure engines (money, tax rules, parsers, classifier, GSTR-1 builder, journal engine, ERP formatters)

## Run locally

```bash
npm install
```

```bash
npx prisma migrate dev
```

```bash
npm run dev
```

Open http://localhost:3000, create a workspace, then on the readiness checklist click **Load sample seller** to get two GSTINs, Amazon and Flipkart stores, orders, invoices, a settlement statement, a bank statement and starter ledger mappings.

Other scripts: `npm test` (unit tests), `npm run typecheck`, `npm run db:studio`.

Environment: `.env` holds `DATABASE_URL`. Optional `SESSION_SECRET`, `SECRETS_KEY` (credential encryption), `STORAGE_ROOT` (immutable file store, defaults to `./data`) or `S3_BUCKET`/`S3_ENDPOINT`/`S3_ACCESS_KEY_ID`/`S3_SECRET_ACCESS_KEY` for object storage, `RESEND_API_KEY`/`ALERT_FROM_EMAIL` for email alerts, `WHATSAPP_WEBHOOK_URL`/`WHATSAPP_WEBHOOK_TOKEN` for WhatsApp alerts.

## What is built (release one)

| Area | Where | Notes |
|---|---|---|
| Sign-up, roles, MFA flag | `/signup`, `/settings/users` | owner, admin, operations, accountant, reviewer, auditor |
| Entities, GSTINs, warehouses, bank accounts | `/settings/*` | GSTIN checksum validated; warehouse state must match GSTIN state |
| SKU / HSN / tax master | `/settings/products` | CSV import with validation; GST rate never inferred from category |
| Chart-of-accounts mapping | `/settings/coa` | canonical taxonomy → Tally / Zoho ledger names, versioned policy, immutable once exported |
| Marketplace connections | `/connections` | published channel matrix; OAuth / credential / file-import modes; encrypted secrets; report upload for orders and settlements |
| Orders | `/orders`, `/orders/[id]` | unified queue, filters, bulk pick/pack/ready, GSTIN and place-of-supply assignment, raw + normalized state timeline |
| Invoices and credit notes | `/invoices` | GSTIN series numbering, PDF, documents-issued register, period-lock gating |
| Shipments and labels | `/shipments`, `/shipments/[id]` | asynchronous label jobs, label upload, immutable original + print derivatives (rotate/crop/scale to printer profile), print log with reprint reasons, pickup requires scan evidence |
| Returns | `/returns` | receive → inspect → refund with linked credit note and proportional GST reversal; returned stock is uninspected until checked |
| Inventory | `/inventory` | available / reserved (computed from open orders) / damaged / returned, oversell and low-stock warnings |
| Settlements | `/settlements`, `/settlements/[id]` | line classification with confidence, bridge invariant, reclassification, opening/closing balances, close gate |
| Bank deposits | `/bank` | statement import, auto-match by payout reference then amount+date, manual many-to-many matching, charge classification |
| Fees | `/fees` | effective-dated rate card, actual-vs-expected variance cases, fee GST vs tax invoices |
| Exceptions | `/exceptions` | owner, due date, evidence, resolve / write-off / claim |
| GSTR-1 | `/gst` | per GSTIN + period: preflight checks, table classification (B2B, B2CL, B2CS, CDNR/CDNUR, HSN, documents issued, Table 14 ECO), JSON + review XLSX + validation report, portal status workflow |
| TCS / TDS schedules | `/tax-credits` | by operator GSTIN / deductor PAN and month, governing Act by event date |
| Journals and ERP export | `/journals`, `/journals/[id]` | order / settlement / period grain, GSTIN or marketplace split, three date bases, maker-checker approval, TallyPrime XML (+ ledger masters), Zoho Books Manual Journals CSV, workpaper, readme, checksums, reversal batches |
| Period locks, audit log | `/periods`, `/audit` | readiness gates, reopen with reason, append-only audit with before/after hashes |

## Deployment

The app ships as a Docker image (Next.js standalone server on Node 26) backed by PostgreSQL.

```bash
docker compose up --build
```

`docker-compose.yml` starts Postgres and the app; the entrypoint applies migrations (`prisma migrate deploy` with `prisma/schema.postgres.prisma`) and then serves on port 3000. Required environment: `SESSION_SECRET` and `SECRETS_KEY` (32+ characters each), `DATABASE_URL`, `APP_URL`; optional `CRON_SECRET`, `SPAPI_CLIENT_ID`, `SPAPI_CLIENT_SECRET`, `STORAGE_ROOT`. In production the app refuses to start without the secrets, cookies are `Secure`, the dev-only mock sandboxes return 404, security headers are set on every response, and sign-in is throttled to 10 attempts per 15 minutes per email.

Operations:

| Need | How |
|---|---|
| Health check | `GET /api/health` (verifies the database; 503 when degraded) |
| Advance asynchronous label jobs | `POST /api/jobs/labels` with `Authorization: Bearer $CRON_SECRET` every minute |
| Incremental marketplace sync | `POST /api/jobs/sync` with the same header every 15–30 minutes |
| Persistent files | mount a volume at `STORAGE_ROOT` (`/data` in the image); files are content-addressed and immutable |
| Schema change | edit `prisma/schema.prisma`, run `npx prisma migrate dev`, then `npm run db:postgres-schema` to regenerate the Postgres schema and migration |

Any platform that runs a container (Fly.io, Render, Railway, ECS, Cloud Run, a VM) works; point `DATABASE_URL` at a managed Postgres and provide a persistent disk or object storage for `STORAGE_ROOT`. CI (`.github/workflows/ci.yml`) validates both schemas, typechecks, runs the unit tests, builds the production bundle and the Docker image.

## P0 gap closure (3 November 2026)

| Gap | Where |
|---|---|
| Meesho, Myntra, JioMart, Ajio, Snapdeal | report parsers for orders and wide-format settlements (`src/lib/connectors/wide-settlements.ts`); channels listed in the matrix |
| Channel stock and price sync | `/inventory/channels`: available-to-promise × channel allocation, pushed via Amazon Listings Items API and Flipkart inventory API; stock file for file-only channels; `POST /api/jobs/inventory` |
| GSTR-2A/2B/8 TCS matching, GSTR-3B working | `/gst/credits`: import portal JSON/CSV, match by operator GSTIN × supplier GSTIN × month, mismatch cases, 3B schedule with ITC set-off and matched TCS cash credit |
| 26AS / AIS TDS matching | `/tax-credits`: import, deductor TAN mapping, quarter-aware matching |
| SKU and order P&L | `/profitability`: net sale − fees − non-creditable fee GST − refunds − ads − COGS; ads spend import; fee tax invoice import on `/fees` |
| Claims and evidence | `/claims`: templates (SAFE-T, SPF, lost, damaged, fee overcharge, wrong return), deadlines from policy windows, evidence packs (photo/video/PDF) attached on orders, shipments, returns and claims |
| Scan-based packing and bins | order page: scan verification gate before packing (SKU, EAN or channel id); bin codes on inventory and pick lists |
| Direct ERP posting | `/journals`: Tally XML over HTTP (server or local agent) and Zoho Books Journals API with acknowledgement; batches are marked imported only on full acknowledgement; local mocks under `/api/dev/erp` |
| CA multi-client workspace | memberships: one login, many workspaces; `/clients` shows close status per workspace; invite existing users by email |
| Alerts | `/notifications`: rules for ship-by risk, failed labels, payout variance, tax mismatches, claim deadlines, sync errors, low stock; email (Resend) and WhatsApp (provider webhook) delivery; `POST /api/jobs/alerts` |
| Historical onboarding | `/imports`: bulk uploads with coverage per channel and immutable file log |
| Launch hygiene | S3-compatible object storage driver (`S3_BUCKET`, `S3_ENDPOINT`, keys), `scripts/backup.sh` for Postgres/SQLite plus files, CI, Docker |

Scheduler calls to run: `labels` every minute, `sync` every 15–30 minutes, `inventory` every 5–15 minutes, `alerts` every 15 minutes.

## Phase 2: marketplace adapters

### Flipkart Marketplace Seller API

`src/lib/connectors/flipkart/`: OAuth2 client-credentials (application id/secret, Basic auth on the token endpoint, scope Seller_Api), shipments/filter for pre- and post-dispatch with `nextPageUrl` paging and a `modifiedDate` cursor, mapping of shipments and order items into canonical rows (FSN/SKU, selling price, Flipkart-funded discount, delivery state, location → warehouse), and the asynchronous label lifecycle: request labels, poll until the PDF is available, store it as the immutable original. Endpoints: production, Flipkart sandbox, or the local mock at `/api/dev/fkapi/*`. Settlements and returns stay on file import until the Payments and Returns API coverage is verified against the current documentation.

### Amazon SP-API adapter

`src/lib/connectors/amazon/` holds the live adapter: LWA refresh-token auth (`x-amz-access-token`), per-operation token buckets from the published usage plans, 429/5xx backoff, one 401 token refresh, NextToken pagination, Orders API v0 (getOrders, getOrderItems) and Finances API v0 (financial event groups and events) mapped into the canonical order and settlement rows. `src/server/sync.ts` runs cursor-based order syncs (LastUpdatedAfter), imports closed financial event groups as settlements, and a conformance test that checks token exchange, pagination, item retrieval, event mapping and that a closed group's events tie to its OriginalTotal. Every run is recorded as a `SyncRun` (requests, rate-limit hits, fetched/created/updated/skipped, cursor, errors).

Endpoints per connection: `production`, Amazon `sandbox`, or `mock` (a dev-only route at `/api/dev/spapi/*` serving deterministic fixtures with pagination and a periodic 429). Credentials: the seller's LWA refresh token on the connection plus `SPAPI_CLIENT_ID` / `SPAPI_CLIENT_SECRET` (or stored with the connection). A connection-level default ship-from warehouse resolves the supplying GSTIN when the API order carries no location; without it such orders are held.

Not yet pulled through the API: shipping labels, reports, returns and inventory. Production use needs an approved SP-API application and the Amazon sandbox's documented static test parameters; the mock proves the adapter path, not Amazon's current response shapes.

## Deliberately not in release one

- Live marketplace API sync for channels other than Amazon. Connectors are modelled (auth, scopes, capability flags, freshness); orders and settlements come from report uploads.
- Direct ERP posting. Files are generated, checksummed and tracked; the seller imports them.
- GST portal filing. The seller uploads the JSON through Prepare Offline and records the portal outcome.
- Silent printing. Printing goes through the OS print dialog.

Golden-file conformance against the current GSTN offline utility, TallyPrime release and Zoho Books importer still has to be run in the target editions before any file is labelled upload-ready for a customer.

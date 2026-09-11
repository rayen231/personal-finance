# Handoff: Flutter mobile app for Personal Finance API

Paste this whole file as your first message to the new Claude Code session,
opened in this same workspace root (`money_helper/`), alongside the OpenAI
file and description the user will provide.

## What already exists

This workspace is a monorepo with two parts:

- **`app/`, `api/`, `tests/`, `scripts/`** - a FastAPI backend, done and tested
  (26 pytest tests passing). It reads/writes an Excel workbook
  (`Personal_Finance_{year}_V1.xlsx`) stored in Vercel Blob, exposing
  transactions CRUD, income, monthly plan, summary, setup, and a `/sync`
  batch endpoint with idempotency. Full endpoint contract:
  **`docs/openapi.json`** - read this before writing any HTTP client code in
  Flutter; don't guess field names or paths.
- **`mobile_app/`** - an empty `flutter create` scaffold (package name
  `money_handler`), not yet touched. This is your responsibility.

Real financial data (`*.xlsx`, `data/`) is gitignored on purpose - the repo
owner's actual income/spending never goes into git. Don't try to commit or
read it; work against the local dev server or the live API instead.

## Your job

Build the Flutter Android app per the original spec (ask the user for the
full spec document/description they mentioned - it has the complete
functional requirements: screens, local SQLite cache, hourly batch sync,
offline-first behavior). In short, from the spec:

- Local SQLite cache; transactions save instantly on-device.
- Roughly hourly, POST pending changes to `/api/v1/sync` as a batch (see
  `docs/openapi.json` for the exact `SyncRequest`/`SyncResponse` shape) and
  clear the local queue for whatever comes back in `processed`; keep
  `failed` entries for retry/user review.
- Screens: Dashboard, Transactions, Add Transaction, Income, Investments,
  Savings, Monthly Plan, Yearly Overview, Settings (per spec section 28).
- Auth: every request needs header `X-API-Key: <key>` (ask the user for the
  real key - never invent or hardcode one from this file).

## Known gaps to fix or flag - don't assume these are solved

1. **The deployed API is currently broken.** Live URL:
   `https://personal-finance-omega-fawn.vercel.app` - `/health` returns 200,
   but any data endpoint (e.g. `/api/v1/setup/2026`) returns 500. This is
   because the Vercel project's environment variables were never set:
   `FINANCE_API_KEY`, `FINANCE_STORAGE_BACKEND=vercel_blob`,
   `BLOB_READ_WRITE_TOKEN`. Ask the user to set these in the Vercel
   dashboard (Project Settings -> Environment Variables) before building
   against the live URL - or point the app at a local
   `uvicorn app.main:app` instance during development instead.
2. **`Personal_Finance_TEMPLATE.xlsx` was never uploaded to the production
   Blob store** - only the 2026 workbook was, during manual testing. Lazy
   creation of a new year's file (e.g. when 2027 starts) will fail in
   production until this template is uploaded. Confirm with the user before
   uploading anything to their real Blob store.
3. **Two pre-existing bugs in the workbook's own Excel formulas** (not
   touched, by design - see git log): a row-41-vs-43 off-by-one in some
   SUMIFS formulas, and "Planned Investments" (`G8`) summing the wrong
   column. The API's own `/summary` endpoint computes correct values
   independently, so this shouldn't affect you, but don't be confused if you
   ever open the raw `.xlsx` and see different numbers there.
4. **`tbl_Subcategories` in the real workbook is already at its row
   capacity** (25/25). `POST /setup/{year}/subcategories` will correctly
   return `409 table_full` until the user expands that table in Excel
   themselves - this is expected, not a bug to fix.

## Working agreements from the backend build (keep applying these)

- Don't over-engineer for a personal, single-user app - no auth beyond the
  static API key, no premature abstractions.
- Verify claims by actually running things (`flutter run`, hitting the
  local API), not by inspecting code and assuming it works.
- Before committing: real financial files must never enter git. Check
  `git status` and the diff for anything under `data/` or `*.xlsx` before
  every commit.
- This session's git remote is public
  (`https://github.com/rayen231/personal-finance.git`) - treat that as a
  constraint on anything you commit.

## Suggested first steps for the new session

1. Read `docs/openapi.json` in full.
2. Ask the user for: the spec document, the real API key, and whether to
   develop against local `uvicorn` or the (currently broken) live URL.
3. Fix the Vercel env var gap if the user wants the live URL working now.
4. Scaffold the Flutter project structure (models, API client, local SQLite
   schema, sync queue) before writing screens.
5. Get one end-to-end path working first (e.g. Add Transaction -> local
   SQLite -> manual "Sync Now" -> appears via `GET
   /months/{year}/{month}/transactions`) before building out every screen.

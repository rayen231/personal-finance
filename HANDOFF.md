# Handoff: Flutter mobile app for Personal Finance API

Paste this whole file as your first message to the new Claude Code session,
opened in this same workspace root (`money_helper/`), alongside the OpenAI
file and description the user will provide.

## What already exists

This workspace is a monorepo with two parts:

- **`app/`, `api/`, `tests/`, `scripts/`** - a FastAPI backend, done and
  tested (27 pytest tests passing). It reads/writes an Excel workbook
  (`Personal_Finance_{year}_V1.xlsx`) stored in Vercel Blob, exposing
  transactions CRUD, income, monthly plan, summary, setup, and a `/sync`
  batch endpoint with idempotency. **Live and working**:
  `https://personal-finance-omega-fawn.vercel.app` (verified end to end,
  including a real transaction create/delete round trip). Full endpoint
  contract: **`docs/openapi.json`** - read this before writing any HTTP
  client code in Flutter; don't guess field names or paths.
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

1. **`Personal_Finance_TEMPLATE.xlsx` was never uploaded to the production
   Blob store** - only the 2026 workbook was. Lazy creation of a new year's
   file (e.g. when 2027 starts) will fail in production until this template
   is uploaded. Confirm with the user before uploading anything to their
   real Blob store.
2. **Two pre-existing bugs in the workbook's own Excel formulas** (not
   touched, by design - see git log): a row-41-vs-43 off-by-one in some
   SUMIFS formulas, and "Planned Investments" (`G8`) summing the wrong
   column. The API's own `/summary` endpoint computes correct values
   independently, so this shouldn't affect you, but don't be confused if you
   ever open the raw `.xlsx` and see different numbers there.
3. **The SETUP sheet had a real structural bug** (two Excel tables
   overlapping the same cells) that leaked garbage data and silently hid
   real subcategories (Food/Fast Food, Food/Snacks, Motorcycle/Fuel,
   Motorcycle/Oil, Motorcycle/Maintenance). This was found and fixed -
   `tbl_Subcategories` now lives at `H7:I45` with real spare capacity - see
   `scripts/relocate_subcategories_table.py` and the git log for the full
   story, including a mistake made and reverted along the way. Nothing left
   to do here, just context in case you see references to the old layout
   anywhere.
4. Editing the real workbook's structure (like #3) was done with the user's
   explicit permission, on their real file, verified via a local throwaway
   copy first. Don't casually extend that permission to future structural
   changes without asking again.

## Working agreements from the backend build (keep applying these)

- Don't over-engineer for a personal, single-user app - no auth beyond the
  static API key, no premature abstractions.
- Verify claims by actually running things (`flutter run`, hitting the
  local or live API), not by inspecting code and assuming it works.
- Before committing: real financial files must never enter git. Check
  `git status` and the diff for anything under `data/` or `*.xlsx` before
  every commit.
- This session's git remote is public
  (`https://github.com/rayen231/personal-finance.git`) - treat that as a
  constraint on anything you commit.
- Before editing the real workbook's structure (not just its data), test
  the change on a throwaway copy first and show/confirm the result - this
  project already had one near-miss where a "corrected" guess overwrote
  real config data before being caught and reverted.

## Suggested first steps for the new session

1. Read `docs/openapi.json` in full.
2. Confirm the live API still works: `curl
   https://personal-finance-omega-fawn.vercel.app/health` and one
   authenticated data endpoint with the real API key from the user.
3. Ask the user for: the spec document and the real API key.
4. Scaffold the Flutter project structure (models, API client, local SQLite
   schema, sync queue) before writing screens.
5. Get one end-to-end path working first (e.g. Add Transaction -> local
   SQLite -> manual "Sync Now" -> appears via `GET
   /months/{year}/{month}/transactions`) before building out every screen.

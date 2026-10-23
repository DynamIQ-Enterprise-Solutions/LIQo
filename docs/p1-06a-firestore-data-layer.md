# P1-06A — Firestore data layer

Owner decisions of 2026-10-23 (`docs/shopper-hybrid-decisions.md` §4, plan approved the same day): the deployed system uses Firestore on the Spark plan; SQL Server stays for local development until the owner retires it; both are tested; Firestore starts empty from the seed; files stay on the server PC's disk.

## How it is built

- **One switch.** `DB_DRIVER=mssql|firestore` in `LIQo backend/.env` (default `mssql`). Each `src/repos/<name>.js` is a front that loads `src/repos/mssql/<name>.js` or `src/repos/firestore/<name>.js`. Both have the same function names, arguments and return shapes, so routes never know which database runs. Shared constants live in `src/repos/shared/`.
- **SQL stays in `src/repos/mssql/`**, unchanged in behaviour. Nothing outside the repos talks to a database.
- **Firestore base** (`src/db/firestore.js`): the client (the emulator when `FIRESTORE_EMULATOR_HOST` is set, else the service-account key file named by `FIREBASE_KEY_FILE`, never in the repo), transactions, and these conventions:
  - Collections are named like the SQL tables and documents keep the SQL column names, so the shapes the routes build are identical.
  - **Integer ids stay.** A counter document per collection (`_counters/<collection>`) hands them out inside a transaction; a record's document id is its number. URLs and both apps are unchanged.
  - **Rules SQL Server enforced become guard documents** written in the same transaction (`_unique/<kind>:<value>`): one account per email, unique mall, branch, store and option names, one map per branch, one waiting profile or credit request per person. A clash raises the same error number SQL Server gave (2627 duplicate, 547 missing link), so routes answer exactly as before. Links (a branch's mall, a store's branch and category, an announcement's branches, a map's branch) are checked on write.
  - "At least one active superadmin" is counted inside the deactivating transaction.
  - Link tables use composite document ids (`mall_admin_assignments/<user>_<branch>`); an announcement keeps its target branches as an array on the document.
- **Files** (`src/storage/files.js`): plan pictures and drawings as today, and under Firestore the map documents too: `data/maps/<branch>/draft.json` and `versions/<n>.json` (a version file is never rewritten). Firestore keeps only the details (draft version, lock, one small record per published version). `FILES_ROOT` moves the whole file area.
- **One server process.** The map writes of a branch and every AI credits step are serialised in the process (SQL Server used row locks and an application lock). The credits steps collect their writes and commit them together in one batch. Never run two API processes against one Firestore database.
- **Analytics** read the small record collections in memory and, for audit-based numbers (sign-ins, map edits, failed sign-ins, lock-outs), daily running totals the audit writes keep (`_daily/<day>`: per action, plus per person for sign-ins, per branch for map edits, per email for failed sign-ins). The audit log itself is never scanned for charts. Days are Philippine days (UTC+8). "Sign-ins in the last 7 days" counts the last 8 calendar days, including today, where SQL Server counted a rolling 7 × 24 hours.
- **Lists** (search, filters, sort, paging) read the scoped collection and do the rest in memory, keeping `{items,totalCount,page,pageSize}`. Fine at internal scale; revisit with real customers.
- **Migrations and seed.** Firestore has no migrations (`npm run migrate` says so); `npm run seed` creates the superadmin on either database.

## Tests

`npm test` runs the whole suite twice: on SQL Server (`npm run test:mssql`), then on the Firestore emulator (`npm run test:firestore`: `firebase emulators:exec` with the demo project `demo-liqo`, files in a fresh temporary folder, needs Java 17 or later). Tests reach data only through `test/support/testDb.js` (set-up, checks and clean-up for both databases), never through SQL directly.

## Still to do (P1-10)

- `firestore.rules` that refuse all browser access (the API uses the admin SDK) and `firestore.indexes.json` with the one composite index the overview needs (`audit_log`: `actor_id`, `created_at` descending).
- Hosting, tunnel and the `deploy-internal` script; the runbook `docs/internal-deploy.md`.

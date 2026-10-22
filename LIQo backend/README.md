# LIQo backend

Express API for the LIQo / Gabay admin platform. SQL Server locally, planned for Cloud Run + a managed database next to Firebase Hosting.

## Run

```bash
npm install
copy .env.example .env     # fill in DATABASE_* and JWT_SECRET
npm run seed               # creates the database tables and the first superadmin
npm run dev                # http://localhost:3000, restarts on file changes
```

First superadmin: `admin@liqo.local` / `Admin@123`.

The local SQL Server login is `liqo_app` on database `liqo` (created with Windows auth; see `.env`).

## Scripts

| Script | What it does |
|---|---|
| `npm run dev` | Start with auto-restart. Applies pending migrations at startup. |
| `npm run migrate` | Apply pending migrations only. |
| `npm run seed` | Migrate, then create the superadmin if missing. |
| `npm test` | Access-control tests (`test/`). They create tagged throw-away rows in the local DB and delete them afterwards. |

## Layout

```
src/
  server.js        connect, migrate, listen
  app.js           middleware order and route mounting
  config.js        env (fails fast if JWT_SECRET is missing)
  db/              pool, migration runner, migrations/*.sql, seed
  middleware/      auth, role guard, zod validation, audit, error shape
  repos/           the only place SQL lives (one file per table group)
  routes/          HTTP handlers; validate → scope → repo → audit
  utils/           scope resolver, pagination, password, tokens, dates, redaction
docs/TESTING.md    manual checklist per phase
test/              node --test suites
```

## Rules of the road

- Raw parameterized SQL only, inside `src/repos/`. Never string-build values into SQL. Sort keys go through an allow-list.
- Every scoped read and write calls `resolveScope(user)` from `src/utils/scope.js`. Superadmin sees all; supervisor sees assigned malls and branches; mall admin sees assigned branches; store owner sees assigned stores.
- One error body: `{ "error": "message" }`. Lists return `{ items, totalCount, page, pageSize }`.
- Writes are audited. Handlers call `recordAudit()` with a named action; anything else is caught by the generic audit middleware.
- Dates: `DATE` columns travel as `yyyy-MM-dd` strings. The pool runs with `useUTC: false` because `SYSDATETIME()` is server-local.
- Migrations are never edited once applied. Add a new numbered file.

# LIQo

Indoor wayfinding for shopping malls. Mall staff keep each branch's indoor map, stores and announcements up to date in the admin platform; shoppers find their way with the LIQo app. "Gabay" is the product's earlier name.

## One-time setup after cloning

Turn on the repository's git hooks. They refuse commits that contain `.env` files or uploaded client floor plans:

```bash
git config core.hooksPath .githooks
```

## What is here

| Folder | What it is |
|---|---|
| `LIQo backend/` | Node 24 + Express + SQL Server API (port 3000) |
| `LIQo web/` | Flutter Web admin dashboard (package `gabay_admin`) |
| `LIQo mobile/` | Flutter shopper app for Android and iPhone (package `liqo_mobile`) |
| `docs/` | Decision record for each build round |
| `tool/` | Scripts that build the live team pages from the documents below |

| Document | Answers |
|---|---|
| [`LIQO_PRD.md`](LIQO_PRD.md) | Why each feature exists, for whom, and its acceptance criteria |
| [`LIQO_MASTER_BLUEPRINT.md`](LIQO_MASTER_BLUEPRINT.md) | How the system is built: stack, architecture, schema, rules |
| [`FEATURE_PIPELINE.md`](FEATURE_PIPELINE.md) | Where each feature stands and what is next |
| [`EXCEPTIONS.md`](EXCEPTIONS.md) | Approved deviations from the company standard |
| [`CLAUDE.md`](CLAUDE.md) | Working rules for AI coding sessions (and a good summary for people) |

## Run it locally

```bash
# backend (inside "LIQo backend")
npm install
copy .env.example .env   # then fill in the database login and JWT_SECRET
npm run migrate
npm run seed
npm run dev              # http://localhost:3000
npm test

# admin web (inside "LIQo web")
flutter pub get
flutter run -d chrome    # API defaults to http://localhost:3000
flutter analyze
flutter test

# shopper app (inside "LIQo mobile")
flutter pub get
flutter test
```

## Local test logins

The passwords in `src/db/seed.js`, the backend tests, `CLAUDE.md` and `LIQo backend/docs/TESTING.md` are **local development logins only**. They exist only in a developer's own database. Never use them, or the seeded superadmin, on a deployed system: create real accounts there and change every temporary password.

## Kept out of this repository

- `.env` files (only `.env.example` is committed). They hold the database password, the JWT secret and the AI gateway key.
- `LIQo backend/uploads/`: clients' floor plans.
- Build output, caches and the demo APK.
- Company-internal and third-party documents (the engineering standard, the AI gateway's documentation, the original user stories and map spec) and the brand source images. Ask the team for them. `LIQo web/tool/crop_brand.mjs` needs `LIQO Brand Guidelines Presentation.png` in the repository root before it can regenerate the logos; the generated logos are already committed.

## Licence

No licence has been chosen yet. Until one is, all rights are reserved: the code may be read but not reused.

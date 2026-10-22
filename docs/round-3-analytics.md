# Round 3 — Analytics (all roles)

Status: **Done 2026-10-21.** Owner answers: fl_chart, all six sections, real CSV export, 7-day default. Backend 39/39 tests, Flutter analyze clean, Flutter tests 22 pass / 5 skipped. Manual checklist: `LIQo backend/docs/TESTING.md`, "Round 3: Analytics".
Requested 2026-10-21: "make analytics more detailed and useful, with graphs and a breakdown of each category."
Stories: US-005 (superadmin dashboard), US-015 (supervisor, scoped), US-023 (mall admin, scoped). All three say cards first, charts after. Cards exist; this round adds the charts and breakdowns.

---

## 1. Goal

One Analytics page that answers the questions each role actually asks, scoped by the server exactly like the lists are:

- Superadmin: is the platform being used, where is it growing, where is it stuck (malls with no branches, maps never published, announcements waiting)?
- Supervisor: what is happening in my malls (stores, admins, announcements, map coverage, sign-ins)?
- Mall admin: my branches: stores by category, map coverage, announcement queue, store-owner sign-ins.
- Store owner: keeps the overview only (no analytics page; US-024 keeps the scope small).

What we cannot show yet, and will not fake: shopper traffic, map views, searches. There is no shopper app sending data. The page says so in one line instead of showing an empty chart.

## 2. The page

Top: the summary cards that exist today, plus a **period switch** (7 / 30 / 90 days) that drives every time chart. One **Refresh**. **Export CSV** becomes real (section 2.7).

### 2.1 Activity over time (line chart, one line per series, by day)
Sign-ins, announcements submitted, announcements published, map publications, map editing sessions. Sources: sign-ins from `audit_log`; announcements and map publications from their own tables (they carry the branch); editing sessions from a new `map_edited` audit entry written once per 10-minute stretch of draft saves (autosaves fire every few seconds and were never audited, so raw save counts did not exist). Hover shows the day and the numbers. Below the chart, totals for the period and the previous period ("Sign-ins 142, up from 98").

### 2.2 Stores (donut + bar + table)
- Donut: stores by **category** (from each branch's option list; "No category" bucket).
- Bar: stores **per branch** (active / inactive stacked).
- Table: per branch — stores, with a store owner, linked to a map space, without a link. This tells a mall admin what is left to do.

### 2.3 Accounts (donut + table)
- Donut: accounts by **role**.
- Table: per role — active, inactive, unassigned (supervisors and mall admins), still on a temp password, locked right now.
- Superadmin only. Supervisors and mall admins see the accounts in their scope (mall admins and store owners).

### 2.4 Announcements (bars + table)
- Bar: by **status** (pending, approved, rejected) and by **time state** (live, upcoming, expired).
- Bar: by **who posted** (supervisor, mall admin, store owner).
- Table: pending queue — oldest first, with "waiting N days"; average days to decision in the period.
- Per branch count for supervisors and superadmin.

### 2.5 Map coverage (table + bar)
Per branch: no map / draft only / published; version count; last published date and by whom; spaces drawn, named, linked to a store. A bar shows published vs draft-only vs no map across the scope. Superadmin and supervisors see all their branches; a mall admin sees theirs.

### 2.6 Sign-in security (superadmin only, small)
Failed sign-ins and lockouts in the period, by day (line), and the accounts with the most failures (table, top 5). This is where a brute-force attempt shows up.

### 2.7 CSV export (real)
One button exports the breakdown tables of the current page (stores per branch, accounts per role, announcements queue, map coverage) as a CSV file generated in the browser. Charts are not exported.

### 2.8 Role differences
| Section | Superadmin | Supervisor | Mall admin |
|---|---|---|---|
| Activity | all | scope | scope |
| Stores | all, grouped by mall | scope | scope |
| Accounts | all roles | mall admins + owners in scope | owners in scope |
| Announcements | all | scope | scope |
| Map coverage | all branches | scope | scope |
| Security | yes | no | no |

## 3. Changes

| Layer | File | Change |
|---|---|---|
| Backend | `src/routes/analytics.js` | New `GET /analytics/report?days=7`. Returns `{period, activity[], stores{byCategory,byBranch}, accounts{byRole}, announcements{byStatus,byTimeState,bySource,pending[],avgDecisionDays}, maps{byBranch}, security?{byDay,topFailures}}`. Every query scoped through `resolveScope`. `days` limited to 7, 30, 90. |
| Backend | `src/repos/analytics.js` (new) | The grouped SQL, one function per section, so the route stays readable. |
| Backend | `test/analytics.test.js` (new) | Section 5.1. |
| Backend | `src/routes/maps.js`, `src/repos/audit.js` | Added during the build: the throttled `map_edited` audit entry on draft saves (`minutesSinceLast` helper). |
| Frontend | `pubspec.yaml` | Add `fl_chart` (charts). See open question 1. |
| Frontend | `features/analytics/analytics_service.dart` (new) | Models + `report(days)`. |
| Frontend | `features/analytics/analytics_view.dart` | The page: period switch, cards, sections 2.1–2.7. |
| Frontend | `features/analytics/charts.dart` (new) | Thin wrappers: `LineSeriesChart`, `BarChart`, `DonutChart`, `BreakdownTable`, all themed from `theme.dart`, with empty states ("No data in this period"). |
| Frontend | `features/analytics/csv_export.dart` (new) | Builds the CSV text. |
| Frontend | `features/analytics/csv_download.dart` + `_web.dart` + `_stub.dart` (new) | Browser download through `package:web`, with a stub for the VM so widget tests compile. |
| Frontend | `test/analytics_test.dart` (new) | Section 5.2. |
| Frontend | `lib/core/theme.dart` | A small palette of chart colours (the only place colour literals may live). |
| Docs | `LIQo backend/docs/TESTING.md` | "Round 3: Analytics" checklist. |

Nothing changes in the overview, the lists, or other roles' screens.

## 4. Definition of done

1. Every section in 2 shows real numbers for each role, scoped, and matches a hand count on the test data.
2. `npm test` passes with the new analytics tests. `flutter analyze` has no issues. `flutter test` passes with the new chart tests.
3. The page renders at phone width without horizontal scroll; charts stack.
4. No exceptions in the Flutter log while switching periods and roles.
5. Export CSV downloads a file that opens in Excel with the right columns.
6. Checklist appended to TESTING.md; this document marked Done.

## 5. End-to-end tests

### 5.1 Backend (`test/analytics.test.js`)
- Superadmin report counts a store created today in `activity` and in `stores.byBranch`.
- Supervisor of mall A does not see mall B's stores, announcements, or map rows in any section.
- Mall admin report `accounts.byRole` has no supervisors or superadmins.
- `days=365` is refused (400); `days=7` returns 7 activity rows (zeros filled).
- Security section is absent for a supervisor and present for a superadmin.

### 5.2 Flutter widget tests
- Donut and bar charts render an empty state when the series is empty, and render once with data (no exception).
- Period switch calls the service with the chosen days.
- CSV builder quotes commas and quotes correctly.

### 5.3 Manual (Chrome)
1. As superadmin: Analytics shows all sections. Switch 7 → 30 → 90: the activity chart changes, the cards do not.
2. Create a store and an announcement, publish a map, refresh: the activity lines for today rise by one each.
3. Stores donut matches the categories in Stores & spaces for SM Mall of Asia.
4. As supervisor `sup@liqo.local`: only SM Prime's branches appear in every table; no Security section.
5. As mall admin `ma@liqo.local`: accounts table has only store owners; map coverage shows SM Mall of Asia published with the version count from History.
6. Export CSV → open the file → the tables are there with headers.
7. Narrow the window to phone width: sections stack, nothing overflows.

## 7. Notes from the build

- The shared `TwoCol` widget measures its children with `IntrinsicHeight`; fl_chart and the breakdown table use `LayoutBuilder`, which cannot be measured that way and asserts on every frame. The Analytics page uses its own side-by-side row without `IntrinsicHeight`. The widget test for the period switch is what caught it.
- A mall admin's Accounts section lists store owners only; a supervisor's lists mall admins and store owners; the caller is never counted in their own table.

## 6. Open questions for the owner (answered 2026-10-21)

1. **Charts library** — answered: `fl_chart`. Original question: `fl_chart` (widely used Flutter package, hover tooltips, animations; adds one dependency) or in-house charts drawn with `CustomPainter` (no dependency, simpler visuals, more work for hover)? Recommendation: `fl_chart`. Its tooltips are painted inside the chart, not in an overlay, so the freeze we hit in the map editor does not apply.
2. **Period default** — answered: 7 days, with 30 and 90 as the other choices.
3. **Which sections matter most** — answered: all six. Original question: all six above, or drop any? Anything missing that you need to see (for example "stores added per month" or "announcements per store")?
4. **CSV export** — answered: real export (section 2.7).

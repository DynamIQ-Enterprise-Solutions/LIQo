# Round 19 — AI credits per mall admin, Requests & reports, problem reports

Status: **Built 2026-10-23.**
- **Backend:** 145/145. New:
  - `test/ai_credits.test.js` (10);
  - `test/reports.test.js` (4);
  - a check in `ai_reading.test.js` that each paid reading comes off the admin's credits.
- **Flutter:** analyze clean; 324 tests pass, 5 skipped. New:
  - `test/round19_test.dart` (14);
  - `settings_tiles_test.dart` updated;
  - sweep: Requests & reports, its tabs and pages, report pages for every role, and the "Report a problem" and "Request AI credits" dialogs.

## Why
The owner asked for four things, and two more while the work was under way:
1. **The model dropdown** in Settings was out of proportion, and its list covered the whole AI tile.
2. **Tile order:** Announcements sat awkwardly in the middle. Later: merge Announcements with "Other" into one tile on the right, with AI reading in the middle.
3. **My account** had no loading skeleton.
4. **AI credits per admin:** the superadmin sets each admin's credits, sees their balances and watches their usage, in Analytics.
5. **Requests & reports:** Profile requests becomes one page for everything people ask of or tell the superadmin, grouped by kind.
6. **Problem reports:** a simple version, built now.

Item 4 reverses Round 15's "only the gateway wallet limits reading". **Giving credits moves no money:** the IQGateway wallet only goes down when a reading is paid. A balance is a share of the wallet set aside for one admin.

## Owner decisions (2026-10-23)
| Topic | Decision |
|---|---|
| Who has credits | Those who edit and create maps: **mall admins**. Superadmins read from the **free part** of the wallet, and are refused when nothing is free. |
| Starting credits | **3** for a mall admin created (or reactivated) from now on; **existing mall admins start at 0**. If fewer are free, the account is still created with what is free, and the Done step says so. |
| Cap | At most **20** per admin |
| Settings | "Starting credits" and "Most credits per admin" are Settings numbers (AI tile) |
| Wallet check | Credits given out **never exceed the wallet** |
| Wallet below what was given | **Warn, and stop giving** until it is topped up; admins keep reading until the gateway itself refuses |
| Low balance | **Allowed, with warnings.** Any balance above 0 may start a reading; the cost (known only after) may take it a little below 0; then reading is blocked. |
| At 0 | Reading is **blocked**; the admin can **request** credits |
| Requests | **An amount only**, one at a time; approved (maybe for less) or declined on **Requests & reports**; every action audited |
| Deactivation | Unused credits **return to the free part**; an open request closes. There is no delete in the platform, so credits never vanish. |
| Superadmin's view | **One split bar + numbers**: Wallet, Given to admins, Free to give, Used in the period. Giving never lowers the wallet number. |
| Admin's bar | Against **their last top-up**, green / yellow / red |
| Who sees what | Mall admins see only their own credits (never the wallet's numbers); mall owners see their admins' credits and use, read only; only the superadmin gives or takes |
| Analytics | Wallet split; per-admin table with Add / Remove; credits used per day; history |
| Requests & reports | Tabs with counts: **All · Profile changes · AI credits · Problem reports**; the sidebar count is the total waiting |
| Problem reports | Mall owners, mall admins and store owners, from a **"Report a problem" button in the top bar** (the page goes with it). A type (Something broke, Wrong data, Question, Idea), a subject and a description. A **thread** with the superadmin until resolved or closed. **My reports** in My account. |
| Settings layout | **Two columns** (final, same day): **AI floor-plan reading on the left**; on the right **one card** with Sign-in & security, then General (announcement length and any setting the page does not know yet). One column below 760 px, AI first. |
| Model picker | Opens **under the field**, as wide as it, about five rows tall; the field shows the model and its maker on two lines |

## Server
- **Migration `012_ai_credits_reports.sql`:**
  - `ai_credit_balances` (balance, full mark);
  - `ai_credit_ledger`: every change, with kind `start`, `grant`, `remove`, `reading`, `returned` or `request`, linked to its reading or request;
  - `ai_credit_requests`, with one open request per admin enforced in SQL;
  - `problem_reports` and `problem_report_messages`.
- **Rules:**
  - `src/ai/credits.js` holds the pure rules (`walletSplit`, `refuseGive`, `refuseRemove`, `startCredits`).
  - `src/ai/creditOps.js` does the work (`give`, `take`, `grantStartCredits`, `returnCredits`, `assertCanRead`, `chargeReading`).
  - `src/repos/credits.js` holds the SQL. Every write runs in one transaction holding an application lock (`sp_getapplock`), so two clicks cannot both pass the cap or wallet checks.
- **Routes:**
  - `/ai/credits`: overview, history, `:userId/adjust`, mine, and requests (create, cancel, list, get, approve, decline);
  - `/reports` (create, mine, list, get, messages, status);
  - `/requests/counts`.
- **`GET /ai/status`:**
  - a mall admin gets `quota: null`, `mine` and `gatewayBlocked`;
  - a superadmin also gets `given`, `free` and `overGiven`.
- **Readings:** `routes/backdrops.js` convert checks credits before calling the gateway (`assertCanRead`), then takes the paid cost, failures included, off the admin (`chargeReading`, linked to its `map_conversions` row, which `recordConversion` now returns).
- **Accounts:** `routes/accounts.js` gives starting credits on create and reactivate (`startCredits` and `startNote` in the response) and returns credits on deactivate.
- **Settings:** `ai_start_credits` (0–1000, default 3) and `ai_credit_cap` (1–10 000, default 20).
- **Retention:** a future job that deletes `map_conversions` rows must first clear their ledger links (`fk_ai_credit_ledger_conversion`).

## Web
- **Settings:**
  - two columns, at most 560 px each: the AI tile, and a `SectionedTile` holding Sign-in & security and General;
  - `AiModelField` uses a `MenuAnchor` under the field;
  - the AI tile shows "Given to mall admins · Free to give";
  - two new numbers.
- **Credits** (`features/ai/`):
  - `credits_service.dart` (models, providers);
  - `my_credits.dart`: `MyCreditsPanel`, `showRequestCreditsDialog`, and `AiReadingCredits`, used above Read with AI in both editors;
  - `credit_bar.dart`: green, yellow (`Pal.caution`) and red levels, plus `WalletSplitBar`.
- **Analytics:** `features/analytics/credits_section.dart` (wallet, admins table with Add / Remove dialogs, `DailyAmountBars` in `charts.dart`, and a history with Show more). Mall owners get a read-only version.
- **Requests & reports** (`features/requests/`):
  - tabs with counts;
  - the AI credit request page (Approve with an editable amount, live limits; Decline with an optional reason);
  - Profile changes reuses the old list.
  - `/superadmin/profile-requests` redirects to the tab.
- **Problem reports** (`features/reports/`):
  - the top bar's "Report a problem" (`app_shell.dart`);
  - `report_problem.dart` (dialog, My reports card);
  - `report_detail_view.dart`, shared by the superadmin and the reporter, with the thread, reply box and status buttons.
- **My account:**
  - a skeleton of its own shape until the first refresh;
  - the "AI credits" card (mall admins);
  - "My reports" (everyone but superadmins).
- **Create-account wizard:** the Done step shows the starting credits, or the note.

## Tests changed on purpose (decision, not a bug)
- **`round15_test.dart`:**
  - a mall admin sees their own credits (not wallet numbers);
  - a blocked gateway is told without the wallet's words;
  - the model is chosen from the new menu and saved with Save settings.
- **`ai_reading.test.js`:**
  - the status test checks the superadmin's and the mall admin's views;
  - the fixture admin gets test credits (`giveTestCredits`), also in `ai_measured.test.js` and `plan_formats.test.js`.
- **`settings_tiles_test.dart` and `credit_bar_test.dart`:** the new tile order and names.

## Also fixed
- The map editor's zoom buttons and the 3D panel's Reset view and Collapse no longer use tooltips, because an earlier fix banned tooltips inside the map editor.

## Not checked by machine
- The live wallet, giving credits and a paid reading's cost coming off a real admin need a look in the browser (TESTING Phase 18). A paid reading needs the owner's OK.

# Round 4 — Mall owners, mall admins, and who reports to whom

Status: **Done 2026-10-21.** Backend 44/44 tests, Flutter analyze clean, Flutter tests pass including the layout sweep (People page covered) and a wording test that fails if any screen text still says "Supervisor". Manual checklist: `LIQo backend/docs/TESTING.md`, "Round 4".
Requested 2026-10-21: "for a mall, it shall let me assign a mall admin and mall supervisors too; I can also connect which admin is under a specific supervisor or mall owner."
Owner answers (2026-10-21): the role is called **Mall owner** now, not supervisor; mall admins stay assigned **per branch**; linking an admin under an owner **restricts** who that owner manages; **one owner per admin**.

Interview answers (2026-10-21):
- **Mall owner** is the new name of the existing supervisor role, renamed everywhere including the URL. The role key stays `supervisor` inside the database and API (no migration, no API break).
- An owner is a person who owns branches, often across different malls: for example one SM branch, one Waltermart branch and one Ayala branch. The existing assignment model already covers this: whole malls and/or single branches of any mall.
- **Reports to** is optional at creation, with a reminder pill and filter.
- **One branch per admin** (added after the first build, 2026-10-21): a mall admin manages exactly one branch; an owner owns as many malls and branches as needed. Admins already placed are not offered to other malls (`/lookups/free_mall_admins`); the superadmin moves an admin by picking another branch, which replaces the old one (owner decision 2026-10-21: allowed, since one mall can have several admins). Two branches on one admin are refused by the API (400); taking an admin who manages a branch in another mall from a People page is refused (409).
- Owners **see only the admins that report to them**. Unowned admins and admins of other owners are invisible to them. The superadmin sees everyone and links them. (Assumed from "the other unrelated are not seen by the owners"; tell me if unowned admins should still be visible to owners.)
- Owners can **create mall admin accounts** (branches limited to their own scope); those admins report to the owner automatically. Owners can **release** their own admins. Moving an admin between owners is superadmin-only. Every one of these actions is audited and shows in the superadmin's audit log and recent activity.

---

## 1. Goal

From a mall's page a superadmin can see and change everyone who works on that mall: its owners, its admins (per branch), and which owner each admin reports to. A mall owner then manages only the admins that report to them.

## 2. Workflows

### A. Rename: Supervisor → Mall owner
- Everywhere a person sees it: sidebar, page titles, role dropdowns, pills, Access column, audit action labels, dialogs, analytics, the sign-in shell badge.
- URL prefix `/supervisor/...` becomes `/mall-owner/...`. Old links redirect.
- The database value stays `supervisor`. The API keeps `role: 'supervisor'`. Only words change.

### B. People on a mall (Malls & branches → mall row → **People**)
A page (not a dialog, it has three lists) for one mall:

| Section | Shows | Actions (superadmin) |
|---|---|---|
| **Mall owners** | Owners with a whole-mall assignment to this mall. Owners who only have single branches here are listed as "branch-level" with the branch names. | **Add owner** (pick an existing owner account; adds a whole-mall assignment). **Remove** (removes this mall from their assignment; the account stays). |
| **Mall admins** | Admins with at least one branch in this mall, grouped by admin: their branches here, and **Reports to** (owner name or an amber "No owner" pill). | **Add admin** (pick an account → tick branches of this mall, "Add all branches", pick Reports to). **Edit branches**. **Set reports to**. **Remove from mall** (drops this mall's branches only). |
| **Create** | Shortcut buttons: **New owner account**, **New admin account** — open the Round 2 create flow with this mall pre-selected. | |

Rules:
- A mall with no branches cannot get an admin; the page says so and offers **Add branch**.
- Reports to can only be an owner who covers at least one of that admin's branches (whole-mall or branch-level). Otherwise the pick is refused with "That owner does not cover any of this admin's branches."
- Removing an owner clears **Reports to** on admins that pointed to them (they get the "No owner" pill). The page warns with the count before confirming.

### C. One owner per admin
- Stored on the admin's account (`reports_to`). One value; changing it moves them.
- Also editable from Account management → Assignments (a **Reports to** picker at the bottom of the mall-admin dialog) and set during **Create account** step 2 (optional; the pill reminds you later).
- Accounts list (superadmin), **Access** column for admins: "Branches 3 · reports to Maria Santos" or "Branches 3 · No owner". Status filter gains **No owner**.

### D. What a mall owner can do after this
- **Mall admins** page lists only admins that report to them. Each has the row menu: edit, assignments (branches within the owner's scope only), reset password, deactivate, and **Release** (clears the link with a confirm; the admin keeps their branches and becomes "No owner" for the superadmin to re-link).
- **Create mall admin** button on that page: the Round 2 two-step flow, branches limited to the owner's malls and branches, Reports to fixed to the owner. Temp password shown once.
- Admins that report to nobody or to another owner are not shown to owners at all.
- Everything else stays scoped as today: branches, stores, announcements, map viewer, analytics follow the mall assignment, not the reports-to link. Analytics "Accounts" for an owner counts their admins plus store owners in scope.
- Superadmin is unchanged: manages everyone, sees every link, and can move an admin between owners.
- Audit: `account_created` (with `createdByRole: supervisor`), `reports_to_set`, `reports_to_released`, `mall_owner_added`, `mall_owner_removed`. The superadmin's audit log and overview activity show them with the owner as actor.

### E. Edge cases
- An admin whose branches span two malls reports to one owner; the other mall's People page shows "Reports to {name} (owner of {other mall})" read-only.
- Deactivating an owner does not clear the links (they come back on reactivation); their admins show "Reports to {name} (inactive)".
- Deleting is never offered; accounts are deactivated.

## 3. Changes

| Layer | File | Change |
|---|---|---|
| Backend | `src/db/migrations/007_reports_to.sql` | `users.reports_to INT NULL REFERENCES users(id)` + index. |
| Backend | `src/repos/users.js`, `src/repos/assignments.js` | `reports_to` on list rows and detail; `setReportsTo`; owner-covers-admin check; `clearReportsTo(ownerId, mallId)`. |
| Backend | `src/routes/malls.js` | `GET /malls/:id/people`, `POST /malls/:id/owners`, `DELETE /malls/:id/owners/:userId`, `PUT /malls/:id/admins/:userId` (branches of this mall + reportsTo), `DELETE /malls/:id/admins/:userId`. Audited. |
| Backend | `src/routes/accounts.js` | `PUT /accounts/:id/reports-to` (superadmin: any owner or null; owner: null only, on their own admins); create accepts `reportsTo`; owners may create mall admins (branches checked against their scope, `reports_to` = owner); `?status=no_owner`; an owner's list and `loadManageable` use `reports_to = me`. |
| Backend | `test/people.test.js` (new) | Section 5.1. |
| Frontend | `shared/nav/role_nav.dart`, `core/router.dart` | Labels and prefix `/mall-owner`; redirect from `/supervisor/*`. |
| Frontend | every label that says Supervisor | Word change only (accounts, malls, announcements, analytics, shell, audit, docs). |
| Frontend | `features/malls/people_view.dart` (new), `people_service.dart` (new) | Section 2.B. Route `/superadmin/malls/:id/people`. |
| Frontend | `features/accounts/create_account_flow.dart` (new) | The two-step create flow, shared by Account management (superadmin and owner) and the People page. |
| Frontend | `test/people_round4_test.dart` (new) | Section 5.2 plus the "no Supervisor wording" check. |
| Frontend | `features/accounts/assignment_dialog.dart`, `accounts_view.dart`, `accounts_service.dart` | Reports to picker, Access column text, No owner filter, read-only rows for owners. |
| Docs | `LIQo backend/docs/TESTING.md`, this file | Checklist; status Done. |

## 4. Definition of done
1. Every workflow in section 2 behaves as written.
2. `npm test` and `flutter test` pass with the new tests; `flutter analyze` clean; the layout sweep covers the new People page at every width.
3. No "Supervisor" wording left in the app (a test greps the Flutter `lib/` for the word outside the role key).
4. Audit entries for: owner added/removed on a mall, admin branches changed from the mall page, reports-to changed.
5. Checklist appended; this document marked Done.

## 5. End-to-end tests

### 5.1 Backend
- Owner with mall A: `GET /malls/A/people` lists them under owners; an owner with only branch A1 is listed as branch-level.
- Admin on A1 reporting to owner X: owner X's `/accounts` lists them; owner Y of the same mall does not see them and gets 403 on `PUT /accounts/:id`.
- Owner X creates a mall admin with a branch outside their scope → 403; with their own branch → 201, `reportsTo` = X, audit `account_created` by X.
- Owner X releases their admin → `reports_to` null; X can no longer see them; superadmin sees them under No owner.
- `PUT /accounts/:id/reports-to` with an owner who covers none of the admin's branches → 400.
- Removing owner X from mall A clears `reports_to` on their admins in A; the response says how many.
- `?status=no_owner` lists only admins with no owner.

### 5.2 Flutter
- People page renders the three sections with the fake API at 360 / 1024 / 1440 px (added to the sweep).
- Assignment dialog shows the Reports to picker only for mall admins.
- Access cell reads "Branches 3 · No owner" when `reportsTo` is null.

### 5.3 Manual (Chrome, as `admin@liqo.local`)
1. Malls → SM Prime → People: `sup@liqo.local` is listed as owner; `ma@liqo.local` as admin on SM Mall of Asia with "No owner".
2. Set reports to → sup. Sign in as sup → Mall admins → ma has the row menu.
3. Create a second owner, assign them mall-wide to SM Prime, sign in as them → Mall admins is empty (ma reports to sup). Create mall admin from that page with an SM Mall of Asia branch → appears, reports to them. Release → gone from their list; superadmin sees "No owner".
4. Back as superadmin: remove the second owner from the mall → gone from People; sup unaffected.
5. Create an admin from the People page with Add all branches + reports to sup → appears in both People and Account management with "reports to".
6. Sidebar, titles and URL now say Mall owner / `/mall-owner`; an old `/supervisor/overview` link lands on `/mall-owner/overview`.

## 6. Open questions (answered in the interview, see the top of this document)
1. Rename scope — everywhere, including the URL.
2. Reports to at creation — optional with a reminder pill.
3. Owner powers — create admins that report to them, release their own; moving between owners is superadmin-only; all audited.

# Round 2 — Superadmin module

Status: **Done 2026-10-21.** Approved by the owner ("okay build") with the proposals in section 6 as the answers. Backend 35/35 tests, Flutter analyze clean, Flutter tests 17 pass / 5 skipped. Manual checklist: `LIQo backend/docs/TESTING.md`, "Round 2: Superadmin".
Scope agreed on 2026-10-21: Accounts flow (A–C), Mall and branch flow (D–E), Map publications tile (F).
Out of scope this round: settings, audit log, managing other superadmins, every other role's screens, the map editor.

---

## 1. Goal

A superadmin can set up a new mall end to end without dead ends: register the mall, add its first branch, create the mall admin with their branches in the same dialog, and see at a glance which accounts have no access yet and what a deactivation will hide.

## 2. Workflows

### A. Create an account (two steps)

| Step | Screen | What happens | Rules |
|---|---|---|---|
| 1 | Account management → **Create account** | Step 1 of 2: Full name, Email, Role (Supervisor / Mall Admin / Superadmin). **Next**. | Name 2–200 chars. Valid email, unique across all roles. |
| 2a | Role = Superadmin | Confirm dialog "Create another superadmin?" → **Yes** → account created at once. | No assignments. Audited as `superadmin_created`. |
| 2b | Role = Supervisor | Step 2 of 2: **Whole malls** picker, **Individual branches** picker, help line "A whole-mall assignment also covers branches created later. Single branches do not." **Create**. | At least one mall or one branch. |
| 2c | Role = Mall Admin | Step 2 of 2: **Mall** picker → **Branches of this mall** picker (only that mall's branches) + button **Add all branches of this mall**. Help line "Branches added to this mall later must be assigned by hand." **Create**. | At least one branch. |
| 3 | After Create | One request creates the account and its assignments together. Temp password shown once with Copy. List refreshes. | Audited as `account_created` with the assignments. |

Edge cases:
- Mall admin step: the chosen mall has **no branches** → message "This mall has no branches yet. Create one under Malls & branches first." **Create** stays disabled.
- **Cancel** on step 2 → nothing is created.
- Email already in use → error inside the dialog; the account is not created; the user stays on the dialog.
- Picker search is server-side; only active malls and branches are offered.

### B. Edit assignments of an existing account

- Row menu → **Assignments**. Same step-2 screen, preloaded with the current assignment.
- Mall admin: mall picker starts on the mall of their first branch. Switching mall shows that mall's branches. Branches already assigned in **other** malls stay listed under "Other malls" with a remove icon, so switching never drops them silently.
- **Save** replaces the whole assignment set in one transaction (existing behaviour). Audited.

### C. See who has no access

- Accounts list, **Access** column: Supervisor "Mall-wide 1 · Branches 2", Mall admin "Branches 3", Store owner "Stores 2", Superadmin "Platform-wide".
- Rows with no assignment show an amber **Unassigned** pill (supervisor and mall admin only).
- Status filter gains **Unassigned**. Empty text under that filter: "No unassigned accounts."

### D. Register a mall, then its first branch

1. Malls & branches → **Register mall** → name, logo → **Create**.
2. A second dialog opens at once: "Add the first branch of {mall}?" with the branch form, mall field locked. **Create branch** or **Later**.
3. Malls tab: amber **No branches** pill when a mall has none. Row menu gains **Add branch** (branch form with the mall locked).

### E. Deactivate with the impact shown

- Mall → **Deactivate**: "Deactivate {mall}? This hides {n} branches and {m} stores from supervisors, mall admins and store owners. {k} mall admins lose access until it is reactivated. Nothing is deleted." **Deactivate** / **Cancel** (Cancel is the default).
- Branch → **Deactivate**: "This hides {m} stores. {o} store owners and {k} mall admins lose access until it is reactivated. Nothing is deleted."
- **Reactivate** keeps the one-line confirm.
- Numbers come from `GET /malls/:id/impact` and `GET /branches/:id/impact` (already built and tested).

### F. Real map publication counts, honest labels

- Overview and Analytics show **Map publications** from the API (count of published versions in scope).
- Cards read "Active malls", "Active branches", "Active stores", "Active accounts" because the counts exclude deactivated records.

## 3. Changes

| Layer | File | Change |
|---|---|---|
| Backend | `src/repos/users.js` | Add per-row counts to the list query: `mall_assignments`, `branch_assignments`, `store_assignments`. Exposed as `access` on the account JSON. |
| Backend | — | No other backend change. Creation with assignments, the unassigned filter, impact endpoints and the publication count already exist. |
| Frontend | `features/accounts/assignment_dialog.dart` (new) | The step-2 screen used by both Create and Assignments: supervisor and mall admin variants, "all branches" helper, "Other malls" list, validation. |
| Frontend | `features/accounts/accounts_view.dart` | Two-step create; Access column; Unassigned pill and filter; uses the new dialog. |
| Frontend | `features/accounts/accounts_service.dart` | Send `assignments` on create; read `access` counts. |
| Frontend | `features/malls/malls_view.dart` | First-branch prompt after Register mall; No branches pill; Add branch row action; impact confirm dialogs. |
| Frontend | `features/malls/malls_service.dart` | `mallImpact(id)`, `branchImpact(id)`. |
| Frontend | `shared/forms/app_form_dialog.dart` | Added during the build: optional `cancelLabel` so the first-branch prompt can say **Later** (workflow D). One optional parameter, default unchanged. |
| Frontend | `test/accounts_round2_test.dart` (new) | The widget tests in section 5.2. |
| Frontend | `features/overview/overview_service.dart`, `overview_view.dart`, `features/analytics/analytics_view.dart` | `mapPublications` field; "Active …" labels. |
| Docs | `LIQo backend/docs/TESTING.md` | "Round 2: Superadmin" checklist (section 5 below). |

## 4. Definition of done

1. Every workflow in section 2 behaves as written, including each edge case.
2. `npm test` passes with the new backend test (section 5.1). `flutter analyze` reports no issues. `flutter test` passes with the new widget tests (section 5.2).
3. The app runs with zero exceptions in the Flutter log through the whole manual checklist (section 5.3).
4. No change outside the files in section 3. No change to any other role's screens.
5. Audit log entries exist for: account created (with assignments), assignments updated, mall created, branch created, mall/branch deactivated and reactivated.
6. Checklist appended to TESTING.md; this document updated to "Done" with the date.

## 5. End-to-end tests

### 5.1 Backend (automated, `test/flows.test.js`)

- Create a mall admin with `assignments.branchIds=[A]` → list row has `access.branches = 1`, not in the unassigned filter.
- Create a mall admin with no assignments → in the unassigned filter, `access.branches = 0`.
- Create a supervisor with `mallIds=[M]` → `access.malls = 1`; a branch created later under M is visible to that supervisor without any new assignment.
- Replace a mall admin's branches with `[A, B]` where B is in another mall → both kept; `access.branches = 2`.
- Mall impact for a mall with one active branch and two active stores returns `{branches: 1, stores: 2, mallAdmins: 1}`.

### 5.2 Flutter (automated, widget tests)

- Assignment dialog, mall admin variant, no branch chosen → **Create** disabled; after choosing one branch → enabled.
- Assignment dialog, supervisor variant, nothing chosen → disabled; one mall chosen → enabled.
- Accounts list renders the Unassigned pill for an account whose `access` counts are all zero and not for one with a branch.

### 5.3 Manual (Chrome, as `admin@liqo.local`)

1. Register mall "Ayala Center" → the first-branch dialog appears → create "Ayala Center Cebu" → the mall row shows 1 branch, no pill.
2. Register mall "Robinsons" → **Later** → the row shows the **No branches** pill → row menu → **Add branch** → create one → pill gone.
3. Create account, role Mall Admin, step 2: pick "Ayala Center" → **Add all branches of this mall** → Create → temp password shown. Row shows "Branches 1".
4. Create account, role Mall Admin, pick a mall with no branches → the message shows and **Create** is disabled → Cancel → no new row.
5. Create account, role Supervisor, step 2 with nothing chosen → Create disabled → pick "Whole malls: Ayala Center" → Create. Row shows "Mall-wide 1".
6. Add a second branch under Ayala Center. Sign in as that supervisor → both branches visible without any new assignment. Sign back in as superadmin.
7. Status filter → Unassigned → only accounts with the pill are listed; "No unassigned accounts" when none.
8. Row menu → Assignments on the mall admin → switch mall to Robinsons → previous Ayala branch is listed under "Other malls" → remove it → add a Robinsons branch → Save. Row shows "Branches 1".
9. Malls → Ayala Center → Deactivate → dialog shows 2 branches, the store count and 1 mall admin → Deactivate. Sign in as that mall admin → no branches, overview counts zero. Reactivate as superadmin → access returns.
10. Branch → Deactivate → dialog shows store and owner counts → Cancel (default) leaves it active.
11. Overview and Analytics: cards read "Active …"; Map publications shows the real number (2 for SM Mall of Asia after earlier tests).
12. Audit log shows every action from steps 1–10 with the right actor.

## 6. Open questions for the owner (answered: built as proposed)

1. **Access column wording** — built with counts ("Mall-wide 1 · Branches 2"). Names are in the Assignments dialog.
2. **First-branch prompt** — built to show after every mall registration, with **Later** to skip; the pill and **Add branch** cover it afterwards.
3. **Deactivating a mall** — built to hide the branches only; each branch keeps its own status, so reactivating the mall restores everything.

# Round 14 — Mall owner dashboard: second gap review

Status: **Done 2026-10-22.** Backend 81/81. New tests:
- `test/reports_to_rule.test.js`, 4 tests;
- `test/owner_round14.test.js`, 10 tests;
- a decision-driven update to `people.test.js`, `mall_owner.test.js`, `flows.test.js` and `scope.test.js`.

Flutter analyze clean; 223 Flutter tests pass, 5 skipped. New tests:
- `test/round14_test.dart`, 7 tests;
- an updated `people_round4_test.dart` and `login_test.dart`.

## How it was found
- **Reviewed:** every mall-owner page in the web app and every server route a `supervisor` can reach, against US-012 to US-016.
- **Found:** 24 gaps, in four groups: A, wrong or unsafe; B, missing; C, polish; D, API hardening.
- **Checked by hand:** the key claims, in the code.
- **Corrected:** one claimed data loss (branch coordinates). The app always resends them, so it was only an API trap and moved to D.

## Owner decisions (2026-10-22)
| Topic | Decision |
|---|---|
| Scope of this round | Build all of A, B, C and D |
| Shared announcement (targets inside and outside an owner's scope) | **Their part only.** Only targeted people see it, and each sees only their own branches in its target list. "Delete" takes it off their branches only, so other malls keep it. Only its author, someone covering all its targets, or a superadmin can change it. The rule applies to every manager. Owners can't edit store-owner submissions (mall admins review them). |
| Inactive branch the owner can open | Its stores and published map stay viewable, **read-only**. |
| Who an admin reports to | **Automatic.** The owner of their own branch first, else the mall's whole-mall owner, the one linked first. Inactive owners are skipped. Nobody means "No owner". It is recalculated after every change, and there is no manual picking or "Release". |
| Tagline | "Smart Way Forward" in the browser tab, the login footer and under the login panel's wordmark |
| Branding | Larger login wordmark; top-bar items vertically centred; larger top-bar wordmark |

## What was built

### Backend
- **Reports-to rule.**
  - `recomputeReportsTo()` in `repos/assignments.js` is one set-based UPDATE with OUTPUT.
  - `utils/ownership.js` `applyReportsToRule()` runs the rule and audits it as `reports_to_recomputed`, listing the changes.
  - It runs after:
    - owner assignments;
    - adding or removing a mall owner;
    - placing, moving or removing an admin;
    - account creation;
    - owner deactivation and reactivation.
  - Migration `009_reports_to_rule.sql` applied the rule to existing data.
- **Manual picking refused.** `PUT /accounts/:id/reports-to` answers 410, and `PUT /malls/:id/admins` refuses `reportsTo`.
- **Second guard.** `loadManageable` also requires the admin's branch to be in the owner's scope.
- **Moving off an inactive branch.** An owner may move an admin off one of their inactive branches; the new branch must be active.
- **Shared announcements.**
  - `managerAccess()` decides view, change and detach rights.
  - `present()` filters targets to the person's own branches and adds `sharedBeyondScope`, `canChange` and `canDetach`.
  - DELETE on a shared post detaches it, audited as `announcement_detached`.
  - Permission checks come before date checks.
- **Read scope for inactive branches.** The store and map read routes use `includeInactive`, which only widens a mall owner's scope, and owners can't write.
- **Slim map for owners.** `GET /maps/:branchId` for people who can't edit returns no draft, lock, versions or warnings.
- **Counts.**
  - Scoped "Active stores" and "Active accounts" count active records only.
  - For owners, admins are counted by the rule's superior.
  - Mall branch counts follow the person's scope.
- **People on a mall.** `GET /malls/:id/people` is open to owners for their malls, read-only, with admins filtered to the owner's branches.
- **Admin edits by owners.** `PUT /accounts/:id` refuses an email waiting in someone's change request, and cancels the admin's own waiting request, audited.
- **New endpoint.** `GET /profile/access` lists what the signed-in person owns or manages.
- **Hardening.**
  - Partial branch PUTs keep the fields they don't send.
  - Branch logos and announcement images must be `http(s)` links.
  - A new announcement can't already be over.

### Web
- **No "reports to" picking.** The pickers are removed from the create wizard, the Assignments dialog and the mall-page admin dialogs, along with "Release".
  - Account pages show "Reports to" read-only for everyone.
  - The Access step says the superior is set automatically.
  - Owners whose mall has no branches are told to ask a superadmin.
- **Announcements.**
  - Shared posts show a "Shared with other branches" note and have no Edit.
  - "Remove from my branches" replaces Delete when the person can't change the post.
  - Statuses read "Waiting for review", "Approved" and "Rejected".
- **Inactive branch page.** Stores and map are shown with "hidden while inactive", and the Reactivate card explains who can't see them.
- **Map viewer.**
  - One "No published map yet" card, with "Back to branch".
  - A real error shows only the error.
  - Inactive branches are labelled in the picker.
- **Mall page for owners.** Read-only Owners and Admins cards; the admins who report to the owner open their page. The deactivation texts are corrected.
- **Store owners.** A new route `/mall-owner/owners/:id` opens them read-only from a store page.
- **Overview.**
  - Stat cards open their pages.
  - Recent activity reads in words; the shared `actionLabel()` is also used in the Audit log, with the raw code kept in its details.
  - Quick actions show up to six pages.
- **Analytics.** "Pending review" rows open the announcement.
- **Lists.** Every list says "Nothing matches these filters." when a search or filter hides everything.
- **Stores pages.** For owners: "Stores", "read-only, their mall admins manage them".
- **My malls.** Owners get the malls list only. A branch opened from a mall goes Back to that mall (`?fromMall=`).
- **My account.** A "Your access" card.
- **Branding.**
  - `brandTagline` and `BrandLockup` (wordmark with tagline);
  - login panel wordmark at 40 px with the tagline, and the narrow header at 30 px with the tagline;
  - footer "LIQO Wayfinding Platform · Smart Way Forward";
  - browser tab "LIQO — Smart Way Forward";
  - top bar items centred (the row used to cling to the top of the bar), with the wordmark at 26 px.

## Tests changed on purpose (decisions, not bugs)
- **`people.test.js`:**
  - A branch-level owner now takes over the admin of their branch.
  - The manual reports-to tests became "refused (410)".
  - A superadmin-created admin gets the mall's first-linked owner.
  - Owners may now read their mall's people.
- **`mall_owner.test.js`:** the earlier branch-level owner is freed first, so the admin reports to the whole-mall owner again.
- **`flows.test.js`:** the owner now sees the stores of their inactive mall's branch, read-only.
- **`scope.test.js`:** a store-owner submission now uses current dates, because expired ones are refused.

## Still deferred
- The shopper API for announcements.
- Image upload instead of links.
- Analytics on shopper map views.

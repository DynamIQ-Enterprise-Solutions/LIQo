# Round 8 — Superadmin gaps and profile change requests

Status: **Done 2026-10-22.** Backend 54/54 tests (new: `test/superadmin.test.js`, `test/profile.test.js`); Flutter analyze clean; 164 Flutter tests (new: `test/round8_test.dart`), the layout sweep covers every new page at ten widths, loaded, loading and half-loaded. Checklist: `LIQo backend/docs/TESTING.md`, "Round 8".

## Why this round

On 2026-10-22 the owner asked whether gaps remain in the superadmin dashboard. A review of US-005 to US-011 found nine items; the owner picked four, then added the profile change requests while answering one of them.

## Built

| # | What | Where |
|---|---|---|
| 5 | **Logos are shown.** Mall and branch logos appear in the lists (28 px) and on their pages (64 px with the URL). No logo, or one that fails to load, shows the name's initials, so a bad URL is visible at once. Hosts without CORS headers still render (`WebHtmlElementStrategy.fallback`). | `shared/widgets/logo_image.dart`, `malls_view.dart`, `mall_detail_view.dart`, `branch_detail_view.dart` |
| 6 | **A store owner's stores** show on their account page for the superadmin (read-only; US-007). | `account_detail_view.dart` via `GET /owners/:id` |
| 7 | **Another superadmin** can be opened, deactivated, reactivated and reset (typed confirmation, audited as `superadmin_deactivated`, `superadmin_reactivated`, `superadmin_password_reset`). Their name and email cannot be edited by others. You cannot deactivate yourself. Deactivation is one SQL statement that refuses to leave no active superadmin, which also covers two superadmins deactivating each other at once. | `routes/accounts.js` (`loadManageable(…, { otherSuperadmin })`), `repos/users.js` (`deactivateKeepingASuperadmin`) |
| 8 | **Release a stuck map lock.** The branch page's Map card shows "Being edited by …" and, for the superadmin, **Release the lock** (typed branch name). Audited as `map_lock_force_released` with the previous holder. | `POST /maps/:branchId/lock/force-release`, `maps.forceReleaseLock`, `MapsService.forceReleaseLock` |
| new | **Own profile changes.** Everyone changes their name and email from My account. A superadmin's change applies at once (`profile_updated`). Everyone else sends a request; one waits at a time (enforced by a filtered unique index); nothing changes until a superadmin approves on **Profile requests** (sidebar item with a count badge). Approve applies the change in one transaction; reject needs a reason the person sees. The email is checked for uniqueness when sent and again at approval. Audited: `profile_change_requested`, `…_cancelled`, `…_approved` (old and new), `…_rejected` (reason). | Migration `008_profile_requests.sql`, `repos/profileRequests.js`, `routes/profile.js`; `features/account/`, `features/profile_requests/` |

## Owner decisions in this round
- A superadmin may deactivate, reactivate and reset another superadmin, with safeguards.
- A superadmin may **not** edit another superadmin's name or email.
- The admin reset route on your own account stays as it is (the screen hides it).
- Own details: name and email; a Profile requests page; one waiting request at a time with Cancel; same round.

## Not covered by an automated test
- The "last active superadmin" refusal (409): the development database always has other active superadmins, so the test would have to deactivate real accounts. It is enforced by the conditional `UPDATE` in `users.deactivateKeepingASuperadmin`.

## Still open (not chosen this round)
1. Overview cards for accounts, sign-ins and map edits (US-005).
2. A user filter on the audit log (US-011).
3. Readable action names in the audit log and the overview.
9. Settings page refresh, and the two "AI" labels that control the no-AI blueprint detection.
10. Changing an account's role (later).
- The loading overflow the owner saw: waiting for the page, window width and moment.

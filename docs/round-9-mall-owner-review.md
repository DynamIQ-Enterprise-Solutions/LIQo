# Round 9 — Mall owner dashboard review

Status: **Done 2026-10-22.** Built: #1, #2, #6, #7, #8 (read-only), #9 (mall admins only), plus owners keeping their own inactive malls and branches. Backend 59/59 (new `test/mall_owner.test.js`); Flutter analyze clean; 170 Flutter tests (new `test/round9_test.dart`), the sweep covers the owner's Stores page, a store page and the viewer opened on a branch. Checklist: `LIQo backend/docs/TESTING.md`, "Round 9".
Checked: Epic 3 of `USER_STORY(ADMIN).md` (US-012 to US-016, written for the "mall supervisor", now called mall owner) against the app as it is after Round 8.

## Already met
- US-012: only assigned malls and branches are listed; branch details and hours are visible; permitted fields are editable; malls and branches can be deactivated and reactivated; no create buttons.
- US-013: edit, deactivate, reactivate, reset password and release the mall admins that report to the owner; move them between branches in scope (one branch per admin); every change audited.
- US-014: published maps open read-only; no edit, publish or rollback.
- US-015: analytics scoped to the owner's malls; cards, charts and a real CSV export.
- US-016: announcements with title, body, image URL, dates and target branches; targets limited to scope; the publication period is enforced.

## Gaps against the stories

| # | Story | Gap | Why it matters | Proposed fix | Size |
|---|---|---|---|---|---|
| 1 | US-012 | **An owner of a single branch can rename or deactivate the whole mall.** Their mall list includes the mall of that branch, and the mall routes only check "is this mall visible". | Deactivating hides every branch and store of that mall, including branches owned by other people. This is a real permission hole. | Mall changes (edit, deactivate, reactivate) need a whole-mall assignment. Branch-level owners see the mall read-only, with a note that only its whole-mall owners or a superadmin can change it. Backend check in `routes/malls.js`, new `assertWholeMallOwner`. | S |
| 2 | US-014 | The branch page's **"Open viewer" opens the viewer with no branch chosen**; the viewer cannot be linked to a branch. | One extra pick every time, and a link to a branch's map cannot be shared. | `/mall-owner/maps?branch=12` preselects that branch; the branch page button uses it. | S |
| 3 | US-016 | Announcements are not yet **available to the shopper app**. | Deferred by US-044 (shopper app integration). | Later, with the shopper API. | — |
| 4 | US-016 | The announcement **image is a URL**, not an upload. | Meets "optional image" minimally. | Later (listed in the gap analysis as image upload). | — |
| 5 | US-013 | The story says owners **cannot create** mall admins. | Changed on purpose by the owner in Round 4 (owners create admins that report to them). Recorded so it is not read as a mistake. | — | — |

## Found while using it

| # | Gap | Why it matters | Proposed fix | Size |
|---|---|---|---|---|
| 6 | The Overview's **Recent activity shows only the owner's own actions**, not what their mall admins did. | The owner oversees those admins; their dashboard should show what their team changed. | Include actions by the admins who report to the owner (the `reports_to` link from Round 4 makes this possible without new data). | S |
| 7 | The **map viewer shows shapes only**: no store names on spaces, no store list, no search. | An owner checking a mall's layout cannot tell which store is where. | A store list beside the viewer (search, click to highlight the store's space) and store names drawn on linked spaces. | M |
| 8 | Owners **cannot open their malls' stores**: no Stores page in their menu, and the branch page lists stores without links. | Not in the stories; an owner may still want to see what is in their malls. | A read-only Stores page and store pages for owners. Owner's choice. | S |
| 9 | Owners can **approve or reject store-owner announcements**, but US-022 gives that review to mall admins. | This was my own earlier call ("owners outrank admins"), never the owner's decision. Under the no-assumptions rule it needs the owner's answer. | Either keep it, or limit review to mall admins (owners still see the queue). | S |

## Owner decisions (2026-10-22)
- Build #1, #2, #6, #7.
- #8: yes, a read-only Stores page for mall owners.
- #9: store-owner announcements are reviewed by **mall admins only** (US-022). Owners still see pending submissions, with a "Waiting for a mall admin" card.
- Found while building #1: an owner who deactivated their own mall or branch lost sight of it and could not reactivate it (US-012 says they can). Decision: **keep it visible, marked Inactive**, with a Reactivate card. Its stores and admins stay hidden from everyone else as before.

## What was built
- **Whole-mall ownership for mall changes.** `resolveScope` returns `wholeMallIds` for owners; `assertWholeMallOwner` guards rename, deactivate and reactivate in `routes/malls.js`; `GET /malls/:id` returns `canManage`. Owners of single branches see the mall page read-only with a note.
- **Owners keep their inactive malls and branches.** `resolveScope(user, { includeInactive: true })` is used only by the mall and branch routes (lists, pages, impact, edits, status changes). Stores, analytics, admins, announcements and maps keep the active-only scope.
- **Viewer opens the branch.** `/mall-owner/maps?branch=12`; picking a branch updates the address so it can be shared; the branch page's "Open viewer" uses it.
- **Store list in the viewer.** `map_editor/store_list_panel.dart`: stores linked to spaces, with the level they are on, a search, "Not on map" for links to spaces that are not drawn; picking a store highlights its space and switches level. Store names were already drawn on linked spaces. Beside the map on wide screens, under it on tablets and phones.
- **Team activity.** An owner's Recent activity includes actions by the mall admins who report to them.
- **Stores for owners.** "Stores" in the mall owner menu, read-only store pages; the branch page's store rows open them.
- **Review by mall admins only.** `POST /announcements/:id/approve|reject` requires a mall admin (or superadmin).

## Test changed on purpose
- `test/flows.test.js`, "deactivating a mall hides its branches…": the line asserting the owner no longer sees the branch of a deactivated mall now asserts the opposite, per the decision above, and adds a check that the stores stay hidden. The other assertions (mall admin, store owner, pickers) are unchanged.

## Loading overflow found and fixed (2026-10-22)
- **Seen** in the running app right after launch: the Overview overflowed by 459 px, then three more pages by 47 to 118 px.
- **Cause.** The shell put the page navigator inside one scroll view. Without a height limit, Flutter sizes the navigator to the top page and forces every other page to that exact height. During the 220 ms fade between pages both are on screen, and the new page is usually still loading and short. The old page was squeezed into that height and overflowed. The layout sweep jumps 250 ms per frame, so it never laid out those frames.
- **Fix.** The shell no longer scrolls. Each page scrolls inside its own `ShellPage`, inside the transition (`router.dart`, `app_shell.dart`). Side effect: each page now opens at the top instead of keeping the previous page's scroll position.
- **Guard.** New `test/page_transition_test.dart`: every page and record page of every role, forward and back, at 360 and 1366 px, loaded and loading, stepped at 16 ms. It failed on seven pages before the fix and passes after. Flutter suite: 186 pass, 5 skipped.

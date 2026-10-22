# Round 7 — Dedicated detail pages (People-page layout), top bar proportions

Status: **Done 2026-10-21.** Owner answers: latitude and longitude are **hidden** until the shopper app exists (kept in the API and database); "Build". Added during the build at the owner's request: skeleton loading on every dashboard of every role (map editor and viewer included) and charts that animate only when scrolled into view (`shared/widgets/reveal_on_scroll.dart`). Backend 45/45; Flutter analyze clean; 61 Flutter tests, the sweep renders every detail page loaded and loading at 360/768/1024/1440 px.
Requested 2026-10-21: the side panel feels off; clicking a row should open a dedicated page laid out like the People page (sections as separate cards with clear separation); the top bar's element placement looks wrong and should follow sound proportions.

## 1. Detail pages

Every list row opens its own page with its own URL (bookmarkable, back button works):

| List | Page URL | Cards on the page |
|---|---|---|
| Malls | `/superadmin/malls/:id` (owners: `/mall-owner/malls/:id`) | **Details** (name, status, branches, logo) with an Edit button that turns the card into the form · **Branches of this mall** (rows that open the branch page; superadmin: Add branch) · **People** (owners and admins summary, "Manage people →" to the People page; superadmin only) · **Danger zone** |
| Branches | `/superadmin/branches/:id` and the owner/admin equivalents | **Details** (mall, address, hours, contacts, location) with Edit / Edit information · **Stores at this branch** (rows that open the store page) · **Map** (published version, spaces, "Open in editor/viewer →") · **Danger zone** (not for mall admins) |
| Accounts | `/superadmin/accounts/:id`, `/mall-owner/admins/:id` | **Details** with Edit · **Access** (malls, branches, reports to, with "Change assignments" opening the existing dialog) · **Sign-in** (last sign-in, temp password, lockout) · **Danger zone** (Reset password, Release for owners, Deactivate) |
| Stores | `/mall-admin/stores/:id`, `/store-owner/stores/:id` (read-only) | **Details** with Edit · **Map spaces** (list + inline edit) · **Owners** (rows, add, remove) · **Danger zone** |
| Store owners | `/mall-admin/owners/:id` | **Details** with Edit · **Stores** (rows, Assign a store, Remove per store in the danger zone) · **Danger zone** (Reset password, Remove store, Deactivate) |
| Option values | `/mall-admin/options/:id` | **Details** with Edit · **Used by** (count of stores) · **Danger zone** (Deactivate, Delete when unused) |
| Announcements | `/<prefix>/announcements/:id` | **Message** · **Details** (dates, branches, store, author, status, reviewer, reason) with Edit · **Review** (Approve / Reject with reason, when pending and allowed) · **Danger zone** (Delete) |

Rules, all taken from the People page:
- `PageHead` with eyebrow "Superadmin / Malls & branches / SM Prime", the record name as title, a one-line context subtitle, and actions: **Back** plus the page's primary action.
- Each section is its own card with `CardHead` (title, subtitle, a trailing button when the section has one action) and `CardBody`. Cards are separated by the standard 18 px gap. Rows inside cards use the People page's `_PersonRow` pattern (name and email left, chips middle, actions right; stacked on tablets).
- Editing turns the Details card body into the form (Save / Cancel); the rest of the page stays visible.
- The **Danger zone** is the last card: red outline, each action explained, every button opens the typed confirmation (unchanged).
- The side panel (`detail_panel.dart`) is removed from the lists; `confirmDangerous`, `DetailRow`, `ActionTile` and `DangerZone` are kept and reused on the pages.
- After an action the page re-fetches its record (every record has a get-by-id route; one is added for option values).

## 2. Top bar proportions

- Height 64 px. One vertical rhythm: every control is 34 px tall and centred; gaps are 12 px; outer padding 24 px (16 on phones).
- Left: the wordmark at 22 px tall (its cap height matches the 34 px controls visually), a 1 px divider 20 px tall, then ADMIN in 10 px caps with 1.4 px tracking. Nothing else on the left.
- Right: the role badge (34 px tall, same radius as buttons), the mode toggle (34 × 34), the avatar (34 px circle, flat brand gradient, no glow). Glow stays only on the active sidebar item.
- The 2 px route line stays, fading at both ends.
- Phone: wordmark + toggle + avatar only; the badge and ADMIN tag are hidden.

## 3. Tests
- Backend: `GET /options/:id` (scoped) test.
- Flutter: each detail page renders with the fake API (data and loading) and is added to the layout sweep at every width; the typed-confirmation and danger-zone tests stay; the panel tests are removed with the panel.

## 4. Decisions
0. **People is part of the mall page** (owner request after the build): the Mall owners and Mall admins cards, with Add / Edit / Remove and the "New owner account" / "New admin account" actions, sit on the mall page itself. The separate People page is removed; its old link redirects to the mall page.
1. Latitude and longitude: hidden from the screens until the shopper app exists; the branch form keeps the stored values untouched when saving.
2. Built as planned. The side panel is gone (`detail_panel.dart` removed); the building blocks live in `shared/widgets/detail_widgets.dart` (`DetailScaffold`, `DetailCard`, `DetailRow`, `RecordRow`, `DangerZone`, `confirmDangerous`). A branch opened from the superadmin's list returns to the Branches tab (`/superadmin/malls?tab=branches`).
3. Charts: `RevealOnScroll` watches the page's scroll position and flips a chart to its real values the first time it is at least 60 px inside the viewport, so the sections lower on the page animate only when reached.

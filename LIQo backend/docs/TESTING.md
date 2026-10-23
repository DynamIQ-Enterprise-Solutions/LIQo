# Manual test checklist

How to run both apps:

```bash
# terminal 1
cd "LIQo backend"
npm run dev            # prints "LIQo API listening on 3000"

# terminal 2
cd "LIQo web"
flutter run -d chrome
```

First-time setup only: `npm install`, `npm run seed` (creates the superadmin), `flutter pub get`.

Superadmin login: `admin@liqo.local` / `Admin@123`

---

## Phase 1 — Sign in, password change, shell

- [ ] Open the app. You land on **/login** (not the dashboard).
- [ ] Submit with empty fields. Both fields show a red "required" message. Nothing is sent.
- [ ] Wrong password → red line "Incorrect email or password." You stay on the page.
- [ ] Correct superadmin login → you land on **/superadmin/overview**. The URL bar shows the path (no `#`).
- [ ] The sidebar shows the superadmin menu. The top-right avatar shows initials "LS".
- [ ] Overview cards show Malls 0, Branches 0, Stores 0, Accounts 1. "Recent activity" shows your login.
- [ ] Click **Refresh** on the overview. Cards reload.
- [ ] Click a sidebar item (for example Account management). A "Coming in Phase 2" page shows; URL changes.
- [ ] Type `/supervisor/overview` in the address bar while signed in as superadmin → "No access" page.
- [ ] Reload the browser tab. You stay signed in on the same page (no login flash).
- [ ] Dark mode toggle (moon icon) switches the theme.
- [ ] Avatar menu → **Sign out** → back to /login.
- [ ] Type `/superadmin/audit` in the address bar while signed out → goes to `/login?from=...`. After signing in you land on the audit placeholder.
- [ ] Backend check: in a DB tool run `SELECT action, actor_email, created_at FROM audit_log ORDER BY id DESC`. You see `login_failed` (no actor id), `login_success`, `logout`.

Forced password change and deactivated accounts are tested in Phase 2, once accounts can be created.

---

## Phase 2 — Superadmin

Sign in as `admin@liqo.local` / `Admin@123`. (Demo data from my API test already exists: mall "SM Prime", branch "SM Mall of Asia", supervisor `sup@liqo.local` with password `Supervisor2026`, mall admin `ma@liqo.local` still on a temp password.)

**Accounts**
- [ ] Account management → **Create account** → fill name, email, role Mall Supervisor → Create. A dialog shows the temporary password once with a Copy button. Copy it.
- [ ] The new account shows a "Temp password" pill.
- [ ] Row menu → **Assignments** → add a whole mall and/or single branches → Save. "Assignments saved." appears.
- [ ] Row menu → **Edit details** → change the name → the list updates.
- [ ] Row menu → **Reset password** → confirm → a new temp password is shown once.
- [ ] Row menu → **Deactivate** → confirm → status pill turns Inactive. **Reactivate** brings it back.
- [ ] Your own row has no Reset or Deactivate options.
- [ ] Filters: role dropdown and status dropdown narrow the list. Search by name or email works after a short pause.

**Forced password change (US-002)**
- [ ] Sign out. Sign in as the new supervisor with the temp password → you land on **Set a new password** and cannot reach any other page (type `/supervisor/overview` in the URL bar: it bounces back).
- [ ] A password shorter than the minimum, or without a letter and a number, is rejected with a clear message.
- [ ] After a valid change you land on the supervisor overview.

**Deactivated account (US-001)**
- [ ] As superadmin, deactivate that supervisor. Sign out, sign in as the supervisor → "Your account has been deactivated."

**Malls & branches**
- [ ] Malls & branches → **Register mall** → create one. Registering the same name again shows "A mall with that name already exists."
- [ ] Row menu → Edit / Deactivate / Reactivate work.
- [ ] Switch to the **Branches** tab → **Create branch** → pick the mall from the search picker, fill name, address, hours, contact → Create.
- [ ] Creating a second branch with the same name under the same mall is rejected.
- [ ] Latitude outside −90…90 is rejected before sending.

**Settings**
- [ ] Platform settings → set Minimum password length to 3 → "must be between 6 and 64." Set it to 10 → Save → "Settings saved."
- [ ] Set it back to 8.

**Audit log**
- [ ] Audit log lists every action above. The action dropdown filters by action. Search by email works. From/To date pickers narrow the range.
- [ ] Click a row → details dialog with the recorded JSON (passwords are shown as `[redacted]`).
- [ ] **Export CSV** shows a placeholder message.

**Analytics**
- [ ] Platform analytics shows the counts; Refresh reloads them.

**Scope (US-003), as the supervisor**
- [ ] Sidebar shows the supervisor menu only. Assigned malls lists only malls in the assignment. Branches & hours lists only branches in scope.
- [ ] Mall admins lists only mall admins assigned to those branches. There is no Create button.
- [ ] Row menu → Edit information on a branch works; the branch name and mall cannot be changed.
- [ ] Typing `/superadmin/audit` in the URL bar shows "No access".

---

## Phase 3 — Supervisor

Sign in as `sup@liqo.local` / `Supervisor2026` (assigned to the whole mall "SM Prime").

- [ ] Overview shows counts for your scope only (1 mall, its branches, its stores, accounts in scope).
- [ ] **Assigned malls**: only SM Prime. Edit works. Deactivate / Reactivate work. No "Register mall" button.
- [ ] **Branches & hours**: only SM Prime branches. Edit information (hours, address, contact). Name and mall are locked.
- [ ] **Mall admins**: only mall admins assigned to those branches. Edit, Assignments (branches limited to your scope), Reset password, Deactivate. No Create button.
- [ ] **Map viewer**: placeholder until Phase 6.
- [ ] **Announcements** → Post announcement → pick target branches (only your branches appear in the picker) → Publish. It shows as "Live" if today is inside the dates, "Scheduled" if the start is in the future.
- [ ] Pending store-owner submissions for your branches are visible; Approve / Reject work.
- [ ] **Analytics**: cards for your scope. Export CSV is a placeholder.

## Phase 4 — Mall Admin

Sign in as `ma@liqo.local` / `MallAdmin2026` (assigned to branch "SM Mall of Asia").

- [ ] **Branch information**: only SM Mall of Asia. Edit information works; the name and mall are locked.
- [ ] **Option lists** → choose the branch → Store categories → Add "Food & Beverage". Edit, Deactivate, Reactivate work. Delete on a category used by a store shows "used by N stores. Deactivate it instead."
- [ ] Switch to Unit types and Floor labels tabs and add a value in each.
- [ ] **Stores & spaces** → Create store → branch (only yours), name, category (from the branch's list), hours, contact → Create. Duplicate name in the same branch is rejected.
- [ ] Row menu → **Map spaces** → enter `sp-a01` and `sp-a02` on separate lines → Save. The Spaces column shows 2.
- [ ] Row menu → **Owners** → Add owner → new email → a temporary password is shown once. Adding an existing owner's email just links the store.
- [ ] Owners dialog → Remove the only store from an owner → message says the owner was deactivated.
- [ ] **Store owners** page lists owners with their stores. Assign a store, Remove a store, Reset password, Deactivate / Reactivate work. Re-assigning a store to a deactivated owner reactivates them.
- [ ] **Announcements**: Post to your branch. Pending submissions from store owners show "Pending review"; Approve publishes, Reject asks for a reason.
- [ ] **Analytics**: counts for your branch only.
- [ ] Type `/supervisor/overview` in the URL bar → "No access".

## Phase 5 — Store Owner

Create an owner from the mall admin's Stores → Owners dialog, then sign in with the temp password and change it. (From the API test: `owner@liqo.local` / `Owner2026x`, owner of "Northline Apparel".)

- [ ] Forced password change on first sign-in, then the store-owner overview.
- [ ] **My stores**: only your stores, read-only.
- [ ] **Announcements** → Submit announcement → pick your store → Submit. Status shows "Pending review".
- [ ] Edit your pending submission: it stays pending. Delete works while pending or rejected; an approved one cannot be deleted by you.
- [ ] After the mall admin approves it, it shows "Live" (or "Scheduled"). After a rejection the reason is visible in View.
- [ ] Approved announcements posted by the mall admin to your branch are also listed.
- [ ] **My account** shows your details; Change password works and returns to the overview.
- [ ] Type `/mall-admin/stores` in the URL bar → "No access".

---

## Phase 6 — Map editor (mall admin) and map viewer (supervisor)

Sign in as `ma@liqo.local` / `MallAdmin2026`. From my API test, branch "SM Mall of Asia" already has a small map with a published version.

**Open and lock**
- [ ] Map editor → pick the branch. The status strip shows "You are editing" and "Draft vN · published vM".
- [ ] Open the same branch as the mall admin in a second browser (or incognito). It shows "Locked by Mia Admin" and the tools are disabled. "Take lock" fails while the first window is active.
- [ ] (Optional) A branch with no map shows a **Create map** button: name the building and level, set width and depth.

**Drawing (left tool rail)**
- [ ] Wall (W): click several points to chain walls; Enter or double-click ends the chain. Angles snap to 15° (hold Shift for free angles). Ends snap to existing wall ends.
- [ ] Space (S): click corners, then click the first point (or press Enter) to close. The new space is selected; give it a name and type in Properties.
- [ ] Outline tool: redraw the level outline as an irregular polygon.
- [ ] Hole: with a space selected (or nothing selected for the level outline), draw a polygon inside it to cut a hole (atrium / void).
- [ ] Opening (O): click on a wall. Change kind to "entrance" in Properties.
- [ ] Feature (pin icon → pick from the catalog, e.g. Restroom, ATM, Entrance): click to place. Rotate and resize in Properties where the catalog allows it.
- [ ] Connector (stairs icon → pick a kind): click on this level, then switch level with the tabs, keep the connector selected, and click again to add the second endpoint. Escalators can be set one-way.
- [ ] Select (V): click to select; drag to move; drag a vertex handle of a selected space / outline; drag a wall end. Arrow keys nudge 0.1 m (Shift: 1 m). Delete removes.
- [ ] Moving a wall moves its openings with it. "Split in the middle" on a wall keeps each opening on the piece it lands on. Deleting a wall deletes its openings.
- [ ] Ctrl+Z / Ctrl+Y undo and redo, including a whole drag as one step.

**Saving, issues, publishing**
- [ ] After a change the chip goes "Unsaved changes" → "Saving…" → "Saved" within about two seconds.
- [ ] Issues tab: an unnamed retail space is listed under "Blocks publishing"; overlapping spaces, unreachable levels, and levels without openings appear as warnings. Clicking a warning selects the element.
- [ ] Publish with a blocking issue → refused with the list. Fix it → Publish → "Map published", status shows the new version.
- [ ] History → earlier version → Roll back → a new version is published and becomes the draft.
- [ ] Copy to… → another branch in your scope → that branch now has a draft with the same drawing (fresh ids, no store links).
- [ ] Stores & spaces → a store → Map spaces: enter a space id shown in the editor (for example `sp-a01`). The store name then appears under that space on the canvas.

**Structure tab**
- [ ] Add level / Add building / delete level work. Level elevation, height, offset and rotation and building origin and rotation are editable in Properties when nothing is selected.

**Supervisor viewer**
- [ ] Sign in as `sup@liqo.local` / `Supervisor2026` → Map viewer → pick the branch → the published map shows read-only with level tabs. No tools, no saving.

---

## Phase 7 (layer 1) — Blueprint upload, calibration, conversion (no AI)

Sign in as `ma@liqo.local` / `MallAdmin2026` → Map editor → open the branch → right panel → **Blueprint** tab.

- [ ] **Upload plan** → pick a PNG or JPG floor plan. It appears under the level, faded, scaled to fit the outline. A PDF or text file is refused with a clear message.
- [ ] Opacity slider, Lock switch, Rotate ±15°, and the 1 m nudge buttons move the picture. Nothing drawn moves with it.
- [ ] **Start calibration** → click two points on the plan with a known distance (a door of 1 m, a dimension line) → type the metres → Apply. The "px per metre" line updates and the first clicked point stays where it was.
- [ ] On an empty level: **Make the floor the size of the plan** sets the outline to the picture's edges. The button disappears once anything is drawn.
- [ ] **Detect walls & spaces** → after a moment a teal proposal is drawn over the plan: walls, amber doors, filled spaces. The panel shows counts and any notes.
- [ ] Click a teal piece on the canvas: it disappears from the proposal only.
- [ ] Untick Spaces, **Add to floor** → only walls and doors are added. Ctrl+Z removes them all in one step. Redo, then **Detect** again and add spaces.
- [ ] Spaces come in unnamed; the Issues tab lists them. Name them in Properties or link stores.
- [ ] Publish: the published map has no backdrop (Supervisor → Map viewer shows geometry only). Rollback keeps the backdrop on the draft.
- [ ] Platform settings: set "AI file size limit" to 1 MB and upload a bigger image → refused. Set "AI conversions per day" to 1 and detect twice → the second is refused until tomorrow. Reset both.
- [ ] **Remove plan from this level**, then delete the upload from the list. Deleting an upload that is still placed is refused.

Not in this layer: PDF page rendering in the browser, angled (non-axis-aligned) walls, AI naming of spaces.

---

## Phase 8 — Module reviews. Round 1: Auth

Built in this round: session length from Platform settings, lockout after repeated failed sign-ins, "My account" and "Change password" for every role, a second superadmin.

- [ ] **Session length.** Superadmin → Platform settings → Session timeout (hours) = 1 → Save. Sign out and in. The token now expires in 1 hour (the app signs you out by itself). Set it back to 8.
- [ ] **Lockout.** Platform settings → "Max failed sign-ins before lockout" shows (default 5). Sign out; enter a wrong password 5 times for `sup@liqo.local`. The 5th attempt says the account is locked for 15 minutes; the correct password is also refused now. Audit log shows `account_locked`.
- [ ] As superadmin → Account management → that account → Reset password → the new temp password signs in immediately (reset clears the lock).
- [ ] **My account for every role.** Sign in as superadmin: the sidebar ends with "My account"; the avatar menu has "My account", "Change password", "Sign out". Change password works and returns to the overview. Repeat as supervisor and mall admin.
- [ ] **Second superadmin.** Account management → Create account → role "Superadmin (platform-wide)" → a confirm dialog appears → Yes → temp password shown once. Audit log shows `superadmin_created`. The new superadmin must change the temp password at first sign-in.
- [ ] A superadmin still cannot deactivate or reset another superadmin from the list (by design for now; tell me if you want that allowed).

Unchanged and still true: wrong password / deactivated / temp-password messages; forced change at first sign-in; deactivated accounts refused on the next request.

---

## Phase 8 — Module reviews. Round 2: Superadmin

Built in this round: two-step account creation with a required assignment, an Access column with an "Unassigned" pill and filter, a mall-first assignment dialog with "Add all branches of this mall", the first-branch prompt after registering a mall, "No branches" pill and "Add branch" row action, deactivation dialogs that show what will be hidden, real map publication counts and "Active …" labels.

Sign in as `admin@liqo.local` / `Admin@123`.

- [ ] **Register mall → first branch.** Malls & branches → Register mall "Ayala Center" → Create. The "Add the first branch of Ayala Center?" dialog opens with the mall locked → name "Ayala Center Cebu" → Create branch. The mall row shows 1 branch and no pill.
- [ ] **Later.** Register mall "Robinsons" → Later. The row shows the amber **No branches** pill. Row menu → Add branch → create one → the pill is gone.
- [ ] **Create a mall admin.** Account management → Create account → name, email, role Mall Admin → Next. Step 2: pick "Ayala Center" → **Add all branches of this mall** → Create → temp password shown once. The row's Access column reads "Branches 1".
- [ ] **Mall with no branches.** Create account, role Mall Admin → Next → pick a mall that has no branches → the message "This mall has no branches yet…" shows and Create is greyed out → Cancel → no new row.
- [ ] **Create a supervisor.** Create account, role Supervisor → Next → with nothing chosen Create is greyed out and the hint says to choose a mall or branch → Whole malls: Ayala Center → Create. Access reads "Mall-wide 1".
- [ ] **Whole mall follows new branches.** Add a second branch under Ayala Center. Sign in as that supervisor (change the temp password) → Branches shows both. Sign back in as superadmin.
- [ ] **Unassigned filter.** Status filter → Unassigned → only rows with the pill are listed. With none, the table says "No unassigned accounts."
- [ ] **Edit assignments across malls.** Row menu → Assignments on the mall admin → switch Mall to Robinsons → the Ayala branch is listed under "Other malls" → remove it with the × → add a Robinsons branch → Save. Access reads "Branches 1".
- [ ] **Deactivate a mall.** Malls → Ayala Center → Deactivate → the dialog lists 2 branches, the store count and 1 mall admin, Cancel is the default → Deactivate. Sign in as that mall admin → no branches, overview counts zero. Reactivate as superadmin → access returns.
- [ ] **Deactivate a branch.** Branches → any branch → Deactivate → the dialog shows store and store-owner counts → Cancel leaves it active.
- [ ] **Counts.** Overview and Analytics cards read "Active malls / branches / stores / accounts"; Map publications shows the real number of published versions.
- [ ] **Audit log** shows: account_created (with the assignments in details), assignments updated, mall_created, branch_created, mall_deactivated, mall_reactivated, with the right actor.

Decisions applied (from the Round 2 doc): Access column shows counts, not names; the first-branch prompt appears after every mall registration; deactivating a mall hides its branches without changing their own status.

---

## Phase 8 — Module reviews. Round 3: Analytics

Built in this round: `GET /analytics/report?days=7|30|90` (scoped), the Analytics page with a period switch, charts (fl_chart), breakdown tables, a real CSV export, and one `map_edited` audit entry per 10-minute editing stretch (draft autosaves themselves are still not audited).

- [ ] **Superadmin** (`admin@liqo.local`): Analytics shows the cards, then Activity over time, Stores per branch + by category, Store readiness, Accounts, Announcements (by status, by time, who posts), Pending review, Announcements per branch, Map coverage, and Sign-in security. The last line says shopper traffic is not available yet.
- [ ] **Period switch.** 7 days → 30 days → 90 days: the activity chart and the "vs previous" numbers change; the cards do not. The activity card subtitle says "last N days".
- [ ] **Activity rises.** Create a store, post an announcement, open the map editor and move a wall (wait for "Saved"), publish. Refresh: today's points for announcements published, map editing sessions and map publications go up. Sign-ins count every login today.
- [ ] **Stores.** The donut matches the categories in Stores & spaces for SM Mall of Asia; "Not linked" = active stores without a map space.
- [ ] **Accounts.** The table shows Unassigned, Temp password and Locked now per role; lock an account with wrong passwords → Locked now = 1 → reset password → 0.
- [ ] **Announcements.** A store-owner submission appears in Pending review with "0 d"; approve it → it leaves the queue and "decided in the last N days" rises.
- [ ] **Map coverage.** SM Mall of Asia shows Published with the version count from History, spaces, named and linked counts. A branch with no map shows "No map".
- [ ] **Supervisor** (`sup@liqo.local`): only SM Prime's branches in every table; Accounts shows mall admins and store owners only; no Sign-in security section.
- [ ] **Mall admin** (`ma@liqo.local`): Accounts shows store owners only; Map coverage shows SM Mall of Asia only.
- [ ] **Export CSV** downloads `liqo-analytics-7d-<date>.csv`; it opens in Excel with every table and a title row above each.
- [ ] **Phone width.** Narrow the window: cards go two per row, side-by-side sections stack, tables scroll sideways, nothing overflows and the Flutter log shows no exception.
- [ ] Audit log shows `map_edited` once per editing stretch, not once per autosave.

---

## Layout sweep (every page, every width)

`flutter test test/overflow_sweep_test.dart` renders every page of every role at 360, 768, 1024 and 1440 px with long fake data, plus the dialogs and the map editor with a document open, and fails on any overflow or exception. It runs as part of `flutter test`. If it fails, the message names the page, the width and the source line.

Manual spot checks after a layout change:
- [ ] Narrow the browser to phone width on each role's pages: tables scroll sideways inside their card, buttons wrap to a second line, nothing shows the yellow-and-black overflow stripes.
- [ ] Map editor below 900 px shows "The map editor needs a wider window" instead of a cramped editor.
- [ ] Long names (branch, email, announcement title) are cut with "…" in lists, chips and legends, never pushed off the edge.

---

## Phase 8 — Module reviews. Round 4: Mall owners, admins, and who reports to whom

Built in this round: the Supervisor role is shown as **Mall owner** everywhere (URL `/mall-owner/...`, old `/supervisor/...` links redirect; the database and API keep the key `supervisor`), a **People** page per mall, one owner per mall admin ("Reports to"), owners who see only their own admins and can create or release them.

Test accounts: `sup@liqo.local` / `Supervisor2026` is now a **Mall owner** of SM Prime.

As `admin@liqo.local`:
- [ ] Sidebar, titles, role dropdowns and pills say Mall owner, never Supervisor. Open `http://localhost:5173/#/supervisor/overview` (or without `#`) while signed in as sup → it lands on `/mall-owner/overview`.
- [ ] Malls & branches → SM Prime → row menu → **People**. Mall owners lists sup (Whole mall). Mall admins lists ma with SM Mall of Asia and the amber **No owner** pill.
- [ ] Mall admins → **Edit** on ma → Reports to: pick sup → Save. The pill becomes "Reports to Supervisor …". Account management shows "Branches 1 · reports to …".
- [ ] **Add owner**: pick an existing owner account → it appears as Whole mall. **Remove** it → confirm dialog states how many admins report to them → gone.
- [ ] **New admin account** from People: step 1 name/email → step 2 starts on SM Prime, Add all branches, Reports to sup → Create → temp password → the new admin appears under Mall admins.
- [ ] Account management → Status filter → **No owner** lists only admins without an owner. Assignments dialog of a mall admin has a Reports to picker at the bottom; picking an owner who covers none of the branches is refused with a clear message.
- [ ] Audit log shows `reports_to_set`, `mall_owner_added`, `mall_owner_removed`, `account_created` with `createdByRole`.

As `sup@liqo.local` (Mall owner):
- [ ] Mall admins lists only admins that report to sup (ma after the step above). An admin with no owner is not shown.
- [ ] **Create mall admin** → no role choice → branches limited to SM Prime → Create. The new admin appears and reports to sup. The superadmin's audit log shows the creation with sup as actor.
- [ ] Row menu → **Release** → confirm → the admin disappears from sup's list. As superadmin, Account management shows them with No owner; People page lets you link them again.
- [ ] Assignments on an own admin: only branches in sup's scope are offered; saving keeps branches the admin has elsewhere.

- [ ] **One branch per admin.** People → Add admin only offers admins with no branch yet; the branch field is single-choice. Account management → Assignments on a mall admin: picking another branch replaces the old one. Creating an admin with two branches is impossible from the app and refused by the API.

Still true: a mall owner cannot create owners or superadmins; a mall with no branches cannot get an admin (People page says so and links to Malls & branches).

---

## Phase 8 — Round 5 and 7: Detail pages instead of row menus (Round 5's side panel was replaced by dedicated pages in Round 7)

- [ ] No list has a three-dot menu. Rows show a chevron and open a side panel from the right (full width on a phone). × , Escape and clicking outside close it.
- [ ] Malls → click SM Prime → Details, Actions (Edit, Add branch), Related (People), Danger zone. Edit replaces the sections with the form; Save returns to the sections with the new name; Cancel discards.
- [ ] Danger zone → Deactivate → the dialog shows the branch and store counts, the red button stays grey until you type "SM Prime" exactly, Cancel is the default. After confirming, the panel shows Inactive and Reactivate appears under Actions with a plain confirm.
- [ ] Branches: Edit information is inline; a mall admin sees no Danger zone.
- [ ] Account management → an account → Assignments closes the panel and opens the assignment dialog; Danger zone has Reset password (typed) and Deactivate (typed). As a mall owner, Release is in the Danger zone and the admin disappears from the list after it.
- [ ] Stores: Map spaces is inline; Owners opens the owners screen; Deactivate is typed. Store owners: Assign a store inline; each store has its own Remove in the Danger zone; Reset password typed.
- [ ] Option lists: rows open a panel; Delete is greyed out with a note when the value is in use.
- [ ] Announcements: the panel shows the full message; Approve plain confirm; Reject asks for a reason inline; Delete typed (the title).
- [ ] People page: Remove owner / Remove admin ask to type the person's name.

## Phase 8 — Round 6: Brand theme

- [ ] On a dark-mode device the app opens dark (Obsidian); on a light device it opens light. The sun/moon button overrides and the choice survives a reload; avatar menu → "Follow device theme" goes back to the device setting.
- [ ] The browser tab shows the dark app tile in dark mode and the light tile in light mode, also right after toggling by hand.
- [ ] The top bar shows the real LIQO wordmark (white letters on dark, dark letters on light, same orange mark); the login page too. The phone sidebar shows the app tile.
- [ ] Manrope is the typeface everywhere (compare the "O" and the rounded letterforms).
- [ ] Moving between pages fades softly; the sidebar highlight glides; nothing jumps. Prefer-reduced-motion users get the same shortened durations (no long effects exist).
- [ ] Pills, toasts, notices and the danger zone all read correctly in both modes.

- [ ] **Charts animate on open.** Analytics → the line chart rises from the baseline, bars grow, the donut ring thickens, the per-branch bars extend from the left, totals count up. Leave the page and come back: it plays again. Switching 7 → 30 days animates the change.
- [ ] **Skeleton loading.** Throttle the network in Chrome DevTools (Slow 3G) and reload: Overview, Analytics, every list, People, Settings and Option lists show shimmering placeholders in the shape of their content, with no overflow stripes, until the data arrives.

## Phase 8 — Round 7: Dedicated pages, top bar, scroll reveal

- [ ] Every list row opens its own page with its own URL (Back button and browser back work). The page is laid out like People: head with Back and the main action, then one card per section, the red Danger zone last.
- [ ] Malls → SM Prime: Details (Edit turns the card into the form), Branches of this mall (rows open the branch page), Mall owners (Add owner, Remove typed), Mall admins (Add admin, Edit branch and owner, Remove typed), New owner / admin account in the page head, Danger zone. Inactive malls show a Reactivate card instead. The old People link lands on the mall page.
- [ ] Branch page: no latitude/longitude anywhere; Stores at this branch (rows open the store page for mall admins), Map card with the published state. Mall admins see no Danger zone.
- [ ] Account page: Details, Access (Change assignments opens the dialog), Sign-in, Danger zone (Reset password, Release for owners, Deactivate). Your own account shows no Danger zone.
- [ ] Store page: Map spaces card edits inline; Owners card adds and removes owners (typed). Store owner page: Stores card with Assign a store inline and Remove per store (typed). Option value page: Delete greyed out while in use. Announcement page: Message, Details, Review (Approve / Reject with reason), Delete (typed).
- [ ] Top bar: everything sits on one 34 px line with 12 px gaps; the wordmark is 22 px; the role badge, the mode toggle and the avatar are the same height; the avatar has no glow. On a phone only the wordmark, the toggle and the avatar remain.
- [ ] Analytics: only the charts in view animate; scroll down and each further chart grows into place as it appears. Scroll back up: already-shown charts stay still.
- [ ] Every dashboard of every role shows shimmer skeletons while loading, including the map editor and viewer document area.

- [ ] **Sidebar motion.** Click another sidebar item: the orange bar on the left glides to it and the highlight fades in; hovering an item nudges it 3 px right. The layout sweep now covers ten widths, fully loading and half-loaded states (155 tests).

## My account (redesign)

- [ ] Open My account as each role: a profile hero (large gradient avatar with initials, name, email, role and status pills, what the role is for), then cards: Profile, Security (Change password), Appearance (Dark / Light / Device, remembered), Session (Sign out). Two columns on a wide window, one column on a tablet or phone, no overflow.
- [ ] Appearance: choosing Dark, Light or Device changes the app at once and survives a reload; Device follows the computer setting again.
- [ ] Sign out ends the session and returns to the sign-in page.

## Phase 8 — Round 8: Superadmin gaps and profile change requests

Run `npm run migrate` first (migration 008).

- [ ] **Logos.** Malls → SM Prime → Edit → set a logo URL → it shows on the page (64 px) and in the Malls list (28 px). Clear it → the initials show. A broken URL → the initials show. Same on a branch.
- [ ] **Store owner page.** Account management → filter Store Owner → open one → a Stores card lists their stores (read-only).
- [ ] **Another superadmin.** Create a second superadmin → open it: no Edit button; the Danger zone has Reset password and Deactivate, each asking to type the name. Deactivate → they cannot sign in; Reactivate → they can. Audit log shows `superadmin_deactivated` and `superadmin_reactivated`. Your own page still has no Danger zone.
- [ ] **Stuck map lock.** As `ma@liqo.local` open the map editor, then close the tab. As superadmin open SM Mall of Asia's branch page → Map card shows "Being edited by …" and **Release the lock** → type the branch name → released. Another admin can open the editor at once. Audit log shows `map_lock_force_released`. A mall owner sees "Being edited by" but no button.
- [ ] **Own profile, superadmin.** My account → Edit → change your name → it shows at once in the top bar and sidebar. Audit log `profile_updated`.
- [ ] **Own profile, everyone else.** As `ma@liqo.local`: My account → Request a change → new name and email → "Waiting for approval" card; Request a change is gone until it is decided; Cancel request works. Send it again.
- [ ] As superadmin: the sidebar shows a count on **Profile requests** → open the request → current values struck through next to the new ones → Approve → confirm. The count goes away.
- [ ] As `ma`: sign out, sign in with the **new email and the old password**. My account shows the new details.
- [ ] Repeat with **Reject** → a reason is required → `ma` sees "Your last request was not approved." with the reason.
- [ ] A requested email that another account already uses is refused when sent; if it is taken before approval, Approve says so and the request stays waiting.

## Phase 8 — Round 9: Mall owner dashboard

As superadmin, create a second mall owner who owns **one branch** of SM Prime (Create account → Mall Owner → Individual branches: SM Mall of Asia).

- [ ] **Whole-mall rule.** As that branch owner: My malls → SM Prime → no Edit, no Danger zone, a "Read only" card. Their branch page still has Edit information and the Danger zone. As `sup@liqo.local` (owns the whole mall): Edit and Deactivate are there.
- [ ] **Inactive stays visible.** As `sup`: deactivate SM Mall of Asia (typed name) → it stays in Branches & hours with an Inactive pill and a Reactivate card → Reactivate. Same for a whole mall from My malls. Meanwhile `ma@liqo.local` loses access as before.
- [ ] **Viewer opens the branch.** Branch page → Map → Open viewer → the viewer opens on that branch, and the address ends with `?branch=…`. Pick another branch: the address follows. Paste the address in a new tab: same branch.
- [ ] **Store list.** In the viewer, the panel beside the map lists the stores linked to spaces with their level; search narrows it; picking a store switches level and highlights its space; a store linked to a deleted space shows "Not on map". On a narrow window the panel sits under the map.
- [ ] **Team activity.** As `ma`, create a store. As `sup`, the Overview's Recent activity ("Your actions and your mall admins'") shows it.
- [ ] **Stores for owners.** As `sup`: Stores in the menu → list of the stores in their malls → open one → details, map spaces and owners, no edit buttons. On a branch page, store rows open their page.
- [ ] **Review.** As `owner@liqo.local` submit an announcement. As `sup`: open it → "Waiting for a mall admin", no Approve or Reject. As `ma`: Approve works.

## Phase 9 — Round 10: Create-account wizard

- [ ] **Steps up front.** As `admin@liqo.local`: Account management → Create account → the bar shows Role, Details, Access, Review, Done ("STEP 1 OF 5"). Pick Superadmin: Access disappears ("STEP 1 OF 4"). Pick Mall admin again: it comes back.
- [ ] **Email while typing.** Details → type `SUP@liqo.local` → "Checking this email…", then "Already used by Sam Supervisor (Mall Owner)" with Open account; Next is faded. Change it to a new address → "Available."
- [ ] **Inactive email.** Deactivate a test account, then type its email → "Belongs to an inactive account…" and Next stays off. Open account goes to it (after "Discard this account?").
- [ ] **Same name.** Type an existing person's full name → a warning naming them and their role; Next still works.
- [ ] **Requested email.** As `ma@liqo.local`, request a new email on My account. As admin, type that email in the wizard → the profile-request warning; creating still works, and approving that request afterwards fails with a clear message.
- [ ] **Access and Review.** Mall admin → pick a mall and SM Mall of Asia → "This branch already has: …". Review lists everything; Create → Done shows the temporary password with Copy; Open account goes to the new account.
- [ ] **Mall owner view.** As `sup@liqo.local`: Mall admins → Create mall admin → steps Details, Access, Review, Done. A taken email says only "This email is already in use."
- [ ] **Discard.** Type a name, press × or Escape → "Discard this account?"; Cancel keeps everything typed.
- [ ] **Store owners.** As `ma@liqo.local`: Store owners → Add store owner → Store, Details, Review, Done. `owner@liqo.local` → "Already a store owner: …", Review says Add store, Done says the store was added and shows no password. Deactivate a store owner with no stores and type their email → blocked, with Open store owner. On a store's page, Add owner skips the Store step.

## Phase 10 — Round 11: Login page

- [ ] **Layout.** Sign out. On a wide window the feature panel is on the left and the sign-in card on the right, clearly raised (border, shadow, orange accent on its top edge).
- [ ] **Carousel.** It moves every 6 s through Map editor, Blueprints, Stores & announcements, Insights & audit. Click a dot or an arrow: it jumps there and stops moving by itself. The counter shows 01 / 04 and follows.
- [ ] **Reduced motion.** Turn on the system's reduce-motion setting, reload: the carousel stays still and switches without a fade.
- [ ] **Theme.** The toggle at the top right switches light and dark; everything turns light in light mode; the choice is remembered after a reload and matches the toggle inside the app.
- [ ] **Narrow window.** Drag the window under about 1050 px: the card comes first and the compact carousel under it; nothing overflows. A short window (about 650 px high) scrolls.
- [ ] **Sign in still works.** Wrong password shows the error inside the card; a correct one opens the dashboard; an expired session shows "Signed out." in the card.
- [ ] **Ambience (Round 11 polish).** On opening, the panel, card and form rise in once. Behind everything a soft glow drifts and thin routes trace themselves to pulsing beacons; a faint IQ mark breathes behind the card; a thin light circles the card's edge. Each carousel slide builds its picture in. With reduce-motion on, all of this is still.

## Phase 11 — Round 12: Brand guidelines crops and glass login

- [ ] **Logos.** Top bar and login: the LIQO wordmark is crisp, with no light or dark rim around any letter or the Q, in both modes; switching theme does not change the logo's size. Dark mode shows white letters and a white arrow; light mode dark letters and a dark arrow.
- [ ] **Tiles and tab icon.** The IQ tile (login card, collapsed sidebar) has clean rounded corners with no grey or shadow fringe; the browser tab shows the dark tile in dark mode and the light tile in light mode (reload after switching the system theme).
- [ ] **Tagline.** The sidebar footer reads "Smart Way Forward".
- [ ] **Glass.** Login, dark mode: the left panel is deep obsidian-to-crimson glass, the moving background shows blurred through it and through the sign-in card. Light mode: frosted white with a peach-to-rose tint. Pictures float in slight 3D over a glow; "Published" and "Walls detected" chips float in front.

## Phase 12 — Round 13: Theme and page transitions

- [ ] **Theme morph.** In the top bar (and on the login page) press the sun/moon: every colour blends over about half a second, the LIQO logo cross-fades, nothing jumps half-way; the icon rotates from moon to sun (and back).
- [ ] **Device switch.** With "Follow device theme" on, change the system theme: the app morphs the same way.
- [ ] **Pages.** Click through the sidebar quickly: the previous page vanishes at once and the new one fades and rises in; two pages are never visible together.

## Fix 2026-10-22 — Creating a branch's first map

- [ ] **Create map shows.** As a mall admin whose branch has no map: Map editor → choose the branch → Open → "… has no map yet." **and** a Create map button. Create map → the form (building, first level, width, depth) → Create map → the editor opens on "Main building / Ground floor", the lock is yours, the draft autosaves; the audit log shows `map_created`. Same as a superadmin on any branch without a map.

## Phase 13 — Round 14: Mall owner dashboard, second review

- [ ] **Reports-to rule.** As superadmin: an admin on SM Mall of Asia shows "Reports to: Sam Supervisor" (whole-mall owner). Create a branch-level owner on SM Mall of Asia → the admin now reports to them. Deactivate that owner → back to Sam; reactivate → back to them. No screen offers a "Reports to" picker or "Release".
- [ ] **Shared announcement.** As superadmin post to SM Mall of Asia and a branch of another mall. As `sup`: it lists only their branch, shows "Shared with other branches", has no Edit; "Remove from my branches" removes it for them only (the superadmin still sees the other branch).
- [ ] **Inactive branch.** As `sup`: deactivate SM Mall of Asia → its page still lists its stores and map ("hidden while inactive"), the viewer opens it; reactivate.
- [ ] **Viewer.** A branch with no published map shows one "No published map yet." card with "Back to branch".
- [ ] **Mall page for owners.** My malls → SM Prime: Owners and Admins cards, read-only; your admins open their page. A branch opened here goes Back to the mall.
- [ ] **Overview.** Cards open their pages; recent activity reads in words ("Signed in", "Created a store"); the Audit log shows the same words (code in the details).
- [ ] **Counts.** Deactivate a store → "Active stores" on Overview drops by one.
- [ ] **Store owners.** As `sup`: Stores → a store → its owner opens read-only.
- [ ] **My account.** "Your access" lists what you own or manage.
- [ ] **Branding.** Browser tab "LIQO — Smart Way Forward"; login: larger wordmark with "Smart Way Forward" under it and in the footer; top bar items on one centre line with a slightly larger wordmark.

## Phase 14 — Round 15: AI floor-plan reading (IQGateway)

- [ ] **Key.** `IQ_GATEWAY_KEY` is in `LIQo backend/.env` (never in the web app); restart the backend.
- [ ] **Settings (superadmin).** "AI floor-plan reading" lists the gateway's models and shows the credit bar. Choose a model, save; the audit log shows "ai_model_changed". Without the key the card says where the key goes.
- [ ] **Whole plan (as `ma@liqo.local`).** Map editor → Blueprint: upload a plan picture, calibrate, then "Read with AI". The proposal shows named rooms, walls, doors and a dashed outline; unsure pieces are dashed amber. "Last reading: … credits" appears and the credit bar moves.
- [ ] **PDF.** Upload a multi-page PDF → pick the page (preview shows) → it is uploaded as a picture.
- [ ] **A part.** "Box a part", drag over a section, read it; box a second section and "Add to proposal": nothing appears twice.
- [ ] **Review.** Click a piece to drop it. Untick the outline when the level already has one. "Add to floor", then Undo removes everything in one step; Add again.
- [ ] **Store links.** A room named like a store of the branch shows "Room → Store"; after adding, the store's page lists the new space.
- [ ] **Errors.** Remove the model (or the key) → the panel says why and nothing is sent. An empty wallet → "AI credits are used up".
- [ ] **Owners.** A mall owner cannot read plans (no button; the route answers 403).

## Phase 15 — Round 16: more plan formats

- [ ] **Pictures.** As `ma@liqo.local`, Map editor → Blueprint → Upload plan: a TIFF, a WebP, a BMP, a GIF and an iPhone HEIC each upload as a PNG and are placed; calibrate as usual.
- [ ] **SVG.** An SVG plan is placed as a picture (lines drawn by the server); calibrate with two clicks.
- [ ] **DXF with a unit.** A DXF saved in millimetres is placed at its exact scale: the panel says "Scale from the drawing (millimetres)"; measure a known wall with the wall tool, it matches.
- [ ] **DXF without a unit.** The unit question appears; "Later" leaves it unplaced with **Set unit** in the list; choosing millimetres places it.
- [ ] **DWG.** Before ODA is installed: a clear "save as DXF or PDF" message. After setting `ODA_FILE_CONVERTER` and restarting: the DWG uploads and is placed like a DXF.
- [ ] **Read a CAD plan with AI** (needs credits): walls sit exactly on the drawing's wall lines with the right thickness; room names use the drawing's spelling.
- [ ] **Refused files.** A renamed file (e.g. a .txt renamed to .png) is refused with the list of accepted formats.

## Phase 16 — Round 17: start from a plan, AI scan, 3D preview

- [ ] **Start from a plan.** As `ma@liqo.local`, open a branch with no map: "Start with your floor plan" with **Upload a floor plan**; the manual link is below. Upload a DXF in mm: the map starts at the drawing's exact size and the Blueprint tab is open, the view framed on the plan.
- [ ] **Picture.** On another branch upload a PNG: the map starts on it with no outline; calibrate, then "Make the floor the size of the plan".
- [ ] **Later.** Upload a DXF without a unit and press Later: no map; the upload is listed with **Start with this plan**.
- [ ] **Fallback.** "Create an empty map by hand" still makes the 120 × 80 m map.
- [ ] **Scan** (needs credits): "Read with AI" shows the full-screen scan over the plan (or the boxed part) with the clock; it closes by itself; the proposal draws itself in. With reduced motion: no moving line, no draw-in.
- [ ] **3D.** The 3D preview sits beside the canvas: drag to turn, wheel to zoom, right-drag to slide, Reset view. Draw a wall in 2D: it appears in 3D at once. Add a level: levels stack, the current one solid. An AI proposal shows teal (unsure amber) and rises in. Drag the divider; Collapse, reload, it stays collapsed; expand again.
- [ ] **Width.** At 900 px the editor still fits (3D collapsed to its strip).

## Phase 19 — Round 20: record pages like My account

- [ ] **Wide window.** Open an account, a mall, a branch, a store, a store owner, an option value, an announcement, a profile change, an AI credit request and a problem report: each starts with a header card (initials, logo or icon; name; pills; one line of facts), then the short cards side by side in pairs, every list full width, and the danger zone (when there is one) last, full width.
- [ ] **Narrow window** (tablet or phone): one column, the main cards first.

## Phase 18 — Round 19: AI credits, Requests & reports, problem reports

- [ ] **Settings.** As `admin@liqo.local`: two columns, AI floor-plan reading on the left, one card with Sign-in & security and General on the right (one column on a narrow window, AI first). The model list opens under its field. "Given to mall admins · Free to give" shows; Starting credits 3 and Most credits per admin 20 can be changed and saved.
- [ ] **Give credits.** Analytics › AI credits: the split bar shows Wallet, Given, Free and Used. Add 5 to `ma@liqo.local`: Given rises, Free falls, History shows it. Try more than 20 or more than Free: refused in words. Remove 1: back to Free.
- [ ] **Admin view.** As `ma@liqo.local`: My account › AI credits shows the balance (no wallet numbers). Request credits 3; the open request shows with Cancel.
- [ ] **Decide.** As superadmin: the sidebar count on Requests & reports; the AI credits tab lists the request; open it, approve 2. The admin's balance rises by 2; the audit log has the approval.
- [ ] **Reading** (needs credits and the owner's OK): as the mall admin, read a plan; the balance drops by the cost. At 0, Read with AI is refused with Request credits.
- [ ] **New admin.** Create a mall admin: the Done step says "Starts with 3 AI credits".
- [ ] **Deactivate.** Deactivate that admin: their credits return to Free; reactivate: they start again with 3.
- [ ] **Report a problem.** As a mall admin, press Report a problem in the top bar, send one. As superadmin: Requests & reports › Problem reports lists it; open it, reply, Mark in progress, Resolve. As the mall admin: My account › My reports shows it with the reply; no reply box once resolved.
- [ ] **My account loading.** Reload My account: a skeleton of its own shape shows briefly, never a spinner.

## Phase 17 — Round 18: accurate AI maps, 3D look, the easy editor

- [ ] **Easy editor by default.** As `ma@liqo.local`, open a map: the step bar shows Plan, Scale, Read with AI, Rooms, Publish, with Undo, Redo and Advanced editing; there is no icon rail. Back and Next move between steps.
- [ ] **Moving around.** Drag anywhere on the map: the view moves, nothing on the map moves. Wheel and the + / − / Fit buttons zoom.
- [ ] **No slips.** Click a room, press Delete, Backspace and the arrow keys: nothing changes. Esc lets go of it.
- [ ] **Scale.** On a picture plan: Set it myself, click two ends of a written dimension, type its length: "The scale is set."
- [ ] **Read with AI** (needs credits, owner OK first): on the penthouse plan the walls follow the double lines, rooms fill between them with their names, doors sit in the gaps, the outline is the building edge. If the plan was not calibrated, a message says the size was found from a written measurement.
- [ ] **Rooms.** Click a room: rename it (Save name), change its type, Undo and Redo at the top. Join two rooms side by side; split one with two clicks across it; Remove a piece, then Undo.
- [ ] **Walls and doors.** Add wall with two clicks (it comes out straight). Select a wall, drag a round end handle (it snaps), drag the wall's middle (only the view moves). Add door: pick Entrance 3.0 m, click a wall.
- [ ] **Stores.** In Rooms press Place on map next to a store, click its room: "… is now on the map."; Show finds it again.
- [ ] **Publish.** Step 5 lists what is missing (for example "1 room has no name."); clicking it jumps to the room.
- [ ] **Advanced editing.** Switch, reload: the full editor stays. "Back to the easy editor" returns.
- [ ] **3D look.** Glass is see-through, doors have frames, entrances are in the accent colour, floors are tinted with an edge line.

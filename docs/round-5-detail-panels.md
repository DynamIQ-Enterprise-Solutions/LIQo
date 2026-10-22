# Round 5 — Detail panels instead of row menus

Status: **Done 2026-10-21.** Flutter analyze clean; 53 tests pass, the layout sweep opens one panel per list at 360/768/1024/1440 px. Multi-step flows (Assignments, Owners, Add branch, People) close the panel and open their own screen; everything else is inline. Checklist: TESTING.md, Round 5.
Requested 2026-10-21: remove the three-dot menu at the end of list rows; clicking a row opens a dashboard with everything the menu had, organised with clear separators and low cognitive load, and a clear design for dangerous actions.
Owner answers: **every list** in the app; the dashboard is a **side panel over the list**; dangerous actions live in a **separate Danger zone at the bottom with typed confirmation**. Second interview: typed name for **Deactivate, Remove, Release, Delete and Reset password** (all Danger zone); mall admins see **no Danger zone** on branches; for editing the owner asked for the best UX practice, and the choice made is **edit inside the panel** (fields replace the sections, Save and Cancel), so no dialog is ever stacked on top of the panel.

---

## 1. Goal

Rows stop hiding their actions behind a menu. Clicking a row opens a side panel that shows what the record is, what you can do with it, and, clearly apart, what would hurt. The same panel layout is used for every list, so once a person has seen one they know them all.

## 2. The panel (shared by every list)

```
┌──────────────────────────────────────────┐
│ ×  SM Mall of Asia            ● Active   │  header: name, status pills, close
│    SM Prime · Branch                     │  one line of context
├──────────────────────────────────────────┤
│ DETAILS                                  │  read-only facts, label + value rows
│ Address   Seaside Blvd …                 │
│ Hours     Mon–Sun 10:00–22:00            │
├──────────────────────────────────────────┤
│ ACTIONS                                  │  one button per action, full width,
│ [ Edit information ]                     │  with a one-line description under each
│ [ Map spaces ]  Link this store to …     │
├──────────────────────────────────────────┤
│ RELATED                                  │  links that leave the panel (People page,
│ Branches of this mall →                  │  filtered lists)
├──────────────────────────────────────────┤
│ ▌DANGER ZONE                             │  red outline, always last, collapsed label
│ ▌Deactivate this branch                  │  "What this does" text, red outlined button
│ ▌Hides 12 stores from … Nothing deleted. │
└──────────────────────────────────────────┘
```

Rules:
- Opens from the right, 480 px wide on desktop, full width on phones; the list stays visible and dimmed behind it. Close with ×, Escape, or clicking outside. The URL does not change.
- After any action that changes the record, the panel refreshes its data and the list behind it refreshes too.
- Rows show a small chevron on the right instead of the three-dot button, and the whole row is clickable (hover highlight already exists).
- Sections that would be empty are not shown (no empty "Related" header).
- Reactivate is not dangerous: it sits under Actions with a plain confirm.
- Edit happens inside the panel: the form replaces the sections, Save returns to the sections with fresh data, Cancel discards.
- **Danger zone** actions open a typed confirmation: the dialog explains the impact (counts from the impact endpoints where they exist), has Cancel as the default, and its red button stays disabled until the person types the record's name exactly.

## 3. What each list's panel contains

| List | Details | Actions | Related | Danger zone (typed) |
|---|---|---|---|---|
| **Malls** (superadmin, owner) | Name, status, number of branches, logo | Edit, Add branch (superadmin), Reactivate when inactive | People (superadmin), Branches of this mall | Deactivate |
| **Branches** | Mall, address, hours, phone, email, map status | Edit / Edit information, Reactivate | Stores of this branch | Deactivate |
| **Accounts** (superadmin, owner) | Email, role, access, reports to, last sign-in, temp-password and lock state | Edit details (in panel), Assignments, Reactivate | — | Reset password; Deactivate; **Release** (owner only) |
| **Stores** | Branch, category, hours, phone, email, spaces linked, owners | Edit, Map spaces, Owners, Reactivate | — | Deactivate |
| **Store owners** | Email, stores, status, last sign-in | Edit details (in panel), Assign a store, Reactivate | — | Reset password; Remove a store; Deactivate |
| **Option lists** | Kind, name, in use by N stores | Edit, Reactivate | — | Deactivate; Delete (refused with a message when in use) |
| **Announcements** | Full text, dates, branches, store, author, status, reviewer and reason | Edit, Approve, Reject (asks for a reason), Reactivate n/a | — | Delete |

Out of scope: the map editor's History dialog (not a list row menu) and the People page rows (they already show their actions inline; their Remove buttons get the typed confirmation too).

## 4. Changes

| Layer | File | Change |
|---|---|---|
| Frontend | `shared/widgets/detail_panel.dart` (new) | `showDetailPanel(context, builder)` side sheet; `PanelSection`, `DetailRow`, `ActionTile`, `DangerZone` widgets; `confirmDangerous(context, name:, title:, impact:, confirmLabel:)` typed confirmation. All overflow-safe, phone full-width. |
| Frontend | `shared/lists/list_scaffold.dart` | `rowActions` removed; `onRowTap` row shows a chevron; rows are focusable and open on Enter. |
| Frontend | each list view (malls, accounts, stores, owners, options, announcements) | Panel builder per record; menu code removed; existing edit dialogs reused. |
| Frontend | `features/malls/people_view.dart` | Remove buttons use the typed confirmation. |
| Frontend | tests | Panel widget tests (section 6.2); the layout sweep opens one panel per list at every width. |
| Backend | — | No change. Impact endpoints already exist for malls and branches. |
| Docs | TESTING.md, this file | Checklist; Done. |

## 5. Definition of done
1. No list in the app has a three-dot row menu; every row opens its panel; every former menu action is reachable from the panel in the section this document names.
2. Every dangerous action requires the typed name; the button is disabled until it matches; Cancel is the default.
3. `flutter analyze` clean; `flutter test` passes including the panel tests and the layout sweep with panels open at 360, 768, 1024 and 1440 px.
4. Manual checklist (6.3) passes with no exception in the Flutter log.

## 6. Tests

### 6.1 Backend — none.

### 6.2 Flutter
- Typed confirmation: button disabled, enabled only when the exact name is typed, Cancel by default, Escape closes without confirming.
- Panel renders Details, Actions and Danger zone for a sample mall, branch and account; empty sections are not rendered.
- Row tap opens the panel (fake API); the three-dot icon is not found anywhere.
- Sweep: for each list page, tap the first row and settle; no overflow at any width.

### 6.3 Manual (Chrome)
1. Malls → click SM Prime → panel: details, Edit, Add branch, People, Danger zone → Deactivate → dialog shows the branch and store counts, the button is grey until you type "SM Prime" → Deactivate → panel shows Inactive, Reactivate under Actions.
2. Branches → click a branch → Edit information works; Danger zone deactivate asks to type the branch name.
3. Account management → click an account → Assignments, Reset password (plain confirm), Danger zone Deactivate (typed). As a mall owner: Release is in the Danger zone.
4. Stores, Store owners, Option lists, Announcements: same pattern; Delete on an option in use is refused with the existing message; Delete on an announcement asks to type its title.
5. Phone width: the panel covers the screen, scrolls, closes with ×.

## 7. Open questions for the owner (answered 2026-10-21, see the top of this document)
1. **Typed confirmation scope** — typed name for Deactivate, Remove, Release and Delete (as proposed), or only for Delete?
2. **Reset password** — under Actions with a plain confirm (proposed), or in the Danger zone?
3. **Edit forms** — keep the existing edit dialogs opened from the panel (proposed, one step), or edit inside the panel itself (bigger change, two more weeks of layout work)?
4. **Branch panel for mall admins** — mall admins only edit branch information today; should their panel show the Danger zone at all (proposed: no, they cannot deactivate)?

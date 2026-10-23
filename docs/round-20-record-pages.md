# Round 20 — Record pages laid out like My account

Status: **Built 2026-10-23.** Flutter: analyze clean; 331 tests pass, 5 skipped. New: `test/record_pages_test.dart` (7). The backend is unchanged.

## Owner decisions (2026-10-23)
| Topic | Decision |
|---|---|
| Which pages | Account pages, mall and branch pages, store and store-owner pages, and the request and report pages (announcements, option values, profile change and AI credit requests, problem reports) |
| Header card | **Yes, where it fits**: people get their initials, malls and stores their logo (initials fallback), everything else an icon; then the name, a sub line, pills and one line of facts |
| Layout | First built as two columns like My account; the owner found the lists crowded, chose from four proposals: **A · short cards side by side in pairs under the header, every list full width below, the danger zone last**; one column at tablet width and below. (B tabs, C slim side panel, D original + header were not chosen.) |

## Shared pieces (`shared/widgets/detail_widgets.dart`)
- **`RecordHero`** with `HeroMark.initials / .logo / .icon`. My account's header card moved here; My account uses it too.
- **`DetailColumns(facts, lists, after)`:**
  - short cards in rows of two (an odd one out spans the full width);
  - lists full width below;
  - `after` holds the danger zone;
  - one column at tablet width and below.
  - `RecordRow` keeps its own rule, since lists are full width again.
- **`DetailScaffold.hero`:** while loading, the page shows a skeleton of the header card, a pair of short cards and a list.
- **`initialsOf(name)`.**

## Pages
| Page | Header card | Short cards (pairs) | Lists (full width) |
|---|---|---|---|
| Account | initials · name · email · role, status (+ temp password, locked, this is you) · created, last sign-in | Details · Pending profile change · Access · Sign-in · Reactivate · Your own account | Stores (store owners) |
| Mall | logo · name · status · branches, owners, mall admins | Details · Read only · Reactivate | Branches · Mall owners · Mall admins |
| Branch | mall logo · name · "Branch of …" · status · stores, map state | Details · Map · Reactivate | Stores at this branch |
| Store | logo · name · branch · mall · status, category · on the map, owners | Details · Map spaces · Reactivate | Owners |
| Store owner | initials · name · email · Store owner, status · stores | Details · Reactivate | Stores |
| Option value | list icon · name · list · status · sort order | Details · Used by · Reactivate | — |
| Announcement | megaphone · title · author, store · state · dates, branches | Details · Shared with other branches | Message · Review |
| Profile change | initials · person · "Profile change", role · status · sent | Change · Person | Decision |
| AI credit request | initials · admin · branch · "Asks for N credits", status · sent, has now | Request · Decision | — |
| Problem report | flag · subject · from / your report · kind, status · sent, page | Report | Conversation |

The danger zone (deactivate, reset, delete) stays the last thing on every page, full width.

## Note
- While switching to layout A, a script cut the shared card classes out of `detail_widgets.dart`; the file was restored from the compiler's cache (`build/test_cache`) and checked by the full test run.
- Running the formatter over the features folder split two `if` statements in the easy editor; they got braces (no change in behaviour).

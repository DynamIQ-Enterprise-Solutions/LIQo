# LIQo — Product Requirements Document

> **Version**: 1.0 | **Date**: 2026-10-22 | **Status**: Living document
> **Why**: this file · **How**: `LIQO_MASTER_BLUEPRINT.md` · **Where**: `FEATURE_PIPELINE.md`
> Written to `Engineering Standards.html` Appendix B.1. Sources: `USER_STORY(ADMIN).md` (US-001–US-047), the owner's decisions in `docs/round-*.md`, and the owner interview of 2026-10-22.

Sections are stable anchors (`PRD §6.7`). Append, never renumber. "Gabay" and "LIQo" are the same product.

## 1. Executive Summary

LIQo is indoor wayfinding for shopping malls. Mall staff keep each branch's indoor map, stores and announcements up to date in the LIQo admin platform; shoppers use the LIQo app to find any store, service or exit inside a large, multi-building mall. **Value: shoppers find their way, and the mall's own staff keep the map true without a drafting team.**

## 2. Product Vision

LIQo becomes the digital map layer of a mall group: one current map per branch, read from the mall's own floor plans with AI help, published to shoppers the moment it changes, later with live indoor positioning from Bluetooth beacons and a feed of mall and store posts.

**LIQo will NOT be:**
- a store point-of-sale, inventory or e-commerce system;
- a building-code, fire-safety or accessibility certification tool (map checks are physical validity only);
- a CAD or architectural drafting product (it reads plans; it does not produce construction drawings);
- an outdoor navigation app (only malls and maps LIQo provides);
- an advertising network (posts are planned, ads are not).

## 3. Target Users & Personas

| Persona | Core need | Working environment |
|---|---|---|
| **Superadmin** (Dynamiqes platform team) | Set up malls, branches and accounts; keep the platform safe and configured. | Desktop browser, office network. |
| **Mall owner** (role key `supervisor`) | Oversee the malls and branches they own and the admins who run them. | Desktop or laptop browser; occasional tablet. |
| **Mall admin** (one branch) | Keep their branch's stores, map and announcements current. | Desktop browser in the mall office; needs a wide screen for the map editor (≥ 900 px). |
| **Store owner** | See their stores and get their announcements approved. | Any browser, often a phone or tablet. |
| **Shopper** | Find a store, service or exit and get turn-by-turn directions inside the mall. | Android or iPhone inside the mall; mobile data or mall Wi-Fi may be weak. |

## 4. Problem Statement

- **Shoppers get lost** in large, multi-building malls. Mall staff answer directions by hand, and printed or static directories go out of date as stores move.
- **Maps are hard to keep current.** A mall's maps live as PDF or CAD files that only a draftsperson can change, so there is no single digital source that staff can update quickly.
- **Why now:** affordable BLE beacons (MOKO Smart H2) and AI that reads floor plans make a self-maintained indoor map practical for a mall's own staff.
- **Cost today:** *Open — owner to supply* (for example hours spent answering directions, cost of redrawing a directory, complaints).

## 5. Solution Overview

- **Access & administration** — sign-in, four admin roles, each seeing only its own malls, branches or stores; every change recorded.
- **Mall operations** — malls, branches, stores, store owners, option lists and announcements, managed by the people responsible for them.
- **Map designer** — a 2D editor with a live 3D preview for one map per branch: buildings, levels, walls, doors, rooms, facilities and connectors; drafts, checks, publishing and rollback.
- **Plan reading** — upload the mall's own plan (picture, PDF or CAD); AI proposes walls, doors and rooms; staff review before anything changes.
- **Insights** — dashboards and analytics per role.
- **Shopper app** — find places, get directions, saved places, in English and Tagalog; later live position from beacons.

## 6. Feature Requirements & Prioritization

Priority → pipeline tier: High → P0/P1, Medium → P2, Low → P3. Tiers confirmed by the owner on 2026-10-22.

### 6.1 Sign-in, roles and audit (Priority: High)
**Description:** People sign in with email and password and see only what their role and assignments allow. Every change and sign-in is recorded. [US-001–US-004, US-045, US-046]
**Acceptance criteria:**
- A deactivated or locked account cannot sign in and sees why; both outcomes appear in the audit log.
- A new account must change its temporary password before any other page opens.
- After the configured number of failed sign-ins the account is locked.
- A mall admin requesting another branch's data gets "access denied", and so does every role outside its scope.
- An admin can reset a password only within their scope; the new temporary password is shown once.
- Audit entries cannot be edited from any screen.
**Out of scope:** self-service "forgot password".

### 6.2 Superadmin administration (Priority: High)
**Description:** The superadmin registers malls and branches, creates accounts through step wizards, assigns mall owners, configures platform settings and reviews the audit log. [US-005–US-011]
**Acceptance criteria:**
- Only a superadmin can create a mall or a branch; registering a mall offers to add its first branch.
- Creating an account blocks a taken or inactive email while typing, and shows the temporary password once at the end.
- Deactivating a mall or branch first shows how many branches, stores and people it hides, and requires typing its name.
- A settings value outside its allowed range is refused with the setting's name.
- The audit log can be filtered by action, date range and user.
- A superadmin can deactivate, reactivate or reset another superadmin, but never leave zero active superadmins.
**Out of scope:** changing an account's role (§6.20).

### 6.3 Mall owner dashboard (Priority: High)
**Description:** A mall owner sees the malls and branches they own, the admins who report to them, read-only stores and maps, and scoped analytics. [US-012–US-015]
**Acceptance criteria:**
- An owner sees only assigned malls and branches, including ones they deactivated, and can reactivate those.
- An owner of a single branch cannot rename or deactivate the whole mall.
- An owner manages only the admins that report to them; who reports to whom is set automatically.
- An owner opens published maps read-only and can link to a branch's map.
**Out of scope:** creating malls or branches; editing maps.

### 6.4 Mall admin dashboard (Priority: High)
**Description:** A mall admin runs one branch: its information, stores, store-to-space links, store owners and option lists. [US-017–US-021, US-023]
**Acceptance criteria:**
- A mall admin sees and edits only their one branch.
- A store can be linked to several map spaces and a space to several stores, without changing the map.
- Adding a store owner by email gives an existing store owner the store; an inactive store owner is refused.
- A store owner left with no stores is deactivated automatically.
- An option value in use cannot be deleted, and changing it does not rewrite stores.
**Out of scope:** stores' own product or sales data.

### 6.5 Store owner dashboard (Priority: High)
**Description:** A store owner sees their own stores and submits announcements for approval. [US-024, US-025]
**Acceptance criteria:**
- A store owner sees only stores assigned to them.
- A submitted announcement shows "Waiting for review" until a mall admin approves or rejects it, and the owner sees the decision and reason.
**Out of scope:** store promotions; store analytics.

### 6.6 Announcements (Priority: High)
**Description:** Mall owners and mall admins publish announcements to branches in their scope; mall admins review store owners' submissions. [US-016, US-022, US-025, US-044]
**Acceptance criteria:**
- An announcement can target only branches in the author's scope and cannot be created already over.
- Only mall admins (or a superadmin) approve or reject store-owner submissions; rejection needs a reason.
- An announcement shared beyond someone's scope shows them only their own branches, and they can only take it off those.
- Pending, rejected, expired and out-of-scope announcements never show as active.
**Out of scope:** image upload (a link is used for now); delivery to shoppers (§6.14).

### 6.7 Map editor (Priority: High)
**Description:** A mall admin draws and maintains one map per branch with buildings, levels, walls, openings, spaces, facilities and connectors, then publishes it as a fixed version. [US-026–US-031, US-037–US-043]
**Acceptance criteria:**
- A branch has at most one map; buildings and levels can be placed, rotated and raised independently on one branch grid.
- A draft with problems can be saved; publishing is refused until every blocking problem is fixed, and the issue list leads to each problem.
- Only one person edits at a time; others can view; a stale save is refused, never merged.
- Each publish creates a fixed version; rollback creates a new version from an old one.
- Copying to another branch creates an independent map without store links.
- Undo and redo work for every edit; a drag or an applied AI proposal is one step; the edit history can be inspected.
**Out of scope:** building-code checks.

### 6.8 Profile change requests (Priority: High)
**Description:** People change their own name and email; non-superadmins need a superadmin's approval. [Round 8]
**Acceptance criteria:**
- A superadmin's own change applies at once; anyone else's waits for approval, one request at a time.
- An approved change applies fully or not at all; a rejected one shows the reason to the person.
**Out of scope:** changing one's own role or assignments.

### 6.9 Analytics (Priority: High)
**Description:** Overview cards and an analytics page per role, scoped like the lists, with charts and CSV export. [US-005, US-015, US-023]
**Acceptance criteria:**
- Every number on the page matches a hand count of the records in the viewer's scope.
- The period switch offers 7, 30 and 90 days.
- CSV export downloads the breakdown tables.
- Sign-in security figures are shown to the superadmin only.
**Out of scope:** shopper traffic, map views and searches (no data source until §6.14–§6.16).

### 6.10 Admin web look and feel (Priority: High)
**Description:** The admin platform follows the LIQO brand guidelines in dark and light mode and stays usable at every screen width.
**Acceptance criteria:**
- Every page renders without overflow from 360 to 1920 px wide, loaded and while loading.
- Switching theme blends every colour; reduced-motion settings stop all animation.
- Dangerous actions need the record's name typed.
**Out of scope:** a native desktop app.

### 6.11 Floor-plan upload (Priority: High)
**Description:** A mall admin uploads the branch's plan in a common format, places it under the map and sets its scale. [US-032, US-033]
**Acceptance criteria:**
- PNG, JPG, PDF (chosen page), TIFF, WebP, BMP, GIF, HEIC, SVG, DXF and DWG plans can be uploaded; other files are refused by content, not by name.
- A DXF or DWG with a known unit is placed at its exact scale without calibration.
- Any other plan is calibrated with two clicks on a known distance, and can be moved, rotated, faded and locked.
- An uploaded plan never appears in a published map.
**Out of scope:** editing the plan file itself.

### 6.12 AI floor-plan reading (Priority: High)
**Description:** AI reads an uploaded plan, or a boxed part of it, and proposes the outline, walls, doors and named rooms, matched to existing stores. [US-034, US-035]
**Acceptance criteria:**
- The result is a proposal that changes nothing until accepted; unsure pieces are marked.
- Accepting is one undo step; discarding leaves the map unchanged; nothing is ever published automatically.
- Every reading records its model and cost; an empty wallet or missing model is explained before reading.
- Each mall admin reads with credits of their own (a share of the wallet: 3 to start, at most 20), asks the superadmin for more, and the superadmin gives, takes back and monitors them in Analytics (Round 19).
- On a CAD plan, walls sit exactly on the drawing's lines.
**Out of scope:** reading plans in the browser without the server.

### 6.13 3D preview (Priority: High)
**Description:** A 3D view beside the 2D editor shows the map as it is edited. [US-036]
**Acceptance criteria:**
- A 2D edit appears in 3D without reloading.
- All levels are shown with the current one highlighted; pieces with problems are shown in the danger colour, never hidden.
- Without 3D support in the browser, a flat preview and a note are shown.
**Out of scope:** editing in 3D.

### 6.14 Shopper data service (Priority: High)
**Description:** A public, read-only service that gives the shopper app the LIQo directory, each branch's shopper package, live store info and out-of-service marks, approved announcements as posts, and receives anonymous counts (the shopper half of US-044). Decisions: `docs/shopper-hybrid-decisions.md`. [US-044, user-story open item 4]
**Acceptance criteria:**
- No sign-in; only published, active or approved data; never drafts, people or emails; rate-limited.
- Store hours per weekday with branch default and special days; store status set by mall admins or store owners; lifts and escalators can be marked out of service.
- Branch location comes from a pasted Google Maps link (short links followed).
- Announcements can carry one picture.
- Counts carry no person or device ID and are tagged by mall, branch and store.
**Out of scope:** shopper accounts; the role-analytics screens (§6.18).

### 6.15 Map publishing to the shopper app (Priority: High)
**Description:** When a mall admin publishes a map, a ready shopper package is built and phones pick it up safely. [user-story open item 4]
**Acceptance criteria:**
- Publishing builds an immutable, versioned package with a checksum, and is refused if any store or room can't be reached from an entrance or a connector end sits outside walkable area (problems listed in plain words).
- Publishing warns when spaces from the previous version will disappear.
- Phones check on opening; map updates download automatically on Wi-Fi and are offered on mobile data; an update found during a trip is switched in after it.
- A phone that can't read a newer package keeps its copy and asks to update the app.
**Out of scope:** background checks while the app is closed.

### 6.16 Shopper app (Priority: High)
**Description:** The LIQo app for Android and iPhone: pick a mall, search places, get turn-by-turn directions across levels, save places, English and Tagalog.
**Acceptance criteria:**
- A shopper can pick a mall, search a place and start directions to it.
- Directions cross levels by stairs, escalators or elevators and can avoid stairs or escalators.
- Saved places and route history stay on the phone.
- A downloaded mall works fully offline (map, search, directions, evacuation, store details as last saved); the internet only brings new malls, updates, posts and sends anonymous counts (`docs/shopper-hybrid-decisions.md`).
- The app follows the brand in dark, light and high-contrast modes.
**Out of scope:** accounts (look-only for now), live position (§6.19), a separate posts feature (§6.21; announcements serve as posts).

### 6.17 Pilot deployment (Priority: High)
**Description:** LIQo runs online, first for the owner's internal test (2026-10-23): web on Firebase Hosting (Spark), the API on a PC behind Cloudflare Tunnel, Firestore (Spark) as the deployed database, files on the server PC (Firebase Storage needs Blaze, later). Then for one mall group.
**Acceptance criteria:**
- The admin platform and API are reachable over HTTPS from the pilot mall offices.
- Uploaded plans survive a server restart.
- A deployment can be rolled back to the previous release.
**Out of scope:** multi-region hosting.

### 6.18 Role analytics redesign (Priority: Medium)
**Description:** What analytics each role sees, decided across web, backend and the shopper app. Owner planning in progress.
**Acceptance criteria:** *to be written after the owner's decisions.*
**Out of scope:** to be decided.

### 6.19 Beacon positioning (Priority: Medium)
**Description:** The shopper app shows the shopper's live position from MOKO Smart H2 beacons.
**Acceptance criteria:** *to be written after the owner's decisions.*
**Out of scope:** outdoor GPS.

### 6.20 Account role change (Priority: Low)
**Description:** A superadmin changes an existing account's role.
**Acceptance criteria:** *to be written when scheduled.*
**Out of scope:** —

### 6.21 Posts feed (Priority: Low)
**Description:** Stores, malls, mall owners and the superadmin post to a feed on the shopper app's Home. Build nothing until the owner asks.
**Acceptance criteria:** *to be written when scheduled.*
**Out of scope:** paid advertising.

## 7. Technical Requirements & Constraints

- **Deployment:** cloud. Web on Firebase Hosting, API on Cloud Run (it must run ODA File Converter), production database on Google Cloud, not yet chosen (`EXCEPTIONS.md` #1, #4). Local development on SQL Server.
- **Stack:** Node.js + Express + SQL Server, Flutter Web admin, Flutter mobile app; pinned versions in Blueprint Part 1.
- **Compliance:** Philippines Data Privacy Act of 2012 (RA 10173, National Privacy Commission); Google Play and Apple App Store rules for location and Bluetooth permissions.
- **Scale at launch:** pilot with one mall group: a few branches, tens of admins and store owners, a few thousand shoppers. Exact numbers: *open — owner to supply.*
- **Engineering baseline:** the company standard's document set, git repository and CI gates (FEATURE_PIPELINE P1-11).

## 8. Dependencies & Integration Points

| Dependency | Who | Needed for |
|---|---|---|
| IQGateway wallet top-up and model choice | Owner | Any AI reading (§6.12) |
| One paid sample reading of a real plan, approved by the owner | Owner | Tuning the AI prompt and cost |
| ODA File Converter installed (and in the server image) | Owner | DWG plans (§6.11, §6.17) |
| Real HEIC, TIFF, DWG and CAD plans to test in a browser | Owner / pilot mall | Proving §6.11 |
| Floor plans of the pilot mall's branches | Pilot mall group | Building the pilot maps |
| Shopper-API and map-sync decisions | Owner | §6.14, §6.15 |
| MOKO Smart H2 beacons and their placement | Owner / pilot mall | §6.19 |
| Production database choice and GCP project | Owner | §6.17 |
| Data Protection Officer named, retention periods for audit and AI cost records | Company / owner | RA 10173 (§7) |

## 9. Release Plan & Timeline

Mirrors Blueprint Part 5 row for row. No dates: a milestone ends when its gate passes.

| Milestone | Phase | Key deliverables | State |
|---|---|---|---|
| M1 | Foundation | Auth, sessions, lockout, roles and scope, audit, settings | Done |
| M2 | Role dashboards | Superadmin, mall owner, mall admin, store owner; announcements; profile requests; analytics; UI platform | Done |
| M3 | Map editor core | Geometry, openings, spaces, features, connectors, issues, lock, save, publish, versions, rollback, copy | In progress (undo-history view) |
| M4 | Plans, AI and 3D | Plan upload in all formats, AI reading via IQGateway, 3D preview | Built; waiting on owner steps |
| M5 | Engineering baseline | Git repo, CI gates, document set, test manuals, version currency | Planned |
| M6 | Shopper integration | Shopper API, map publish/sync to mobile, mobile app port | In progress / blocked on owner decisions |
| M7 | Pilot deployment | Firebase Hosting + Cloud Run + production DB, plan storage, runbook, one mall group | Planned |
| M8 | After pilot | Beacon positioning, role analytics redesign, posts feed, account role change | Planned |

## Open items

From `USER_STORY(ADMIN).md` "Items requiring confirmation":

| # | Item | State |
|---|---|---|
| 1 | Meaning of "rulings" | **Settled 2026-10-21:** physical validity only. |
| 2 | AI extraction scope | **Settled 2026-10-22 (Round 15):** AI reads outline, walls, doors and named rooms. |
| 3 | CAD conversion | **Settled 2026-10-22 (Round 16):** SVG, DXF, DWG supported. |
| 4 | Shopper integration contract | **Settled 2026-10-23:** `docs/shopper-hybrid-decisions.md` (§6.14, §6.15); endpoint names and the package format still to agree between the sessions. |
| 5 | Separate company / owner record | **Open.** |
| 6 | Detailed opening rules | **Partly settled 2026-10-21:** openings follow their host wall. Placement limits, shapes, dimensions and custom-property rules still open. |

Owner to supply: cost of the problem today (§4); exact launch scale (§7); retention periods for `audit_log` and AI cost records; the company's Data Protection Officer.

# Shopper app hybrid offline/online, shopper service, Firestore

Owner decisions of 2026-10-23, from interviews in the mobile session (liqo-62), with the web/backend session's (liqo-0a) review folded in. These settle user-story open item 4 (shopper integration). Pipeline: P1-06A, P1-07, P1-08, P1-09, P1-10.

## 1. Principle

Everything works offline for a downloaded mall. The internet only brings new malls, map updates, store info, out-of-service notices and posts, and it receives anonymous counts.

## 2. The app (LIQo mobile)

**Offline and online**
- A mall in the app is a **branch**. The picker groups branches under their mall.
- Picking a branch downloads its whole map and its stores once.
- Offline, everything for a downloaded branch works:
  - the map, search, routes, turn-by-turn, Find another way and evacuation;
  - store details as last saved;
  - saved places, routes and history;
  - the last-loaded posts.
- The release has no sample malls. They stay in the code for tests and debug builds.
- Saved places, routes and history stay on the phone. There are no accounts.

**Updates**
- When to check: when the app opens and when a saved mall opens, if online. There are no background checks.
- Map updates download automatically on Wi-Fi. On mobile data the app shows "Update available (size) · Update" and waits.
- Store info and out-of-service marks refresh separately on every check, on any network.
- A map update found during a trip is downloaded, but switched in after the trip ends.
- Branch switched off, or its map unpublished: the saved copy keeps working, marked "no longer updated by LIQo". It leaves the picker and can be deleted.
- Places and stores that disappear:
  - A place gone in a new version stays in Saved and History, greyed "no longer on the map", with directions off. It works again if the place comes back.
  - Saved **stores are kept by store id** and follow a store that moves. Other places are kept by space id.
  - A store on a space the phone's map doesn't have yet is listed with "Directions come with the next map update · Update now" (any network).
- Storage and first launch:
  - More › Saved malls lists each branch with its size, last update and Delete. Nothing is cleaned up on its own.
  - First launch offline shows "Connect once to download your mall", with Try again and an automatic retry.
  - An app that can't read a newer package format keeps its saved copy and asks to update. The server can mark an app version "must update".
- Offline notice: shown on Home's feed and the directory only, never on the map.

**Directory and search**
- A small LIQo directory always stays on the phone: every branch's name, address, location and hours, plus a store index (name, category, floor). It refreshes on every check.
- Search inside a mall shows only that mall. Outside a mall, results are grouped by store name, with the malls that have it under each (nearest first).

**Home and Map**
- With no mall picked:
  - Home shows What's on at LIQo malls, Find a store in any mall, Malls near you (top 3 and See all) and Get ready before you go.
  - The Map tab is the full mall chooser, with "Get there" opening Google Maps (Apple Maps on iPhone).
- With a mall picked, Home shows the mall first and the LIQo-wide sections below it.

**Being in a mall**
- Ways in: picking it, the phone's location being inside its area, beacons (later), or setting "Where are you?" there.
- **Confirmed visit:**
  - Location or beacons put you inside, or you answer "I'm here" to "Are you at <mall> now? · I'm here / Just looking".
  - A confirmed visit stays until you leave.
  - Not confirmed (picked at home, or "Just looking"): the real location wins when you're inside a mall.
- Area: a fixed 200 m around the branch pin.
- Overlapping malls: keep the current one, otherwise ask "Which mall are you in?".
- Leaving:
  - the "Leave <mall>" button, which asks before ending a trip;
  - location outside the area for a few minutes, counted only if location saw you inside, and waiting until any trip ends;
  - 6 h without opening the app.
- Leaving returns to the LIQo-wide Home. An evacuation always finishes first.
- Location permission is asked when first needed, and only used while the app is open.

**Posts**
- Posts are the existing announcements: approved, targeted to the branch, within their dates. What's on shows the same from every branch.
- Offline they behave like FB/IG: the last-loaded feed is shown, and posts past their end date disappear even offline.
- Pictures are cached up to 50 MB.
- Names, descriptions and posts show as written. Only the app's own words are translated.

**Anonymous counts**
- Always on, with no switch.
- What is counted:
  - places opened;
  - directions started and finished;
  - category and chip taps;
  - search words, trimmed and filtered for personal text;
  - app opens per mall.
- Each count is tagged with mall, branch and store, for each role's analytics. The analytics screens wait for the owner's role-analytics plan (P2-01).
- No person or device ID. Counts are queued offline and sent in batches.
- A privacy note goes on the last onboarding slide and in More › Privacy. The company's privacy text is needed before release (RA 10173).

## 3. Web and backend

- **Hours:** per weekday. A store without hours uses its branch's hours. Dated special days are closed or have different hours. All times are Philippine time. The old free-text hours stay as a read-only note until they are re-entered.
- **Store status:** Open / Temporarily closed / Being repaired / Opening soon, set by the mall admin or the **store owner**. Store owners get a new narrow, audited route limited to their own stores, plus a control on their store page. The app still gives directions whatever the status.
- **Out of service:** mall admins mark a lift, escalator or stairs. It is kept separately from map versions, keyed by branch and connector id, and reaches phones through the live refresh. Publishing a version without that connector clears the mark, noted in the audit log.
- **Branch location:** the admin pastes a Google Maps link. Short `maps.app.goo.gl` links are followed once on the server. The pin's place name is shown back to the admin to confirm. The numbers stay hidden.
- **Announcement pictures:** one optional picture per announcement, size-limited, stored with the floor plans.
- **Shopper package:**
  - Built at publish in the same transaction, by a pure module (`src/maps/shopper/`). It derives the walkway graph, which spaces each opening joins, store doors and the area around each connector end.
  - It is immutable, versioned, with a format version and a checksum.
  - **Publishing is refused** if any store or room can't be reached on foot from an entrance, or a connector end sits outside walkable area. Each problem is listed in plain words, including in the easy editor's Publish step.
  - Publishing **warns, without blocking,** when spaces from the previous version will disappear.
- **Shopper routes:**
  - public, read-only, mounted before the sign-in middleware;
  - never audited;
  - their own per-IP limiter, with a stricter limit, body cap and event cap on counts;
  - only published, active or approved data, never drafts, people or emails;
  - a written exception to the `utils/scope.js` rule.
- **Draft endpoints** (names still open):
  - `GET /api/shopper/directory`
  - `GET /api/shopper/branches/:id/package`
  - `GET /api/shopper/branches/:id/live`
  - `GET /api/shopper/posts`
  - `POST /api/shopper/counts`
  - `GET /api/shopper/app-config`
- Packages and posts are gzipped and size-limited, with ETags.

## 4. Deployment and database (owner, 2026-10-23)

- **Internal test:** the owner tests alone, with no customers yet. Real floor plans are allowed. The web app is on Firebase Hosting on the free **Spark** plan. Firestore (Spark) is the deployed database.
- **The server:** the Node/Express server runs on the owner's PC (or an office PC), exposed over HTTPS by **Cloudflare Tunnel**. There is no Cloud Run and no Cloud Functions. The own login stays (JWT, bcrypt, lockout, forced password change), with no Firebase Auth.
- **Phones:** they need to know the shopper API's address. A quick tunnel's address changes whenever the tunnel restarts, and a named tunnel with a domain stays fixed. **Open:** the owner is deciding this with the web/backend session. Until then, the app takes the address as a setting and assumes nothing. When the PC is off, phones keep working offline; updates and posts wait until it is back.
- **Files:** floor plans, announcement pictures and shopper packages stay on the server PC's disk during the internal test. Under the Firestore driver, map documents (drafts and published versions) are JSON files there too: `data/maps/<branch>/draft.json`, `versions/<n>.json`, with shopper packages beside them in `packages/<version>.json`. Only metadata (versions, publisher, lock, draft version, checksum) is kept in Firestore or SQL, so the 1 MB document limit never applies. Firebase Storage needs the Blaze plan (since February 2026), so it waits until real users come. Back the PC up.
- **Spark limits:** about 50k reads and 20k writes per day, 1 GB in total. Counts are pre-aggregated, and packages are not stored in Firestore.
- **This laptop:** SQL Server stays, so `src/repos/` gets a second, Firestore implementation behind the same interface.
- **Tests:** `npm test` runs the full suite against both SQL Server and the Firestore emulator, so neither copy drifts.
- **Data:** Firestore starts fresh from the seed. Nothing is copied from SQL Server.
- **Rules SQL Server enforces today move into code and are tested:**
  - unique emails;
  - at least one active superadmin;
  - links between malls, branches, stores and maps;
  - map version immutability.
- **Analytics on Firestore:** running totals instead of large scans, to keep reads (cost) down.
- **Order:** the Firestore data layer (P1-06A) comes before the shopper service, so the shopper parts are written once.
- **Standard:** a deviation from the company standard, recorded in `EXCEPTIONS.md` #1 and approved by the owner.

## 5. Order of work

Each step ends committed and pushed to `main` after full checks.

1. Firestore data layer, P1-06A (web/backend session).
2. Shopper service and web additions, P1-07 and P1-08 (web/backend session). The app's offline core can be built meanwhile against a fake server that follows the contract (mobile session).
3. App: offline core, Home and Map modes, posts, counts (P1-09).
4. Deployment, P1-10: Firebase Hosting (Spark) for the web, the server on a PC behind Cloudflare Tunnel. The named tunnel and domain are being asked of the owner by the web/backend session.

## 6. Still to agree between the sessions

- The app's package format: coordinates and units (metres, x/z), level order, and how connectors and one-way are encoded. The mobile session writes it, and the web/backend session reviews it.
- The exact refusal messages for unwalkable maps.

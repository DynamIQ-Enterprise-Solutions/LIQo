# Round 21 — Shopper service (P1-07) and map publishing to the app (P1-08)

Owner decisions of 2026-10-23 (`docs/shopper-hybrid-decisions.md` §2–§3, and the answers given while planning this round). The contract with the shopper app is `docs/shopper-package-format.md`, reviewed by both sessions. Step A (this record's first part) is built; step B (the package builder and the publish gate) follows.

## Owner answers in this round

- **Website:** not now. Shoppers see the phone number and the description.
- **Old free-text hours:** stay on the web as a read-only "Old hours note". Shoppers see that note only when neither the store nor its branch has hours (`hoursNote` in `/live`).
- **Announcement picture:** one uploaded picture replaces the image link field. Old links keep showing until the announcement is edited.
- **Store hours:** changed by the mall admin and by the store owner, like the store status.
- **Big screens:** the login stays one centred block (Round 11 note).

## Step A — web additions and the public shopper routes

### Data (migration 013, both databases)

| Table / column | What |
|---|---|
| `branches.hours_json`, `stores.hours_json` | `{week:[{day 1–7, open, close}], specials:[{date, closed \| open/close, note?}]}`, one shared zod rule in `utils/hours.js`. Philippine time, `HH:MM`, `"24:00"` is midnight, a close at or before the open runs past midnight, one range per weekday, at most 60 special days, notes up to 40 characters. |
| `stores.status` | `open`, `temporarily_closed`, `being_repaired`, `opening_soon` (default `open`). Directions are given whatever it is. |
| `branch_options.app_category` | The shopper app's category for a store category: `food`, `fashion`, `tech`, `books`, `services`, `other` (default `other`). |
| `branches.maps_link`, `branches.place_name` | The pasted Google Maps link and the pin's place name; latitude and longitude are filled from it and stay off the screens. |
| `announcements.image_key`, `image_mime` | The uploaded picture, stored as `uploads/pictures/<key>.png\|jpg` (`storage/files.js` `pictures`). |
| `connector_outages (branch_id, connector_id, since, marked_by)` | Lifts, escalators and stairs out of service, kept apart from map versions. |
| `shopper_counts (day, branch_id, event, store_id, dim, n)` | Anonymous per-day totals. `dim` is the place id, the category or the search word. On Firestore one document per day and branch (`shopper_counts/<day>_<branch>`), so a batch costs one write per branch. At most 500 search words per day and branch. |
| setting `app_must_update_below` | Shopper app builds below this number are asked to update (0 = none). In Settings under General as "Oldest shopper app build". |

### Admin routes and screens

| What | Route | Who | Screen |
|---|---|---|---|
| Store hours | `PUT /stores/:id/hours` `{hours \| null}` | mall admin; the store owner for their own active store | store page, Opening hours card (`shared/widgets/hours_card.dart`) |
| Store status | `PUT /stores/:id/status` `{status}` | the same | store page, "Status for shoppers"; store list and header show it when not Open |
| Branch hours | `PUT /branches/:id/hours` | mall owner, mall admin, superadmin (like the branch information) | branch page, Opening hours card |
| Location | `POST /branches/:id/location/check` (reads the link, saves nothing) and `PUT /branches/:id/location` `{mapsLink \| null}` | the same | branch page, Location card: paste, check, "Pin: <place>. Is this the branch?", save |
| App category | `PUT /options/:id/app-category` | mall admin | store category page |
| Out of service | `GET /maps/:branchId/connectors`, `PUT /maps/:branchId/connectors/:id/out-of-service` `{out}` | everyone in scope reads; mall admins change | branch page, "Lifts, escalators and stairs" |
| Picture | `POST`/`DELETE /announcements/:id/picture`, `GET` for the admin screens | whoever may change the announcement; a store owner's change goes back for review | announcement page, Picture card |

Every change is audited: `store_hours_updated`, `store_status_changed` (with the role), `branch_hours_updated`, `branch_location_updated`, `option_app_category_set`, `connector_out_of_service`, `connector_back_in_service`, `announcement_picture_set`, `announcement_picture_removed`, and at publish `connector_marks_cleared` when a marked connector is no longer on the map.

**The Google Maps link:**
- Full links are read as they are. Short `maps.app.goo.gl` and `goo.gl/maps` links are followed once (no other host, 5 s).
- The place's own pin (`!3d…!4d…`) wins over the view centre (`@lat,lng`); `q=` and `query=` with numbers also work.
- The place name comes from `/maps/place/<name>/`.
- A link to anything but Google Maps, or without a pin, is refused in plain words (`utils/mapsLink.js`).

**Pictures:** PNG or JPEG sniffed from the bytes, at most 2 MB and 4000 px per side. They are public (`/api/shopper/pictures/<key>`) only while their announcement is approved and not over.

### Public shopper routes (`src/routes/shopper.js`)

- Mounted at `/api/shopper` before the sign-in middleware. Never audited.
- Limits: their own per-IP limit (300 a minute; counts 30 a minute), a body of at most 256 KB and 500 events for counts.
- Only active branches of active malls with a published map, active stores, approved and live announcements. Never people, emails or drafts. This is the written exception to the `utils/scope.js` rule: shoppers have no scope, and the published-and-active filter is the scope.
- `ETag` on every read, `304` on `If-None-Match`; bodies over 1 KB are gzipped when the phone accepts it.

| Route | Answers |
|---|---|
| `GET /directory` | `{branches:[{id, name, mallId, mallName, address, lat, lng, active, hours, package, stores:[{storeId, name, category, floor}]}], generatedAt}`. `package` is null until step B. `floor` is the short label of the store's first space level in the published map (`maps/shopper/levels.js`: "Ground floor" → G, "Level 2" → 2, "Basement 1" → B1; a floor-label option of at most 3 characters that appears in the level name wins). Only stores with a space on the published map. |
| `GET /branches/:id/live` | §7 of the format: `branchHours`, stores with `spaceIds`, `category`, `status`, `hours`, optional `hoursNote`, `phone`, `description`, `logoUrl`, and `outOfService`. The ETag leaves out `generatedAt`. An unknown, inactive or unpublished branch answers `404 {error}`. |
| `GET /posts?branch=<id>` or `?scope=all` | §8: approved announcements live on today's Philippine date, newest first (start date, then id), 10 a page, an opaque `nextCursor`. `author` is the store (with its id) or the mall (its name). `imageUrl` is our picture's absolute URL, or an old link. |
| `GET /pictures/:key` | The picture, while its post is approved and not over. |
| `POST /counts` | §9, always `204`. Dropped without a word: an unknown type, a branch not in the directory, a day older than 30 days or more than 1 day ahead, `n` outside 1–10 000, and search words that are empty, look like an email or hold 4+ digits. A store not in the branch is counted without the store. |
| `GET /app-config` | `{mustUpdateBelow: <build> \| null, serverTime: "…+08:00", formatVersion: 1}`. |

### Tests
- Backend `test/shopper_service.test.js`: 11 tests, run on SQL Server and on the Firestore emulator.
- Web `test/round21_test.dart`: the editor at 360 and 1600 px, the store owner's limits, the location check and save, the out-of-service toggle, the App category, and the picture upload.
- The layout sweep's fake API now carries every new field with long values.

## Step B — the shopper package and the publish gate (P1-08)

### Contract corrections (agreed with the mobile session, folded into the format doc §1–§4)

1. **`enter` edges:** only an opening between indoors and outdoors is an `enter` edge. Every other door is a short `walk` edge as wide as the door.
2. **`through`:** carries the place (space) id.
3. **Levels:** editor levels at the same elevation are one package level, with `outlines: [{building, outer, holes}]`.
4. **No `walkway` hop type in format 1:**
   - a moving walkway on one level becomes `bridge` edges (one-way when the editor says so); an inclined one becomes an escalator hop;
   - editor bridges and walkways become `bridge` edges on one level, or `ramp` hops between levels.
5. **Exits:** also `entrance` features. Entrances in outer walls are also places (`cat: exit`).
6. **Encoding:**
   - fields at their default are left out;
   - opening `angle` is in radians;
   - hops carry `ctype`.
7. **Walkability:** decided by space type. The editor's walkable flag only switches a walkable type off. Connectors marked not walkable, and vehicle ramps, are left out.

### The builder (`src/maps/shopper/`, pure, no new dependency)

The builder works per editor level, in level metres, on a raster of 0.15–0.3 m cells (at most 6 M cells):

1. **Walkable area** (`area.js`):
   - the outline's free area plus the walkable spaces, minus the other spaces, the walls (with their thickness) and the blocking catalog features;
   - an exact distance transform;
   - **passable** means at least 0.3 m from anything, which closes small gaps in traced walls;
   - connected areas under 2 m² are dropped.
2. **Network** (`skeleton.js`):
   - Zhang–Suen thinning gives the centre lines, keeping loops around columns and kiosks;
   - dead ends shorter than about 1.5 m are pruned;
   - runs are straightened (0.25 m tolerance) and split so no edge is longer than 10 m;
   - an edge's width is twice the median clearance.
3. **Doors** (`network.js`):
   - Each opening's host wall is probed on both sides: a walkway, a room, the outside, a wall or nothing.
   - A room with no opening of its own gets "virtual doors" on its open edges, at most 4, each at least 0.8 m. So a unit drawn without walls is reachable, and a walled room without a door is refused.
   - Room-to-room doors join the other doors of the room they open into, marked as crossing it.
   - Stores and anchors with two or more doors at least 2 m apart get cut-throughs: inner nodes 1.5 m inside, walks across the floor at 1.25 × the distance.
   - A point joins the network by searching across walkable cells for the nearest centre line and splitting it there. The link is as wide as that walkway.
4. **Connectors:**
   - each stop is the nearest walkable cell within the endpoint's pad plus 1 m;
   - a one-way connector keeps its endpoint order; others are ordered low to high.
5. **Finalise:**
   - everything moves to the branch frame (the same transform as the 3D preview);
   - nodes snap to 0.1 m and equal positions merge, so the phone never merges silently;
   - nodes are numbered by (level, y, x), and every array is in a stable order. The same map always gives the same bytes.

### The gate (`gate.js`)

- **How reachability is found:** a flood from the entrances (entrance openings; entrance, exit and parking-entrance features), respecting one-way edges and not using cut-throughs. A room also counts as reached when the room its only door opens into is reached.
- **What blocks publishing** (plain words, each with the ids to select):
  - "{Level} has no corridor";
  - "{Level} can't be reached from an entrance: add stairs, an escalator or a lift that leads there";
  - "{Connector}, {Level}: the lift door isn't on a walkway";
  - "{Store} ({Unit}) can't be reached: it has no door to a corridor", "…its only door leads into another room that can't be reached" or "…the corridor outside it doesn't lead to an entrance";
  - a package over 20 MB.
- **What only warns:**
  - places shoppers may have saved that this version drops;
  - no way back from a place (one-way escalators);
  - an unnamed restroom without a door;
  - a space linked to more than one store.

### Publish, rollback and the routes

- **Publish and rollback** build the package before `maps.publish`. Problems refuse it (`400`, with `problems` as text and `problemDetails` with ids).
- **After the version is recorded:**
  - the package is stamped (version, Philippine publish time, SHA-256);
  - it is written once to `data/maps/<branch>/packages/<version>.json`, under both drivers;
  - it is recorded in `map_packages` (migration 014, and its Firestore twin).
  - If saving fails, the publish still stands and `packageError` says so; phones keep the previous version.
- **Out-of-service marks** of connectors no longer on the map are cleared, as in step A.
- **`POST /maps/:branchId/publish-check`:** the same build and gate without publishing, cached per draft version. Nothing is written or audited.
  - The easy editor's Publish step asks it once per saved draft and lists the problems (a click selects the room or connector) and the warnings.
  - The advanced editor runs it before the publish dialog and lists the results under Issues.
- **`GET /api/shopper/branches/:id/package?version=N`:** the bytes as built, with `ETag` and `X-Package-Checksum` as the SHA-256 of the un-gzipped bytes, `304`, and gzip on the wire.
- **`/directory`:** lists `package: {version, formatVersion, checksum, sizeBytes}` for the published version. Store floors are read from that package.
- **Deleting a map** removes its packages too.

### Tests and fixtures

- **Builder tests** (`test/shopper_package.test.js`, 12, pure):
  - a corridor with walled shops;
  - cut-throughs;
  - three levels with a lift and a one-way escalator, with level refusal and the no-way-back warning;
  - a rotated building checked against the 3D preview's transform;
  - unreachable shops (exact messages), a stop off the walkway, no corridor;
  - byte-identical builds;
  - the maps other tests publish;
  - places gone, and too big;
  - a large two-floor mall built in about 2 s.
- **Route tests:** `test/shopper_service.test.js` covers package download and the gate end to end, on SQL Server and on the Firestore emulator.
- **Fixtures for the mobile session:** `node tool/shopper-fixtures.mjs` writes `LIQo mobile/test/fixtures/published/<name>.json` and `.expect.json` (corridor, two-levels, rotated, doors). The expect files hold the start node, the node count, the reachable places, reference route totals, one-way edges and the places a wheelchair route cannot reach. A backend test fails when they are stale.
- **Web:** `round18_test.dart` checks that the Publish step lists what shoppers could not reach and that a click selects the room.

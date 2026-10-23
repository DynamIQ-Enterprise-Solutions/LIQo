# Shopper package format

What the server builds at publish (P1-08) and the phone downloads per branch and version. It was written by the mobile session and reviewed against the editor's catalog (`src/maps/catalog.js`) and validator by the web/backend session; the owner's answers are folded in (2026-10-23). Decisions behind it: `docs/shopper-hybrid-decisions.md`.

The phone draws the map from **section 2** and routes on **section 3** without any geometry work of its own. Everything that changes often (store names and hours, status, phone, logo, out of service) is **not** in the package; it comes from `/live`.

## 1. Envelope

```json
{
  "formatVersion": 1,
  "branchId": 12,
  "version": 7,
  "publishedAt": "2026-10-23T10:15:00+08:00",
  "units": "m",
  "levels": [ ... ],
  "spaces": [ ... ],
  "walls": [ ... ],
  "openings": [ ... ],
  "features": [ ... ],
  "graph": { "nodes": [ ... ], "edges": [ ... ] },
  "places": [ ... ],
  "connectors": [ ... ],
  "exits": [ ... ],
  "buildings": [ ... ],
  "bounds": [x1, y1, x2, y2]
}
```

**The envelope itself**
- `formatVersion` goes up only for changes an older app can't read. The app refuses a higher number than it knows, keeps its old copy and asks to update.
- **Checksum:** SHA-256 of the un-gzipped bytes. It travels in two places:
  - `/directory` carries `{branchId, version, formatVersion, checksum, sizeBytes}` per branch, so the app knows an update exists and how big it is (for the Wi-Fi / mobile-data rule);
  - `/package` sends `ETag` = checksum and `X-Package-Checksum`, and answers `If-None-Match`.

  The app checks the bytes before swapping the new copy in. The body is gzipped on the wire.
- **Order matters.** The app's routing breaks ties by insertion order, so the builder emits every array in a stable order (by id) for the same input. The same published map always gives the same bytes and the same routes on every phone.

**Coordinates and levels**
- **Units:** metres.
- **One branch-wide frame.** The editor's building origin and rotation and each level's offset and rotation are applied by the builder, so the app never sees per-building frames.
- **Axes:** `x` points east and `y` points south (downward on screen). The editor's `z` becomes `y`. The app reads `bounds` and fits the view itself.
- **Levels:** `levels` are ordered **lowest to highest**. A level's index in this array is the `lv` used everywhere else.

## 2. Drawing

**Levels**
```json
{ "id": "L1", "name": "Ground floor", "short": "G", "elev": 0, "height": 4.5, "ground": true,
  "outlines": [ { "building": "b1", "outer": [[x,y],...], "holes": [[[x,y],...]] } ] }
```
- Editor levels at the same elevation (to the centimetre) are **one package level**; `outlines` has one entry per building, and `outlines[].building` tells them apart. The level takes the first building's level name (buildings in id order).
- `ground` is worked out by the builder: the level whose elevation is closest to 0, the lowest one on a tie. Exactly one level has it.
- `short` is worked out from the name, at most 3 characters: "Ground floor" → `G`, "Level 2" → `2`, "Basement 1" → `B1`. A matching floor-label option wins if one exists. Owner: worked out, not an editor field.

**Spaces**
```json
{ "id": "sp_abc", "lv": 0, "name": "Unit 101", "type": "retail", "shape": [[x,y],...],
  "storeId": 345, "walkable": false, "outdoor": false, "label": [x,y] }
```
- One entry per space. `storeId` comes from `store_spaces`, or `null`.
- `type` is the editor's space type: retail, food, anchor, service, office, storage, atrium, corridor, restroom, parking, outdoor, custom.
- **Walkable:** corridor, atrium, outdoor and parking, plus each level's free area inside the outline. The editor's `walkable` flag defaults to true for every type, so it can only switch a walkable type off (an atrium void); it never makes a shop walkable.
- **Outdoor:** outdoor and parking.
- `label` is where the name is drawn: the centre of the polygon's largest inscribed area, or its centroid.

**Walls, openings and features**
```json
{ "lv": 0, "a": [x,y], "b": [x,y], "t": 0.2, "kind": "solid|glass|partition|boundary" }
{ "id": "op_1", "lv": 0, "kind": "door|entrance|gate|passage|shutter|window", "at": [x,y], "w": 1.8, "angle": 0.0, "walkable": true }
{ "id": "ft_1", "lv": 0, "type": "atm", "at": [x,y], "label": "ATM" }
```
- Wall `t` is the thickness.
- Opening `at` is the opening's centre, worked out from its host wall; `angle` is the host wall's direction in radians (`atan2` in package axes). `window` is drawn only (`walkable: false`); every other opening kind is walkable.
- Feature `type` is the editor's catalog key, so the app picks the icon. Every feature is drawn; only catalog features with `target: true` also become places (§3).

**Buildings**
```json
{ "id": "b1", "name": "Main Mall", "short": "Main", "levels": [0,1,2], "bounds": [x1,y1,x2,y2] }
```
These feed the Layers panel's "Go to" buttons and the whole-site view.

## 3. Routing

**Nodes**
```json
{ "id": "n12", "lv": 0, "x": 12.5, "y": 40.0, "out": false, "inner": false, "emergencyOnly": false }
```
- `out`: outdoors.
- `inner`: inside a store on a cut-through, never anyone's "nearest point".
- `emergencyOnly`: always `false` in format 1, because there are no fire-only stairs yet (owner: not now). The field is kept so a later version can use it without a format change.

**Edges** (listed once each)
```json
{ "a": "n12", "b": "n13", "kind": "walk|enter|bridge|hop", "len": 8.2, "cost": 8.2, "w": 3.0,
  "oneWay": false, "covered": false, "through": null, "conn": null, "label": null, "emergencyOnly": false }
```
- The app adds both directions unless `oneWay`, in which case only `a → b`.
- `len`: metres walked, 0 for a hop.
- `cost`: the routing cost. It equals `len` for a walk, is 1.25 × `len` across a store's floor, and is `null` for a hop, in which case the app uses its own per-type hop cost so routing tuning stays in one place.
- `w`: the walkway's width in metres.
- `through`: the **place (space) id** walked across (cut-throughs and room-to-room doors; the app leaves them out for step-free and evacuation routes). The store's name still shows, because `/live` renames places by `spaceIds`.
- `conn` and `ctype`: the connector id and its package type (`lift`, `escalator`, `stairs`, `ramp`), for hops; the app's hop cost needs `ctype`.
- **Fields at their default are left out** (`out`, `inner`, `emergencyOnly`, `oneWay`, `covered`, `through`, `conn`, `ctype`, `label`), as the app's own export does; a missing field means false or null.
- `label`: a bridge or entrance name, for directions.

**How the builder makes the walkways** (the details are the builder's)
- A network of centre-lines through walkable spaces and the free area of each level's outline. It doesn't have to be grid-aligned.
- An opening joins the two sides of its host wall (found by probing either side). **Only an opening between indoors and outdoors is an `enter` edge**, named for directions ("Go in/out through {label}"); every other door is a short `walk` edge with `w` = the door width.
- A store with two or more doors gets `through` edges across its floor.
- Each connector stop is a node joined to the walkway.

**Places**
```json
{ "id": "sp_abc", "storeId": 345, "lv": 0, "name": "Unit 101", "cat": "fashion", "type": "retail",
  "kind": "store|box|svc|zone|conn", "at": [x,y], "doors": [[x,y],...], "nodes": ["n40","n41"],
  "wing": "b1", "exit": false }
```
- One entry per thing a shopper can look up and go to: stores, named rooms, target features, parking zones and exits.
- `nodes` are the door nodes a route ends at. Saved places use `storeId` when there is one and `id` otherwise.
- `type` is the editor's space type or catalog key, for icons.
- **`cat`**, one of: `food`, `fashion`, `tech`, `books`, `services`, `other`, `restroom`, `atm`, `info`, `exit`, `parking`.
  - **A store:** the **App category** the mall admin set on that store-category option (owner decision: each store-category option on the web gets an App category pick from Food, Fashion, Tech, Books, Services, Other, defaulting to Other).
  - **A space with no store:** food → food, restroom → restroom, parking → parking, service → services, everything else → other. Office, storage and custom spaces become places only when they have a name.
  - **Target features:**
    - `restroom` → restroom;
    - `atm` → atm;
    - `info_desk`, `customer_service`, `concierge`, `directory_sign`, `lost_found` → info;
    - `entrance`, `exit`, `fire_exit` → exit;
    - `parking_entrance` → parking;
    - other target features (prayer room, nursing room, first aid, AED, security, charging, water fountain, locker, kiosk, taxi bay, bus stop, stage, play area, fountain, marker) → services.
  - Features with `target: false` (fire extinguisher, hose, seating, column and the like) are drawn only.
- A store's display name, hours and status come from `/live` by `storeId`. `name` is the space's own name, a fallback for a space with no store.

**Connectors**
```json
{ "id": "cn_1", "type": "lift|escalator|stairs|ramp|walkway", "name": "West lifts",
  "stops": [{ "lv": 0, "node": "n90" }, { "lv": 1, "node": "n91" }], "oneWay": false, "building": "b1" }
```
- **Types:** editor `elevator` → `lift`; `stairs`, `escalator` and `ramp` as they are. Format 1 has **no `walkway` type** (the app has no name for it yet): a moving walkway on one level becomes `bridge` edges (one-way when the editor says so), an inclined one an `escalator` hop. Editor `bridge` and `walkway` become `bridge` edges with a label on one level, or `ramp` hops between levels; they get no connector entry. `vehicle_ramp` and connectors marked not walkable are left out of the shopper graph.
- **`oneWay`** is a boolean. When `true`, the stops keep the editor's endpoint order and hops run from each stop to the next only, which covers escalators and same-level moving walkways. When `false`, the stops are ordered low to high and hops run both ways.
- Out-of-service marks come from `/live` by connector id; the app takes those hops out of routing and draws the connector crossed out.

**Exits**
```json
{ "id": "ex_1", "name": "Grand Court north doors", "node": "n5", "assembly": false }
```
- Ways out for evacuation: `entrance` openings on `boundary` walls (with a node just outside; they are also places with `cat: exit`), plus `entrance`, `exit` and `fire_exit` features (many hand-made maps have only an Entrance feature).
- `assembly_point` features are listed with `assembly: true` as places to head for once outside.

## 4. What the publish gate checks

Built by `LIQo backend/src/maps/shopper/` (Round 21). Each problem also carries the editor ids to select (`problemDetails: [{code, message, ids}]`), and `POST /api/maps/:branchId/publish-check` asks the same questions without publishing (the easy editor's Publish step).

Publishing is refused, with each problem listed in plain words, when:
1. A space linked to a store, or a named room, has no route on foot from any entrance. Entrances are `entrance` openings and `entrance`, `exit` and `parking_entrance` features. Example: "Uniqlo (Unit 101) can't be reached: it has no door to a corridor".
2. A connector stop sits outside walkable area. Example: "West lifts, level 2: the lift door isn't on a walkway".
3. A level has no walkway at all. Example: "Level 3 has no corridor".

Publishing **warns, without blocking,** when a space or store from the previous published version is missing ("3 places shoppers may have saved will be gone: …").

## 4a. Optional fields the app also reads

None are required; a package without them works.
- **Envelope:** `branchName` and `mallName` (otherwise the directory's).
- **Node:** `label` (an exit or entrance name, used in directions).
- **Edge:** `tech` (technical wording for a bridge).
- **Place:**
  - `rect` `[x1,y1,x2,y2]`, its bounding box, for highlighting;
  - `door`, the main door point, otherwise the first of `doors`;
  - `w`, the door width in metres (narrow doors are avoided by wheelchair routes);
  - `status`, used only until `/live` says otherwise.
- **`presets`:** hand-tuned camera presets and a demo trip. Only the built-in sample malls carry them; for a published map the app works them out from `bounds` and `buildings`, and there is no demo trip.

**Distinct positions.** The app keys walkway points by their position rounded to 0.1 m, so two nodes on the same level must not sit within 0.1 m of each other.

## 5. Size

A large branch is expected to be a few MB gzipped. Publishing is refused above **20 MB uncompressed**, with a clear message.

## 6. Settled

- Endpoint names as drafted in `docs/shopper-hybrid-decisions.md` §3.
- The checksum travels in both `/directory` and `/package` (see §1).
- Fire-only stairs: not now.
- Store category to app category: an App category pick per store-category option on the web.
- Floor short label and ground floor: worked out from the levels, with no editor field.

## 7. Live store info (`/live`, draft for review)

Separate from the package, because it changes far more often (owner decisions 2026-10-23). The app asks for it on every check, on any network, and keeps the last reply on the phone for offline use.

```
GET /api/shopper/branches/:id/live        ETag; answers 304 to If-None-Match
{
  "branchId": 12,
  "generatedAt": "2026-10-23T10:15:00+08:00",
  "branchHours": <Hours> | null,
  "stores": [
    { "storeId": 345, "spaceIds": ["sp_abc"], "name": "Uniqlo", "category": "fashion",
      "status": "open|temporarily_closed|being_repaired|opening_soon",
      "hours": <Hours> | null, "hoursNote": "10am-9pm daily", "phone": "+63 2 ...", "description": "...", "logoUrl": "https://..." }
  ],
  "outOfService": [ { "connectorId": "cn_1", "since": "2026-10-23T08:00:00+08:00" } ]
}

<Hours> = {
  "week":     [ { "day": 1, "open": "10:00", "close": "21:00" }, ... ],   // day 1 = Monday … 7 = Sunday; a missing day = closed that day; one range per day
  "specials": [ { "date": "2026-12-25", "closed": true, "note": "Holiday" },
                { "date": "2026-11-11", "open": "10:00", "close": "24:00", "note": "Midnight sale" } ]   // note optional, short
}
```

**Rules**
- **Times:**
  - Philippine time, 24-hour `HH:MM`.
  - `"24:00"` is midnight at the end of the day.
  - A `close` at or before `open` runs past midnight.
- **Special days** override the week on their date. `note` is optional and shown as written: "Closed today · Holiday".
- **A store with `hours: null`** uses `branchHours`. If both are null, the app shows no open/closed line (owner: fallback for now).
- **`status`** comes from the store's status on the web:
  - `temporarily_closed`, `being_repaired` and `opening_soon` show as such;
  - directions are still given whatever the status.
- **`category`** is the App category of the store's category option (Food, Fashion, Tech, Books, Services, Other), in lower case.
- **`spaceIds`** are the spaces the store occupies (`store_spaces`).
  - A store whose space isn't in the phone's package yet is listed with "Directions come with the next map update".
  - A store with no space at all is not sent.
- **`outOfService`** lists connector ids from the published map. Routes avoid them, and the map draws them crossed out.
- **No people, emails or drafts.** Only active stores of an active, published branch of an active mall.
- **`storeId`** is a number, the same as the package's `places[].storeId`, so saved stores match by plain equality.
- **`spaceIds`** are `store_spaces.space_key`, the layout space ids, so they match the package's `places[].id`.
- **One open/close range per day** (no split days such as a lunch break), the same on the web and in the app.
- **ETag:** a hash of the body without `generatedAt`, so an unchanged store list answers 304.
- **An inactive, unpublished or unknown branch** answers `404 {error}`. The app keeps its last copy and asks again only after the next directory refresh.
- **Optional fields:**
  - `hoursNote`: the store's old free-text hours, shown as written only when its `hours` and `branchHours` are both null (owner, 2026-10-23);
  - `logoUrl`, used from step 4 (the picture cache).
- **No website** for now (owner, 2026-10-23): shoppers see the phone and the description.

## 8. Posts (`/posts`, draft for review)

The approved announcements shoppers see (owner decisions 2026-10-23). Home shows them as a feed, newest first, 10 at a time.

```
GET /api/shopper/posts?branch=<id>&cursor=<opaque>      ETag on the first page; 304 on If-None-Match
GET /api/shopper/posts?scope=all&cursor=<opaque>        every branch (What's on, step 3)
{
  "items": [
    { "id": 812, "title": "50% off this weekend", "body": "…", "imageUrl": "https://…",
      "author": { "kind": "store", "storeId": 345, "name": "Uniqlo" },      // or { "kind": "mall", "name": "SM North EDSA" }
      "startsOn": "2026-10-23", "endsOn": "2026-10-26",
      "branch": { "id": 12, "name": "SM North EDSA", "mallName": "SM Malls" } }
  ],
  "nextCursor": "…" | null
}
```

**Rules**
- Only **approved** announcements targeted to that branch whose dates include today. "Today" is the Philippine date, and `endsOn` is inclusive.
- **Newest first** (by `startsOn`, then `id`), **10 per page**. With `scope=all`, one item per announcement per branch it targets.
- `author.storeId` is a number, the same as the package's and `/live`'s, so a store's post can offer Directions to that store.
- `imageUrl` is optional (the announcement's one picture). The text is shown as written.
- No reviewer names, reasons or drafts. A rejected, pending or expired announcement is never sent.

## 9. Anonymous counts (`/counts`, draft for review)

Always on (owner decision 2026-10-23). The phone adds them up per day and sends them in batches when online.

```
POST /api/shopper/counts        answers 204
{ "events": [ { "type": "place_opened", "branchId": 12, "storeId": 345, "placeId": "sp_abc", "day": "2026-10-23", "n": 3 },
              { "type": "category_tap", "branchId": 12, "category": "food", "day": "2026-10-23", "n": 5 },
              { "type": "search", "branchId": 12, "query": "uniqlo", "day": "2026-10-23", "n": 2 } ] }
```

**Rules**
- `type` is one of `place_opened`, `directions_started`, `directions_finished`, `category_tap`, `search` or `mall_opened`.
- **No person or device id**, and no IP kept with the counts.
- At most **500 events per batch**. A batch that can't be sent stays queued on the phone (capped), and resends are de-duplicated by the phone.
- **Search words** are cleaned on the phone before sending:
  - trimmed, lower case, at most 40 characters;
  - anything that looks like an email, or holds 4 or more digits (a phone number), is dropped.

  The server may filter again.
- The server adds them into per-day totals by branch, store and event, for each role's analytics (P2-01).

## 10. The directory's store list (for "Find a store in any mall", step 3)

Part of the `/directory` reply, refreshed with it, kept on the phone:

```
"branches": [ { "id": 12, …, "stores": [ { "storeId": 345, "name": "Uniqlo", "category": "fashion", "floor": "2" } ] } ]
```

- `floor` is the floor's short label (as in the package).
- `category` is the store's App category.
- Only active stores that are on the published map.

## 11. App settings (`/app-config`)

```
GET /api/shopper/app-config
{ "mustUpdateBelow": 7 | null, "serverTime": "2026-10-23T10:15:00+08:00", "formatVersion": 1 }
```

- **`mustUpdateBelow`** is an app **build number** (the `+N` of the app's version), set by a superadmin; 0 or none means `null`. An app whose build number is below it shows only "Please update LIQo" (rare, for serious problems).
- **`serverTime`** lets the app correct the phone's clock (differences under a minute are ignored) for opening hours and post end dates.
- **`formatVersion`** is the newest package format the server builds.

## 12. Finding the server (internal deployment)

Owner decision 2026-10-23: until a domain gives the server a fixed address, the server's address changes at every restart (a Cloudflare quick tunnel). The apps find it through a small file on the web app's own fixed address, which every server start updates:

```
GET https://liqo-12a80.web.app/config/api.json        Cache-Control: no-cache
{ "apiBase": "https://<random words>.trycloudflare.com", "updatedAt": "2026-10-23T18:30:00+08:00" }
```

- The shopper routes are at `<apiBase>/api/shopper/…`. The admin web app reads the same file.
- `apiBase` is a plain `https://host` with no path, query or trailing slash. Anything else is ignored.
- **When to read it:** when the app opens. Read it again whenever the server cannot be reached, then retry once. Remember the last good `apiBase` for when the file cannot be read.
- **When a domain exists,** the file will simply hold the fixed address, so nothing changes in the apps.

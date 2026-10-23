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
  "outline": { "outer": [[x,y],...], "holes": [[[x,y],...]] } }
```
- `ground` is worked out by the builder: the level whose elevation is closest to 0, the lowest one on a tie. Exactly one level has it.
- `short` is worked out from the name, at most 3 characters: "Ground floor" → `G`, "Level 2" → `2`, "Basement 1" → `B1`. A matching floor-label option wins if one exists. Owner: worked out, not an editor field.

**Spaces**
```json
{ "id": "sp_abc", "lv": 0, "name": "Unit 101", "type": "retail", "shape": [[x,y],...],
  "storeId": 345, "walkable": false, "outdoor": false, "label": [x,y] }
```
- One entry per space. `storeId` comes from `store_spaces`, or `null`.
- `type` is the editor's space type: retail, food, anchor, service, office, storage, atrium, corridor, restroom, parking, outdoor, custom.
- **Walkable:** corridor, atrium, outdoor and parking, plus each level's free area inside the outline.
- **Outdoor:** outdoor and parking.
- `label` is where the name is drawn: the centre of the polygon's largest inscribed area, or its centroid.

**Walls, openings and features**
```json
{ "lv": 0, "a": [x,y], "b": [x,y], "t": 0.2, "kind": "solid|glass|partition|boundary" }
{ "id": "op_1", "lv": 0, "kind": "door|entrance|gate|passage|shutter|window", "at": [x,y], "w": 1.8, "angle": 0.0, "walkable": true }
{ "id": "ft_1", "lv": 0, "type": "atm", "at": [x,y], "label": "ATM" }
```
- Wall `t` is the thickness.
- Opening `at` is the opening's centre, worked out from its host wall. `window` is drawn only (`walkable: false`); every other opening kind is walkable.
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
- `through`: the store id walked through (cut-throughs; the app leaves them out for step-free and evacuation routes).
- `conn`: the connector id, for hops.
- `label`: a bridge or entrance name, for directions.

**How the builder makes the walkways** (the details are the builder's)
- A network of centre-lines through walkable spaces and the free area of each level's outline. It doesn't have to be grid-aligned.
- Every walkable opening joins the two sides it connects with a short `enter` edge. The builder finds the sides by probing either side of the host wall.
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
- **Types:** editor `elevator` → `lift`, `moving_walkway` → `walkway`, `stairs`, `escalator` and `ramp` as they are. `bridge` is not a connector; it becomes `bridge` walk edges with a label. `vehicle_ramp` is left out of the shopper graph, because it is for cars.
- **`oneWay`** is a boolean. When `true`, the stops keep the editor's endpoint order and hops run from each stop to the next only, which covers escalators and same-level moving walkways. When `false`, the stops are ordered low to high and hops run both ways.
- Out-of-service marks come from `/live` by connector id; the app takes those hops out of routing and draws the connector crossed out.

**Exits**
```json
{ "id": "ex_1", "name": "Grand Court north doors", "node": "n5", "assembly": false }
```
- Ways out for evacuation: `entrance` openings on `boundary` walls, plus `exit` and `fire_exit` features, each with a node just outside.
- `assembly_point` features are listed with `assembly: true` as places to head for once outside.

## 4. What the publish gate checks

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
      "hours": <Hours> | null, "phone": "+63 2 ...", "website": "https://...", "description": "...", "logoUrl": "https://..." }
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
- **** is a number, the same as the package's `places[].storeId`, so saved stores match by plain equality.
- **** are `store_spaces.space_key`, the layout space ids, so they match the package's `places[].id`.
- **One open/close range per day** (no split days such as a lunch break), the same on the web and in the app.
- **ETag:** a hash of the body without `generatedAt`, so an unchanged store list answers 304.
- **An inactive, unpublished or unknown branch** answers `404 {error}`. The app keeps its last copy and asks again only after the next directory refresh.
- **Optional fields:**
  - `website`, until the owner decides on a website field;
  - `logoUrl`, used from step 4 (the picture cache);
  - `hoursNote`, waiting for the owner (the old free-text hours, shown only when `hours` and `branchHours` are both null).

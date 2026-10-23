# Shopper package format (draft for review)

What the server builds at publish (P1-08) and the phone downloads per branch and version. It is written by the mobile session for the web/backend session to review. Decisions behind it: `docs/shopper-hybrid-decisions.md`.

The phone draws the map from **section 2** and routes on **section 3** without any geometry work of its own. Everything shoppers see change often (hours, status, phone, logo, out of service) is **not** in the package; it comes from `/live`.

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
- **Checksum:** SHA-256 of the exact bytes served, sent with the metadata (`/package` headers or `/directory`). The app checks it before swapping the new copy in. The body is gzipped on the wire and the checksum covers the un-gzipped bytes.
- **Order matters.** The app's routing breaks ties by insertion order, so the builder must emit every array in a stable order (by id) for the same input. The same published map always gives the same bytes and the same routes on every phone.

**Coordinates and levels**
- **Units:** metres. Plan coordinates `x` (east) and `y` (south, downward on screen). The web's `z` becomes `y`. The plan origin is kept as in the editor; the app reads `bounds` and fits the view itself.
- **Levels:** `levels` are ordered **lowest to highest**. A level's index in this array is the `lv` used everywhere else.

## 2. Drawing

**Levels**
```json
{ "id": "L1", "name": "Ground floor", "short": "G", "elev": 0, "height": 4.5, "ground": true,
  "outline": { "outer": [[x,y],...], "holes": [[[x,y],...]] } }
```
- Exactly one level has `ground: true`.
- `short` is at most 3 characters, for the floor picker.

**Spaces**
```json
{ "id": "sp_abc", "lv": 0, "name": "Unit 101", "type": "retail", "shape": [[x,y],...],
  "storeId": 345, "walkable": false, "outdoor": false, "label": [x,y] }
```
- One entry per space.
- `storeId` comes from `store_spaces`, or `null`.
- `walkable` covers corridors and atria.
- `label` is where the name is drawn: the centre of the polygon's largest inscribed area, or its centroid.

**Walls, openings and features**
```json
{ "lv": 0, "a": [x,y], "b": [x,y], "t": 0.2, "kind": "solid|glass|partition" }
{ "id": "op_1", "lv": 0, "kind": "door|entrance|shutter|passage|gate", "at": [x,y], "w": 1.8, "angle": 0.0 }
{ "id": "ft_1", "lv": 0, "type": "restroom|atm|info|...", "at": [x,y], "label": "ATM" }
```
- Wall `t` is the thickness.
- Opening `at` is the opening's centre, already worked out from the host wall.
- Features are the editor catalog's facility and access types.

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
- `emergencyOnly`: used by evacuation only.

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

**How the builder makes the walkways** (agreed approach, details are the builder's)
- A network of centre-lines through walkable spaces and the free area of each level's outline. A straight-skeleton or medial-axis style path is fine; it does not have to be grid-aligned.
- Every opening joins the two sides it connects with a short `enter` edge.
- A store with two or more doors gets `through` edges across its floor, as today's sample malls do.
- Each connector stop is a node joined to the walkway.

**Places**
```json
{ "id": "sp_abc", "storeId": 345, "lv": 0, "name": "Unit 101", "cat": "fashion",
  "kind": "store|box|svc|zone|conn", "at": [x,y], "doors": [[x,y],...], "nodes": ["n40","n41"],
  "wing": "b1", "exit": false }
```
- One entry per thing a shopper can look up and go to: stores, rooms with a name, restrooms, ATMs, desks, parking zones and exits.
- `nodes` are the door nodes the route ends at. Saved places use `storeId` when there is one and `id` otherwise (decided).
- `cat` uses the app's categories: `food`, `fashion`, `tech`, `books`, `services`, `other`, `restroom`, `atm`, `info`, `exit`, `parking`. The mapping from the web's store categories and space types is agreed below.
- The store's display name, hours, status and so on come from `/live` by `storeId`. `name` is the space's own name, a fallback for a space with no store.

**Connectors**
```json
{ "id": "cn_1", "type": "lift|escalator|stairs|ramp|walkway", "name": "West lifts",
  "stops": [{ "lv": 0, "node": "n90" }, { "lv": 1, "node": "n91" }], "oneWay": null, "building": "b1",
  "emergencyOnly": false }
```
- `stops` are ordered low to high; hops join neighbouring stops.
- `oneWay` is `null` (both ways) or `"up"` / `"down"`, for escalators.
- Out-of-service marks come from `/live` by connector id; the app takes those hops out of routing and draws the connector crossed out.

**Exits**
```json
{ "id": "ex_1", "name": "Grand Court north doors", "node": "n5" }
```
Ways out for evacuation, each with a node just outside the door.

## 4. What the publish gate checks (decided rule, messages to agree)

Publishing is refused, with each problem listed in plain words, when:
1. A space linked to a store, or a named room, has no route on foot from any entrance (`kind: entrance` opening). Example: "Uniqlo (Unit 101) can't be reached: it has no door to a corridor".
2. A connector stop sits outside walkable area. Example: "West lifts, level 2: the lift door isn't on a walkway".
3. A level has no walkway at all. Example: "Level 3 has no corridor".

Publishing **warns, without blocking,** when a space or store from the previous published version is missing ("3 places shoppers may have saved will be gone: …").

## 5. Size

Gzipped, a large branch is expected to be a few MB. The server refuses to publish above a set limit, proposed at 20 MB uncompressed, with a clear message.

## 6. To agree (web/backend session)

- The category mapping: web store categories and space types to the app's `cat` values.
- Whether the editor has emergency-only (fire) stairs, as a connector flag or a stairs type.
- Which space types count as `walkable` and as `outdoor`.
- Endpoint naming, and whether the checksum travels in `/directory` or in `/package` headers (or both).

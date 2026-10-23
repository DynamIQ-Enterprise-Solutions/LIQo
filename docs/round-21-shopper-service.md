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

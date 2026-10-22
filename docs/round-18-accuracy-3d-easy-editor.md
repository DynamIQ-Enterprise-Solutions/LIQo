# Round 18 — Accurate AI maps, a nicer 3D look, and an editor anyone can use

Status: **Built 2026-10-22.**
- **Backend:** 128/128. New:
  - `test/measure.test.js`, 6 tests (the wall measurer on drawn plans);
  - `test/ai_measured.test.js`, 2 tests (measured walls kept, AI names the rooms, scale found from a dimension);
  - more cases in `test/map3d_model.test.js` (door frames, glass, floor finishes).
- **Flutter:** analyze clean; 294 tests pass, 5 skipped. New:
  - `test/round18_test.dart`, 27 tests;
  - sweep cases: the easy editor at 900, 1024, 1440 and 1920 px, every step.
- **Not yet done:** a live re-read of the real penthouse plan. It costs credits, so it waits for the owner's OK.

## Why
The owner read a real office plan (5000 × 3534 px, CAD export, walls as double lines) with GPT-5.1 and got 42, then 24, then 12 walls, 26 of them unsure. The owner said "not even close or accurate". The AI can only estimate lines to a few percent of the picture, much of the sheet is not building, and the AI drew rooms freehand.

The owner also found the 2D editor too hard: "a tiny mistake or click can ruin the whole thing … even a child would be able to use it".

## Owner decisions (2026-10-22)
| Topic | Decision |
|---|---|
| Accuracy | **Measured walls + AI names.** Walls are measured from the picture's pixels (or the CAD lines) inside "Read with AI"; the AI adds names, types, doors and glass. This changes the earlier "AI does everything", for walls only. |
| Rooms | **Shaped by the walls.** Each room is the area its walls enclose; the AI's name and type go to the room its label sits in. |
| Scale | **The AI finds it itself** from a written dimension on the plan. |
| "Realistic" | Accurate shapes **and** a nicer 3D look |
| Editor | **Guided steps** for everyone: ① Plan ② Scale ③ Read with AI ④ Rooms ⑤ Publish. The full tools stay under "Advanced editing". |
| Easy fixes | Remove a piece; add a door or entrance on a wall; join and split rooms; add a missing wall; drag a wall's end to adjust it; pick a store, then click its room. |

## A. Accurate readings (backend)
- **Measured walls** (`src/maps/measure.js`, `measurePlan`):
  - two parallel ink lines 6–28 cm apart, overlapping 0.5 m or more, make a wall, with its true thickness;
  - gaps of 0.6–2.6 m along a wall are doors;
  - desks, chairs, text and single dimension lines do not match that shape.
- **Scale first:** a wrong scale makes chairs look like walls. The AI reads one written dimension (two points and the millimetres); `scaleFromDimension` turns it into metres per pixel. The response carries `scaleFound`, and the editor applies it as its own Undo step. A plan calibrated by hand keeps its scale.
- **Merge** (`mergeMeasured` in `src/ai/floorplan.js`):
  - measured walls are sure;
  - AI glass and partition walls that no measured wall covers are added, trimmed to meet the measured walls;
  - anything outside the outline (+1 m) is dropped;
  - doors from the gaps and from the AI, duplicates within 0.5 m merged.
- **Fallback:** with fewer than 4 walls or 8 m measured, the AI's own walls are used, with a note.
- **Rooms from walls** (`roomsFromWalls`): the walls are filled on a fine grid, loose ends up to 0.7 m bridged, each closed area traced and tidied (`tidyRing`). `nameRooms` gives each the AI room that covers most of it; unmatched rooms stay unnamed and unsure. The outline is the edge of the whole inside.
- **CAD plans:** the CAD lines go through `snapToCad` (face pairs give centre and thickness), as in Round 16.

## B. Nicer 3D (`web/map3d/`)
- Glass walls are thin and see-through (a light tint).
- Doors get frames (two posts and a header); entrances are in the brand accent. Windows and passages have no frame.
- Room floors have a finish per type (corridor and atrium slightly glossy) and a thin edge line.
- Solid walls have soft outline edges; ACES tone mapping, a softer sky light and a fill light.
- The pure `model.js` builds all of it and is tested in Node.

## C. The easy editor (web)
- **Default for everyone.** The choice is remembered on the device (`map.editor.guided`). "Advanced editing" in the step bar opens the full editor; "Back to the easy editor" returns.
- **Step bar** (`guided/guided_editor.dart`, `GuidedStepBar`): the five steps (click any), **Undo** and **Redo**, and Advanced editing. Each step's panel (`GuidedPanel`) shows a short hint and **Back / Next**. No icon rail.
- **Moving around** (`map_canvas.dart`, guided mode):
  - a left drag anywhere moves the view; nothing on the map moves;
  - the wheel and the **+ / − / Fit** buttons zoom;
  - a click only selects.
- **Safe editing:**
  - only a selected wall's two round end handles drag; the end snaps to nearby walls and straight lines;
  - each tool does one thing and is then done;
  - Delete, Backspace, Enter and the arrow keys do nothing (they are kept from the page, so the keyboard focus stays on the map); Esc steps back (tool, then selection);
  - every change is one Undo; removing says "Removed. Undo (at the top) brings it back."
- **The steps:**
  1. **Plan:** upload or replace (all formats from Round 16).
  2. **Scale:** "The scale is set" or a guided two-click calibration ("Click the START… Now click its END… How long is it really?").
  3. **Read with AI:** one button, the credit line, the full-screen scan, then "The AI found …" with **Add to the map** or **Discard**. Adding moves on to Rooms.
  4. **Rooms:**
     - tools: **Add wall** (two clicks, snaps, straightened), **Add door** with sizes in words (Door 0.9 m, Double door 1.8 m, Entrance 3 m, Shop front 6 m), **Split a room** (two clicks across; a wall is placed on the cut);
     - the room card: Name (Save name), Type in plain words (Shop, Food & drink, Restroom…), **Join with a room next to it**, **Split in two**, **Remove**;
     - a wall card ("Drag one of its round ends") with **Add a door here**;
     - a searchable list of rooms and the branch's stores; **Place on map**, then click the room, links the store (the draft is saved first; the link is not part of Undo); **Show** finds a linked store's room.
  5. **Publish:** a checklist ("1 room has no name.", warnings, publish problems); each item jumps to the room. Then **Publish the map**.
- **Starting a new map** goes to step 2 (Scale) for a picture and straight to step 3 (Read with AI) for a drawing with an exact scale.
- **Join** (`mergeSpaces`): the two shapes are joined on a fine grid across the wall between them; that wall goes unless another room borders it. Rooms that do not touch are refused in plain words.

## Tests changed on purpose (decision, not a bug)
- **`test/round17_test.dart`** "a DXF starts the map … and opens Blueprint": runs in the full editor (`map.editor.guided: false`), because the easy editor is now the default and has no Blueprint tab. The easy-editor version is in `round18_test.dart` ("starting from a DXF goes straight to Read with AI").
- **`test/overflow_sweep_test.dart`**: the two older map-editor cases now set the full editor; the easy editor has its own case.

## Bug found by the tests
- In the easy editor the arrow keys went up to the page, which moved the keyboard focus off the map, so Esc stopped working afterwards. The editing keys are now kept by the map and do nothing.

## Not checked by machine
- The real penthouse plan has not been re-read with the new measurer through the gateway (it costs credits). Offline, at the right scale, the measurer follows its real walls; some gaps remain for the AI walls to close.
- Dragging, handles and the new 3D look need a look in the browser (TESTING Phase 17).

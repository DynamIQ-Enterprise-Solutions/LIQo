# Round 17 — Start a map from a plan, the AI scan, and the 3D preview

Status: **Built 2026-10-22.**
- **Backend:** 116/116. New:
  - `test/map3d_model.test.js`, 7 tests (the 3D geometry builder run in Node);
  - a no-outline create test in `maps_create.test.js`.
- **Flutter:** analyze clean; 262 tests pass, 5 skipped. New:
  - `test/round17_test.dart`, 10 tests;
  - sweep cases: the editor with 3D open and collapsed at 900, 1024, 1440 and 1920 px, and the scan dialog.

## Owner decisions (2026-10-22)
| Topic | Decision |
|---|---|
| Starting a map | **Upload the floor plan first**; "Create an empty map by hand" is the fallback link |
| Names | Defaults ("Main building", "Ground floor"), renamed later in Structure |
| First outline | **From the plan:** a DXF/DWG gets its exact size at once; a picture after calibration ("Make the floor the size of the plan") or the AI's outline |
| After upload | The Blueprint tab, plan placed. Reading with AI is still a click. |
| While reading | **A full-screen dialog**: the plan (or boxed part) with a scanning animation |
| When it ends | **New pieces draw themselves in** |
| 3D | **Always beside the canvas** (collapsible) |
| 3D content | Walls, doors, rooms; AI proposal; features; connectors; all levels stacked (current highlighted). Only the map: no people figures. |
| 3D control | Drag to turn, wheel to zoom, right-drag to slide, Reset view; editing stays in 2D |

## Starting a map from a plan
- **Server:** `POST /maps/:branchId` takes `outline: false`, which gives the first level no outline (`blankLayout`). A draft may lack one; publishing already warns.
- **Upload steps:** `map_editor/plan_upload.dart` (`PlanUpload`) holds them for both the Blueprint panel and the start screen:
  - the PDF page picker;
  - the browser conversion of TIFF, WebP, BMP, GIF and HEIC;
  - drawing uploads;
  - the unit question.
- **Start screen** (`_StartMap` in `map_editor_view.dart`):
  - "Start with your floor plan" with **Upload a floor plan**;
  - plans already uploaded for the branch can be used with **Start with this plan** (for example a drawing whose unit was left for later);
  - the "No plan? Create an empty map by hand" link opens the old form.
- **Order of steps:**
  1. The plan is uploaded first, so a bad file never leaves an empty map.
  2. The unit is asked if needed. "Later" makes no map.
  3. `createMap(outline: false)`, then open and lock.
  4. `placeBackdrop`; with an exact scale, `fitOutlineToBackdrop`.
  5. Save, `requestFit()`, and the Blueprint tab.
- **Canvas framing:** `EditorData.fitRequest` makes the canvas frame the level again, including the plan's picture. It frames again when the picture finishes loading and the level is still empty.

## The scan (`map_editor/ai_scan_dialog.dart`)
- **When:** `showAiScan` opens with "Read with AI" and "Add to proposal" and closes itself when the reading ends, whether it succeeds or fails. It cannot be dismissed while reading.
- **Shows:**
  - the plan picture, or only the boxed part, on a glass sheet (`GlassSurface`), shown dark in dark mode;
  - the reading grid (every 1/20, as the AI sees it), brighter near the line;
  - corner brackets;
  - a soft glow band with a bright line sweeping down and up (2.6 s);
  - the elapsed time;
  - "Nothing is added to the map until you review it."
- **No invented progress:** no steps or percentages are shown.
- **Reduced motion:** the line stands still, and nothing keeps animating.

## The draw-in (`map_canvas.dart`)
- **Animation:** a new proposal plays about 0.9 s. Walls grow from their start, rooms fade in after a quarter of the time, and doors and labels come last.
- **Only new pieces:** a merged section animates only its new pieces; dropping a piece animates nothing. With reduced motion everything appears at once.

## 3D preview (US-036)
- **three.js 0.186.1** (MIT) in `web/map3d/three/`. `OrbitControls.js` imports `./three.module.js`, so no import map is needed. Nothing loads from outside (EXCEPTIONS #2).
- **`web/map3d/model.js`** (pure; tested in Node) turns the document into shapes:
  - walls as boxes at the level height and their thickness, cut around doors, with lintels at 2.1 m and sills under windows;
  - the outline slab;
  - room floors in the canvas's type colours, with names on the current level;
  - features at their catalog size or their own `w/d/h`;
  - connector pads on each level plus a line between levels;
  - building origin and rotation, level offset, rotation and elevation;
  - the current level solid and the others faded;
  - the AI proposal in teal, unsure pieces amber, rising in;
  - pieces named in warnings in the danger colour (never hidden).
  - Each level has a fingerprint, so only changed levels are rebuilt.
- **`web/map3d/map3d.js`:**
  - soft hemisphere and sun light with a soft ground shadow, and the theme's background;
  - OrbitControls with damping (none with reduced motion) and Reset view;
  - it renders only when something changed;
  - **without WebGL**, a flat outline preview with "3D needs WebGL; showing a flat preview".
- **Flutter side:**
  - `map3d_panel.dart` (`map3dPayload`, `Map3dPanel`, `Map3dCollapsed`);
  - `map3d_host*.dart`: an `HtmlElementView` on the web and a placeholder in tests;
  - the scene follows edits at most every 150 ms.
- **Layout:**
  - canvas and 3D side by side under the level tabs, with a draggable divider (3D starts at 40%, 25–65%);
  - Collapse leaves a slim "3D preview" strip, remembered on the device (`map3d.collapsed`);
  - collapsed by default below 600 px for the pair, and always collapsed below 480 px.

## Tests changed on purpose (decision, not a bug)
- **`test/map_create_test.dart`:** the start screen now offers "Upload a floor plan" first, and the empty map comes from the "Create an empty map by hand" link, which the test now follows (owner decision 2026-10-22).

## Not checked by machine
- **Not in the tests:** the three.js scene and the real scan picture in the browser (the tests use a placeholder and no picture).
- **Where it has been checked:** the 3D geometry is tested in Node, and the app compiles and serves `web/map3d/`.
- **Still to look at in the browser:** turning, zooming and the rising walls (TESTING Phase 16).

## Fixes after the first use (2026-10-22)
- **Lag:**
  - a 31-megapixel plan was drawn in full every frame, and the dialog re-blurred the whole screen;
  - plans are now decoded once at screen size (`plan_image.dart`; the canvas at most 4096 px, the scan about 2048 px, more for a boxed part);
  - the real pixel size still drives every measurement;
  - the scan draws the still parts once and moves only a thin line layer;
  - the card keeps its glass look without a live blur.
- **Graceful errors:**
  - a failed reading stops the scan and the dialog says, in plain words, "The plan could not be read this time", with **Try again** and **Close**;
  - no raw provider text is shown;
  - "no credits were used" is said only when true.
- **Bug found by the tests:** Close and Try again waited for a frame that a still dialog never asked for; they now ask for it.

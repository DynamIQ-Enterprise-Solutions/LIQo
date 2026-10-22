# Round 16 — More plan formats: pictures, SVG, DXF, DWG

Status: **Built 2026-10-22.**
- **Backend:** 108/108. New: `test/plan_formats.test.js`, 11 tests, with a fake gateway and a fake ODA converter.
- **Flutter:** analyze clean; 246 tests pass, 5 skipped. New:
  - `test/round16_test.dart`, 6 tests;
  - the unit question in the layout sweep's dialogs.
- **Waiting on the owner:**
  - DWG needs ODA File Converter installed;
  - reading a CAD plan with AI needs gateway credits (the wallet was empty).

## Owner decisions (2026-10-22)
| Topic | Decision |
|---|---|
| Formats | More picture types (TIFF, WebP, BMP, GIF, HEIC), SVG, DXF, DWG |
| CAD and vector use | **Exact lines + AI for names** |
| Which lines are walls | **The AI does all the work.** No layer list for the admin. |
| DWG | **ODA File Converter** on our server |
| DXF without a unit | **The admin picks the unit** (mm, cm, m, in, ft). SVG keeps the two-click calibration. |
| HEIC | Bundle the LGPL-3.0 decoder with its licence |

## How each format is handled
| Format | Converted where | Shown as | Scale |
|---|---|---|---|
| PNG, JPG | — | the picture | two-click calibration |
| PDF | browser, pdf.js (Round 15) | PNG of one page | two-click calibration |
| WebP, BMP, GIF | browser (its own decoder; GIF: first frame) | PNG | two-click calibration |
| TIFF | browser, UTIF.js + pako (largest page) | PNG | two-click calibration |
| HEIC/HEIF | browser, libheif-js | PNG | two-click calibration |
| SVG | server (`src/maps/vector/svg.js`) | our own PNG | two-click calibration |
| DXF | server (`src/maps/vector/dxf.js`) | our own PNG | **exact** from `$INSUNITS`, or the unit the admin picks |
| DWG | server: ODA → DXF (`dwg.js`) | our own PNG | exact, as DXF |

### Pictures (browser)
- **Helper:** `web/plan_convert/convert.js`, our own module, loaded on first use with its decoders from the same folder; the licence texts sit beside them.
- **Size:** big pictures are shrunk to the server's limits (10 000 px a side, 50 megapixels).
- **Dart side:** `picture_convert.dart` (types and providers), with a web/stub pair like `pdf_open`.

### Drawings (server)
- **Detection:** the type is found from the bytes, never the name. DXF text starts with `0 / SECTION`; DWG with `AC10xx`; SVG has `<svg`. Binary DXF is refused with "save as ASCII DXF".
- **DXF:**
  - model space only;
  - LINE, (LW)POLYLINE with bulges, ARC, CIRCLE, ELLIPSE, SPLINE (fit or control points), SOLID and 3DFACE;
  - INSERT blocks expanded with nested place, scale and rotation, rows and columns; lines on layer 0 in a block take the insert's layer;
  - TEXT and MTEXT, with formatting codes removed;
  - y is turned to point down like a picture.
- **SVG:**
  - line, polyline, polygon, rect, circle, ellipse and path (curves become short pieces), all with group transforms;
  - a group's id or Inkscape label names its "layer";
  - `<text>`;
  - scripts, styles, defs, images and foreign content are skipped, and entities are not expanded;
  - the SVG is never served back to a browser.
- **DWG:**
  - ODA File Converter runs with `execFile` (no shell), a 3-minute limit and a temporary folder that is always removed;
  - the path comes from `ODA_FILE_CONVERTER` in `.env`; without it, DWG is refused: "save as DXF or PDF".
- **Limits:** 400 000 lines, 20 000 texts, 2 000 layers and 12 levels of nesting, then "too complex".
- **Drawing the picture** (`render.js`):
  - white paper, dark lines, no text (texts go to the AI as data);
  - about 50 px per metre when the unit is known, else 4000 px across;
  - at most 6000 px a side and 24 megapixels.
- **Kept beside the picture:** the original file and `<key>.vector.json` (lines and texts in picture pixels, layers with line counts, the scale).
- **Exact scale:** `mpp = metres per unit ÷ pixels per unit`.
- **Database:** `map_backdrops` gains `source_kind`, `source_file`, `units` and `mpp_from_units` (migration `011_plan_formats.sql`).
- **Unit route:** `PUT /maps/:branchId/backdrops/:key/unit {unit}` (DXF and DWG only) sets the unit and the exact scale; it is audited as `backdrop_unit_set`.
- **Deleting:** a plan's delete also removes its original drawing and its line data.

## Reading a CAD plan with AI
1. **The AI gets more:** the same reading as Round 15, plus the layer list (largest first, up to 100) and the drawing's texts inside the box on the 0–1000 grid (up to 300). The answer has a new field, `wallLayers`.
2. **`snapToCad()`** in `src/ai/floorplan.js`:
   - **Matching:** each AI wall takes the CAD lines that are near-parallel (within 4°), within 40 cm, and cover at least half of it. Lines on the AI's wall layers are preferred.
   - **Geometry from the drawing alone:**
     - two faces 6–28 cm apart give the centre line and the true thickness;
     - one face gives a wall on that line;
     - the direction and extent come from the drawing, kept within 50 cm of the AI's ends.
   - **Missed lines:** lines on the wall layers that no wall took become walls too, as face pairs or single lines of 1 m or more (partitions).
   - **Marks:** these walls are `exact` and sure. AI walls with no matching lines keep their own "sure" mark.
3. **Tidy-up:** exact walls are never moved sideways; others line up to them, and ends still close corners along their own line.
4. **Room names:** when a CAD text inside a room reads like the AI's name (0.8 or more), the drawing's spelling is used.
5. **Stats:** `exactWalls` is added.

## In the editor
- **Uploading:**
  - the picker offers png, jpg, jpeg, pdf, tif, tiff, webp, bmp, gif, heic, heif, svg, dxf and dwg;
  - a DXF or DWG with a unit is placed at its exact scale, centred on the level, with "Scale from the drawing (millimetres). Calibration is not needed.";
  - without a unit, "Which unit is this drawing in?" asks first; "Later" leaves it in the list with **Set unit**.
- **The uploads list** shows "DXF drawing", "SVG drawing" and so on.

## Security
- **SVG:** never served as SVG; XML entities are not expanded.
- **DWG converter:** no shell, a time limit, a temporary folder, and its own licence, accepted by the owner.
- **Bundled decoders:** served from the app; nothing loads from outside. Their licences are listed in `EXCEPTIONS.md` (#3, #4).

## Checked by hand outside the app
- **HEIC decoder API:** checked in Node. It decodes synchronously, and junk returns no images, which shows "could not be read".
- **TIFF decoder:** a TIFF round-trip through UTIF in Node keeps its pixels.
- **Not checked yet:** a real HEIC, TIFF, DWG or CAD reading in the browser. That needs the owner's files, ODA, and credits.

## Owner steps
1. **Install ODA File Converter** (free, from the Open Design Alliance; you accept its licence). Then set `ODA_FILE_CONVERTER` in `LIQo backend/.env` to the full path of `ODAFileConverter.exe`, and restart the backend.
2. **Top up the gateway wallet** before reading CAD plans with AI.
3. **Deploy:** see `EXCEPTIONS.md` #4 (Cloud Run with the converter; `xvfb-run` on Linux).

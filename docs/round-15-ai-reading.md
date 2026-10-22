# Round 15 — AI floor-plan reading through IQGateway

Status: **Built 2026-10-22, waiting for the key.** The owner adds the key and chooses the model before the first live reading.
- **Backend:** 97/97 tests. New:
  - `test/ai_reading.test.js`, 10 tests, against a fake gateway, so no credits are spent;
  - `test/floorplan.test.js`, 6 tests;
  - `test/image.test.js`, 3 tests.
- **Flutter:** analyze clean; 239 tests pass, 5 skipped. New:
  - `test/round15_test.dart`, 14 tests;
  - sweep cases for the editor with a proposal and for the PDF page picker.

## Owner decisions (2026-10-22)
| Topic | Decision |
|---|---|
| What the AI does | **Everything:** the floor outline, walls, doors and entrances, and rooms with names and types. Pieces it is unsure about are marked. |
| The old free "Detect" | **Replaced** by "Read with AI". The raster detector is removed. |
| Model | Read through IQGateway with the owner's key. **The gateway's model list is fetched first, then the owner chooses.** A superadmin can change it in Settings. |
| Extras | Match room names to existing stores; read part of a plan (box and sections); PDF floor plans; credit usage bar |
| Who | Mall admins of the branch (superadmins also pass) |
| Limits | **Only the gateway wallet** (balance and daily cap). The platform's "AI conversions per day" is no longer enforced. Every run is audited with its cost. |

## IQGateway in short
- **What it is:** one door to several AI providers (OpenAI, Anthropic, Gemini), billed to one wallet.
- **Calls:**
  - `POST https://iqlicense.dynamiqes.com/v1/chat/completions`, in OpenAI's format, with `Authorization: Bearer gws_…`;
  - the picture goes in as an `image_url` with a `data:` URL;
  - `response_format` asks for JSON.
- **Routing:** the `provider` field, else the model name (`gpt-*`, `claude-*`, `gemini-*`), else the gateway default.
- **Cost:** every answer carries `x_gateway {credits, usd}`.
- **Free helpers:** `GET /v1/models` (models for this key) and `GET /v1/quota` (balance, used, daily cap). Their formats are not documented, so the server reads them tolerantly (`normaliseModels`, `normaliseQuota`). Check them once the key is in.
- **Errors:**

  | Gateway | What people see |
  |---|---|
  | 401 | "key refused" (502) |
  | 402 | "credits used up" (402) |
  | 500 | "no provider for this model" (502) |
  | 502 | "failed or timed out" (502) |

## How a reading works
1. **Prepare.** The mall admin uploads a plan (PNG, JPG, or a PDF page), places it, calibrates it and saves; the server reads the calibration from the saved draft. The plan is read whole, or a part is boxed on the canvas.
2. **Picture.** The server (`src/ai/floorplan.js`):
   - cuts out the box;
   - shrinks it to at most 2000 px, keeping thin lines dark;
   - draws a light red reference grid every 50 of 1000 units, labelled every 100 (spec §10.1).
3. **Request.** The server sends the gateway:
   - the picture;
   - its real size in metres;
   - the branch's store names (for spelling only);
   - a strict JSON schema: `isFloorPlan`, `outline`, `walls{kind, sure}`, `doors{kind, sure}`, `rooms{name, type, polygon, sure}`, `notes`.
4. **Check the answer.** zod checks it. If it is not readable JSON, the server retries once; both calls are recorded. A cut-off answer gets "read it section by section".
5. **Tidy up (spec §10.4).**
   - Drop walls under 30 cm.
   - Put near-straight walls (within 4°) on shared exact lines.
   - Close corners and T-junctions within 25 cm along each wall's own line.
   - Merge copies of the same wall.
   - Put doors on the nearest wall within 60 cm.
   - Keep rooms of 1 m² or more.
   - Map the result through the backdrop calibration into level metres.
6. **Validate.** The result is checked inside a copy of the draft (`validateLayout`); pieces that could not be saved are dropped.
7. **Match stores.** Room names are matched to the branch's active stores: case, accents and punctuation are ignored, and a name contained in another or a small spelling slip still counts (0.8 or more).
8. **Record.** The reading is recorded in `map_conversions` (model, credits, USD, box) and audited as `map_converted`, or `map_convert_failed` when a paid call failed.

## In the editor (Blueprint tab)
- **Credit bar** (`/ai/status`), or the reason reading is not possible yet (no key, no model).
- **Box a part:** drag a box over the plan; Esc cancels. Then "Read with AI", or "Add to proposal" to merge another section. Walls already proposed (both ends within 30 cm) and rooms already proposed are not doubled.
- **The proposal:**
  - teal on the canvas, with unsure pieces dashed in amber;
  - room names, and "→ store" for matches;
  - the outline dashed;
  - clicking a piece drops it.
- **Review:** walls, doors, rooms, the floor outline (on by default only when the level has none) and "Link matched stores".
- **Add to floor:** one undo step. Ticked matches are linked after the draft saves. Store links live outside the map, so Undo does not remove them.
- **PDF:** pick the page (with a preview); it is rendered to a 5000 px PNG in the browser by pdf.js 5.7.284, bundled in `web/pdfjs` (no outside script; `isEvalSupported: false`), then uploaded as usual.

## Settings (superadmin)
- **"AI floor-plan reading" card:**
  - model dropdown filled from the gateway (`GET /ai/models`; `PUT /ai/model` checks that the choice is offered and audits `ai_model_changed`);
  - credit bar;
  - a clear note when the key is missing.
- **Removed:** "AI conversions per day".

## Security
- The key is only `IQ_GATEWAY_KEY` in `LIQo backend/.env`, read in `src/config.js`. It is never in responses, logs, audit details or the web app; the tests check this.
- The browser talks only to our server: `/ai/*` and `/maps/:id/backdrops/:key/convert`.

## Files
- **Backend:**
  - `src/ai/gateway.js`, `src/ai/floorplan.js`, `src/routes/ai.js`;
  - `src/routes/backdrops.js` (convert reworked);
  - `src/maps/image.js` (the image helpers kept from the removed `detect.js`);
  - migration `010_ai_reading.sql`;
  - `repos/settings.js` (`ai_model`, `getText`), `repos/backdrops.js`, `repos/stores.js` (`namesForBranch`).
- **Web:**
  - `features/ai/` (service, credit bar, settings card);
  - `map_editor/blueprint_panel.dart`, `editor_state.dart`, `map_canvas.dart`, `maps_service.dart` (Proposal, StoreMatch, AiCost);
  - `map_models.dart` (`Backdrop.toLevel/toPicture/boxFor`);
  - `pdf_document.dart`, `pdf_open*.dart`, `web/pdfjs/`;
  - `Pal.aiProposal*`, `Pal.aiUnsure`.

## Tests changed on purpose (decisions, not bugs)
- `test/detect.test.js` was removed with the detector, because the owner replaced Detect with AI. Its picture checks (type and size) moved to `test/image.test.js`.
- The fake API no longer lists the daily cap as a setting.

## Fixed along the way
- The proposal card painted a coloured box behind its checkbox rows (a Flutter assertion; their ink was hidden). It is now a Material surface.

## Gateway formats seen with the owner's key (2026-10-22)
- `GET /v1/models`: OpenAI's list plus `type` (chat, image, audio, realtime), `label` and `available`. Only **available chat** models can read a plan, so Settings offers only those (`readingModels`). That day: GPT-5.1, GPT-5, GPT-5 mini, GPT-5 nano, GPT-4.1, GPT-4.1 mini, GPT-4o, GPT-4o mini, o1, Gemini 3.5 Flash Lite and Gemini 3.1 Flash Lite. Claude Sonnet 5 was listed but marked not available.
- `GET /v1/quota`: `{enforced, blocked, reason, balance, daily:{usedTokens, limitTokens, usedCredits, limitCredits}}`. The panel and Settings show the gateway's own `reason` when `blocked`, and "Read with AI" stays off. A daily credit limit of 0 is shown as no cap.
- That day the wallet was **0 credits, blocked**: "Out of AI credits. Contact your administrator to top up."
- The key does not start with `gws_` like the doc's examples, but the gateway accepts it.

## Still to do (needs the owner)
1. ~~Add `IQ_GATEWAY_KEY` to `LIQo backend/.env`~~ (done 2026-10-22; the backend has been restarted).
2. Settings → choose the model from the gateway's list. Check that the list and the credit bar read correctly, since those formats are undocumented.
3. Top up the gateway wallet (it is empty), then one paid sample reading of a real plan, with the owner's OK, to tune the prompt and see the cost.

## Findings from the first real readings (2026-10-22)
- **Gemini 3.5 Flash Lite** (listed as available) refuses **every** request through the gateway, even a bare "Say hi", with 500 "Request contains an invalid argument." This is a gateway or provider issue, not our request. **Gemini 3.1 Flash Lite** works, including with our reading format. Four owner-approved probe calls cost 0.0643 credits in total.
- **The gateway's 500** also carries provider refusals, not only "no provider key". Its own words now decide the message. People see plain words; the raw text goes to the server log.
- **Answer format by model:** OpenAI models get the strict schema. Others get a relaxed schema (no `additionalProperties`), with plain JSON as the fallback when a format is refused (`responseFormats`).
- **Cost fields** are `x_gateway.creditsCharged` and `costUSD` (the docs said `credits`/`usd`); both are read now.
- **Server log:** every refused gateway call and every failed reading leaves one line in it, without the key.

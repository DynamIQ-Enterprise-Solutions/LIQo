# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workspace layout

Git repository, public: https://github.com/DynamIQ-Enterprise-Solutions/LIQo (branch `main`). After cloning, run `git config core.hooksPath .githooks` once; the pre-commit hook refuses `.env` files and anything under `LIQo backend/uploads/`. Never commit secrets or client data, and never commit or push without the owner's approval. The root `.gitignore` also keeps the company-internal and third-party documents below (and the brand source images) out of the repository; they exist only in local copies. Apps plus planning docs at the root:

- `LIQo backend/` — Node 24 + Express + SQL Server API. Port 3000. Local DB `liqo`, SQL login `liqo_app`.
- `LIQo web/` — Flutter Web admin dashboard (package `gabay_admin`). Riverpod + go_router + dio.
- `LIQo mobile/` — Flutter shopper app (package `liqo_mobile`, Android + iOS): indoor wayfinding, offline with three sample malls until admin maps and beacons arrive. Riverpod 3 + go_router. See "LIQo mobile" below.
- `USER_STORY(ADMIN).md` — the requirements (47 stories, 10 epics, open items at the end).
- `OFFICE_MAP_DESIGNER_SPEC.md` — map-designer spec ported from another system. Revise against the user stories before using it; close gaps by asking the user.
- `Engineering Standards.html` — company standard. The local DB (SQL Server) matches it. `EXCEPTIONS.md` notes the planned Firebase deployment.
- `LIQO_PRD.md` (why), `LIQO_MASTER_BLUEPRINT.md` (how), `FEATURE_PIPELINE.md` (where each feature stands, what is next). Read the Blueprint before schema or architecture work. Move the pipeline entry, and the Blueprint and PRD where they change, in the same change as the code (pipeline §5). All three have live team pages: PRD https://claude.ai/artifact/BgKuNBKJBDx4jKJ5BnfXto, Blueprint https://claude.ai/artifact/TioJyWUxE2KA2VRRL9NtJ1, pipeline https://claude.ai/artifact/8QeFNHg6Xhp1jSQaMsSUx1. `tool/doc-data.mjs` (PRD, Blueprint → `doc/current`) and `tool/pipeline-data.mjs` (pipeline → `pipeline/current`) build their data; the PostToolUse hook in `.claude/settings.json` (`tool/pipeline-hook.mjs`) rebuilds it after each edit of those files and says how to push it with ArtifactData `set`. After a hand edit, run the script (`node tool/doc-data.mjs prd|blueprint`, `node tool/pipeline-data.mjs`) and push the same way.

"Gabay" and "LIQo" are the same product.

## Commands

```bash
# backend (inside "LIQo backend")
npm install
npm run migrate        # applies src/db/migrations/*.sql in order
npm run seed           # superadmin admin@liqo.local / Admin@123
npm run dev            # node --watch, http://localhost:3000
npm test               # node --test test/

# frontend (inside "LIQo web")
flutter pub get
flutter run -d chrome  # API base defaults to http://localhost:3000, override with --dart-define=API_BASE=...
flutter analyze
flutter test
```

Verification before reporting a task done: backend starts and prints "listening on 3000", `flutter analyze` has zero issues, `npm test` and `flutter test` pass. If a test fails, fix the code, not the test.

Brand rule: the reference is `LIQO Brand Guidelines Presentation.png` (it replaced the old brand board on 2026-10-22): dark mode "Obsidian", light mode its inversion, tokens only in `lib/core/theme.dart` (`Pal`), Manrope font. Logos, tiles, the IQ mark and tab/install icons in `assets/brand` and `web/` are generated only by `node "LIQo web/tool/crop_brand.mjs"` (matted edges, transparent holes, analytic tile masks, same letter size in both modes, 2 px margins; see `docs/round-12-brand-guidelines.md`); never edit them by hand. The mark is "IQ"; the tagline is "Smart Way Forward". Lists have no row menus: rows open the record's own page (routes in `core/router.dart` `_detailRoutes`), laid out like the People page with `shared/widgets/detail_widgets.dart`: `DetailScaffold` (Back + actions), one `DetailCard` per section, `RecordRow` for rows inside cards, inline edit via `AppFormBody`, and a `DangerZone` last whose actions use the typed confirmation (`confirmDangerous`). Owners and admins of a mall are managed on the mall page itself (no separate People page). Mall owners change a mall only if they own the whole mall (`assertWholeMallOwner`); owners of single branches see it read-only. Owners keep seeing their own inactive malls and branches, and read (never write) their stores and published maps (`resolveScope(user, { includeInactive: true })` on those read routes; it only widens a mall owner's scope). Store-owner announcements are reviewed by mall admins only. A shared announcement (targets inside and outside someone's scope) shows each manager only their own branches; only its author, someone covering all targets or a superadmin changes it; others can only take it off their branches (`managerAccess`/`present` in `routes/announcements.js`). Audit actions are shown through `shared/widgets/action_label.dart`. Decisions in `docs/round-14-mall-owner-gaps.md`. A superadmin may deactivate, reactivate and reset another superadmin (never edit their details; at least one active superadmin always remains, enforced in SQL). People change their own name and email from My account: a superadmin at once, everyone else through a profile change request that a superadmin approves on Profile requests (one waiting request per person, `profile_requests`). Branch latitude/longitude stay in the API but are hidden from screens. Charts animate when scrolled into view (`RevealOnScroll`). Accounts are created only through the step wizards (`create_account_wizard.dart`, `store_owner_wizard.dart`, frame in `shared/forms/wizard_dialog.dart`): the step bar shows every step, `GET /accounts/check` runs while typing, a taken or inactive email blocks Next, a repeated name, an email waiting in a profile change request and a branch that already has admins only warn, holder details go to a superadmin only, an inactive store owner is refused, closing after typing asks to discard, and the temporary password shows on the Done step (decisions in `docs/round-10-create-wizard.md`). The login page (`features/auth/login_view.dart`, `login_features.dart`) is the form in its own raised card beside a feature carousel (4 slides, drawn illustrations with generic placeholders, never live data, 6 s auto-advance that stops after a pick and never runs with reduced motion); at 1050 px and below it stacks form then carousel; a living background, a faint IQ watermark and a travelling edge light (`login_ambience.dart`) run on one 24 s clock and stop with reduced motion, so tests of the login page step time with `pump(duration)` instead of `pumpAndSettle` (decisions in `docs/round-11-login.md`). The login panel and card are frosted glass (`features/auth/glass.dart`: two backdrop blurs only; cards inside use `innerGlass`, no second blur).

Theme rule: switching light and dark morphs every colour in 450 ms (`Pal` is a `ThemeExtension`; `motionTheme`). Never choose a colour or strength with `p.dark ? a : b`; use `p.pick(light, dark)`, `p.mix(light, dark)` or `p.darkOnly(shadows)` so it blends; `p.dark` is only for labels, icons and image paths, and images with two versions use `ThemedAsset` (cross-fades). Page changes are "instant out, soft in": never two pages on screen (`_InstantOutSoftIn` in `core/router.dart`). Decisions in `docs/round-13-transitions.md`.

Loading rule: a page or module that waits for data shows a shimmer skeleton of its own shape from `shared/widgets/skeleton.dart` (relative sizes only), never a spinner; the layout sweep also renders every page in its loading state. Charts in `features/analytics/charts.dart` reveal themselves on first frame (`_Reveal` mixin) and respect reduced motion.

Layout rule: `test/overflow_sweep_test.dart` renders every page of every role at ten widths from 360 to 1920 px (both breakpoints included) with long fake data, fully loading, and in four half-loaded mixes (FakeApiAdapter hangWhen) (`test/support/fake_api.dart`) and fails on any overflow or exception. New pages are covered automatically through `role_nav.dart`; add new dialogs to the dialog section of that test. Never put a fixed-width child in a `Row` without `Flexible`/`ShrinkTo`; use `Wrap` for button rows and pill groups; charts and `LayoutBuilder` must not sit inside `TwoCol`/`GridRows` (IntrinsicHeight). Tools that need room (the map editor) sit behind `MinWidthGate`. The shell never scrolls: every shell route wraps its page in `ShellPage` (its own scroll view) inside the page transition, because a navigator inside a scroll view forces the old page to the new page's height during the fade. `test/page_transition_test.dart` steps through page changes at 16 ms to guard this.

## Conventions

- Backend: raw parameterized SQL (SQL Server via the `mssql` driver) only, and only inside `src/repos/`. Routes validate with zod, call repos, return `{error}` on failure and `{items,totalCount,page,pageSize}` for lists. Every scoped read and write goes through `src/utils/scope.js`. Migrations are never edited once applied; add a new numbered file.
- Auth: JWT (8h) + bcrypt cost 10 via `src/utils/password.js`. `must_change_password` blocks every route except change-password and me.
- Audit: `src/middleware/audit.js` writes on `res.on('finish')` for POST/PUT/PATCH/DELETE with secrets redacted. Login success and failure are audited explicitly.
- Frontend: `lib/core` (config, api client, session, theme, router), `lib/shared` (widgets, forms, lists, messaging), `lib/features/<name>/{models,services,providers,views}`. Color literals live only in `lib/core/theme.dart`. No `ScaffoldMessenger.showSnackBar`; use the shared message overlay. Forms are built from `FieldSpec`s, not bare `TextFormField`s. User-facing errors go through `formatApiError`.
- Roles: `superadmin`, `supervisor` (shown to people as **Mall owner**; the key never changes), `mall_admin`, `store_owner`. Route prefixes `/superadmin`, `/mall-owner` (old `/supervisor` links redirect), `/mall-admin`, `/store-owner`. A mall admin manages exactly one branch. Who they report to (`users.reports_to`) is never set by hand: `utils/ownership.js` `applyReportsToRule()` recomputes it after every ownership or placement change (the owner of their branch first, else the mall's whole-mall owner, first linked, inactive owners skipped, else "No owner"). An owner owns many malls or branches and manages only the admins that report to them.

## AI floor-plan reading (Round 15)

Plans are read by AI through IQGateway (OpenAI-compatible, `https://iqlicense.dynamiqes.com/v1`). The key is only `IQ_GATEWAY_KEY` in `LIQo backend/.env` (via `src/config.js`), never in the web app, responses, logs or audit; the browser calls only our `/ai/*` and `.../backdrops/:key/convert` routes. All gateway calls go through `src/ai/gateway.js`; prompt, picture prep and tidy-up are in `src/ai/floorplan.js`. The model is the `ai_model` setting, chosen by a superadmin from the gateway's own list. Only the gateway wallet limits reading (no platform cap); every paid call is recorded in `map_conversions` and audited with its cost. Tests use a fake gateway (`test/ai_reading.test.js`), never real credits. PDF plans are rendered in the browser by the bundled pdf.js (`web/pdfjs`, no outside script). Decisions in `docs/round-15-ai-reading.md`.

## Plan formats (Round 16)

Plans upload as PNG/JPG (stored as they are), PDF/TIFF/WebP/BMP/GIF/HEIC (turned into PNG in the browser: pdf.js, `web/plan_convert/convert.js` with bundled decoders), or SVG/DXF/DWG (read on the server by `src/maps/vector/`, drawn into our own PNG; the original and `<key>.vector.json` are kept). The server sniffs the type from the bytes. DXF/DWG get an exact scale from their unit (`mpp_from_units`); without one the admin picks it (`PUT .../backdrops/:key/unit`); SVG is calibrated by hand. DWG goes through ODA File Converter (`ODA_FILE_CONVERTER` in `.env`, `execFile`, no shell); without it DWG is refused clearly. Reading a CAD plan sends the layers and texts to the AI, which names the wall layers; `snapToCad()` lays its walls on the exact CAD lines (face pairs give centre and thickness). SVG is never served back as SVG. Decisions in `docs/round-16-plan-formats.md`; deploy note in `EXCEPTIONS.md` #4.

## Map start, AI scan and 3D preview (Round 17)

A branch with no map starts from its floor plan (`_StartMap`, `PlanUpload` in `map_editor/plan_upload.dart`): upload first, then `createMap(outline: false)`, place, exact outline for DXF/DWG, Blueprint tab; "Create an empty map by hand" is the fallback link. "Read with AI" shows the full-screen `showAiScan` (closes itself; no invented progress) and new proposal pieces draw in on the canvas (`MapCanvasState._reveal`). The 3D preview (US-036) sits beside the canvas: three.js 0.186.1 bundled in `web/map3d/`, geometry from the pure `web/map3d/model.js` (tested in Node by `LIQo backend/test/map3d_model.test.js`), hosted by `map3d_host_web.dart` (placeholder in tests), fed by `map3dPayload`; collapsible, remembered per device. Decisions in `docs/round-17-map-start-scan-3d.md`.

## Accurate AI maps, 3D look and the easy editor (Round 18)

"Read with AI" measures walls from the plan's pixels (`src/maps/measure.js`: paired ink lines 6–28 cm apart; gaps are doors) and the AI adds names, types, doors and glass (`mergeMeasured`); rooms are the areas the walls enclose (`roomsFromWalls`, named by `nameRooms`); the AI's own walls are only the fallback. The scale comes from a dimension the AI reads (`scaleFromDimension`, `scaleFound`, applied as an Undo step) unless the plan was calibrated (`Backdrop.calibrated`). The map editor opens in the easy editor for everyone (`map_editor/guided/`: step bar ① Plan ② Scale ③ Read with AI ④ Rooms ⑤ Publish, `EditorData.guided`, remembered as `map.editor.guided`); "Advanced editing" is the full editor. In easy mode a left drag only moves the view, only a selected wall's end handles drag, each `GuidedTool` does one thing, and Delete/arrows do nothing; geometry for join/split/snap is in `guided/geometry.dart`. Decisions in `docs/round-18-accuracy-3d-easy-editor.md`.

## Things to check before building

Open items in the user-story doc are not settled: meaning of "rulings", AI extraction scope, CAD formats, shopper-app API, ownership model, opening-rule details. Ask before Phase 6 (map editor). Do not invent behaviour for them.

## LIQo mobile

The shopper app: indoor wayfinding for LIQo malls, like Google Maps but only for LIQo's malls; positioning will come from MOKO Smart H2 beacons (not built). Ported on 2026-10-22 from the demo `C:\Users\User\FlutterProjects\demo_app` ("Gabay Demo"); every product decision of that port is in `C:\Users\User\.claude\plans\do-you-know-what-starry-stearns.md`. Screens follow `LIQO Indoor Navigation Brand Board.png`; colours, logos and Manrope follow the guidelines PNG, as on web. Nothing in `LIQo web/` or `LIQo backend/` is changed for mobile work.

```bash
# inside "LIQo mobile"
flutter pub get
flutter run            # an Android emulator or a phone; iOS needs a Mac
flutter analyze
flutter test           # test/engine, test/logic, test/app (the layout sweep takes a few minutes)
node "LIQo mobile/tool/crop_brand.mjs"   # from the LIQo folder, after `npm install` in "LIQo mobile/tool"
```

Verification before reporting mobile work done: `flutter analyze` has zero issues, `flutter test` passes, `flutter build apk --debug` succeeds.

- Layout: `lib/core` (theme, router, storage, i18n, haptics, clock, `engine/`), `lib/shared/widgets`, `lib/features/<name>/{models,data,services,providers,views}`. `core/engine` is the demo's routing engine (venue model, walkway graph, Dijkstra, directions, other ways, evacuation, kit venues): pure Dart, no Flutter, no app code (`test/logic/structure_test.dart`). Fastest routes are byte-identical to the demo's; Shortest (`RouteOpts.metric`) counts metres walked.
- State: `navProvider` (`NavController` over a mutable `NavState`: position, trip, simulated walk, "Where are you?", other ways, evacuation) and `mapProvider` (camera, level, gestures, sheet), both per mall and reset when the mall changes (`switchMall`). They notify with `ref.notifyListeners()` every frame of the walk; the walk's ticker lives in `AppShell`, so it goes on while another tab is shown. Settings, route options, favourites, saved routes, history, recents and visits are small providers saved through `storeProvider`.
- There is no fixed start point: no dot, no distances and no route until the shopper says where they are; tests choose their own spot (`test/support/spots.dart`). The simulated walk runs at 1.4 m/s at a Normal pace (Slow, Relaxed, Normal, Brisk +25%, Fast +50%; the minutes shown follow the same pace) and stops at each lift, escalator or stairs to ask; it answers itself two seconds after the Map tab is seen.
- Theme: `Pal` (light, Obsidian, and a high-contrast version of each) and `MapPal` (the map's tokens) are `ThemeExtension`s in `core/theme.dart`, the only place with colour values; they morph in 450 ms; never `p.dark ? a : b` for a colour. Page transitions are the platform's own. The map and its panels use the demo's line icons (`shared/widgets/glyphs.dart`); the other screens use Material icons.
- Words: everything shown is plain English passed through `tr()` (`core/i18n/words.dart`), turned into Tagalog by `core/i18n/tagalog.dart` (exact phrases, then templates); add the Tagalog in the same change (`test/logic/tagalog_test.dart` scans the source). Data text (posts, About) carries both languages (`Bilingual`). Level and shop names stay as they are.
- Brand images (`assets/brand`, Android launcher and launch images, iOS AppIcon and LaunchImage, `res/values/colors.xml`) come only from `tool/crop_brand.mjs`, a copy of web's cutting; never edit them by hand.
- Sample data: the offline malls' hours, fictional phones (`+63 2 5550 01NN`), `example.com` websites, About texts and the five posts per mall are made up and labelled as samples. Call, Website and Share go through `placeActionsProvider` (tests replace it).
- Layout: `test/app/overflow_sweep_test.dart` renders every screen and every Map state at 320–1024 px with long names, light and dark high contrast with the largest text, and Tagalog; new screens and dialogs go into it. Use `Wrap` or a scrolling row for chips; never a fixed-width child in a `Row` without `Flexible`.
- Not built yet, on purpose: accounts (Sign in / Sign up are look-only and say "Accounts are coming soon"), notifications, AR view, live location (beacons), the shopper API, and the Home posts feed (posts by stores, malls, mall owners and the superadmin; Home shows samples in its place).

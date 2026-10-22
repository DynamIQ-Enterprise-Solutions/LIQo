# Round 11 — Login page redesign

Status: **Done 2026-10-22.** Flutter analyze clean; 207 Flutter tests pass, 5 skipped (new `test/login_test.dart`, 11 tests). No backend change. Design canvas: https://claude.ai/artifact/5p6zYeYubFafJmtzDePq54 (row "A2 · Atlas refined").

## How it was decided
- Three directions were drawn (A Atlas, B Beacon, C Levels). The owner chose **A Atlas**, with two changes: a **clear distinction between the form and everything around it, without looking disconnected**, and a **carousel of the system's useful features** in the other panel.
- Interview answers (2026-10-22):
  - Slides: all four, Map editor, Blueprints, Stores & announcements, Insights & audit. **Commercial illustrations only, never actual data.**
  - Auto-advance every **6 s**.
  - Sample content: **generic placeholders** (Store A, Unit 214, …).
  - Light mode: **everything light** (straight inversion, like the rest of the app).
  - It is a web app; when the window is too narrow for two panels (≤ 1050 px), **stack: form first, then the carousel**.
  - Build straight into the app.

## What was built
- `lib/features/auth/login_view.dart`
  - **Wide windows:** the carousel panel is about 55% of the width. The form side has a theme toggle, the form card and a footer.
  - **Short windows:** the page keeps a minimum height of 780 px and scrolls.
  - **Narrow windows:** wordmark and toggle, then the form card, then the compact carousel, then the footer.
  - **The form card:** a panel surface with a border, a shadow and a short orange accent on its top edge. A full-width divider sits above the "Forgot your password?" note.
  - **Fields:** taller and filled. The Sign in button has an arrow and the brand glow.
- `lib/features/auth/login_features.dart`, `FeatureCarousel`
  - **Slides:** four, each with an eyebrow, a title, one line and a drawn illustration. The illustrations are a floor plan with a route, a blueprint with detected walls and a scale line, a store directory beside an announcement waiting for review, and a sign-ins chart beside audit rows.
  - **Controls:** dots, previous and next (44 px targets), and a "01 / 04" counter.
  - **Motion:** a 380 ms fade and rise between slides. It moves every 6 s and stops for good once someone picks a slide. With reduced motion turned on it never moves by itself and the fade is off.
- **Colours** come only from the `Pal` tokens. Ground is `bg`; the carousel panel is `shell` in dark and `boxBg` in light; the card is `panel` with a `fieldLine` border and `shadow`.

## Tests
`test/login_test.dart`:
- The carousel sits beside the form on wide windows, and the arrows and dots move it, wrapping around.
- It advances at 6 s and 12 s, and stops after a pick.
- With reduced motion it stays still.
- On a narrow window the form comes first.
- There is no overflow on any slide at these sizes:

| Width × height | Mode |
|---|---|
| 1051 × 640 | light |
| 1366 × 640 | dark |
| 1920 × 1080 | dark |
| 1050 × 700 | light |
| 360 × 640 | dark |

The layout sweep still renders `/login` at ten widths.

Found by these tests and fixed: the "Waiting for review" pill could push past the Approve button in the illustration. It now shrinks with an ellipsis.

## Not changed
- The white "Sign in" text on brand orange stays as in the rest of the app; its contrast is about 3:1.

## Visual polish (same day)
The owner asked for an expensive, sophisticated look without overdoing it, especially in the animations.

**Interview answers:**
- **Background:** glow plus a living map.
- **Finishing touches:** entrance on load, a glowing card edge, illustrations that come alive.
- **Mark:** emphasize the **IQ** mark (spelled "IQ", never exaggerated) with the tile on the card and a faint watermark.
- **Scope:** the login page only.

**What was built:**
- `lib/features/auth/login_ambience.dart`
  - `LoginBackdrop` draws three brand light blooms drifting slowly on long loops, and a faint dot grid. On that grid, four thin routes trace themselves with a glowing head, rest while their end beacon pulses, then fade. Each route is at its own point in the cycle.
  - `IqWatermark` is a large IQ mark breathing between about 3.5% and 5.5% opacity behind the card. It shows only on wide windows. The mark is cut from the logo into `assets/brand/iq-dark.png` and `iq-light.png`.
  - `EdgeGlowPainter` sends a thin light around the card's border, with a soft halo.
  - One 24 s clock drives all three. The routes and the edge light do 3 laps per loop; the watermark takes 4 breaths.
- `login_view.dart`
  - A one-time staged entrance of about 1.1 s: the panel, then the card, then the heading, fields and button rise in.
  - The IQ tile sits on the card with a soft brand glow, replacing the orange accent bar.
- `login_features.dart`
  - Each illustration builds itself in over 1.4 s:
    - **Plan:** the stores appear, then the route draws with a glowing head to the store, which lights up.
    - **Blueprint:** the walls trace, then the scale line extends and the legend appears.
    - **Stores:** the cards and rows slide in.
    - **Insights:** the bars grow one after another, the line draws, the audit rows slide in.
  - The panel is slightly translucent, so the glow reads through it. The active dot glows.
- **Reduced motion:** no entrance, no build-in, no clock. One calm still frame.

**Tests:** `test/login_test.dart` now has 14 tests. They check that the background keeps animating, that reduced motion stops every frame, that the IQ tile and watermark are present, and that the watermark is absent when stacked. Login tests step time in 1.2 s chunks, because the page never "settles".

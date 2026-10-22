# Round 6 — Brand theme: Obsidian dark mode, inverted light mode, 1:1 logos

Status: **Done 2026-10-21.**
Requested 2026-10-21: every dashboard follows the LIQO brand board; three variants were shown (`https://claude.ai/artifact/SxB2hHbhjoU9Xgunqb7BMc`); the owner chose **Variant A, Obsidian**, as dark mode, with a **straight inversion** as light mode; the device setting decides the mode until the person picks one (remembered per browser); the logo and the browser-tab icon are **1:1 copies from the brand board**, and the tab icon swaps with the mode; subtle transition animations, nothing grand.

## What was built

| Area | Change |
|---|---|
| Logos | `assets/brand/logo-dark.png` (white letters, orange mark) and `logo-light.png` (brand-dark letters) cut from the board's primary logo; the letters were recoloured pixel by pixel with coverage-based edges, the IQ mark is untouched. `icon-dark.png` / `icon-light.png` are the board's rounded app tiles. Script: `scratchpad/crop_brand.mjs` (kept in the session scratchpad; the assets are in the repo). |
| Browser tab | `web/favicon-dark.png` and `favicon-light.png` with `media` queries in `web/index.html`, plus the app sets the `href` whenever its own mode changes (`lib/core/favicon_web.dart`, stub for the VM). Install icons 192/512 are the dark tile upscaled; replace them when original files arrive. |
| Fonts | Manrope (variable) bundled in `assets/fonts`; every `ts()` style and the Material theme use it. |
| Palette | `lib/core/theme.dart`: dark = Obsidian (near-black surfaces, white type, orange glow), light = inversion with the same structure. New tokens: `shell` (top bar and sidebar), `glow`, `scrim`, toast colours, brand constants. Every colour literal outside the theme was moved into it, except the map canvas drawing palette and the blueprint proposal teal (map editor; later). |
| Mode | `ThemeMode.system` by default; the sun/moon button overrides and the choice is saved in SharedPreferences; the avatar menu has "Follow device theme". |
| Motion | Pages fade in with a 1% rise (220 ms); the active sidebar item animates its highlight and glow (150 ms); list loading dims with a fade; the side panel slides (220 ms). Nothing loops or bounces. |
| Chrome | Top bar shows the wordmark at 26 px, an ADMIN tag, the role badge, the mode toggle and the glowing avatar; a thin orange-to-crimson route line runs along its bottom edge. The phone sidebar shows the app tile. |

## Not changed on purpose
- The map editor canvas colours (walls, spaces, proposal teal) stay as they are; they are a drawing palette, to be revisited with the 3D preview.
- No layout changed in this round; Round 5's panels and the lists are the structure the theme sits on.

## Added the same day: chart reveal and skeleton loading

- **Charts grow into place** every time the Analytics page opens: the first frame draws each chart empty (lines on the baseline, bars at zero, the donut ring thin, horizontal bars at zero width) and the next frame draws the real values, so fl_chart animates between them (650 ms, ease-out). Totals count up from zero. Switching the period animates the change the same way. Devices that ask for reduced motion get the final state at once. Code: the `_Reveal` mixin in `features/analytics/charts.dart`, `CountUp`, and `AnimatedFractionallySizedBox` in `HBarList`.
- **Skeleton loading per module** (`shared/widgets/skeleton.dart`): a soft shimmer sweeps over placeholders that have the module's real shape (stat tiles, chart area, table rows, form fields). Overview, Analytics (cards and every section), every list, the People page, Settings, Option lists and the store-owners screen use them instead of a spinner. Every placeholder size is relative (fractions and Expanded), so a skeleton can never overflow.
- **Loading sweep**: the layout test now also renders every page of every role at 360 and 1440 px with a server that never answers, so a loading state that overflows fails the build.

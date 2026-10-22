# Round 12 — New brand reference, precise crops, glass login

Status: **Done 2026-10-22.** Flutter analyze clean; 211 Flutter tests pass, 5 skipped. No backend change.

## Brand reference
`LIQO Brand Guidelines Presentation.png` replaces `LIQO Indoor Navigation Brand Board.png` as the brand reference (owner, 2026-10-22: "it is clearer"). Its colours are the same four: #FF5A3D primary, #8B1E2D accent, #1A1A1F dark, #F8F8FA light. `Pal` is unchanged.

### Owner decisions (interview)
| Question | Decision |
|---|---|
| Dark-mode wordmark | Cut from the **hero banner** (white letters, white arrow), background removed |
| Light-mode wordmark | The sheet's **primary logo**, without its tagline |
| Tab and app icons | **Dark tile in dark mode, light tile in light mode** (as before) |
| IQ mark (watermark) | The sheet's **"Icon usage (alternative)" IQ**; dark mode turns its I and arrow white |
| Tagline | **"Smart Way Forward"** replaces "Navigate Your World" everywhere in the app (sidebar footer) |

### How the crops are made
`LIQo web/tool/crop_brand.mjs` regenerates every image from the sheet. Run it from the LIQo folder:

```
node "LIQo web/tool/crop_brand.mjs"
```

- **Matting, not keying.** Each edge pixel is unmixed from its local background (alpha = projection onto foreground − background), and its colour is set to what it would be at full coverage. No halo of the sheet's light grey or the hero's dark red stays on an edge.
  - The sheet adds a 1 px white sharpening rim around the Q; it is removed.
  - The only light pixels left are the white highlight stripe in the Q's tail, which is part of the design.
- **Holes.** The insides of the Q and O become transparent in both wordmarks and in the IQ mark.
- **Tiles.**
  - Edges come from the sheet's measurements: the dark tile from its 50% edge crossing, the light tile from between its soft shadow lines.
  - Each is inset past the bevel and the shadow, and both are output at the same 143 × 134 px.
  - The tiles are slightly wider than tall on the sheet. They keep those proportions and are never stretched square.
  - The corner radius is measured along the corner's diagonal (27 px on 143 px), and the mask is drawn analytically with anti-aliasing.
- **Same logo size in both modes.** Each wordmark keeps its own full resolution (light 340 × 129, dark 516 × 202). Both get the same space above and below the letters, measured in letter heights, so switching theme does not change the letter size.
- **Margins.** Every wordmark and IQ image has exactly 2 transparent pixels around its content, and nothing touches an image edge. This was checked by script.
- **Tab and install icons.**
  - The tile sits on a square canvas, centred, with its proportions kept and Catmull-Rom resampling.
  - Maskable icons are flattened on brand dark, with the tile inside the 80% safe zone.

### Code
- `BrandTile` draws the tile at its true proportions (`BrandTile.aspect`, `BrandTile.radiusShare`).
- `BrandWordmark` is unchanged; its height is the image height.

## Login: glass showcase (owner request, same day)
"The left side panel looks too plain to be a commercial or flagship visual … the light mode seems too plain, make it a bit transparent like glassmorphism."

### Interview
- **Panel:** a glass showcase on a deep gradient, with the pictures floating as glass UI cards in slight 3D perspective, a glow beneath and a parallax entrance.
- **Glass:** panel and card, in light and dark.
- **Blur:** real blur, only behind those two.
- **Light-mode panel:** the light frosted version (frosted white with a peach-to-rose tint).

### Built
- **`features/auth/glass.dart`**
  - `GlassSurface`: clip, then a backdrop blur (sigma 24, behind this surface only), then a gradient tint, a hairline border and a highlight on the top edge.
  - Panel tint: obsidian to deep crimson in dark mode; frosted white, peach and rose in light mode.
  - Card tint: neutral and readable.
  - `innerGlass()` styles the cards inside the panel: tint, hairline and soft shadow, with no second blur.
- **`login_features.dart`**
  - The panel is a `GlassSurface` with two inner blooms (brand light at the top right, crimson depth at the bottom left).
  - Each picture sits on a stage in 3D perspective. It turns in from the side as it builds, floats 5 px with the page clock, and has a brand glow ellipse beneath.
  - Plan and blueprint sit on glass cards. A glass chip floats in front: "Published" on the map, "Walls detected" on the blueprint.
  - Arrows and dots are glass too.
- **`login_view.dart`:** the sign-in card is a `GlassSurface` with a soft lifting shadow; the travelling edge light stays.
- **`login_ambience.dart`:** light mode has warmer, stronger blooms (peach and rose plus a fourth bloom), so the glass has colour to frost.
- **Fix:** the "Waiting for review" pill no longer gets cut to "Waiting for …".

### Tests
`test/login_test.dart` checks that exactly two glass surfaces, and so exactly two blurs, exist in light and dark.

The look was checked on rendered images of the page, in both modes, with real shadows on. Flutter's test renderer turns shadow blur off by default, which made shadows look like hard slabs.

## Not changed
The tagline still reads "Navigate Your World" on the guidelines sheet itself. Only the app's text changed.

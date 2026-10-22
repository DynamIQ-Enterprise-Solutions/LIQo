# Round 13 — Theme and page transitions

Status: **Done 2026-10-22.** Flutter analyze clean; 213 Flutter tests pass, 5 skipped (new `test/theme_transition_test.dart`). No backend change.

## Owner decisions (interview)
| Question | Decision |
|---|---|
| Switching light and dark | **Smooth colour morph**: every colour blends; logos and icons cross-fade |
| Duration | **About half a second** (450 ms, ease in-out) |
| Toggle icon | **Rotate and swap** (sun and moon), in step with the morph |
| Overlap seen when moving between pages | **Instant out, soft in**: the old page disappears at once, the new one fades and rises in (220 ms) |

## What was built
- **Blendable palette.** `Pal` is now a `ThemeExtension`, set by `buildTheme`.
  - `MaterialApp` animates the theme with `themeAnimationDuration: motionTheme` (450 ms).
  - `Pal.lerp` blends all 41 colours, the shadows and the chart series.
  - `Pal.darkness` runs from 0 (light) to 1 (dark), and between them while switching.
- **No mid-way jumps.** Every colour or strength that used to be chosen with `p.dark ? a : b` now blends:
  - `p.pick(light, dark)` for colours;
  - `p.mix(light, dark)` for numbers;
  - `p.darkOnly(shadows)` for dark-only glows.
  - `p.dark` stays only for labels, icons and image paths.
- **Images.** `ThemedAsset` (in `shared/widgets/common.dart`) cross-fades the light and dark versions in step with `darkness`. When settled it draws one image. It is used by `BrandWordmark`, `BrandTile` and the login's IQ watermark.
- **Toggle.** `ThemeToggleIcon` rotates and scales the moon out and the sun in (and back) with `darkness`. It is used in the top bar and on the login page.
- **Pages.** In `core/router.dart` (`_InstantOutSoftIn`), a page is hidden (its state kept) as soon as the next page starts covering it. The new page fades and rises in over 220 ms. Going back has no reverse animation.

## Tests
`test/theme_transition_test.dart`:
- **Half-way through a switch:** the palette is a real blend, not either mode. Both logos are drawn and both icons are present.
- **Settled:** exactly one logo and the right icon.
- **Page changes:** stepping through five page changes frame by frame, exactly one page is on screen in every frame.

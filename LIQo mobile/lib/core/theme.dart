import 'package:flutter/material.dart';

/// Colour palette, built like LIQo web's (lib/core/theme.dart there): dark mode is
/// the brand's "Obsidian" look, light mode its inversion, and each has a high
/// contrast version (black/white + brand orange, owner decision 2026-10-22).
/// Use `context.pal` inside build methods. Colour literals live only in this file.
@immutable
class Pal extends ThemeExtension<Pal> {
  const Pal({
    required this.dark,
    double? darkness,
    this.hc = false,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.hint,
    required this.line,
    required this.softLine,
    required this.bg,
    required this.panel,
    required this.raised,
    required this.brand,
    required this.onBrand,
    required this.brand2,
    required this.soft,
    required this.green,
    required this.warn,
    required this.danger,
    required this.dangerBg,
    required this.open,
    required this.openBg,
    required this.closed,
    required this.closedBg,
    required this.maint,
    required this.maintBg,
    required this.soon,
    required this.soonBg,
    required this.shadow,
    required this.glow,
    required this.tiles,
  }) : darkness = darkness ?? (dark ? 1.0 : 0.0);

  /// Whether the palette is (mostly) the dark one. While the theme morphs
  /// between modes this flips half-way; use [darkness], [pick] and [mix]
  /// for anything that should blend smoothly.
  final bool dark;

  /// 0 in light mode, 1 in dark mode, in between while switching.
  final double darkness;

  /// High contrast: thicker outlines, pure text.
  final bool hc;

  /// The light-mode value blended toward the dark-mode one by [darkness].
  Color pick(Color light, Color dark) => Color.lerp(light, dark, darkness)!;

  /// Same as [pick], for numbers (opacities, sizes).
  double mix(double light, double dark) => light + (dark - light) * darkness;

  /// Shadows that exist only in dark mode, faded in with [darkness].
  List<BoxShadow> darkOnly(List<BoxShadow> shadows) =>
      darkness <= 0 ? const [] : [for (final s in shadows) s.copyWith(color: s.color.withValues(alpha: s.color.a * darkness))];

  final Color ink,
      muted,
      faint,
      hint,
      line,
      softLine,

      /// The page background.
      bg,

      /// Cards, sheets and bars.
      panel,

      /// A surface raised off a card: chips, segmented controls, inputs.
      raised,
      brand,

      /// Text and icons on a [brand] fill.
      onBrand,

      /// Brand colour that reads as text on [soft] and [panel] backgrounds.
      brand2,
      soft,
      green,
      warn,
      danger,
      dangerBg;

  /// Store status chips: text colour and background.
  final Color open, openBg, closed, closedBg, maint, maintBg, soon, soonBg;

  final List<BoxShadow> shadow;

  /// The orange glow behind the primary button and the selected tab.
  final List<BoxShadow> glow;

  /// Initials tiles (store logos until real ones exist): white text on each.
  final List<Color> tiles;

  /// Outline width: thicker in high contrast.
  double get lineW => hc ? 2 : 1;

  /// Scrim behind pop-ups.
  Color get scrim => pick(const Color(0x5A111827), const Color(0x99000000));

  /// Confetti colours on arrival.
  List<Color> get confetti => [brand, brand2, const Color(0xFFF2B33D), const Color(0xFF7A5AF8), const Color(0xFF3D8BF2), const Color(0xFFE85D9A)];

  /// Light mode: LIQo web's light neutrals.
  static const light = Pal(
    dark: false,
    ink: Color(0xFF1A1A1F),
    muted: Color(0xFF6B6B78),
    faint: Color(0xFF8A8A95),
    hint: Color(0xFFA0A0AB),
    line: Color(0xFFE6E6EC),
    softLine: Color(0xFFEDEDF2),
    bg: Color(0xFFF8F8FA),
    panel: Color(0xFFFFFFFF),
    raised: Color(0xFFF3F3F6),
    brand: Color(0xFFFF5A3D),
    onBrand: Color(0xFFFFFFFF),
    brand2: Color(0xFF8B1E2D),
    soft: Color(0xFFFFEFEA),
    green: Color(0xFF168A5E),
    warn: Color(0xFFA3620A),
    danger: Color(0xFFB42318),
    dangerBg: Color(0xFFFBECEE),
    open: Color(0xFF0F6B47),
    openBg: Color(0xFFE3F4EC),
    closed: Color(0xFFB42318),
    closedBg: Color(0xFFFDECEA),
    maint: Color(0xFF8A5208),
    maintBg: Color(0xFFFFF3E0),
    soon: Color(0xFF5B4C96),
    soonBg: Color(0xFFEFEAFB),
    shadow: [BoxShadow(color: Color(0x14191C2E), blurRadius: 18, offset: Offset(0, 6))],
    glow: [BoxShadow(color: Color(0x40FF5A3D), blurRadius: 16, offset: Offset(0, 4))],
    tiles: _tiles,
  );

  /// Dark mode: "Obsidian". Near-black surfaces, white type, orange glow.
  static const darkPal = Pal(
    dark: true,
    ink: Color(0xFFF8F8FA),
    muted: Color(0xFFA4A4AF),
    faint: Color(0xFF8A8A95),
    hint: Color(0xFF6E6E7A),
    line: Color(0xFF2A2A31),
    softLine: Color(0xFF222228),
    bg: Color(0xFF121216),
    panel: Color(0xFF1A1A1F),
    raised: Color(0xFF24242B),
    brand: Color(0xFFFF5A3D),
    onBrand: Color(0xFFFFFFFF),
    brand2: Color(0xFFFF8A6E),
    soft: Color(0xFF3A2420),
    green: Color(0xFF3DDC97),
    warn: Color(0xFFFFB547),
    danger: Color(0xFFFF6B5A),
    dangerBg: Color(0xFF2A1515),
    open: Color(0xFF3DDC97),
    openBg: Color(0xFF15302A),
    closed: Color(0xFFFF8A7A),
    closedBg: Color(0xFF3A1A18),
    maint: Color(0xFFFFB547),
    maintBg: Color(0xFF3A2A12),
    soon: Color(0xFFC4B5FD),
    soonBg: Color(0xFF2A2440),
    shadow: [BoxShadow(color: Color(0x66000000), blurRadius: 22, offset: Offset(0, 8))],
    glow: [BoxShadow(color: Color(0x66FF5A3D), blurRadius: 20, offset: Offset(0, 4))],
    tiles: _tiles,
  );

  /// High contrast, light: black on white; orange only as a fill (with black on it),
  /// a darker orange where it is text.
  static const hcLight = Pal(
    dark: false,
    hc: true,
    ink: Color(0xFF000000),
    muted: Color(0xFF333338),
    faint: Color(0xFF4A4A55),
    hint: Color(0xFF5A5A66),
    line: Color(0xFF4A4A55),
    softLine: Color(0xFF6B6B78),
    bg: Color(0xFFFFFFFF),
    panel: Color(0xFFFFFFFF),
    raised: Color(0xFFF0F0F2),
    brand: Color(0xFFFF5A3D),
    onBrand: Color(0xFF000000),
    brand2: Color(0xFFA3270F),
    soft: Color(0xFFFFE3DA),
    green: Color(0xFF0B5C3B),
    warn: Color(0xFF6B3F00),
    danger: Color(0xFF8F1A10),
    dangerBg: Color(0xFFFDECEA),
    open: Color(0xFF0B5C3B),
    openBg: Color(0xFFE3F4EC),
    closed: Color(0xFF8F1A10),
    closedBg: Color(0xFFFDECEA),
    maint: Color(0xFF6B3F00),
    maintBg: Color(0xFFFFF3E0),
    soon: Color(0xFF3B2F6E),
    soonBg: Color(0xFFEFEAFB),
    shadow: [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
    glow: [],
    tiles: _tilesHc,
  );

  /// High contrast, dark: white on black, brand orange.
  static const hcDark = Pal(
    dark: true,
    hc: true,
    ink: Color(0xFFFFFFFF),
    muted: Color(0xFFE6E6E6),
    faint: Color(0xFFCFCFD6),
    hint: Color(0xFFBDBDC6),
    line: Color(0xFFBDBDC6),
    softLine: Color(0xFF8A8A95),
    bg: Color(0xFF000000),
    panel: Color(0xFF0A0A0A),
    raised: Color(0xFF1A1A1F),
    brand: Color(0xFFFF5A3D),
    onBrand: Color(0xFF000000),
    brand2: Color(0xFFFFB098),
    soft: Color(0xFF3A1A12),
    green: Color(0xFF7CF0C0),
    warn: Color(0xFFFFD38A),
    danger: Color(0xFFFF8A7A),
    dangerBg: Color(0xFF2A0E0B),
    open: Color(0xFF7CF0C0),
    openBg: Color(0xFF0F2A22),
    closed: Color(0xFFFFB3A6),
    closedBg: Color(0xFF3A1210),
    maint: Color(0xFFFFD38A),
    maintBg: Color(0xFF3A2A0A),
    soon: Color(0xFFDDD6FE),
    soonBg: Color(0xFF221C3A),
    shadow: [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4))],
    glow: [],
    tiles: _tilesHc,
  );

  static const _tiles = [
    Color(0xFFC2410C),
    Color(0xFF8B1E2D),
    Color(0xFF1D4ED8),
    Color(0xFF15803D),
    Color(0xFF7E22CE),
    Color(0xFF0E7490),
    Color(0xFF854D0E),
    Color(0xFF475569),
  ];
  static const _tilesHc = [
    Color(0xFF9A3412),
    Color(0xFF7F1D1D),
    Color(0xFF1E3A8A),
    Color(0xFF14532D),
    Color(0xFF581C87),
    Color(0xFF164E63),
    Color(0xFF713F12),
    Color(0xFF1E293B),
  ];

  /// The palette for the chosen look.
  static Pal of({required bool dark, required bool hc}) => hc ? (dark ? hcDark : hcLight) : (dark ? darkPal : light);

  /// Brand constants that do not change with the mode.
  static const brandOrange = Color(0xFFFF5A3D);
  static const brandCrimson = Color(0xFF8B1E2D);
  static const brandDark = Color(0xFF1A1A1F);
  static const brandLight = Color(0xFFF8F8FA);

  /// Fully transparent (the status bar over the app).
  static const clear = Color(0x00000000);

  /// Only used by the framework; palettes are fixed per mode.
  @override
  Pal copyWith() => this;

  /// Blends every colour, so switching modes morphs smoothly (about 450 ms, as on web).
  @override
  Pal lerp(covariant Pal? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<Color> colors(List<Color> a, List<Color> b) => [for (var i = 0; i < a.length; i++) c(a[i], i < b.length ? b[i] : a[i])];
    final d = darkness + (other.darkness - darkness) * t;
    return Pal(
      dark: d >= 0.5,
      darkness: d,
      hc: t < 0.5 ? hc : other.hc,
      ink: c(ink, other.ink),
      muted: c(muted, other.muted),
      faint: c(faint, other.faint),
      hint: c(hint, other.hint),
      line: c(line, other.line),
      softLine: c(softLine, other.softLine),
      bg: c(bg, other.bg),
      panel: c(panel, other.panel),
      raised: c(raised, other.raised),
      brand: c(brand, other.brand),
      onBrand: c(onBrand, other.onBrand),
      brand2: c(brand2, other.brand2),
      soft: c(soft, other.soft),
      green: c(green, other.green),
      warn: c(warn, other.warn),
      danger: c(danger, other.danger),
      dangerBg: c(dangerBg, other.dangerBg),
      open: c(open, other.open),
      openBg: c(openBg, other.openBg),
      closed: c(closed, other.closed),
      closedBg: c(closedBg, other.closedBg),
      maint: c(maint, other.maint),
      maintBg: c(maintBg, other.maintBg),
      soon: c(soon, other.soon),
      soonBg: c(soonBg, other.soonBg),
      shadow: BoxShadow.lerpList(shadow, other.shadow, t) ?? other.shadow,
      glow: BoxShadow.lerpList(glow, other.glow, t) ?? other.glow,
      tiles: colors(tiles, other.tiles),
    );
  }
}

/// The map's colours: the demo's token names (its CSS variables), re-coloured from
/// the LIQo palette. The map painter asks for them by name (`pal['route']`).
@immutable
class MapPal extends ThemeExtension<MapPal> {
  const MapPal._(this.dark, this.hc, this._m, [double? darkness]) : darkness = darkness ?? (dark ? 1.0 : 0.0);

  final bool dark, hc;
  final double darkness;
  final Map<String, Color> _m;

  static final light = MapPal._(false, false, _mapLight);
  static final darkPal = MapPal._(true, false, _mapDark);
  static final hcLight = MapPal._(false, true, {..._mapLight, ..._mapHcLight});
  static final hcDark = MapPal._(true, true, {..._mapDark, ..._mapHcDark});

  static MapPal of({required bool dark, required bool hc}) => hc ? (dark ? hcDark : hcLight) : (dark ? darkPal : light);

  /// Outlines are thicker in high contrast.
  double get line => hc ? 2 : 1;

  /// A token by its name, with or without the leading `--`.
  Color operator [](String name) => _m[name.startsWith('--') ? name.substring(2) : name]!;

  /// White, for glyphs on a pin and the dot's ring.
  Color get white => const Color(0xFFFFFFFF);

  /// The soft shadow under the dot.
  Color get dotShadow => const Color(0x2E000000);

  @override
  MapPal copyWith() => this;

  @override
  MapPal lerp(covariant MapPal? other, double t) {
    if (other == null) return this;
    final d = darkness + (other.darkness - darkness) * t;
    return MapPal._(d >= .5, t < .5 ? hc : other.hc, {for (final k in _m.keys) k: Color.lerp(_m[k], other._m[k] ?? _m[k], t)!}, d);
  }
}

Color _rgba(int r, int g, int b, double a) => Color.fromRGBO(r, g, b, a);

final Map<String, Color> _mapLight = {
  'ground': const Color(0xFFF8F8FA), 'surface': const Color(0xFFFFFFFF), 'alt': const Color(0xFFF1F1F4), 'text': const Color(0xFF1A1A1F), 'muted': const Color(0xFF6B6B78), 'outline': const Color(0xFFE6E6EC),
  'accent': const Color(0xFFFF5A3D), 'on-accent': const Color(0xFFFFFFFF), 'accent-text': const Color(0xFFC23A1E), 'cone': const Color(0xFFFF5A3D),
  'grass': const Color(0xFFDFE8D6), 'road': const Color(0xFFD3D3DA), 'road-line': const Color(0xFFF4F4F7), 'walk': const Color(0xFFECECF0), 'lot': const Color(0xFFDADAE0), 'stall': const Color(0xFFE4E4EA), 'stall-line': const Color(0xFFA9A9B4), 'plazaG': const Color(0xFFEEEDEA),
  'tree': const Color(0xFF9DBB8C), 'tree-dark': const Color(0xFF7A9A6A),
  'floor': const Color(0xFFECECF0), 'corridor': const Color(0xFFF7F7F9), 'store': const Color(0xFFFFE9E2), 'store-line': const Color(0xFFE6D9D5), 'staff': const Color(0xFFE9DCE0), 'void': const Color(0xFFCFCFD6),
  'box': const Color(0xFFF7D9CF), 'box-a': const Color(0xFFD9B2A6), 'box-b': const Color(0xFFC79D90), 'roof': const Color(0xFFD9D9DF), 'bs': const Color(0xFFD0D0D6), 'bs-line': const Color(0xFF9A9AA5),
  'wall-top': const Color(0xFFD0D0D8), 'wall-a': const Color(0xFFA8A8B3), 'wall-b': const Color(0xFF94949F),
  'slab-a': const Color(0xFFE3C7BD), 'slab-b': const Color(0xFFD3B3A8),
  'col-top': const Color(0xFFBDBDC4), 'col-a': const Color(0xFF8E8E97), 'col-b': const Color(0xFF7A7A83),
  'glass-top': _rgba(140, 190, 200, .45), 'glass-a': _rgba(120, 170, 185, .32), 'glass-b': _rgba(100, 150, 165, .32),
  'label': const Color(0xFF1A1A1F), 'halo': const Color(0xFFF8F8FA),
  'route': const Color(0xFFFF5A3D), 'route-rim': const Color(0xFF8B1E2D), 'route-text': const Color(0xFFC23A1E), 'route-alt': const Color(0xFF2563EB),
  'poi': const Color(0xFF8B1E2D), 'conn': const Color(0xFF3F3F4A),
  'open': const Color(0xFF0F6B47), 'open-chip': const Color(0xFFE3F4EC), 'closed': const Color(0xFFB42318), 'closed-chip': const Color(0xFFFDECEA),
  'maint': const Color(0xFF8A5208), 'maint-chip': const Color(0xFFFFF3E0), 'soon': const Color(0xFF5B4C96), 'soon-chip': const Color(0xFFEFEAFB),
  'good': const Color(0xFF168A5E), 'mid': const Color(0xFFC98A12), 'bad': const Color(0xFFD92D20),
  'water': const Color(0xFFCFE0EA), 'sand': const Color(0xFFEFE6D2),
};

/// Dark mode's map: a lighter blue-grey, like Google Maps at night (owner decision 2026-10-23:
/// the first dark map was too dark to read), with clearly lighter corridors and shops, white
/// labels on a dark halo, and a brighter route and pins.
final Map<String, Color> _mapDark = {
  'ground': const Color(0xFF232733), 'surface': const Color(0xFF2B303B), 'alt': const Color(0xFF353B48), 'text': const Color(0xFFF2F4F7), 'muted': const Color(0xFFB8BEC9), 'outline': const Color(0xFF4A5160),
  'accent': const Color(0xFFFF6A4D), 'on-accent': const Color(0xFFFFFFFF), 'accent-text': const Color(0xFFFF9F88), 'cone': const Color(0xFFFF8A6E),
  'grass': const Color(0xFF2E3A34), 'road': const Color(0xFF3B4250), 'road-line': const Color(0xFF59606E), 'walk': const Color(0xFF363C49), 'lot': const Color(0xFF323845), 'stall': const Color(0xFF3A404D), 'stall-line': const Color(0xFF6B7280), 'plazaG': const Color(0xFF383E4B),
  'tree': const Color(0xFF4D7058), 'tree-dark': const Color(0xFF3C5A46),
  'floor': const Color(0xFF2F3542), 'corridor': const Color(0xFF4A5262), 'store': const Color(0xFF4A403E), 'store-line': const Color(0xFF6E625E), 'staff': const Color(0xFF4A3F48), 'void': const Color(0xFF1A1D25),
  'box': const Color(0xFF57463F), 'box-a': const Color(0xFF3D312C), 'box-b': const Color(0xFF342A26), 'roof': const Color(0xFF3E4451), 'bs': const Color(0xFF2C313C), 'bs-line': const Color(0xFF6B7280),
  'wall-top': const Color(0xFF6B7280), 'wall-a': const Color(0xFF4B5260), 'wall-b': const Color(0xFF424856),
  'slab-a': const Color(0xFF3A322F), 'slab-b': const Color(0xFF332C2A),
  'col-top': const Color(0xFF7A808C), 'col-a': const Color(0xFF565C68), 'col-b': const Color(0xFF4B515C),
  'glass-top': _rgba(140, 200, 215, .34), 'glass-a': _rgba(110, 170, 185, .28), 'glass-b': _rgba(90, 145, 160, .28),
  'label': const Color(0xFFFFFFFF), 'halo': const Color(0xFF1A1D25),
  'route': const Color(0xFFFF6A4D), 'route-rim': const Color(0xFFFFE1D8), 'route-text': const Color(0xFFFF9F88), 'route-alt': const Color(0xFF7FB8FF),
  'poi': const Color(0xFFE8553A), 'conn': const Color(0xFFD5D9E0),
  'open': const Color(0xFF3DDC97), 'open-chip': const Color(0xFF15302A), 'closed': const Color(0xFFFF8A7A), 'closed-chip': const Color(0xFF3A1A18),
  'maint': const Color(0xFFFFB547), 'maint-chip': const Color(0xFF3A2A12), 'soon': const Color(0xFFC4B5FD), 'soon-chip': const Color(0xFF2A2440),
  'good': const Color(0xFF3DDC97), 'mid': const Color(0xFFFFB547), 'bad': const Color(0xFFFF6B6B),
  'water': const Color(0xFF1F3A4D), 'sand': const Color(0xFF3B362C),
};

/// High contrast: pure text, darker secondary text and outlines, so labels read at WCAG AA or better.
final Map<String, Color> _mapHcLight = {
  'text': const Color(0xFF000000), 'muted': const Color(0xFF333338), 'outline': const Color(0xFF4A4A55), 'accent-text': const Color(0xFFA3270F), 'on-accent': const Color(0xFF000000),
  'label': const Color(0xFF000000), 'halo': const Color(0xFFFFFFFF), 'ground': const Color(0xFFFFFFFF), 'route-rim': const Color(0xFF5A0F1A), 'route-text': const Color(0xFFA3270F), 'route-alt': const Color(0xFF1D4ED8),
  'open': const Color(0xFF0B5C3B), 'closed': const Color(0xFF8F1A10), 'maint': const Color(0xFF6B3F00), 'soon': const Color(0xFF3B2F6E), 'store-line': const Color(0xFF7A7A85), 'conn': const Color(0xFF000000),
};
final Map<String, Color> _mapHcDark = {
  'text': const Color(0xFFFFFFFF), 'muted': const Color(0xFFE6E6E6), 'outline': const Color(0xFFBDBDC6), 'accent-text': const Color(0xFFFFB098), 'on-accent': const Color(0xFF000000),
  'label': const Color(0xFFFFFFFF), 'halo': const Color(0xFF000000), 'ground': const Color(0xFF000000), 'surface': const Color(0xFF0A0A0A), 'route-rim': const Color(0xFF3A0A10), 'route-text': const Color(0xFFFFC2B0),
  'route-alt': const Color(0xFF93C5FD), 'open': const Color(0xFF7CF0C0), 'closed': const Color(0xFFFFB3A6), 'maint': const Color(0xFFFFD38A), 'soon': const Color(0xFFDDD6FE), 'store-line': const Color(0xFF6E6E78), 'conn': const Color(0xFFFFFFFF),
};

extension PalContext on BuildContext {
  /// The palette, blended while the theme switches modes.
  Pal get pal => Theme.of(this).extension<Pal>() ?? (Theme.of(this).brightness == Brightness.dark ? Pal.darkPal : Pal.light);

  /// The map's colours, blended the same way.
  MapPal get mapPal => Theme.of(this).extension<MapPal>() ?? (Theme.of(this).brightness == Brightness.dark ? MapPal.darkPal : MapPal.light);
}

/// The brand face, bundled in assets/fonts.
const brandFont = 'Manrope';

/// Transitions: short enough to feel instant, long enough to read as motion.
const motionFast = Duration(milliseconds: 150);
const motionBase = Duration(milliseconds: 220);

/// Switching between light and dark: every colour morphs (as on web).
const motionTheme = Duration(milliseconds: 450);

/// Compact TextStyle helper, the same as web's. When [color] is null the text
/// inherits the theme colour, so it adapts to light and dark mode.
TextStyle ts(
  double size, {
  FontWeight w = FontWeight.w400,
  Color? color,
  double? ls,
  double height = 1.35,
}) {
  return TextStyle(
    fontFamily: brandFont,
    fontSize: size,
    fontWeight: w,
    color: color,
    letterSpacing: ls,
    height: height,
  );
}

/// The app's theme for one look. Page transitions are the platform's own
/// (owner decision 2026-10-22), so no pageTransitionsTheme is set.
ThemeData buildTheme({required bool dark, required bool hc}) {
  final pal = Pal.of(dark: dark, hc: hc), map = MapPal.of(dark: dark, hc: hc);
  final brightness = dark ? Brightness.dark : Brightness.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: brandFont,
    colorScheme: ColorScheme.fromSeed(
      seedColor: pal.brand,
      brightness: brightness,
      primary: pal.brand,
      onPrimary: pal.onBrand,
      surface: pal.panel,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: pal.bg,
    dividerColor: pal.line,
    iconTheme: IconThemeData(color: pal.ink),
    textTheme: base.textTheme.apply(bodyColor: pal.ink, displayColor: pal.ink, fontFamily: brandFont),
    textSelectionTheme: TextSelectionThemeData(cursorColor: pal.brand, selectionHandleColor: pal.brand, selectionColor: pal.brand.withValues(alpha: .3)),
    extensions: [pal, map],
  );
}

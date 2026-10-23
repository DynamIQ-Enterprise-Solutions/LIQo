import 'package:flutter/material.dart';

/// Colour palette. One instance for dark mode (the brand's "Obsidian" look,
/// chosen 2026-10-21) and one for light mode (a straight inversion of it).
/// Use `context.pal` inside build methods. Colour literals live only here.
@immutable
class Pal extends ThemeExtension<Pal> {
  const Pal({
    required this.dark,
    double? darkness,
    required this.ink,
    required this.muted,
    required this.line,
    required this.bg,
    required this.panel,
    required this.shell,
    required this.brand,
    required this.brand2,
    required this.soft,
    required this.green,
    required this.softLine,
    required this.rowLine,
    required this.fieldLine,
    required this.slate,
    required this.faint,
    required this.iconBg,
    required this.noticeBg,
    required this.noticeLine,
    required this.noticeText,
    required this.noticeBold,
    required this.hover,
    required this.tableHead,
    required this.boxBg,
    required this.statNote,
    required this.btnText,
    required this.hint,
    required this.dropText,
    required this.chartText,
    required this.quickHover,
    required this.demoBg,
    required this.demoLine,
    required this.demoText,
    required this.avatarBg,
    required this.avatarFg,
    required this.sideNote,
    required this.warn,
    required this.caution,
    required this.cautionText,
    required this.shadow,
    required this.glow,
    required this.chart,
    required this.danger,
    required this.dangerBg,
    required this.toastError,
    required this.toastSuccess,
    required this.toastInfo,
  }) : darkness = darkness ?? (dark ? 1.0 : 0.0);

  /// Whether the palette is (mostly) the dark one. While the theme morphs
  /// between modes this flips half-way; use [darkness], [pick] and [mix]
  /// for anything that should blend smoothly.
  final bool dark;

  /// 0 in light mode, 1 in dark mode, in between while switching.
  final double darkness;

  /// The light-mode value blended toward the dark-mode one by [darkness].
  Color pick(Color light, Color dark) => Color.lerp(light, dark, darkness)!;

  /// Same as [pick], for numbers (opacities, sizes).
  double mix(double light, double dark) => light + (dark - light) * darkness;

  /// Shadows that exist only in dark mode, faded in with [darkness].
  List<BoxShadow> darkOnly(List<BoxShadow> shadows) =>
      darkness <= 0 ? const [] : [for (final s in shadows) s.copyWith(color: s.color.withValues(alpha: s.color.a * darkness))];
  final Color ink,
      muted,
      line,
      bg,
      panel,

      /// Top bar and sidebar background (the brand frame).
      shell,
      brand,

      /// Brand colour that reads as text on [soft] backgrounds.
      brand2,
      soft,
      green,
      softLine,
      rowLine,
      fieldLine,
      slate,
      faint,
      iconBg,
      noticeBg,
      noticeLine,
      noticeText,
      noticeBold,
      hover,
      tableHead,
      boxBg,
      statNote,
      btnText,
      hint,
      dropText,
      chartText,
      quickHover,
      demoBg,
      demoLine,
      demoText,
      avatarBg,
      avatarFg,
      sideNote,
      warn;

  /// The credit bar when credits run low: a yellow fill, and words in a yellow that stays readable.
  final Color caution, cautionText;
  final List<BoxShadow> shadow;

  /// The orange glow behind the active nav item, the primary button and the avatar.
  final List<BoxShadow> glow;

  /// Series colours for charts, in order of use.
  final List<Color> chart;

  /// Destructive actions: outline, text and the filled confirm button.
  final Color danger;

  /// Background of the danger zone.
  final Color dangerBg;

  /// Toast backgrounds (white text on all three).
  final Color toastError, toastSuccess, toastInfo;

  /// Light mode: the brand board's light neutrals with the same structure as dark.
  static const light = Pal(
    dark: false,
    ink: Color(0xFF1A1A1F),
    muted: Color(0xFF6B6B78),
    line: Color(0xFFE6E6EC),
    bg: Color(0xFFF8F8FA),
    panel: Color(0xFFFFFFFF),
    shell: Color(0xFFFFFFFF),
    brand: Color(0xFFFF5A3D),
    brand2: Color(0xFF8B1E2D),
    soft: Color(0xFFFFEFEA),
    green: Color(0xFF168A5E),
    softLine: Color(0xFFEDEDF2),
    rowLine: Color(0xFFEEEEF2),
    fieldLine: Color(0xFFD9D9E1),
    slate: Color(0xFF4F4F5C),
    faint: Color(0xFF8A8A95),
    iconBg: Color(0xFFFFF0EB),
    noticeBg: Color(0xFFFFF4EF),
    noticeLine: Color(0xFFFFD2C2),
    noticeText: Color(0xFF3A3A44),
    noticeBold: Color(0xFF8B1E2D),
    hover: Color(0xFFF3F3F6),
    tableHead: Color(0xFFF5F5F8),
    boxBg: Color(0xFFF3F3F6),
    statNote: Color(0xFF7B7B88),
    btnText: Color(0xFF2A2A33),
    hint: Color(0xFFA0A0AB),
    dropText: Color(0xFF3F3F4A),
    chartText: Color(0xFF6B6B78),
    quickHover: Color(0xFFFFF7F4),
    demoBg: Color(0xFFF3F3F6),
    demoLine: Color(0xFFE1E1E8),
    demoText: Color(0xFF666673),
    avatarBg: Color(0xFFFF5A3D),
    avatarFg: Color(0xFFFFFFFF),
    sideNote: Color(0xFF8A8A95),
    warn: Color(0xFFA3620A),
    caution: Color(0xFFE2B203),
    cautionText: Color(0xFF7A5C00),
    shadow: [
      BoxShadow(color: Color(0x14191C2E), blurRadius: 28, offset: Offset(0, 10)),
    ],
    glow: [
      BoxShadow(color: Color(0x40FF5A3D), blurRadius: 16, offset: Offset(0, 4)),
    ],
    chart: [
      Color(0xFFFF5A3D),
      Color(0xFF2563EB),
      Color(0xFF16A34A),
      Color(0xFF9333EA),
      Color(0xFF0891B2),
      Color(0xFF8B1E2D),
      Color(0xFFCA8A04),
      Color(0xFF64748B),
    ],
    danger: Color(0xFF8B1E2D),
    dangerBg: Color(0xFFFBECEE),
    toastError: Color(0xFF8B1E2D),
    toastSuccess: Color(0xFF14532D),
    toastInfo: Color(0xFF1A1A1F),
  );

  /// Dark mode: "Obsidian". Near-black surfaces, white type, orange glow.
  static const darkPal = Pal(
    dark: true,
    ink: Color(0xFFF8F8FA),
    muted: Color(0xFFA4A4AF),
    line: Color(0xFF26262C),
    bg: Color(0xFF121216),
    panel: Color(0xFF1A1A1F),
    shell: Color(0xFF15151A),
    brand: Color(0xFFFF5A3D),
    brand2: Color(0xFFFF8A6E),
    soft: Color(0xFF3A2420),
    green: Color(0xFF3DDC97),
    softLine: Color(0xFF222228),
    rowLine: Color(0xFF222228),
    fieldLine: Color(0xFF33333B),
    slate: Color(0xFFC4C4CE),
    faint: Color(0xFF8A8A95),
    iconBg: Color(0xFF2E1F1C),
    noticeBg: Color(0xFF2A1B14),
    noticeLine: Color(0xFF5A3418),
    noticeText: Color(0xFFD9D9E2),
    noticeBold: Color(0xFFFFB098),
    hover: Color(0xFF22222A),
    tableHead: Color(0xFF1F1F25),
    boxBg: Color(0xFF202027),
    statNote: Color(0xFF9A9AA6),
    btnText: Color(0xFFE6E6EC),
    hint: Color(0xFF6E6E7A),
    dropText: Color(0xFFD4D4DC),
    chartText: Color(0xFFA4A4AF),
    quickHover: Color(0xFF231A18),
    demoBg: Color(0xFF1F1F26),
    demoLine: Color(0xFF30303A),
    demoText: Color(0xFFB9B9C4),
    avatarBg: Color(0xFFFF5A3D),
    avatarFg: Color(0xFFFFFFFF),
    sideNote: Color(0xFF7F7F8C),
    warn: Color(0xFFFFB547),
    caution: Color(0xFFF3D34A),
    cautionText: Color(0xFFF3D34A),
    shadow: [
      BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 12)),
    ],
    glow: [
      BoxShadow(color: Color(0x66FF5A3D), blurRadius: 20, offset: Offset(0, 4)),
    ],
    chart: [
      Color(0xFFFF5A3D),
      Color(0xFF60A5FA),
      Color(0xFF3DDC97),
      Color(0xFFC084FC),
      Color(0xFF22D3EE),
      Color(0xFFFF8A6E),
      Color(0xFFFACC15),
      Color(0xFF94A3B8),
    ],
    danger: Color(0xFFFF5A5A),
    dangerBg: Color(0xFF2A1515),
    toastError: Color(0xFF8B1E2D),
    toastSuccess: Color(0xFF14532D),
    toastInfo: Color(0xFF2A2A32),
  );

  /// Brand constants that do not change with the mode.
  static const brandOrange = Color(0xFFFF5A3D);
  static const brandCrimson = Color(0xFF8B1E2D);
  static const brandDark = Color(0xFF1A1A1F);
  static const brandLight = Color(0xFFF8F8FA);

  /// Scrim behind dialogs and the detail panel.
  Color get scrim => pick(const Color(0x5A111827), const Color(0x99000000));

  /// AI proposal on the map canvas and in the Blueprint panel (Round 15): teal
  /// pieces, amber dashes for the pieces the AI is not sure about.
  Color get aiProposal => pick(const Color(0xFF0D9488), const Color(0xFF2DD4BF));
  Color get aiProposalFill => pick(const Color(0x2614B8A6), const Color(0x262DD4BF));
  Color get aiProposalPanel => pick(const Color(0x1A14B8A6), const Color(0x1A2DD4BF));
  Color get aiUnsure => pick(const Color(0xFFD97706), const Color(0xFFFBBF24));

  /// Only used by the framework; palettes are fixed per mode.
  @override
  Pal copyWith() => this;

  /// Blends every colour, so switching modes morphs smoothly (owner decision
  /// 2026-10-22: a colour morph of about 450 ms).
  @override
  Pal lerp(covariant Pal? other, double t) {
    if (other == null) return this;
    List<Color> colors(List<Color> a, List<Color> b) => [for (var i = 0; i < a.length; i++) Color.lerp(a[i], i < b.length ? b[i] : a[i], t)!];
    final d = darkness + (other.darkness - darkness) * t;
    return Pal(
      dark: d >= 0.5,
      darkness: d,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      shell: Color.lerp(shell, other.shell, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brand2: Color.lerp(brand2, other.brand2, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      green: Color.lerp(green, other.green, t)!,
      softLine: Color.lerp(softLine, other.softLine, t)!,
      rowLine: Color.lerp(rowLine, other.rowLine, t)!,
      fieldLine: Color.lerp(fieldLine, other.fieldLine, t)!,
      slate: Color.lerp(slate, other.slate, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      iconBg: Color.lerp(iconBg, other.iconBg, t)!,
      noticeBg: Color.lerp(noticeBg, other.noticeBg, t)!,
      noticeLine: Color.lerp(noticeLine, other.noticeLine, t)!,
      noticeText: Color.lerp(noticeText, other.noticeText, t)!,
      noticeBold: Color.lerp(noticeBold, other.noticeBold, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      tableHead: Color.lerp(tableHead, other.tableHead, t)!,
      boxBg: Color.lerp(boxBg, other.boxBg, t)!,
      statNote: Color.lerp(statNote, other.statNote, t)!,
      btnText: Color.lerp(btnText, other.btnText, t)!,
      hint: Color.lerp(hint, other.hint, t)!,
      dropText: Color.lerp(dropText, other.dropText, t)!,
      chartText: Color.lerp(chartText, other.chartText, t)!,
      quickHover: Color.lerp(quickHover, other.quickHover, t)!,
      demoBg: Color.lerp(demoBg, other.demoBg, t)!,
      demoLine: Color.lerp(demoLine, other.demoLine, t)!,
      demoText: Color.lerp(demoText, other.demoText, t)!,
      avatarBg: Color.lerp(avatarBg, other.avatarBg, t)!,
      avatarFg: Color.lerp(avatarFg, other.avatarFg, t)!,
      sideNote: Color.lerp(sideNote, other.sideNote, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
      cautionText: Color.lerp(cautionText, other.cautionText, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      toastError: Color.lerp(toastError, other.toastError, t)!,
      toastSuccess: Color.lerp(toastSuccess, other.toastSuccess, t)!,
      toastInfo: Color.lerp(toastInfo, other.toastInfo, t)!,
      shadow: BoxShadow.lerpList(shadow, other.shadow, t) ?? other.shadow,
      glow: BoxShadow.lerpList(glow, other.glow, t) ?? other.glow,
      chart: colors(chart, other.chart),
    );
  }
}

extension PalContext on BuildContext {
  /// The palette, blended while the theme switches modes.
  Pal get pal => Theme.of(this).extension<Pal>() ?? (Theme.of(this).brightness == Brightness.dark ? Pal.darkPal : Pal.light);
}

/// Same breakpoints as the HTML mockup's media queries.
class Bp {
  static const double mobile = 720;
  static const double tablet = 1050;

  static bool isMobile(BuildContext c) => MediaQuery.sizeOf(c).width <= mobile;
  static bool isTablet(BuildContext c) => MediaQuery.sizeOf(c).width <= tablet;
}

/// The brand face, bundled in assets/fonts.
const brandFont = 'Manrope';

/// Transitions: short enough to feel instant, long enough to read as motion.
const motionFast = Duration(milliseconds: 150);
const motionBase = Duration(milliseconds: 220);

/// Switching between light and dark: every colour morphs (owner decision 2026-10-22).
const motionTheme = Duration(milliseconds: 450);

/// Compact TextStyle helper. When [color] is null the text inherits the
/// theme colour, so it adapts to light and dark mode automatically.
TextStyle ts(
  double size, {
  FontWeight w = FontWeight.w400,
  Color? color,
  double? ls,
  double height = 1.45,
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

ThemeData buildTheme(Brightness brightness) {
  final pal = brightness == Brightness.dark ? Pal.darkPal : Pal.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: brandFont,
    colorScheme: ColorScheme.fromSeed(
      seedColor: pal.brand,
      brightness: brightness,
      primary: pal.brand,
      surface: pal.panel,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: pal.bg,
    dividerColor: pal.line,
    iconTheme: IconThemeData(color: pal.ink),
    textTheme: base.textTheme.apply(bodyColor: pal.ink, displayColor: pal.ink, fontFamily: brandFont),
    splashFactory: InkSparkle.splashFactory,
    extensions: [pal],
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
    }),
  );
}

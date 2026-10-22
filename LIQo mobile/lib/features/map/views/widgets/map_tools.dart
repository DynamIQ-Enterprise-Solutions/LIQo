// The map's controls (from the demo's map_screen): the search bar, the category
// chips, the level chips, the tool rail (3D, whole site, all levels, heading-up,
// the walk's pause while the sheet is down), the wing pad and the banner.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme.dart';
import '../../../../shared/widgets/common.dart';
import '../../../../shared/widgets/glyphs.dart';
import '../../../places/models/category.dart';
import 'map_scope.dart';
import 'map_sheet.dart' show nearGlyph;

/// A square map button.
class SquareBtn extends StatelessWidget {
  const SquareBtn({super.key, required this.icon, required this.label, required this.onTap, this.on = false, this.opacity = 1, this.color});
  final String icon, label;
  final VoidCallback? onTap;
  final bool on;
  final double opacity;
  final Color? color;

  static const size = 46.0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tap(
      onTap: onTap,
      child: Semantics(
        button: true,
        toggled: on ? true : null,
        label: label,
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: size,
            height: size,
            decoration: cardDeco(p, 13).copyWith(color: on ? p.soft : p.panel, border: Border.all(color: on ? p.brand : p.line, width: p.lineW)),
            alignment: Alignment.center,
            child: AppIcon(icon, color: color ?? (on ? p.brand2 : p.ink)),
          ),
        ),
      ),
    );
  }
}

/// The search bar: opens the Search page.
class MapSearchBar extends StatelessWidget {
  const MapSearchBar({super.key});
  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), p = context.pal;
    if (sc.s.emergency) {
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: cardDeco(p, 14).copyWith(color: p.dangerBg, border: Border.all(color: p.danger, width: p.lineW)),
        child: Row(children: [
          AppIcon('i-alert', color: p.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(sc.tr('Emergency evacuation'), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15, w: FontWeight.w700, color: p.danger))),
        ]),
      );
    }
    return Semantics(
      button: true,
      label: sc.tr('Where do you want to go?'),
      excludeSemantics: true,
      onTap: () => context.push('/search'),
      child: Tap(
        onTap: () => context.push('/search'),
        child: Container(
          key: const ValueKey('map-search'),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: cardDeco(p, 14),
          child: Row(children: [
            AppIcon('i-search', color: p.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(sc.tr('Where do you want to go?'), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15, color: p.muted))),
          ]),
        ),
      ),
    );
  }
}

/// The category chips: the nearest of a kind.
class CategoryChips extends StatelessWidget {
  const CategoryChips({super.key});
  static const height = 34.0 + 12;

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), p = context.pal, s = sc.s;
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        clipBehavior: Clip.none,
        children: [
          for (final (i, c) in categories.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Builder(builder: (context) {
              final on = s.near != null && s.near!.type == c.id;
              return Semantics(
                button: true,
                selected: on,
                label: sc.tr(c.label),
                excludeSemantics: true,
                onTap: () => sc.nav.showNearest(c.id),
                child: Tap(
                  onTap: () => sc.nav.showNearest(c.id),
                  child: Container(
                    key: ValueKey('chip-${c.id}'),
                    height: 34,
                    padding: const EdgeInsets.fromLTRB(9, 0, 12, 0),
                    decoration: cardDeco(p, 999).copyWith(color: on ? p.brand : p.panel, border: Border.all(color: on ? p.brand : p.line, width: p.lineW)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AppIcon(nearGlyph(c.id), size: 16, color: on ? p.onBrand : p.brand2),
                      const SizedBox(width: 5),
                      Text(sc.tr(c.label), textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4), style: ts(12.5, w: FontWeight.w600, color: on ? p.onBrand : p.ink)),
                    ]),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// The map tools: 3D, whole site, all levels, heading-up, then a fold toggle; the walk's pause
/// joins them while the sheet is swiped down. Folded, only one button remains. When the room is
/// short, the tools wrap into more columns (leftwards) instead of running under the sheet.
class Rail extends StatelessWidget {
  const Rail({super.key, required this.maxHeight});
  final double maxHeight;
  static const _btn = SquareBtn.size, _gap = 8.0, _fold = 26.0;

  /// One button: anything shorter and the rail steps aside.
  static const double minHeight = _btn;

  static ({int rows, bool foldInGrid}) layout(double maxHeight, int n) {
    int fit(double h) => ((h + _gap) / (_btn + _gap)).floor();
    final withFoldRow = fit(maxHeight - _gap - _fold);
    if (withFoldRow >= 1) return (rows: math.min(n, withFoldRow), foldInGrid: false);
    return (rows: math.max(1, math.min(n + 1, fit(maxHeight))), foldInGrid: true);
  }

  /// How wide the rail is with [n] tools in the room it has.
  static double width(double maxHeight, int n) {
    final cols = (n / layout(maxHeight, n).rows).ceil().clamp(1, n);
    return cols * _btn + (cols - 1) * _gap;
  }

  /// How many tools are shown.
  static int count(MapScope sc) => 4 + (sc.s.route != null && !sc.s.arrived && sc.mv.sheetMin ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), s = sc.s, mv = sc.mv, p = context.pal, stack = mv.mode == 'stack';
    final dimmed = stack ? .35 : 1.0;
    Widget column(Iterable<Widget> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [for (final (i, w) in items.indexed) ...[if (i > 0) const SizedBox(height: _gap), w]],
        );
    // columns fill top to bottom; the first column is the rightmost
    Widget grid(List<Widget> items, int rows) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, c) in [for (var i = 0; i < items.length; i += rows) column(items.skip(i).take(rows))].reversed.indexed) ...[
              if (i > 0) const SizedBox(width: _gap),
              c,
            ],
          ],
        );
    if (sc.settings.railFolded) {
      return SquareBtn(key: const ValueKey('railfold'), icon: 'i-more', label: sc.tr('Show map tools'), onTap: sc.onFoldRail);
    }
    final tools = <Widget>[
      SquareBtn(key: const ValueKey('tool-3d'), icon: 'i-cube', label: sc.tr('3D view'), on: mv.cam.tilt > 0.5, opacity: dimmed, onTap: sc.map.toggleTilt),
      SquareBtn(key: const ValueKey('tool-site'), icon: 'i-site', label: sc.tr('Whole site'), opacity: dimmed, onTap: sc.map.flyToSite),
      SquareBtn(key: const ValueKey('tool-stack'), icon: 'i-layers', label: sc.tr('All levels'), on: stack, onTap: sc.map.toggleStack),
      SquareBtn(
        key: const ValueKey('tool-headup'),
        icon: 'i-headup',
        label: sc.settings.headingUp ? sc.tr('The map faces the way you walk. Tap for north up') : sc.tr('Make the map face the way you walk'),
        on: sc.settings.headingUp,
        opacity: dimmed,
        onTap: () => sc.map.setHeadingUp(!sc.settings.headingUp),
      ),
      // pause / resume the walk while the sheet is swiped down to one line
      if (s.route != null && !s.arrived && mv.sheetMin)
        SquareBtn(
          key: const ValueKey('walk'),
          icon: s.playing ? 'i-pause' : 'i-play',
          label: s.playing ? sc.tr('Pause the walk') : sc.tr('Resume the walk'),
          onTap: s.playing ? sc.nav.pause : (s.paused ? sc.nav.resume : sc.nav.start),
        ),
    ];
    final l = layout(maxHeight, tools.length);
    Widget fold(double h) => Semantics(
          button: true,
          label: sc.tr('Hide map tools'),
          child: Tap(
            onTap: sc.onFoldRail,
            child: Container(
              key: const ValueKey('railfold'),
              width: _btn,
              height: h,
              decoration: cardDeco(p, h == _btn ? 13 : 10),
              alignment: Alignment.center,
              child: AppIcon('i-up', size: 18, color: p.muted),
            ),
          ),
        );
    if (l.foldInGrid) return grid([...tools, fold(_btn)], l.rows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [grid(tools, l.rows), const SizedBox(height: _gap), fold(_fold)],
    );
  }
}

/// The level chips. They fit the room they are given: a tall venue's chips scroll, keeping the
/// shown level in view. Folded, only the shown level's chip remains.
class Levels extends StatefulWidget {
  const Levels({super.key, required this.maxHeight});
  final double maxHeight;

  /// One chip and the fold toggle.
  static const double minHeight = 42 + 5 + _LevelsState._fold;

  @override
  State<Levels> createState() => _LevelsState();
}

class _LevelsState extends State<Levels> {
  final _scroll = ScrollController();
  int? _shown;
  static const _chip = 47.0, _fold = 34.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), s = sc.s, mv = sc.mv, p = context.pal, rt = s.route, u = s.user;
    final shownLvs = sc.settings.levelsFolded ? [mv.level] : s.levelsDesc;
    final room = widget.maxHeight - _fold;
    final n = shownLvs.length, full = n * _chip, fits = full <= room;
    if (fits) {
      _shown = null;
    } else if (_shown != mv.level) {
      _shown = mv.level;
      final i = shownLvs.indexOf(mv.level);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final target = (i * _chip - room / 2 + _chip / 2).clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });
    }
    final onRoute = <int>{
      if (rt != null)
        for (final x in rt.verts) x.lv,
    };
    Widget dot(Color fill, Color border) => Container(width: 9, height: 9, decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: Border.all(color: border, width: 2)));
    final reduce = sc.settings.reduceMotion || MediaQuery.disableAnimationsOf(context);
    final chips = Column(
      children: [
        for (final lv in shownLvs) ...[
          Semantics(
            button: true,
            excludeSemantics: true,
            onTap: () => sc.map.showLevel(lv),
            selected: mv.level == lv,
            label: [
              s.levels[lv].name,
              if (u?.lv == lv) sc.tr('you are here'),
              if (onRoute.contains(lv) && !s.arrived) sc.tr('on your route'),
            ].join(', '),
            child: Tap(
              onTap: () => sc.map.showLevel(lv),
              child: SizedBox(
                key: ValueKey('level-$lv'),
                width: 42,
                height: 42,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: cardDeco(p, 12).copyWith(color: mv.level == lv ? p.brand : p.panel, border: Border.all(color: mv.level == lv ? p.brand : p.line, width: p.lineW)),
                        alignment: Alignment.center,
                        child: Text(s.levels[lv].short, textScaler: TextScaler.noScaling, style: ts(15, w: FontWeight.w700, color: mv.level == lv ? p.onBrand : p.ink)),
                      ),
                    ),
                    if (u?.lv == lv) Positioned(right: -3, top: -3, child: mv.level == lv ? dot(p.panel, p.brand) : dot(p.brand, p.panel)),
                    // the route dot; while riding, the floor you are going to pulses
                    if (onRoute.contains(lv) && !s.arrived)
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: Transform.scale(scale: s.ridingTo == lv && !reduce ? 1 + .7 * (1 - s.pulse) : 1, child: dot(context.mapPal['route'], p.panel)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
        ],
      ],
    );
    return Column(
      children: [
        if (fits)
          chips
        else
          SizedBox(
            height: math.max(_chip, room),
            width: 50,
            child: SingleChildScrollView(controller: _scroll, padding: const EdgeInsets.fromLTRB(0, 4, 8, 0), clipBehavior: Clip.hardEdge, child: chips),
          ),
        // folds the chips to the shown level, or unfolds them
        Semantics(
          container: true,
          button: true,
          excludeSemantics: true,
          onTap: sc.onFoldLevels,
          label: sc.settings.levelsFolded ? sc.tr('Show all levels') : sc.tr('Hide other levels'),
          child: Tap(
            onTap: sc.onFoldLevels,
            child: Container(
              key: const ValueKey('levelsfold'),
              width: 42,
              height: _fold - 4,
              decoration: cardDeco(p, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(sc.settings.levelsFolded ? 'i-down' : 'i-up', size: 14, color: p.muted),
                  // a caption under a chevron: it keeps its size (the screen reader has the full label)
                  Text(sc.tr('Levels'), textScaler: TextScaler.noScaling, maxLines: 1, overflow: TextOverflow.clip, style: ts(9.5, w: FontWeight.w600, color: p.muted, height: 1.1)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The wing pad: jump to a part of the venue.
class WingPad extends StatelessWidget {
  const WingPad({super.key});

  /// 36 px buttons in 4 px of padding.
  static const double height = 36 + 8;

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), p = context.pal;
    Widget b(String key, String label, {bool main = false}) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: () => sc.map.flyToWing(key),
          child: Tap(
            onTap: () => sc.map.flyToWing(key),
            child: Container(
              key: ValueKey('wing-$key'),
              constraints: const BoxConstraints(minWidth: 34),
              height: 36,
              padding: EdgeInsets.symmetric(horizontal: main ? 9 : 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: main ? p.brand : p.raised, borderRadius: BorderRadius.circular(10)),
              child: Text(label, textScaler: TextScaler.noScaling, style: ts(main ? 11 : 12, w: FontWeight.w700, color: main ? p.onBrand : p.ink)),
            ),
          ),
        );
    final items = [for (final x in sc.s.v.pad) b(x.key, sc.tr(x.simple), main: x.main)];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: cardDeco(p, 14),
      child: Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(width: 3), items[i]]]),
    );
  }
}

/// The banner over the map: refining a spot, the stacked or site view, another level shown, the evacuation.
class MapBanner extends StatelessWidget {
  const MapBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), s = sc.s, mv = sc.mv, p = context.pal, mode = mv.mode, u = s.user;
    final style = ts(12.5, w: FontWeight.w600, color: p.ink);
    Widget action(String key, String label, VoidCallback onTap) => Semantics(
          button: true,
          child: Tap(
            onTap: onTap,
            child: Container(
              key: ValueKey(key),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(999)),
              child: Text(label, style: ts(12.5, w: FontWeight.w700, color: p.onBrand)),
            ),
          ),
        );
    // the words, then the button; the button goes under them when the banner is narrow
    Widget wrap(List<Widget> children) => Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: children);
    Widget? body;
    var plain = false;
    if (s.refining) {
      body = wrap([
        Text(sc.tr('Approximate · tap the map where you are'), style: style, textAlign: TextAlign.center),
        action('locdone', sc.tr('Done'), sc.nav.finishRefine),
      ]);
    } else if (mode == 'stack') {
      body = Text(sc.tr('All levels · tap one to open it'), style: style, textAlign: TextAlign.center);
      plain = true;
    } else if (mode == 'site') {
      body = Text(sc.tr('Whole site · tap a building to go in'), style: style, textAlign: TextAlign.center);
      plain = true;
    } else if (u != null && mv.level != u.lv) {
      body = wrap([
        Text(sc.tr('You are on ${sc.t.levelLow(u.lv)}'), style: style, textAlign: TextAlign.center),
        action('show-my-level', sc.tr('Show'), () => sc.map.showLevel(u.lv)),
      ]);
    } else if (s.emergency) {
      body = Text(sc.tr('Use the stairs, not the lifts'), style: style.copyWith(color: p.danger), textAlign: TextAlign.center);
      plain = true;
    }
    if (body == null) return const SizedBox.shrink();
    return Container(
      padding: plain ? const EdgeInsets.symmetric(horizontal: 14, vertical: 7) : const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: cardDeco(p, 999),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Flexible(child: body)]),
    );
  }
}

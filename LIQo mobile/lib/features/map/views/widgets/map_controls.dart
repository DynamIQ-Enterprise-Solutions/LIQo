// The map's controls, laid out like Google Maps (owner decisions 2026-10-23):
// one search bar on top with the mall inside it, the category chips under it,
// at most one slim hint, and on the right only a Layers button, the floor
// picker and the my-location button. Everything else (3D, the whole site, all
// floors, heading-up, the wings, changing your location) is in the Layers panel.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme.dart';
import '../../../../shared/widgets/common.dart';
import '../../../../shared/widgets/glyphs.dart';
import '../../../../shared/widgets/mall_switcher.dart';
import '../../../navigation/providers/nav_provider.dart';
import '../../../places/models/category.dart';
import '../../../settings/providers/settings_provider.dart';
import '../../../settings/providers/words_provider.dart';
import '../../providers/map_provider.dart';
import 'map_scope.dart';
import 'map_sheet.dart' show nearGlyph;
import 'nav_bar.dart' show navMode;

/// A round floating map button (Google Maps' style).
class RoundMapButton extends StatelessWidget {
  const RoundMapButton({super.key, this.icon, this.iconData, required this.label, required this.onTap, this.on = false, this.filled = false, this.color});

  /// A map glyph, or a Material icon (Directions' bent arrow).
  final String? icon;
  final IconData? iconData;
  final String label;
  final VoidCallback? onTap;

  /// [on]: a toggle that is on; [filled]: the brand colour without being a toggle (Directions).
  final bool on, filled;
  final Color? color;

  static const size = 48.0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal, solid = on || filled, fg = solid ? p.onBrand : color ?? p.ink;
    return Semantics(
      button: true,
      label: label,
      toggled: on ? true : null,
      excludeSemantics: true,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: p.shadow),
        child: Material(
          color: solid ? p.brand : p.panel,
          shape: CircleBorder(side: BorderSide(color: solid ? p.brand : p.line, width: p.lineW)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: size, height: size, child: Center(child: iconData != null ? Icon(iconData, size: 26, color: fg) : AppIcon(icon!, color: fg))),
          ),
        ),
      ),
    );
  }
}

/// The search bar: "Search Bayview Grand", opening the Search page; the mall at its end switches malls.
class MapSearchBar extends ConsumerWidget {
  const MapSearchBar({super.key});
  static const height = 52.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = MapScope.of(context), p = context.pal;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(height / 2), boxShadow: p.shadow),
      child: Material(
        color: p.panel,
        shape: StadiumBorder(side: BorderSide(color: p.line, width: p.lineW)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: height,
          child: Row(children: [
            Expanded(
              child: Semantics(
                button: true,
                label: sc.tr('Search in ${sc.s.v.name}'),
                excludeSemantics: true,
                onTap: () => context.push('/search'),
                child: InkWell(
                  key: const ValueKey('map-search'),
                  onTap: () => context.push('/search'),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Row(children: [
                      AppIcon('i-search', color: p.muted),
                      const SizedBox(width: 10),
                      Expanded(child: Text(sc.tr('Search in ${sc.s.v.name}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15.5, color: p.muted))),
                    ]),
                  ),
                ),
              ),
            ),
            Container(width: p.lineW, height: 28, color: p.line),
            Semantics(
              button: true,
              label: sc.tr('Mall: ${sc.s.v.name}. Change mall'),
              excludeSemantics: true,
              onTap: () => pickMall(context, ref),
              child: InkWell(
                key: const ValueKey('mall-switcher'),
                onTap: () => pickMall(context, ref),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.storefront_outlined, color: p.brand2, size: 22),
                    Icon(Icons.expand_more, color: p.muted, size: 20),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The category chips: the nearest of a kind, one swipeable row.
class CategoryChips extends StatelessWidget {
  const CategoryChips({super.key});
  static const height = 36.0 + 10;

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), p = context.pal, s = sc.s;
    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        clipBehavior: Clip.none,
        child: Row(children: [
          for (final (i, c) in categories.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Builder(builder: (context) {
              final on = s.near != null && s.near!.type == c.id;
              return Semantics(
                button: true,
                selected: on,
                label: sc.tr(c.label),
                excludeSemantics: true,
                onTap: () => sc.nav.showNearest(c.id),
                child: DecoratedBox(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: p.shadow),
                  child: Material(
                    color: on ? p.brand : p.panel,
                    shape: StadiumBorder(side: BorderSide(color: on ? p.brand : p.line, width: p.lineW)),
                    child: InkWell(
                      key: ValueKey('chip-${c.id}'),
                      customBorder: const StadiumBorder(),
                      onTap: () => sc.nav.showNearest(c.id),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          AppIcon(nearGlyph(c.id), size: 17, color: on ? p.onBrand : p.brand2),
                          const SizedBox(width: 6),
                          Text(sc.tr(c.label), textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4), style: ts(13.5, w: FontWeight.w600, color: on ? p.onBrand : p.ink)),
                        ]),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ]),
      ),
    );
  }
}

/// At most one slim hint over the map: refining your spot (Done), another floor shown (Show),
/// and, when not walking a route, all floors or the whole site.
class MapHint extends StatelessWidget {
  const MapHint({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), s = sc.s, mv = sc.mv, p = context.pal, mode = mv.mode, u = s.user;
    final style = ts(13, w: FontWeight.w600, color: p.ink);
    Widget action(String key, String label, VoidCallback onTap) => Semantics(
          button: true,
          child: Tap(
            onTap: onTap,
            child: Container(
              key: ValueKey(key),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(999)),
              child: Text(label, style: ts(13, w: FontWeight.w700, color: p.onBrand)),
            ),
          ),
        );
    // the words, then the button; the button goes under them when the hint is narrow
    Widget wrap(List<Widget> children) => Wrap(alignment: WrapAlignment.start, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: children);
    final Widget? body;
    if (s.refining) {
      body = wrap([Text(sc.tr('Approximate · tap the map where you are'), style: style), action('locdone', sc.tr('Done'), sc.nav.finishRefine)]);
    } else if (u != null && mode == 'building' && mv.level != u.lv) {
      body = wrap([Text(sc.tr('You are on ${sc.t.levelLow(u.lv)}'), style: style), action('show-my-level', sc.tr('Show'), () => sc.map.showLevel(u.lv))]);
    } else if (navMode(s)) {
      body = null;
    } else if (mode == 'stack') {
      body = Text(sc.tr('All levels · tap one to open it'), style: style);
    } else if (mode == 'site' && !s.emergency) {
      body = Text(sc.tr('Whole site · tap a building to go in'), style: style);
    } else {
      body = null;
    }
    if (body == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey('map-hint'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: p.panel.withValues(alpha: .96), borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line, width: p.lineW), boxShadow: p.shadow),
        child: body,
      ),
    );
  }
}

/// The floor picker (right side, like Google Maps indoors). Folded, it is one chip: the floor
/// shown, which starts as yours; a tap opens every floor, scrolled to the one shown, and picking
/// one shows it and folds the list again (owner decision 2026-10-23). A dot marks where you are
/// (left) and the floors your route uses (right).
class FloorPicker extends StatefulWidget {
  const FloorPicker({super.key, required this.maxHeight});
  final double maxHeight;

  static const chip = 44.0, _fold = 28.0;

  /// The folded chip.
  static const double minHeight = chip + _fold + 8;

  @override
  State<FloorPicker> createState() => _FloorPickerState();
}

class _FloorPickerState extends State<FloorPicker> {
  final _scroll = ScrollController();
  bool _open = false;
  int? _shown;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toggle() => setState(() {
        _open = !_open;
        _shown = null;
      });

  void _pick(MapScope sc, int lv) {
    sc.map.showLevel(lv);
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), s = sc.s, mv = sc.mv, p = context.pal, rt = s.route, u = s.user;
    final lvs = s.levelsDesc, room = widget.maxHeight - 8 - FloorPicker._fold, fits = lvs.length * FloorPicker.chip <= room;
    if (_open && !fits && _shown != mv.level) {
      // keep the floor shown in view
      _shown = mv.level;
      final i = lvs.indexOf(mv.level);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final target = (i * FloorPicker.chip - room / 2 + FloorPicker.chip / 2).clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.jumpTo(target);
      });
    }
    final onRoute = <int>{if (rt != null && !s.arrived) for (final x in rt.verts) x.lv};
    final reduce = MediaQuery.disableAnimationsOf(context);
    Widget dot(Color fill) => Container(width: 8, height: 8, decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: Border.all(color: p.panel, width: 1.5)));
    String said(int lv) => [s.levels[lv].name, if (u?.lv == lv) sc.tr('you are here'), if (onRoute.contains(lv)) sc.tr('on your route')].join(', ');
    // the floor in the middle; you-are-here on its left, the route on its right
    Widget chip(int lv) => SizedBox(
          width: RoundMapButton.size,
          height: FloorPicker.chip,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 32,
              height: 36,
              decoration: BoxDecoration(color: mv.level == lv ? p.brand : null, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Text(s.levels[lv].short, textScaler: TextScaler.noScaling, style: ts(14.5, w: FontWeight.w800, color: mv.level == lv ? p.onBrand : p.ink)),
            ),
            if (u?.lv == lv) Positioned(left: 0, child: dot(p.brand)),
            if (onRoute.contains(lv))
              Positioned(
                right: 0,
                child: Transform.scale(scale: s.ridingTo == lv && !reduce ? 1 + .7 * (1 - s.pulse) : 1, child: dot(context.mapPal['route'])),
              ),
          ]),
        );
    final Widget body;
    if (!_open) {
      body = Semantics(
        button: true,
        expanded: false,
        excludeSemantics: true,
        onTap: _toggle,
        label: '${said(mv.level)}. ${sc.tr('Show all floors')}',
        child: InkWell(
          key: const ValueKey('floors-toggle'),
          onTap: _toggle,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            chip(mv.level),
            SizedBox(height: FloorPicker._fold, child: Center(child: AppIcon('i-down', size: 16, color: p.muted))),
          ]),
        ),
      );
    } else {
      final column = Column(mainAxisSize: MainAxisSize.min, children: [
        for (final lv in lvs)
          Semantics(
            button: true,
            selected: mv.level == lv,
            excludeSemantics: true,
            onTap: () => _pick(sc, lv),
            label: said(lv),
            child: InkWell(key: ValueKey('level-$lv'), onTap: () => _pick(sc, lv), child: chip(lv)),
          ),
      ]);
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          button: true,
          expanded: true,
          excludeSemantics: true,
          onTap: _toggle,
          label: sc.tr('Hide the floors'),
          child: InkWell(
            key: const ValueKey('floors-toggle'),
            onTap: _toggle,
            child: SizedBox(width: RoundMapButton.size, height: FloorPicker._fold, child: Center(child: AppIcon('i-up', size: 16, color: p.muted))),
          ),
        ),
        if (fits) column else SizedBox(height: math.max(FloorPicker.chip, room), child: SingleChildScrollView(controller: _scroll, child: column)),
      ]);
    }
    const radius = BorderRadius.all(Radius.circular(RoundMapButton.size / 2));
    return DecoratedBox(
      key: const ValueKey('floor-picker'),
      decoration: BoxDecoration(borderRadius: radius, boxShadow: p.shadow),
      child: Material(
        color: p.panel,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: p.line, width: p.lineW)),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: body),
      ),
    );
  }
}

/// The Layers panel (like Google Maps' layers sheet): change my location, the 3D view, the
/// whole site, all floors, the map facing the way you walk, and the wings to go to.
Future<void> showLayersPanel(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.pal.panel,
      isScrollControlled: true,
      builder: (context) => const SafeArea(child: _LayersPanel()),
    );

class _LayersPanel extends ConsumerWidget {
  const _LayersPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider), mv = ref.watch(mapProvider), s = ref.watch(navProvider);
    final map = ref.read(mapProvider.notifier), nav = ref.read(navProvider.notifier), headingUp = ref.watch(settingsProvider.select((x) => x.headingUp));
    final stack = mv.mode == 'stack';
    void close() => Navigator.of(context).pop();
    Widget tile(String key, String icon, String label, VoidCallback? onTap, {bool on = false}) => Expanded(
          child: Opacity(
            opacity: onTap == null ? .45 : 1,
            child: Semantics(
              button: true,
              toggled: on ? true : null,
              label: label,
              excludeSemantics: true,
              onTap: onTap,
              child: InkWell(
                key: ValueKey(key),
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: Ink(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                  decoration: BoxDecoration(color: on ? p.soft : p.raised, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? p.brand : p.line, width: on ? 2 : p.lineW)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AppIcon(icon, size: 26, color: on ? p.brand2 : p.ink),
                    const SizedBox(height: 6),
                    Text(label, textAlign: TextAlign.center, style: ts(13, w: FontWeight.w700, color: p.ink, height: 1.2)),
                  ]),
                ),
              ),
            ),
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Semantics(header: true, child: Text(w.tr('Map view'), style: ts(19, w: FontWeight.w800, color: p.ink)))),
          IconButton(tooltip: w.tr('Close'), onPressed: close, icon: Icon(Icons.close, color: p.ink)),
        ]),
        const SizedBox(height: 4),
        if (!s.emergency || s.evac == null)
          ListTile(
            key: const ValueKey('layers-location'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: AppIcon('i-pin', color: p.brand2),
            title: Text(w.tr('Change my location'), style: ts(15, w: FontWeight.w700, color: p.ink)),
            trailing: Icon(Icons.chevron_right, color: p.muted),
            onTap: () {
              close();
              nav.openLocation();
            },
          ),
        const SizedBox(height: 6),
        Row(children: [
          tile('layers-3d', 'i-cube', w.tr('3D view'), stack ? null : map.toggleTilt, on: mv.cam.tilt > .5),
          const SizedBox(width: 10),
          tile('layers-site', 'i-site', w.tr('Whole site'), stack
              ? null
              : () {
                  map.flyToSite();
                  close();
                }),
          const SizedBox(width: 10),
          tile('layers-floors', 'i-floors', w.tr('All floors'), map.toggleStack, on: stack),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('layers-headup'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: AppIcon('i-headup', color: p.brand2),
          title: Text(w.tr('The map faces the way I walk'), style: ts(15, w: FontWeight.w600, color: p.ink)),
          value: headingUp,
          activeThumbColor: p.onBrand,
          activeTrackColor: p.brand,
          onChanged: map.setHeadingUp,
        ),
        if (s.v.pad.isNotEmpty) ...[
          const SizedBox(height: 6),
          SectionLabel(w.tr('Go to'), padding: const EdgeInsets.only(top: 4, bottom: 8)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in s.v.pad)
              ActionChip(
                key: ValueKey('wing-${b.key}'),
                label: Text(w.tr(b.simple)),
                labelStyle: ts(14, w: FontWeight.w700, color: b.main ? p.onBrand : p.ink),
                backgroundColor: b.main ? p.brand : p.raised,
                side: BorderSide(color: b.main ? p.brand : p.line, width: p.lineW),
                shape: const StadiumBorder(),
                onPressed: stack
                    ? null
                    : () {
                        map.flyToWing(b.key);
                        close();
                      },
              ),
          ]),
        ],
      ]),
    );
  }
}

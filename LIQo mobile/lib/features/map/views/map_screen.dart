// The Map tab: the map and everything over it, laid out like Google Maps (owner
// decisions 2026-10-23). Browsing: the search bar with the mall in it, the
// category chips, one slim hint, the Layers button, the floor picker, the
// Directions button, the my-location button and the draggable sheet. Walking a route: the next-turn
// banner on top and the bottom bar instead (red on the way out). Over both: the
// question pop-up and the arrival confetti.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/confetti.dart';
import '../../malls/providers/mall_provider.dart';
import '../../navigation/providers/nav_provider.dart';
import '../../navigation/services/narration.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/providers/words_provider.dart';
import '../providers/map_provider.dart';
import '../services/map_painter.dart';
import 'widgets/map_scope.dart';
import 'widgets/map_sheet.dart';
import 'widgets/map_controls.dart';
import 'widgets/nav_bar.dart';
import 'widgets/prompt_overlay.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _sheetKey = GlobalKey(), _topKey = GlobalKey();
  final _locFocus = FocusNode();
  double _sheetH = 0, _topH = 0;
  int _version = 0, _burst = 0;

  // how far the sheet has been dragged (down is positive), until it snaps
  double _dragDy = 0;

  @override
  void dispose() {
    _locFocus.dispose();
    super.dispose();
  }

  void _drag(double dy) => setState(() => _dragDy += dy);

  void _endDrag(double velocity) {
    final dy = _dragDy, map = ref.read(mapProvider.notifier);
    setState(() => _dragDy = 0);
    if (dy > 48 || velocity > 500) {
      _locFocus.unfocus();
      map.sheetDown();
    } else if (dy < -32 || velocity < -500) {
      map.sheetUp();
    }
  }

  static double _heightOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    return (box != null && box.hasSize) ? box.size.height : 0.0;
  }

  /// The sheet (or the bottom bar) and the top chrome, measured after each frame.
  void _measure() {
    if (!mounted) return;
    final sheet = _heightOf(_sheetKey), top = _heightOf(_topKey);
    if ((sheet - _sheetH).abs() > 0.5 || (top - _topH).abs() > 0.5) {
      setState(() {
        _sheetH = sheet;
        _topH = top;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(navProvider), mv = ref.watch(mapProvider), t = ref.watch(navTextProvider);
    final settings = ref.watch(settingsProvider), mallId = ref.watch(mallProvider)!;
    // arriving: confetti (not at the end of an evacuation, nor with animations off)
    ref.listen(navProvider.select((x) => x.arrivalSeq), (a, b) {
      final reduce = ref.read(settingsProvider).reduceMotion || MediaQuery.disableAnimationsOf(context);
      if (b > (a ?? 0) && ref.read(navProvider).evac == null && !reduce) setState(() => _burst++);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return MapScope(
      s: s,
      mv: mv,
      t: t,
      nav: ref.read(navProvider.notifier),
      map: ref.read(mapProvider.notifier),
      settings: settings,
      mallId: mallId,
      version: ++_version,
      child: ColoredBox(
        color: context.mapPal['ground'],
        child: LayoutBuilder(builder: (context, c) => _layout(context, c.biggest)),
      ),
    );
  }

  Widget _layout(BuildContext context, Size size) {
    final sc = MapScope.of(context), s = sc.s, mv = sc.mv, map = sc.map, p = context.pal;
    final walking = navMode(s), site = mv.mode == 'site';
    final top = MediaQuery.paddingOf(context).top + 8, chromeBottom = top + _topH;
    // the middle of the map area, between the top chrome and the sheet
    mv.centreX = size.width / 2;
    mv.centreY = (chromeBottom + size.height - _sheetH) / 2;
    map.syncSheet(sheetKind(s));
    final body = walking ? null : sheetBody(context, locFocus: _locFocus);
    final sheet = body != null && mv.sheetMin ? sheetMini(context) : body;
    // the sheet always leaves room for the my-location button under the top chrome
    final sheetMax = (size.height - chromeBottom - 12 - RoundMapButton.size - 12).clamp(140.0, walking ? 440.0 : 380.0);
    // Google Maps' Directions button (pick a place, the route starts), while browsing
    final directions = !walking && !s.emergency;
    final floorsMax = size.height - _sheetH - 12 - RoundMapButton.size - (directions ? RoundMapButton.size + 10 : 0) - 10 - (chromeBottom + 10);
    final sheetDeco = BoxDecoration(
      color: p.panel,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      border: Border(top: BorderSide(color: p.line, width: p.lineW), left: BorderSide(color: p.line, width: p.lineW), right: BorderSide(color: p.line, width: p.lineW)),
      boxShadow: p.shadow,
    );
    return Stack(
      children: [
        // the map
        const Positioned.fill(child: _MapCanvas()),
        // the top chrome: the next-turn banner while walking, else the search bar and the chips
        // (not during an evacuation); then the hint and the Layers button
        Positioned(
          left: 0,
          right: 0,
          top: top,
          child: Column(
            key: _topKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (walking)
                const Padding(padding: EdgeInsets.fromLTRB(14, 0, 14, 10), child: NavBanner())
              else if (!s.emergency) ...[
                const Padding(padding: EdgeInsets.fromLTRB(14, 0, 14, 10), child: MapSearchBar()),
                const CategoryChips(),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Expanded(child: MapHint()),
                  const SizedBox(width: 10),
                  RoundMapButton(key: const ValueKey('layers'), icon: 'i-layers', label: sc.tr('Layers'), onTap: () => showLayersPanel(context)),
                ]),
              ),
            ],
          ),
        ),
        // the floor picker, Directions and the my-location button, above the sheet
        Positioned(
          right: 14,
          bottom: _sheetH + 12,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (!site && floorsMax >= FloorPicker.minHeight) ...[FloorPicker(maxHeight: floorsMax), const SizedBox(height: 10)],
            if (directions) ...[
              RoundMapButton(key: const ValueKey('directions'), iconData: Icons.directions, filled: true, label: sc.tr('Directions'), onTap: () => context.push('/search?go=1')),
              const SizedBox(height: 10),
            ],
            RoundMapButton(
              key: const ValueKey('recenter'),
              icon: 'i-locate',
              label: s.hasPosition ? sc.tr('My location') : sc.tr('Where are you?'),
              color: p.brand2,
              onTap: s.hasPosition ? map.recenter : sc.nav.openLocation,
            ),
          ]),
        ),
        // walking: the bottom bar (tap or swipe up for more)
        if (walking)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GestureDetector(
              key: const ValueKey('nav-bar'),
              onVerticalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if ((v < -300 && !mv.navOpen) || (v > 300 && mv.navOpen)) map.toggleNavOpen();
              },
              child: Container(
                key: _sheetKey,
                constraints: BoxConstraints(maxHeight: sheetMax),
                decoration: sheetDeco,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                  child: s.emergency ? const EvacBottomBar() : const NavBottomBar(),
                ),
              ),
            ),
          )
        // browsing: a draggable sheet, swipe down to one line, swipe up to open it again
        else if (sheet != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GestureDetector(
              key: const ValueKey('sheet'),
              onVerticalDragUpdate: (d) => _drag(d.delta.dy),
              onVerticalDragEnd: (d) => _endDrag(d.primaryVelocity ?? 0),
              child: Transform.translate(
                offset: Offset(0, _dragDy.clamp(-24.0, _sheetH)),
                child: Container(
                  key: _sheetKey,
                  constraints: BoxConstraints(maxHeight: sheetMax),
                  decoration: sheetDeco,
                  // a long sheet scrolls; pulling past its top (or bottom) carries on as a swipe
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is OverscrollNotification && n.dragDetails != null) _drag(-n.overscroll);
                      if (n is ScrollEndNotification && _dragDy != 0) _endDrag(0);
                      return false;
                    },
                    child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 14), child: sheet),
                  ),
                ),
              ),
            ),
          ),
        // a question that needs an answer ("Are you at the escalator?", "Are you here?", "I've arrived"):
        // a pop-up over everything, so it is never hidden in a swiped-down sheet
        if (s.prompt != null && !s.locSheet) const Positioned.fill(child: PromptOverlay()),
        // arriving (keyed, so the burst survives the pop-up leaving the stack just before it)
        Positioned.fill(key: const ValueKey('confetti'), child: Confetti(burst: _burst, colors: p.confetti)),
      ],
    );
  }
}

class _MapCanvas extends ConsumerWidget {
  const _MapCanvas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = MapScope.of(context), map = sc.map;
    final reduce = sc.settings.reduceMotion || MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      key: const ValueKey('map-canvas'),
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => map.mapTap(d.localPosition),
      onScaleStart: (d) => map.gestureStart(),
      onScaleUpdate: (d) => map.gestureUpdate(focal: d.localFocalPoint, delta: d.focalPointDelta, scale: d.scale, rotation: d.rotation, pointers: d.pointerCount),
      child: Semantics(
        container: true,
        label: sc.t.mapSummary(sc.mv.mode, sc.mv.level),
        child: CustomPaint(
          painter: MapPainter(sc.mv, sc.s, context.mapPal, ref.watch(wordsProvider), textScale: MediaQuery.textScalerOf(context).scale(1), reduceMotion: reduce),
          size: Size.infinite,
        ),
      ),
    );
  }
}

// The Map tab: the map and everything over it (from the demo's PhoneShell,
// restyled to the board's main screen): the header with the mall, the search
// bar, the category chips, the level chips, the tools, the banner, the wing pad,
// "set my location" and "centre on me", the draggable sheet, the question
// pop-up and the arrival confetti.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/brand.dart';
import '../../../shared/widgets/confetti.dart';
import '../../../shared/widgets/mall_switcher.dart';
import '../../malls/providers/mall_provider.dart';
import '../../navigation/providers/nav_provider.dart';
import '../../navigation/services/narration.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/providers/words_provider.dart';
import '../providers/map_provider.dart';
import '../services/map_painter.dart';
import 'widgets/map_scope.dart';
import 'widgets/map_sheet.dart';
import 'widgets/map_tools.dart';
import 'widgets/prompt_overlay.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _sheetKey = GlobalKey();
  final _locFocus = FocusNode();
  double _sheetH = 0;
  int _version = 0, _burst = 0;

  // how far the sheet has been dragged (down is positive), until it snaps
  double _dragDy = 0;

  /// set my location + centre on me, stacked
  static const _locPairH = SquareBtn.size * 2 + 8.0;

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

  void _measureSheet() {
    if (!mounted) return;
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    final h = (box != null && box.hasSize) ? box.size.height : 0.0;
    if ((h - _sheetH).abs() > 0.5) setState(() => _sheetH = h);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureSheet());
    final settingsN = ref.read(settingsProvider.notifier);
    return MapScope(
      s: s,
      mv: mv,
      t: t,
      nav: ref.read(navProvider.notifier),
      map: ref.read(mapProvider.notifier),
      settings: settings,
      mallId: mallId,
      version: ++_version,
      onFoldRail: settingsN.toggleRail,
      onFoldLevels: settingsN.toggleLevels,
      child: ColoredBox(
        color: context.mapPal['ground'],
        child: LayoutBuilder(builder: (context, c) => _layout(context, c.biggest)),
      ),
    );
  }

  Widget _layout(BuildContext context, Size size) {
    final sc = MapScope.of(context), s = sc.s, mv = sc.mv, map = sc.map, p = context.pal;
    final mode = mv.mode, site = mode == 'site', stack = mode == 'stack';
    final top = MediaQuery.paddingOf(context).top + 8;
    final searchTop = top + 44, chipsTop = top + 100, railTop = top + 100 + CategoryChips.height;
    // the middle of the map area, between the top chrome and the sheet
    mv.centreX = size.width / 2;
    mv.centreY = (railTop - 20 + size.height - _sheetH) / 2;
    map.syncSheet(sheetKind(s));
    final body = sheetBody(context, locFocus: _locFocus);
    final sheet = body != null && mv.sheetMin ? sheetMini(context) : body;
    final sheetTop = size.height - _sheetH;
    final pad = !site && !stack && sc.s.v.pad.isNotEmpty;
    // the sheet is at most 380 px, less on a short phone, so a row of tools and the location pair always fit above it
    final sheetMax = (size.height - railTop - 10 - Rail.minHeight - 12 - _locPairH).clamp(140.0, 380.0);
    final levelsMax = (pad ? sheetTop - 12 - WingPad.height : sheetTop - 12) - 10 - railTop;
    final railMax = sheetTop - 12 - _locPairH - 10 - railTop;
    final toolCount = Rail.count(sc);
    return Stack(
      children: [
        // the map
        const Positioned.fill(child: _MapCanvas()),
        // level chips
        if (!site && levelsMax >= Levels.minHeight) Positioned(left: 14, top: railTop, child: Levels(maxHeight: levelsMax)),
        // the rail
        if (railMax >= Rail.minHeight) Positioned(right: 14, top: railTop, child: Rail(maxHeight: railMax)),
        // banner: clear of the level chips on the left and of however many columns the rail wraps into
        Positioned(left: 68, right: 14 + (sc.settings.railFolded ? SquareBtn.size : Rail.width(railMax, toolCount)) + 8, top: railTop, child: const MapBanner()),
        // category chips
        if (!s.emergency) Positioned(left: 0, right: 0, top: chipsTop, child: const CategoryChips()),
        // dock: wing pad, set my location / centre on me, the sheet
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: pad
                        // shrinks on very narrow phones instead of overflowing
                        ? const Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(padding: EdgeInsets.only(right: 8), child: FittedBox(fit: BoxFit.scaleDown, child: WingPad())),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    SquareBtn(key: const ValueKey('setloc'), icon: 'i-pin', label: sc.tr('Set my location'), color: p.brand2, onTap: sc.nav.openLocation),
                    const SizedBox(height: 8),
                    SquareBtn(key: const ValueKey('recenter'), icon: 'i-nav', label: sc.tr('Centre on me'), color: p.brand2, onTap: s.hasPosition ? map.recenter : sc.nav.openLocation),
                  ]),
                ]),
              ),
              if (sheet != null)
                // a draggable sheet: swipe down to one line, swipe up to open it again
                GestureDetector(
                  key: const ValueKey('sheet'),
                  onVerticalDragUpdate: (d) => _drag(d.delta.dy),
                  onVerticalDragEnd: (d) => _endDrag(d.primaryVelocity ?? 0),
                  child: Transform.translate(
                    offset: Offset(0, _dragDy.clamp(-24.0, _sheetH)),
                    child: Container(
                      key: _sheetKey,
                      constraints: BoxConstraints(maxHeight: sheetMax),
                      decoration: BoxDecoration(
                        color: p.panel,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        border: Border(top: BorderSide(color: p.line, width: p.lineW), left: BorderSide(color: p.line, width: p.lineW), right: BorderSide(color: p.line, width: p.lineW)),
                        boxShadow: p.shadow,
                      ),
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
            ],
          ),
        ),
        // the header: the wordmark and the mall
        Positioned(
          left: 14,
          right: 14,
          top: top,
          child: const SizedBox(
            height: 36,
            child: Row(children: [
              BrandWordmark(size: 22),
              SizedBox(width: 12),
              Spacer(),
              Flexible(flex: 4, child: Align(alignment: Alignment.centerRight, child: MallSwitcher(compact: true))),
            ]),
          ),
        ),
        // search
        Positioned(left: 14, right: 14, top: searchTop, child: const MapSearchBar()),
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

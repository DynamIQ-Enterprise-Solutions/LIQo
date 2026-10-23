// Walking a route, in Google Maps' style (owner decisions 2026-10-23): a compact
// next-turn banner on top in the brand colour (it shrinks to a pill after 4 s), and a bottom bar with the minutes,
// the distance, Pause and End; tapping the bar opens the notes, other ways and
// all the steps. The evacuation looks the same in red, with the next step to the
// exit on top and the minutes to the exit, Get help and Stop evacuation below.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Step;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/clock.dart';
import '../../../../core/engine/routing.dart';
import '../../../../core/theme.dart';
import '../../../../shared/widgets/common.dart';
import '../../../../shared/widgets/glyphs.dart';
import '../../../navigation/models/nav_state.dart';
import '../../../navigation/services/narration.dart';
import '../../../places/services/place_info_catalog.dart';
import '../../../places/services/place_status.dart';
import '../../../saved/providers/saved_providers.dart';
import 'location_panel.dart';
import 'map_scope.dart';
import 'reroute_panel.dart';

/// Walking a route (or the way out): the banner and the bottom bar replace the search, the chips and the sheet.
bool navMode(NavState s) {
  final r = s.route;
  if (s.locSheet || s.reroute != null || r == null || s.arrived || s.preview) return false;
  if (s.emergency) return s.evac != null && !s.evac!.outside;
  return s.place != null && s.wcError == null;
}

/// Which way a step points, for the banner's shine and arrow: left, right, up, down, or ahead
/// (drawn as left to right).
Offset _pointing({String? turn, int? from, int? to}) {
  if (turn != null) return turn.endsWith('left') ? const Offset(-1, 0) : const Offset(1, 0);
  if (from != null && to != null && from != to) return to > from ? const Offset(0, -1) : const Offset(0, 1);
  return const Offset(1, 0);
}

/// The next step, on top, in one compact line (owner decisions 2026-10-23). A new step opens it in
/// full with a shine sweeping and the arrow sliding the way the step points; after 4 seconds it
/// shrinks to a small pill, until the next step or a tap. The evacuation's banner is the same in red.
class NavBanner extends StatefulWidget {
  const NavBanner({super.key});

  static const shrinkAfter = Duration(seconds: 4);

  @override
  State<NavBanner> createState() => _NavBannerState();
}

class _NavBannerState extends State<NavBanner> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900), value: 1);
  Timer? _shrink;
  String? _step;
  bool _small = false;

  @override
  void dispose() {
    _shrink?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _showFull() {
    _small = false;
    _shrink?.cancel();
    _shrink = Timer(NavBanner.shrinkAfter, () {
      if (mounted) setState(() => _small = true);
    });
  }

  /// A new step: full again, then the shine and the arrow's slide.
  void _newStep(String key, bool reduce) {
    if (key == _step) return;
    _step = key;
    _showFull();
    if (reduce) {
      _anim.value = 1;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _anim.forward(from: 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), s = sc.s, t = sc.t, p = context.pal, r = s.route!;
    final reduce = sc.settings.reduceMotion || MediaQuery.disableAnimationsOf(context);
    final String icon, title, step, pill;
    String? metres, extra, tag;
    final Color bg, fg;
    final String spoken;
    final Offset dir;
    if (s.emergency) {
      final steps = stepsOf(r), i = steps.indexWhere((st) => r.progress < st.endAt - 0.001);
      final st = steps.isEmpty ? null : steps[i < 0 ? steps.length - 1 : i];
      icon = st == null ? 'i-alert' : t.stepIcon(st);
      title = st == null ? sc.tr('Emergency: get out by the nearest exit') : t.stepText(st);
      extra = sc.tr('Use the stairs, not the lifts');
      pill = title;
      dir = st != null && st.kind == 'hop' ? _pointing(from: st.from, to: st.to) : _pointing();
      step = 'e:$i';
      bg = p.danger;
      fg = p.panel;
      spoken = '${sc.tr('Emergency')}. $title. $extra';
    } else {
      final next = s.nextDirection, transit = pointAt(r, r.progress).transit;
      if (transit != null) {
        // riding: the ride's own floor, not the next direction's
        final to = s.ridingTo ?? next?.$2.to ?? r.verts.last.lv;
        icon = 'g-${transit.ctype}';
        title = sc.tr('Riding the ${hopName[transit.ctype]![0]} to ${t.levelLow(to)}');
        extra = t.landingShown;
        pill = t.levelName(to);
        dir = _pointing(from: s.user?.lv, to: to);
        step = 'r:${transit.ctype}:$to';
        spoken = title;
      } else if (next != null) {
        final d = next.$2, m = d.atM - r.progress;
        icon = d.glyph;
        title = t.dirTitle(d);
        metres = m >= 3 ? t.fmtM(m) : d.kind == 'arrive' ? null : sc.tr('now');
        // a second line only when there is more to say: paused, a passing cue, what to expect after a ride
        extra = s.paused ? sc.tr('Paused · tap Resume to go on') : s.cueShown ?? t.afterRideLine;
        pill = metres ?? title;
        dir = d.kind == 'turn' ? _pointing(turn: d.turn) : d.kind == 'hop' ? _pointing(from: d.from, to: d.to) : _pointing();
        step = 'd:${next.$1}';
        spoken = t.narrate(next.$1).text;
      } else {
        icon = 'i-flag';
        title = sc.tr('Almost there');
        pill = title;
        dir = _pointing();
        step = 'end';
        spoken = title;
      }
      tag = s.paused ? sc.tr('Paused') : s.almostThere && next != null ? sc.tr('Almost there') : null;
      bg = p.brand;
      fg = p.onBrand;
    }
    _newStep('${identityHashCode(r)}:$step', reduce);

    // the arrow slides in the way the step points, settling with a small overshoot
    Widget arrow(double size) => AnimatedBuilder(
          animation: _anim,
          builder: (context, child) {
            final a = (_anim.value / .6).clamp(0.0, 1.0);
            return Opacity(
              opacity: (a / .4).clamp(0.0, 1.0),
              child: Transform.translate(offset: -dir * 22 * (1 - Curves.easeOutBack.transform(a)), child: child),
            );
          },
          child: AppIcon(icon, size: size, color: fg),
        );
    final radius = BorderRadius.circular(_small ? 999 : 18);
    final Widget body;
    if (_small) {
      body = Tap(
        key: const ValueKey('nav-banner-small'),
        onTap: () => setState(_showFull),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            arrow(24),
            const SizedBox(width: 8),
            Flexible(child: Text(pill, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(16, w: FontWeight.w800, color: fg))),
            if (s.paused) ...[const SizedBox(width: 8), AppIcon('i-pause', size: 18, color: fg)],
          ]),
        ),
      );
    } else {
      body = SizedBox(
        width: double.infinity,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(children: [
              arrow(32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: title),
                      if (metres != null) TextSpan(text: '  ·  $metres', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ts(17, w: FontWeight.w800, color: fg, height: 1.2),
                  ),
                  if (extra != null && extra.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text(extra, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w500, color: fg.withValues(alpha: .9)))),
                ]),
              ),
              if (tag != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(10)),
                  child: Text(tag, style: ts(12, w: FontWeight.w800, color: bg)),
                ),
              ],
            ]),
          ),
          // the shine, sweeping the way the step points
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, _) => CustomPaint(painter: _Shine(Curves.easeInOut.transform(_anim.value), dir, p.onBrand.withValues(alpha: .38))),
              ),
            ),
          ),
        ]),
      );
    }
    return Semantics(
      liveRegion: true,
      container: true,
      button: _small,
      label: tag == null ? spoken : '$tag. $spoken',
      onTap: _small ? () => setState(_showFull) : null,
      child: ExcludeSemantics(
        child: Align(
          alignment: Alignment.topLeft,
          child: AnimatedSize(
            duration: reduce ? Duration.zero : const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: Container(
              key: const ValueKey('nav-banner'),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: bg, borderRadius: radius, boxShadow: p.shadow),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft band of light crossing the banner once, in the step's direction.
class _Shine extends CustomPainter {
  _Shine(this.t, this.dir, this.color);
  final double t;
  final Offset dir;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final across = dir.dy == 0, len = across ? size.width : size.height, band = across ? 110.0 : size.height;
    // the band's middle runs from before the near edge to past the far one
    final forward = dir.dx + dir.dy > 0, c = -band + (len + 2 * band) * (forward ? t : 1 - t);
    final from = across ? Offset(c - band / 2, 0) : Offset(0, c - band / 2);
    final to = across ? Offset(c + band / 2, size.height * .6) : Offset(size.width * .2, c + band / 2);
    final clear = color.withValues(alpha: 0);
    canvas.drawRect(Offset.zero & size, Paint()..shader = ui.Gradient.linear(from, to, [clear, color, clear], [0, .5, 1]));
  }

  @override
  bool shouldRepaint(_Shine old) => old.t != t || old.dir != dir || old.color != color;
}

/// The bottom bar while walking: minutes and distance left, Pause and End. Tapping it (or swiping
/// it up) opens the notes, Find another way, the route options and all the steps.
class NavBottomBar extends ConsumerWidget {
  const NavBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = MapScope.of(context), s = sc.s, t = sc.t, p = context.pal, m = context.mapPal, r = s.route!;
    final pl = s.placeById(s.place!)!, open = sc.mv.navOpen, rem = r.total - r.progress;
    final fav = ref.watch(favouritesProvider).any((f) => f.mallId == sc.mallId && f.placeId == pl.id);
    final status = placeStatus(pl, placeInfoFor(s.v, pl), ref.watch(clockProvider)(), t.w);
    final big = ts(22, w: FontWeight.w800, ls: -.2, color: m['route-text']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        button: true,
        expanded: open,
        label: sc.tr(open ? 'Hide the details' : 'Show the details'),
        onTap: sc.map.toggleNavOpen,
        child: Tap(
          key: const ValueKey('nav-expand'),
          onTap: sc.map.toggleNavOpen,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Grab(),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: t.fmtEta(rem), style: big),
                    TextSpan(text: '  ·  ${t.fmtM(rem)}', style: big.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
                  ])),
                  Text(sc.tr('To ${pl.name} · ${s.levels[pl.lv].name}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(13.5, color: p.muted)),
                  // not open: the way is still given; its status says why (owner decision 2026-10-23)
                  if (status.notOpen && pl.kind != 'zone' && pl.kind != 'conn') Text(status.line, key: const ValueKey('nav-status'), style: ts(13.5, w: FontWeight.w700, color: statusColour(p, status.key))),
                ]),
              ),
              const SizedBox(width: 8),
              AppIcon(open ? 'i-down' : 'i-up', color: p.muted),
            ]),
          ]),
        ),
      ),
      // a lift, escalator or stairs on this route went out of service: say so, offer another way
      if (s.outNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            key: const ValueKey('out-note'),
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(color: p.maintBg, borderRadius: BorderRadius.circular(12)),
            // the words, then the button under them (no crowding on a narrow phone with large text)
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.construction_rounded, size: 18, color: p.maint),
                const SizedBox(width: 8),
                Expanded(child: Text(sc.tr('${s.outNote}: out of service'), style: ts(13.5, w: FontWeight.w700, color: p.ink))),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(key: const ValueKey('out-reroute'), onPressed: sc.nav.findAnotherWay, child: Text(sc.tr('Find another way'))),
              ),
            ]),
          ),
        ),
      // start, pause or resume, and End (at the end the pop-up asks for "I've arrived" instead)
      btns([
        if (s.prompt != 'end')
          s.playing
              ? Btn(sc.tr('Pause'), key: const ValueKey('walk'), primary: true, onTap: sc.nav.pause, semantics: sc.tr('Pause the walk'))
              : s.paused
                  ? Btn(sc.tr('Resume'), key: const ValueKey('walk'), primary: true, onTap: sc.nav.resume, semantics: sc.tr('Resume the walk'))
                  : Btn(sc.tr('Start'), key: const ValueKey('walk'), primary: true, onTap: sc.nav.start, semantics: sc.tr('Start the walk')),
        Btn(sc.tr('End'), key: const ValueKey('nav-end'), danger: true, onTap: sc.nav.stop, semantics: sc.tr('End the route')),
      ], top: 10),
      if (open) ...[
        if (s.helpNote) helpNote(context),
        // the shopper avoids stairs or escalators, but nothing else reaches the place
        if (s.needsNote != null)
          note(
            context,
            'warn',
            Text(s.needsNote == 'stairs' ? sc.tr('This way needs stairs: no lift or ramp reaches this floor.') : sc.tr('This way needs an escalator: nothing else reaches this floor.')),
          ),
        findAnotherWayRow(context),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Btn(sc.tr('All the steps'), key: const ValueKey('nav-steps'), onTap: () => context.push('/route')),
            if (pl.kind != 'conn') ...[
              const SizedBox(width: 10),
              RoundBtn('i-star', on: fav, label: fav ? sc.tr('Remove from favourites') : sc.tr('Add to favourites'), onTap: () => ref.read(favouritesProvider.notifier).toggle(sc.mallId, pl.id)),
            ],
          ]),
        ),
      ],
    ]);
  }
}

/// The bottom bar of the way out: minutes to the exit, Start or Pause, Get help, Stop evacuation.
class EvacBottomBar extends StatelessWidget {
  const EvacBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), s = sc.s, t = sc.t, p = context.pal, r = s.route!, e = s.evac!;
    final rem = r.total - r.progress, big = ts(22, w: FontWeight.w800, ls: -.2, color: p.danger);
    final where = e.refuge ? sc.tr('the stairs (a safe place to wait)') : e.exit!.name;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Grab(),
      Text.rich(TextSpan(children: [
        TextSpan(text: t.fmtEta(rem), style: big),
        TextSpan(text: '  ·  ${t.fmtM(rem)}', style: big.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
      ])),
      Text(sc.tr('To $where'), maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(13.5, color: p.muted)),
      if (e.refuge)
        iconNote(
          context,
          'warn',
          'i-flag',
          s.routeOpts.wheel
              ? sc.tr('Lifts must not be used in an emergency. Go to the stairs and wait there: staff will help you down.')
              : sc.tr('No exit can be reached from here. Go to the stairs and wait for staff.'),
        ),
      if (s.evacHelp) iconNote(context, 'info', 'i-help', sc.tr('Tell any member of staff where you are. Staff are trained to help everyone get out.')),
      btns([
        s.playing
            ? Btn(sc.tr('Pause'), key: const ValueKey('walk'), danger: true, onTap: sc.nav.pause, semantics: sc.tr('Pause the walk'))
            : Btn(sc.tr('Start'), key: const ValueKey('walk'), danger: true, onTap: sc.nav.start, semantics: sc.tr('Start the walk')),
      ], top: 10),
      btns([Btn(sc.tr('Get help'), onTap: sc.nav.help), Btn(sc.tr('Stop evacuation'), key: const ValueKey('evac-stop'), onTap: sc.nav.stopEmergency)], top: 10),
    ]);
  }
}

// The bottom nav (Home / Map / Saved / More, as on the board) around the four
// tabs. It also runs the clock of the simulated walk, so the walk goes on while
// another tab is shown (owner decision 2026-10-22), buzzes on arrival, tells the
// navigation when the Map tab is on screen, handles Back on the tabs' first
// screens (to Home, then out), and holds a mall's map update back while a trip
// is going there, switching it in (position kept) once the trip ends.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/theme.dart';
import '../../features/malls/providers/mall_provider.dart';
import '../../features/malls/providers/malls_provider.dart';
import '../../features/map/providers/map_provider.dart';
import '../../features/navigation/models/nav_state.dart';
import '../../features/navigation/providers/nav_provider.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../features/settings/providers/words_provider.dart';
import 'toast.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  /// The Map tab's index.
  static const mapTab = 1;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int? _reportedTab;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final nav = ref.read(navProvider.notifier), map = ref.read(mapProvider.notifier);
      nav.tick(elapsed);
      map.tick(elapsed);
      if (!nav.animating && !ref.read(mapProvider).animating) _ticker.stop();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _maybeStartTicker() {
    if (!mounted || _ticker.isActive) return;
    if (ref.read(navProvider.notifier).animating || ref.read(mapProvider).animating) {
      ref.read(navProvider.notifier).tickerStarted();
      _ticker.start();
    }
  }

  void _reportTab() {
    final i = widget.shell.currentIndex;
    if (_reportedTab == i) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reportedTab == widget.shell.currentIndex) return;
      _reportedTab = widget.shell.currentIndex;
      ref.read(navProvider.notifier).setMapVisible(_reportedTab == AppShell.mapTab);
    });
  }

  /// A trip or an evacuation is going on.
  static bool _tripOn(NavState s) => s.emergency || (s.route != null && !s.arrived);

  /// The trip ended: an update that waited for it is switched in, the shopper's spot kept.
  Future<void> _applyPending() async {
    final id = ref.read(mallProvider);
    if (id == null || ref.read(mallsProvider).saved[id]?.pending == null) return;
    final u = ref.read(navProvider).user, w = ref.read(wordsProvider);
    if (!await ref.read(mallsProvider.notifier).applyPending(id) || !mounted) return;
    if (u != null) ref.read(navProvider.notifier).refineAt(u.lv, u.x, u.y);
    showToast(context, w.tr('Map updated'));
  }

  void _back() {
    final i = widget.shell.currentIndex;
    if (i == AppShell.mapTab && ref.read(navProvider.notifier).handleBack()) return;
    if (i != 0) {
      widget.shell.goBranch(0);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(navProvider, (_, _) => _maybeStartTicker());
    ref.listen(mapProvider, (_, _) => _maybeStartTicker());
    // map updates wait while a trip is going in this mall
    ref.listen(navProvider.select(_tripOn), (_, on) {
      ref.read(mallsProvider.notifier).tripIn = on ? ref.read(mallProvider) : null;
      if (!on) _applyPending();
    });
    ref.listen(mallsProvider.select((m) => m.saved[ref.read(mallProvider)]?.pending), (_, pending) {
      if (pending != null && !_tripOn(ref.read(navProvider))) _applyPending();
    });
    // arriving: a buzz, on whichever tab is shown
    ref.listen(navProvider.select((s) => s.arrivalSeq), (a, b) {
      if (b > (a ?? 0) && ref.read(settingsProvider).vibration) ref.read(hapticsProvider).arrive();
    });
    _reportTab();
    final p = context.pal, w = ref.watch(wordsProvider), i = widget.shell.currentIndex;
    final items = [
      (Icons.home_outlined, Icons.home, w.tr('Home')),
      (Icons.map_outlined, Icons.map, w.tr('Map')),
      (Icons.bookmark_border, Icons.bookmark, w.tr('Saved')),
      (Icons.more_horiz, Icons.more_horiz, w.tr('More')),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: widget.shell,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(color: p.panel, border: Border(top: BorderSide(color: p.line, width: p.lineW))),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(children: [
                for (final (k, (icon, active, label)) in items.indexed)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: k == i,
                      label: label,
                      excludeSemantics: true,
                      onTap: () => widget.shell.goBranch(k, initialLocation: k == i),
                      child: InkWell(
                        key: ValueKey('tab-$k'),
                        onTap: () => widget.shell.goBranch(k, initialLocation: k == i),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(k == i ? active : icon, color: k == i ? p.brand : p.muted, size: 24),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
                            style: ts(11.5, w: k == i ? FontWeight.w700 : FontWeight.w500, color: k == i ? p.brand : p.muted),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// Downloading malls through the screens (owner decisions 2026-10-23): the
// picker downloads a mall it doesn't have and opens it; with no connection and
// no mall it is the "Connect once" screen, which tries again by itself; a first
// download on mobile data asks; Saved malls deletes a mall and Saved keeps its
// places greyed; Home's card offers an update waiting on mobile data and can be
// hidden for the day; a retired app version shows only "Please update LIQo".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liqo_mobile/core/data/net.dart';
import 'package:liqo_mobile/core/router.dart';
import 'package:liqo_mobile/features/malls/providers/mall_provider.dart';
import 'package:liqo_mobile/features/malls/providers/malls_provider.dart';
import 'package:liqo_mobile/features/navigation/providers/nav_provider.dart';
import 'package:liqo_mobile/features/saved/providers/saved_providers.dart';

import '../support/app.dart';
import '../support/fake_server.dart';
import '../support/spots.dart';

extension on AppHarness {
  MallsState get malls => c.read(mallsProvider);
  String get path {
    final cfg = c.read(routerProvider).routerDelegate.currentConfiguration, last = cfg.last;
    return last is ImperativeRouteMatch ? last.matches.uri.path : cfg.uri.path;
  }

  Future<void> tapKey(String key, {int frames = 30}) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await step(frames);
  }
}

void main() {
  testWidgets('the picker lists the directory by mall, downloads a mall and opens it', (tester) async {
    final h = await pumpApp(tester, mall: null);
    expect(find.text('Choose a mall'), findsOneWidget);
    expect(find.text('LIQO SAMPLE MALLS'), findsOneWidget, reason: 'branches grouped under their mall');
    expect(find.byKey(const ValueKey('chip-saved')), findsNothing, reason: 'nothing on the phone yet');
    await h.tapKey('mall-spire');
    expect(h.api.calls, contains('package:spire'));
    expect(h.malls.isSaved('spire'), isTrue);
    expect(h.c.read(mallProvider), 'spire');
    expect(find.text('Categories'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no mall and no connection: "Connect once", which tries again by itself', (tester) async {
    final api = FakeShopperApi()..offline = true;
    final h = await pumpApp(tester, mall: null, api: api, net: NetKind.none);
    await h.step(10);
    expect(find.byKey(const ValueKey('connect-once')), findsOneWidget);
    expect(find.text('Connect once to download your mall'), findsOneWidget);
    // the connection comes back
    api.offline = false;
    h.net.value = NetKind.wifi;
    await tester.pump(const Duration(seconds: 11));
    await h.step(10);
    expect(find.byKey(const ValueKey('connect-once')), findsNothing);
    expect(find.byKey(const ValueKey('mall-bayview')), findsOneWidget);
  });

  testWidgets('a first download on mobile data asks first', (tester) async {
    final h = await pumpApp(tester, mall: null, net: NetKind.mobile);
    await h.tapKey('mall-meridian');
    expect(find.text('Download on mobile data?'), findsOneWidget);
    await h.tapKey('mobile-no');
    expect(h.malls.isSaved('meridian'), isFalse);
    await h.tapKey('mall-meridian');
    await h.tapKey('mobile-yes');
    expect(h.malls.isSaved('meridian'), isTrue);
    expect(h.c.read(mallProvider), 'meridian');
  });

  testWidgets('Saved malls: delete a mall; Saved keeps its places greyed and can download it again', (tester) async {
    final h = await pumpApp(tester, installed: ['bayview', 'spire']);
    final place = h.malls.venues['spire']!.places.firstWhere((p) => p.kind == 'store');
    h.c.read(favouritesProvider.notifier).toggle('spire', place.id);
    h.c.read(routerProvider).push('/more/malls');
    await h.step(30);
    expect(find.byKey(const ValueKey('saved-mall-spire')), findsOneWidget);
    await h.tapKey('saved-mall-delete-spire');
    await h.tapKey('delete-yes');
    expect(h.malls.isSaved('spire'), isFalse);
    h.c.read(routerProvider).go('/saved');
    await h.step(30);
    expect(find.text(place.name), findsOneWidget);
    expect(find.textContaining('Download this mall to use it'), findsOneWidget);
    await tester.tap(find.text(place.name));
    await h.step(30);
    expect(h.malls.isSaved('spire'), isTrue, reason: 'opening it downloads the mall again');
    expect(h.path, '/place/spire/${place.id}');
  });

  testWidgets('Home card: an update waiting on mobile data; Update downloads it; hide for today', (tester) async {
    final api = FakeShopperApi();
    final h = await pumpApp(tester, api: api, net: NetKind.mobile);
    api.publish('bayview', 2);
    await h.c.read(mallsProvider.notifier).checkForUpdates();
    await h.step(5);
    expect(find.byKey(const ValueKey('update-card')), findsOneWidget);
    await h.tapKey('update-card-go');
    expect(h.malls.saved['bayview']!.package.version, 2);
    expect(find.byKey(const ValueKey('update-card')), findsNothing);
    api.publish('bayview', 3);
    await h.c.read(mallsProvider.notifier).checkForUpdates();
    await h.step(5);
    await h.tapKey('update-card-hide');
    expect(find.byKey(const ValueKey('update-card')), findsNothing, reason: 'hidden for the day');
    await tester.pump(const Duration(seconds: 5)); // the toast
  });

  testWidgets('a retired app version shows only "Please update LIQo"', (tester) async {
    final api = FakeShopperApi()..mustUpdateBelow = '99.0.0';
    final h = await pumpApp(tester, api: api);
    await h.step(10);
    expect(find.byKey(const ValueKey('update-app')), findsOneWidget);
    expect(h.path, '/update-app');
  });

  testWidgets('out of service: a mid-trip mark shows a note with Find another way; new routes avoid it', (tester) async {
    final api = FakeShopperApi();
    final h = await pumpApp(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await h.step(20);
    final nav = h.c.read(navProvider.notifier);
    final st = scenarioStart(h.c.read(navProvider).v);
    nav.refineAt(st.lv, st.x, st.y);
    nav.startTo('3-M1');
    await h.step(10);
    final conn = h.c.read(navProvider).route!.conns.first;
    api.setLive('bayview', {
      'stores': const [],
      'outOfService': [
        {'connectorId': conn},
      ],
    });
    await h.c.read(mallsProvider.notifier).checkForUpdates();
    await h.step(10);
    expect(find.byKey(const ValueKey('out-note')), findsOneWidget);
    expect(h.c.read(navProvider).route!.conns, contains(conn), reason: 'the route does not change by itself');
    await h.tapKey('out-reroute');
    expect(h.c.read(navProvider).reroute, isNotNull);
    nav.stop();
    nav.startTo('3-M1');
    await h.step(10);
    expect(h.c.read(navProvider).route!.conns, isNot(contains(conn)), reason: 'new routes avoid it');
    expect(find.byKey(const ValueKey('out-note')), findsNothing);
  });

  testWidgets('a store not on the map yet is listed with Update now', (tester) async {
    final api = FakeShopperApi();
    final h = await pumpApp(tester, api: api);
    api.setLive('bayview', {
      'stores': [
        {'storeId': 9, 'spaceIds': ['sp_new'], 'name': 'Taco Stop', 'category': 'food'},
      ],
    });
    await h.c.read(mallsProvider.notifier).checkForUpdates();
    h.c.read(routerProvider).push('/home/category/food');
    await h.step(30);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('not-on-map-9')), 300, scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
    expect(find.text('Directions come with the next map update'), findsOneWidget);
    expect(find.byKey(const ValueKey('not-on-map-update-9')), findsOneWidget);
  });
}

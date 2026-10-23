// Posts on Home (owner decisions 2026-10-23): a feed, newest first, 10 at a time
// with "More posts"; ended posts hidden; offline the last loaded posts stay with
// "You're offline · showing posts from …"; a store's post has Directions; the
// heart and Comment wait for accounts; pictures are kept up to a limit.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/data/blob_store.dart';
import 'package:liqo_mobile/core/data/net.dart';
import 'package:liqo_mobile/core/data/picture_cache.dart';
import 'package:liqo_mobile/core/storage/store.dart';
import 'package:liqo_mobile/features/home/providers/posts_provider.dart';
import 'package:liqo_mobile/features/navigation/providers/nav_provider.dart';

import '../support/app.dart';
import '../support/fake_server.dart';
import '../support/spots.dart';

extension on AppHarness {
  Future<void> tapKey(String key, {int frames = 30}) async {
    final f = find.byKey(ValueKey(key));
    // Home's own list (inside its pull-to-refresh)
    await tester.scrollUntilVisible(f, 300, scrollable: find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable)).first);
    await tester.pump();
    await tester.tap(f);
    await step(frames);
  }
}

void main() {
  testWidgets('the feed: 10 at a time, "More posts" loads the next page; ended posts never show', (tester) async {
    final api = FakeShopperApi()
      ..setPosts('bayview', [
        for (var i = 25; i >= 1; i--) fakePost(i),
        fakePost(99, title: 'Ended', ends: '2026-10-10'),
      ]);
    final h = await pumpApp(tester, api: api);
    await h.step(10);
    expect(h.c.read(postsProvider).items, hasLength(10));
    expect(find.byKey(const ValueKey('post-25')), findsOneWidget);
    await h.tapKey('posts-more');
    expect(h.c.read(postsProvider).visible(h.c.read(postsProvider.notifier).today()), hasLength(20));
    await h.tapKey('posts-more');
    final shown = h.c.read(postsProvider).visible(h.c.read(postsProvider.notifier).today());
    expect(shown, hasLength(25));
    expect(shown.where((p) => p.id == '99'), isEmpty, reason: 'its last day has passed');
    expect(find.byKey(const ValueKey('posts-more')), findsNothing);
  });

  testWidgets('offline: the last loaded posts stay, saying when they are from', (tester) async {
    final api = FakeShopperApi()..setPosts('bayview', [fakePost(1), fakePost(2)]);
    final h = await pumpApp(tester, api: api);
    await h.step(10);
    expect(find.byKey(const ValueKey('posts-offline')), findsNothing);
    api.offline = true;
    h.net.value = NetKind.none;
    await h.c.read(postsProvider.notifier).refresh();
    await h.step(5);
    expect(find.byKey(const ValueKey('posts-offline')), findsOneWidget);
    expect(find.byKey(const ValueKey('post-1')), findsOneWidget);
  });

  testWidgets("a store's post has Directions to the store; the heart asks to sign in", (tester) async {
    final h = await pumpApp(tester); // the stand-in server's sample posts
    await h.step(10);
    final nav = h.c.read(navProvider.notifier);
    final st = scenarioStart(h.c.read(navProvider).v);
    nav.refineAt(st.lv, st.x, st.y);
    nav.stop();
    await h.tapKey('post-heart-bay-2', frames: 5);
    expect(find.text('Sign in to react and comment · Accounts are coming soon'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await h.tapKey('post-bay-2');
    expect(find.byKey(const ValueKey('post-directions')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-directions')));
    await h.step(30);
    expect(h.c.read(navProvider).route?.placeId, 'G-WDS');
    await tester.pump(const Duration(seconds: 4));
  });

  test('pictures are kept up to the limit, the least recently shown dropped first; offline only kept ones show', () async {
    var online = true;
    final cache = PictureCache(MemoryBlobStore(), MemoryStore(), (url) async {
      if (!online) throw Exception('offline');
      return Uint8List(100);
    }, limit: 250);
    await cache.get('https://x/a.png');
    await cache.get('https://x/b.png');
    await cache.get('https://x/c.png');
    expect(cache.size, lessThanOrEqualTo(250));
    online = false;
    expect(await cache.get('https://x/c.png'), isNotNull, reason: 'kept');
    expect(await cache.get('https://x/a.png'), isNull, reason: 'dropped first, and offline now');
  });
}

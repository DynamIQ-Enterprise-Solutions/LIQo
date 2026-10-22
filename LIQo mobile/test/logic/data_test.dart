// The sample data: place details (hours, fictional phones, example.com sites,
// About in both languages), opening status, the mall details and the sample
// posts.
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/i18n/words.dart';
import 'package:liqo_mobile/features/home/data/sample_posts.dart';
import 'package:liqo_mobile/features/home/models/sample_post.dart';
import 'package:liqo_mobile/features/malls/data/mall_info.dart';
import 'package:liqo_mobile/features/malls/data/registry.dart';
import 'package:liqo_mobile/features/places/models/category.dart';
import 'package:liqo_mobile/features/places/models/place_info.dart';
import 'package:liqo_mobile/features/places/services/place_actions.dart';
import 'package:liqo_mobile/features/places/services/place_info_catalog.dart';
import 'package:liqo_mobile/features/places/services/place_status.dart';

import '../support/harness.dart';

void main() {
  test('place details are the same every time, fictional and in both languages', () {
    final phone = RegExp(r'^\+63 2 5550 01\d\d$');
    for (final e in venueRegistry) {
      final v = e.build(), again = e.build();
      for (final p in v.places) {
        final a = placeInfoFor(v, p), b = placeInfoFor(again, again.placeById(p.id)!);
        expect((a.phone, a.website, a.about.en, a.art.tone), (b.phone, b.website, b.about.en, b.art.tone), reason: p.id);
        final shop = p.kind == 'store' || p.kind == 'box';
        if (shop) {
          expect(a.phone, matches(phone), reason: p.id);
          expect(int.parse(a.phone!.substring(a.phone!.length - 2)), greaterThanOrEqualTo(3), reason: 'the malls have 00-02');
          expect(Uri.parse(a.website!).host, 'example.com', reason: p.id);
          expect(a.website, startsWith('https://example.com/${v.id}/'));
        } else {
          expect(a.phone, isNull);
          expect(a.website, isNull);
        }
        expect(a.about.en, isNotEmpty);
        expect(a.about.tl, isNotEmpty);
        expect(a.about.tl, isNot(a.about.en), reason: '${p.id}: About has its Tagalog');
      }
    }
    for (final m in mallInfos.values) {
      expect(m.phone, matches(phone));
      expect(Uri.parse(m.website).host, 'example.com');
    }
  });

  test('opening hours: 12-hour clock; food later, cinemas and arenas on their own hours, ATMs all day', () {
    expect(OpeningHours.clock(21 * 60), '9:00 PM');
    expect(OpeningHours.clock(10 * 60), '10:00 AM');
    expect(OpeningHours.clock(24 * 60), '12:00 AM');
    expect(OpeningHours.clock(12 * 60 + 30), '12:30 PM');
    final v = venueRegistry.first.build(), w = const Words('en');
    final food = v.places.firstWhere((p) => p.cat == 'food' && p.kind == 'store' && p.status == 'open');
    final shop = v.places.firstWhere((p) => p.cat == 'fashion' && p.kind == 'store' && p.status == 'open');
    final atm = v.places.firstWhere((p) => p.cat == 'atm');
    final cinema = v.placeById('2-IMX')!;
    expect(placeInfoFor(v, food).hours!.closeMin, placeInfoFor(v, shop).hours!.closeMin + 60);
    expect(placeStatus(atm, placeInfoFor(v, atm), DateTime(2026, 10, 22, 3), w).line, 'Open 24 hours');
    expect(placeStatus(shop, placeInfoFor(v, shop), DateTime(2026, 10, 22, 14), w).line, 'Open · Closes 10:00 PM');
    final night = placeStatus(shop, placeInfoFor(v, shop), DateTime(2026, 10, 22, 23), w);
    expect(night.key, 'closedNow');
    expect(night.line, 'Closed now · Opens 10:00 AM');
    expect(night.blocksRouting, isFalse, reason: 'closed by the hours, a place can still be routed to');
    expect(placeStatus(cinema, placeInfoFor(v, cinema), DateTime(2026, 10, 22, 23, 30), w).isOpen, isTrue);
    final closed = v.places.firstWhere((p) => p.status == 'closed');
    expect(placeStatus(closed, placeInfoFor(v, closed), DateTime(2026, 10, 22, 14), w).blocksRouting, isTrue);
    expect(placeStatus(shop, placeInfoFor(v, shop), DateTime(2026, 10, 22, 14), const Words('tl')).line, 'Bukas · Magsasara nang 10:00 PM');
  });

  test('five sample posts per mall from mixed authors; store posts point at real places', () {
    for (final e in venueRegistry) {
      final v = e.build(), posts = postsFor(e.id);
      expect(posts, hasLength(5), reason: e.id);
      expect(posts.map((p) => p.author).toSet(), {PostAuthor.mall, PostAuthor.store, PostAuthor.management}, reason: e.id);
      for (final p in posts) {
        expect(p.title.tl, isNot(p.title.en), reason: p.id);
        expect(p.body.tl, isNot(p.body.en), reason: p.id);
        if (p.author == PostAuthor.store) {
          final place = v.placeById(p.placeId!);
          expect(place, isNotNull, reason: '${p.id} -> ${p.placeId}');
          expect(place!.name, p.authorName, reason: p.id);
        }
      }
    }
    expect(samplePosts.map((p) => p.id).toSet(), hasLength(samplePosts.length));
  });

  test('categories: Shops is every store-type place but food; Elevators one row per lift bank; Parking the zones', () {
    final h = Harness();
    final shops = categoryById('shops').placesIn(h.s), food = categoryById('food').placesIn(h.s);
    expect(shops.every((p) => (p.kind == 'store' || p.kind == 'box') && p.cat != 'food'), isTrue);
    expect(shops.any((p) => p.cat == 'cinema') && shops.any((p) => p.cat == 'arena'), isTrue);
    expect(food.every((p) => p.cat == 'food'), isTrue);
    final lifts = categoryById('lift').placesIn(h.s);
    expect(lifts.length, h.v.connectors.where((c) => c.type == 'lift').length);
    expect(lifts.every((p) => p.id.startsWith('CONN:')), isTrue);
    expect(categoryById('parking').placesIn(h.s).every((p) => p.kind == 'zone'), isTrue);
  });

  test('Share sends the place, its level and the mall, as plain text', () {
    expect(shareText('Opal Comics', 'Level 3', 'Bayview Grand'), 'Opal Comics — Level 3, Bayview Grand');
  });

  test('a stable hash', () {
    expect(stableHash('bayview/3-M1'), stableHash('bayview/3-M1'));
    expect(slug('Bay IMAX · Lobby'), 'bay-imax-lobby');
  });
}

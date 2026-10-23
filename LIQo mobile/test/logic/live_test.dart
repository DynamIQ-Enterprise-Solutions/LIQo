// Live store info (docs/shopper-package-format.md §7, owner decisions
// 2026-10-23): hours per day in Philippine time with special days and their
// notes, a store without hours using the mall's, nothing said when no hours are
// known, stores renamed and re-statused in place (and back), kept on the phone
// for offline use, an unchanged reply skipped, and stores the map doesn't have
// yet listed apart.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/data/net.dart';
import 'package:liqo_mobile/core/engine/package/live_info.dart';
import 'package:liqo_mobile/core/engine/package/package_venue.dart';
import 'package:liqo_mobile/core/i18n/words.dart';
import 'package:liqo_mobile/features/malls/data/sample_server.dart';
import 'package:liqo_mobile/features/places/services/place_info_catalog.dart';
import 'package:liqo_mobile/features/places/services/place_status.dart';

import '../support/phone.dart';

/// A published mall (an id the sample catalog doesn't know), read from a sample's package.
PackageVenue published([String sample = 'spire']) =>
    PackageVenue((jsonDecode(utf8.decode(samplePackageBytes(sample))) as Map).cast<String, Object?>()..remove('presets'), id: 'real-$sample');

/// An instant at [h]:[m] Philippine time on Thursday 2026-10-22 (or [day] days later).
DateTime ph(int h, [int m = 0, int day = 0]) => DateTime.utc(2026, 10, 22 + day, h - 8, m);

Map<String, Object?> hoursJson({List<int> days = const [1, 2, 3, 4, 5, 6, 7], String open = '10:00', String close = '21:00', List<Map<String, Object?>> specials = const []}) => {
      'week': [for (final d in days) {'day': d, 'open': open, 'close': close}],
      'specials': specials,
    };

void main() {
  const w = Words('en');

  group('hours, in Philippine time', () {
    test('open, closing time, next opening today or tomorrow; past midnight', () {
      final h = WeekHours.fromJson(hoursJson())!;
      expect(h.isOpenAt(phTime(ph(14, 30))), isTrue);
      expect(h.closesAt(phTime(ph(14, 30))), 21 * 60);
      expect(h.nextOpen(phTime(ph(8))), (inDays: 0, at: 600));
      expect(h.nextOpen(phTime(ph(22))), (inDays: 1, at: 600));
      final late = WeekHours.fromJson(hoursJson(open: '18:00', close: '02:00'))!;
      expect(late.isOpenAt(phTime(ph(23))), isTrue);
      expect(late.isOpenAt(phTime(ph(1, 0, 1))), isTrue, reason: "last night's hours run past midnight");
      expect(late.isOpenAt(phTime(ph(3, 0, 1))), isFalse);
    });

    test('special days override the week, with their note', () {
      final h = WeekHours.fromJson(hoursJson(specials: [
        {'date': '2026-10-22', 'closed': true, 'note': 'Holiday'},
        {'date': '2026-10-23', 'open': '10:00', 'close': '24:00', 'note': 'Midnight sale'},
      ]))!;
      expect(h.isOpenAt(phTime(ph(14))), isFalse);
      expect(h.day(phTime(ph(14))).note, 'Holiday');
      expect(h.closesAt(phTime(ph(22, 0, 1))), 24 * 60);
    });
  });

  group('a published mall\'s places', () {
    test('a store\'s own hours; without them the mall\'s; with neither, nothing is said', () {
      final v = published(), shop = v.places.firstWhere((p) => p.kind == 'store'), other = v.places.where((p) => p.kind == 'store' && p.status == 'open' && p != shop).first;
      expect(placeStatus(shop, placeInfoFor(v, shop), ph(14, 30), w).known, isFalse, reason: 'no live info yet: no guess');
      v.applyLive(LiveInfo.fromJson({
        'branchHours': hoursJson(close: '22:00'),
        'stores': [
          {'storeId': 345, 'spaceIds': [shop.id], 'name': 'Uniqlo', 'category': 'fashion', 'status': 'open', 'hours': hoursJson(open: '11:00', close: '20:00')},
        ],
      }));
      expect(placeStatus(shop, placeInfoFor(v, shop), ph(14, 30), w).line, 'Open · Closes 8:00 PM');
      expect(placeStatus(shop, placeInfoFor(v, shop), ph(21), w).line, 'Closed now · Opens tomorrow 11:00 AM');
      expect(placeStatus(other, placeInfoFor(v, other), ph(14, 30), w).line, 'Open · Closes 10:00 PM', reason: "no hours of its own: the mall's");
      v.applyLive(LiveInfo.fromJson({'stores': []}));
      expect(placeStatus(other, placeInfoFor(v, other), ph(14, 30), w).known, isFalse, reason: 'no hours anywhere: no open/closed line');
    });

    test('the old free-text hours show only when neither the store nor the mall has hours', () {
      final v = published(), shop = v.places.firstWhere((p) => p.kind == 'store');
      Map<String, Object?> live({Object? branch}) => {
            'branchHours': branch,
            'stores': [
              {'storeId': 2, 'spaceIds': [shop.id], 'name': 'Opal', 'hoursNote': '10am-9pm daily'},
            ],
          };
      v.applyLive(LiveInfo.fromJson(live()));
      final note = placeStatus(shop, placeInfoFor(v, shop), ph(14), w);
      expect((note.line, note.known, note.notOpen), ('10am-9pm daily', true, false));
      v.applyLive(LiveInfo.fromJson(live(branch: hoursJson())));
      expect(placeStatus(shop, placeInfoFor(v, shop), ph(14), w).line, 'Open · Closes 9:00 PM', reason: "the mall's hours win over the note");
    });

    test('a special day says why', () {
      final v = published(), shop = v.places.firstWhere((p) => p.kind == 'store');
      v.applyLive(LiveInfo.fromJson({
        'stores': [
          {'storeId': 1, 'spaceIds': [shop.id], 'name': 'Opal', 'hours': hoursJson(specials: [{'date': '2026-10-22', 'closed': true, 'note': 'Holiday'}])},
        ],
      }));
      expect(placeStatus(shop, placeInfoFor(v, shop), ph(14), w).line, 'Closed today · Holiday');
    });

    test('names, categories and statuses change in place, and go back when the store leaves', () {
      final v = published(), shop = v.places.firstWhere((p) => p.kind == 'store'), was = (shop.name, shop.cat, shop.status);
      v.applyLive(LiveInfo.fromJson({
        'stores': [
          {'storeId': 345, 'spaceIds': [shop.id], 'name': 'Kopi Corner', 'category': 'food', 'status': 'being_repaired', 'phone': '+63 2 8888 0000'},
        ],
      }));
      expect((shop.name, shop.cat, shop.status), ('Kopi Corner', 'food', 'maintenance'));
      expect(placeStatus(shop, placeInfoFor(v, shop), ph(14), w).line, 'Being repaired');
      expect(placeInfoFor(v, shop).phone, '+63 2 8888 0000');
      expect(v.storeOf[shop.id], '345');
      for (final (web, app) in [('temporarily_closed', 'closed'), ('opening_soon', 'comingSoon'), ('open', 'open')]) {
        expect(appStatus(web), app);
      }
      v.applyLive(LiveInfo.fromJson({'stores': []}));
      expect((shop.name, shop.cat, shop.status), was);
    });

    test('a store on a space the map lacks is kept apart, for "Directions come with the next map update"', () {
      final v = published();
      v.applyLive(LiveInfo.fromJson({
        'stores': [
          {'storeId': 9, 'spaceIds': ['sp_new'], 'name': 'Taco Stop', 'category': 'food'},
        ],
      }));
      expect(v.storesNotOnMap.map((s) => s.name), ['Taco Stop']);
    });
  });

  test('the store info is fetched on every check, kept for offline, and an unchanged reply is skipped', () async {
    final ph1 = Phone(installed: ['spire']);
    await ph1.boot();
    final shop = ph1.s.venues['spire']!.places.firstWhere((p) => p.kind == 'store');
    ph1.api.setLive('spire', {
      'stores': [
        {'storeId': 7, 'spaceIds': [shop.id], 'name': 'Renamed Store', 'status': 'opening_soon'},
      ],
      'outOfService': [
        {'connectorId': ph1.s.venues['spire']!.connectors.first.id},
      ],
    });
    await ph1.malls.checkForUpdates();
    expect(ph1.s.venues['spire']!.placeById(shop.id)!.name, 'Renamed Store');
    expect(ph1.malls.outOfService('spire'), hasLength(1));
    final seq = ph1.s.liveSeq;
    await ph1.malls.checkForUpdates();
    expect(ph1.s.liveSeq, seq, reason: 'unchanged (304): nothing applied again');
    // a restart with no connection still has it
    final again = Phone(store: ph1.store, blobs: ph1.blobs, net: NetKind.none);
    await again.boot();
    expect(again.s.venues['spire']!.placeById(shop.id)!.name, 'Renamed Store');
    expect(again.s.venues['spire']!.placeById(shop.id)!.status, 'comingSoon');
  });
}

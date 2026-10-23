// Shopper packages (docs/shopper-package-format.md): each sample mall written
// out as a package and read back gives the same places, the same graph (edge
// order included) and so the same routes; newer formats are refused; one-way
// links can only be walked one way.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/engine/kit/kit_venue.dart';
import 'package:liqo_mobile/core/engine/package/package_export.dart';
import 'package:liqo_mobile/core/engine/package/package_venue.dart';
import 'package:liqo_mobile/core/engine/routing.dart';
import 'package:liqo_mobile/features/malls/data/bayview.dart';
import 'package:liqo_mobile/features/malls/data/meridian.dart';
import 'package:liqo_mobile/features/malls/data/spire.dart';

import '../support/spots.dart';

final specs = {'bayview': bayviewSpec, 'meridian': meridianSpec, 'spire': spireSpec};

/// Through JSON text, as a download would be.
PackageVenue roundTrip(KitVenue v) => PackageVenue((jsonDecode(jsonEncode(exportPackage(v))) as Map).cast<String, Object?>());

String routeSig(RouteT? r) => r == null ? '-' : '${r.total.toStringAsFixed(3)} ${[for (final v in r.verts) '${v.lv}|${v.x},${v.y}'].join(' ')}';

void main() {
  for (final MapEntry(key: id, value: spec) in specs.entries) {
    group(id, () {
      final kit = KitVenue(spec), pkg = roundTrip(kit);

      test('the same places, levels, connectors and exits', () {
        expect(pkg.id, kit.id);
        expect([for (final l in pkg.levels) '${l.id} ${l.short} ${l.name} ${l.elev}'], [for (final l in kit.levels) '${l.id} ${l.short} ${l.name} ${l.elev}']);
        expect(pkg.ground, kit.ground);
        expect([for (final p in pkg.places) '${p.id}|${p.name}|${p.cat}|${p.kind}|${p.lv}|${p.status}|${p.w}|${p.nodes}|${p.exitNode}'],
            [for (final p in kit.places) '${p.id}|${p.name}|${p.cat}|${p.kind}|${p.lv}|${p.status}|${p.w}|${p.nodes}|${p.exitNode}']);
        expect([for (final c in pkg.connectors) '${c.id} ${c.type} ${c.lvs} ${c.at}'], [for (final c in kit.connectors) '${c.id} ${c.type} ${c.lvs} ${c.at}']);
        expect([for (final e in pkg.exits) '${e.id} ${e.node}'], [for (final e in kit.exits) '${e.id} ${e.node}']);
      });

      test('the same graph, edge order included', () {
        expect(pkg.graph.nodes.keys.toList(), kit.graph.nodes.keys.toList());
        for (final k in kit.graph.nodes.keys) {
          final a = kit.graph.nodes[k]!, b = pkg.graph.nodes[k]!;
          expect('${b.out} ${b.inner} ${b.emergencyOnly} ${b.label}', '${a.out} ${a.inner} ${a.emergencyOnly} ${a.label}', reason: k);
          String sig(e) => '${e.to} ${e.d.toStringAsFixed(6)} ${e.len.toStringAsFixed(6)} ${e.w} ${e.kind} ${e.conn} ${e.ctype} ${e.label} ${e.tech} ${e.covered} ${e.through} ${e.emergencyOnly}';
          expect([for (final e in pkg.graph.adj[k]!) sig(e)], [for (final e in kit.graph.adj[k]!) sig(e)], reason: k);
        }
      });

      test('the same routes to every place, every way', () {
        for (final from in [firstExit(kit), scenarioStart(kit)]) {
          for (final p in kit.places) {
            final q = pkg.placeById(p.id)!;
            for (final (wheel, metric, through) in [(false, RouteOpts.fastest, true), (true, RouteOpts.fastest, false), (false, RouteOpts.shortest, true)]) {
              final a = routesTo(kit.graph, p.id, p.nodes, from, wheel, metric: metric, throughStores: through);
              final b = routesTo(pkg.graph, q.id, q.nodes, from, wheel, metric: metric, throughStores: through);
              expect([for (final r in b) routeSig(r)], [for (final r in a) routeSig(r)], reason: '${p.id} wheel:$wheel $metric');
            }
          }
        }
      });

      test('camera presets and drawing data are worked out', () {
        expect(pkg.basePx, greaterThan(0));
        expect(pkg.pad, isNotEmpty);
        expect(pkg.pad.where((b) => b.main), hasLength(1));
        expect(pkg.spaces, isNotEmpty);
        for (var lv = 0; lv < pkg.levelCount; lv++) {
          expect(pkg.outlines[lv], isNotEmpty, reason: 'level $lv has an outline');
          final c = pkg.levelCentre(lv);
          expect(pkg.graph.nearestNodeAt(lv, c.x, c.y), isNotNull);
        }
        expect(pkg.tripTarget, kit.tripTarget, reason: 'samples keep their demo trip');
        expect((pkg.basePx, pkg.pad.length, pkg.sizeText), (kit.basePx, kit.pad.length, kit.sizeText), reason: 'and their own presets');
      });
    });
  }

  test('a published map (no presets) gets no demo trip and works out its own camera presets', () {
    final j = exportPackage(KitVenue(meridianSpec))..remove('presets');
    final v = PackageVenue(j);
    expect(v.tripTarget, '');
    expect(v.basePx, greaterThan(0));
    expect(v.pad.map((b) => b.key), containsAll(['A', 'B']));
    expect(v.pad.where((b) => b.main), hasLength(1));
    expect(v.stack.gapM, greaterThan(0));
    final c = v.levelCentre(v.ground);
    expect(v.graph.nearestNodeAt(v.ground, c.x, c.y), isNotNull);
  });

  test('a newer format is refused as "update the app"; a broken one as unreadable', () {
    final j = exportPackage(KitVenue(spireSpec))..['formatVersion'] = packageFormatVersion + 1;
    expect(() => PackageVenue(j), throwsA(isA<PackageFormatException>().having((e) => e.newerFormat, 'newerFormat', isTrue)));
    final broken = exportPackage(KitVenue(spireSpec))..remove('graph');
    expect(() => PackageVenue(broken), throwsA(isA<PackageFormatException>().having((e) => e.newerFormat, 'newerFormat', isFalse)));
  });

  test('a one-way link (an escalator) is walked only one way', () {
    final j = <String, Object?>{
      'formatVersion': 1, 'branchId': 't', 'version': 1, 'bounds': [0, 0, 100, 100],
      'levels': [
        {'id': 'G', 'name': 'Ground floor', 'short': 'G', 'elev': 0, 'ground': true, 'outlines': [{'outer': [[0, 0], [100, 0], [100, 100], [0, 100]]}]},
        {'id': '2', 'name': 'Level 2', 'short': '2', 'elev': 6, 'outlines': [{'outer': [[0, 0], [100, 0], [100, 100], [0, 100]]}]},
      ],
      'graph': {
        'nodes': [
          {'id': 'a', 'lv': 0, 'x': 10, 'y': 10}, {'id': 'b', 'lv': 0, 'x': 50, 'y': 10},
          {'id': 'c', 'lv': 1, 'x': 50, 'y': 10}, {'id': 'd', 'lv': 1, 'x': 90, 'y': 10},
        ],
        'edges': [
          {'a': 'a', 'b': 'b', 'kind': 'walk', 'len': 40, 'cost': 40, 'w': 3},
          {'a': 'b', 'b': 'c', 'kind': 'hop', 'len': 0, 'cost': null, 'w': 4, 'conn': 'esc', 'ctype': 'escalator', 'oneWay': true},
          {'a': 'c', 'b': 'd', 'kind': 'walk', 'len': 40, 'cost': 40, 'w': 3},
        ],
      },
      'places': [
        {'id': 'top', 'lv': 1, 'name': 'Top', 'at': [90, 10], 'nodes': ['d']},
        {'id': 'bottom', 'lv': 0, 'name': 'Bottom', 'at': [10, 10], 'nodes': ['a']},
      ],
      'connectors': [{'id': 'esc', 'type': 'escalator', 'name': 'Up escalator', 'oneWay': true, 'stops': [{'lv': 0, 'node': 'b'}, {'lv': 1, 'node': 'c'}]}],
    };
    final v = PackageVenue(j);
    final up = routesTo(v.graph, 'top', v.placeById('top')!.nodes, const Pos(0, 10, 10), false);
    expect(up, isNotEmpty);
    expect(up.first.seg.any(isHop), isTrue);
    final down = routesTo(v.graph, 'bottom', v.placeById('bottom')!.nodes, const Pos(1, 90, 10), false);
    expect(down, isEmpty, reason: 'there is no way down: the escalator only goes up');
  });
}

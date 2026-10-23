// Writes a sample (kit) mall as a shopper package, so the sample malls travel
// the same path as published maps: debug builds and tests serve them from the
// stand-in server and the app reads them back with PackageVenue. The graph is
// written in the order it was built (Graph.linkLog), so routes come out the same.
import '../kit/kit_spec.dart';
import '../kit/kit_venue.dart';
import '../venue.dart';
import 'package_venue.dart';

List<List<double>> _rect(List<double> r) => [[r[0], r[1]], [r[2], r[1]], [r[2], r[3]], [r[0], r[3]]];
List<double> _view(View v) => [v.cx, v.cy, v.zoom];
List<double> _r1(List<double> p) => [for (final v in p) double.parse(v.toStringAsFixed(2))];

Map<String, Object?> exportPackage(KitVenue v, {int version = 1}) {
  final s = v.spec, gr = v.graph;
  final ids = <String, String>{};
  var n = 0;
  final nodes = [
    for (final node in gr.nodes.values)
      {
        'id': ids[node.k] = 'n${n++}',
        'lv': node.lv, 'x': node.x, 'y': node.y,
        if (node.out) 'out': true,
        if (node.inner) 'inner': true,
        if (node.emergencyOnly) 'emergencyOnly': true,
        if (node.label != null) 'label': node.label,
      },
  ];
  final edges = [
    for (final (a, e) in gr.linkLog)
      {
        'a': ids[a], 'b': ids[e.to], 'kind': e.kind, 'len': e.len,
        // hops are costed by the app; everything else carries its own cost
        'cost': e.kind == 'hop' ? null : e.d,
        'w': e.w,
        if (e.oneWay) 'oneWay': true,
        if (e.covered) 'covered': true,
        if (e.through != null) 'through': e.through,
        if (e.conn != null) 'conn': e.conn,
        if (e.ctype != null) 'ctype': e.ctype,
        if (e.label != null) 'label': e.label,
        if (e.tech != null) 'tech': e.tech,
        if (e.emergencyOnly) 'emergencyOnly': true,
      },
  ];

  // drawing: corridors and courts are walkable spaces; shops, anchors and restrooms are rooms
  final spaces = <Map<String, Object?>>[];
  var sp = 0;
  void space(int lv, List<double> rect, String type, {String name = '', bool walkable = false, bool outdoor = false}) =>
      spaces.add({'id': 'sp${sp++}', 'lv': lv, 'name': name, 'type': type, 'shape': _rect(rect), if (walkable) 'walkable': true, if (outdoor) 'outdoor': true});
  for (final l in s.lines) {
    for (final lv in l.lvs) {
      space(lv, lineRect(l.x1, l.y1, l.x2, l.y2, l.w), l.zone != null ? 'parking' : l.out ? 'outdoor' : 'corridor', walkable: true, outdoor: l.out || l.zone != null);
    }
  }
  for (final k in s.links) {
    space(k.lv, lineRect(k.x1, k.y1, k.x2, k.y2, k.w), 'corridor', walkable: true);
  }
  for (final a in s.areas) {
    for (final lv in a.lvs) {
      space(lv, a.rect, switch (a.kind) { 'court' || 'plaza' || 'portal' => 'atrium', 'garden' => 'outdoor', 'boh' => 'storage', _ => 'custom' }, walkable: a.kind != 'void' && a.kind != 'boh' && a.kind != 'bowl');
    }
  }
  for (final k in v.kslots) {
    space(k.lv, k.rect, k.kind == 'wc' ? 'restroom' : 'retail');
  }
  for (final a in s.anchors) {
    for (final lv in a.names.keys) {
      space(lv, a.rect, 'anchor', name: a.names[lv]![0]);
    }
  }
  final walls = [
    for (final b in s.buildings)
      if (b.kind == 'mall' || b.kind == 'arena' || b.kind == 'tower')
        for (final lv in b.lvs)
          for (final e in [[b.rect[0], b.rect[1], b.rect[2], b.rect[1]], [b.rect[2], b.rect[1], b.rect[2], b.rect[3]], [b.rect[2], b.rect[3], b.rect[0], b.rect[3]], [b.rect[0], b.rect[3], b.rect[0], b.rect[1]]])
            {'lv': lv, 'a': [e[0], e[1]], 'b': [e[2], e[3]], 't': .5, 'kind': 'boundary'},
  ];

  return {
    'formatVersion': packageFormatVersion,
    'branchId': v.id,
    'branchName': v.name,
    'mallName': v.tagline,
    'version': version,
    'units': 'm',
    'levels': [
      for (final (i, l) in v.levels.indexed)
        {
          'id': l.id, 'name': l.name, 'short': l.short, 'elev': l.elev, 'height': 6.0, 'ground': i == v.ground,
          'outlines': [for (final b in s.buildings) if (b.lvs.contains(i)) {'building': b.id, 'outer': _rect(b.rect)}],
        },
    ],
    'spaces': spaces,
    'walls': walls,
    'openings': const [],
    'features': const [],
    'graph': {'nodes': nodes, 'edges': edges},
    'places': [
      for (final p in v.places)
        {
          'id': p.id, 'lv': p.lv, 'name': p.name, 'cat': p.cat, 'kind': p.kind, 'wing': p.wing,
          'rect': _r1(p.rect), 'at': p.at, 'door': p.door, 'doors': p.doors, 'nodes': [for (final k in p.nodes) ids[k]],
          'status': p.status, 'w': p.w,
          if (p.onLine) 'onLine': true,
          if (p.exitNode) 'exit': true,
          if (p.attach != null) 'attach': p.attach,
        },
    ],
    'connectors': [
      for (final c in v.connectors)
        {'id': c.id, 'type': c.type, 'name': c.name, 'building': c.bld, 'oneWay': false, 'stops': [for (final lv in c.lvs) {'lv': lv, 'node': ids[c.at[lv]]}]},
    ],
    'exits': [for (final e in v.exits) {'id': e.id, 'name': e.name, 'node': ids[e.node]}],
    'buildings': [
      for (final b in s.buildings)
        if (b.tappable) {'id': b.id, 'name': b.name, 'short': b.name, 'levels': b.lvs, 'bounds': b.rect},
    ],
    'bounds': s.site,
    // the sample's own hand-tuned presets (published maps have none; the app works them out)
    'presets': {
      'tagline': s.tagline, 'keywords': s.keywords, 'sizeText': s.sizeText, 'basePx': s.basePx, 'demoTrip': s.tripTarget,
      'buildingCount': v.buildingCount,
      'wingNames': v.wingNames,
      'siteView': _view(s.siteView),
      'buildingViews': {for (final e in s.buildingViews.entries) e.key: _view(e.value)},
      'pad': [for (final b in s.pad) {'key': b.key, 'simple': b.simple, 'tech': b.tech, 'view': _view(b.view), 'main': b.main}],
      'stack': {'cx': s.stack.cx, 'cy': s.stack.cy, 's': s.stack.s, 'gapM': s.stack.gapM, 'yaw': s.stack.yaw, 'ky': s.stack.ky, 'kz': s.stack.kz, 'mid': s.stack.mid, 'labelAt': s.stack.labelAt},
      'centres': {for (final e in s.centres.entries) '${e.key}': e.value},
      'wingLabels': [for (final w in s.wingLabels) [w.$1, w.$2, w.$3, w.$4]],
    },
  };
}

/// A sample mall's package, keyed like the stand-in server serves it.
Map<String, Object?> samplePackage(KSpec spec) => exportPackage(KitVenue(spec));


// Skyline Spire: an invented 16-level tower mall around a full-height atrium,
// with express escalators that skip floors, half-height mezzanines reached by
// a ramp, split lift banks (low-rise / high-rise), ramped parking and a
// rooftop garden.
import '../../../core/engine/constants.dart';
import '../../../core/engine/venue.dart';
import '../../../core/engine/kit/kit_spec.dart';

const _lv = [
  LevelDef('B2', 'B2', 'Basement 2', -9), LevelDef('B1', 'B1', 'Basement 1', -4.5), LevelDef('G', 'G', 'Ground floor', 0),
  LevelDef('2', '2', 'Level 2', 6), LevelDef('2M', '2M', 'Level 2 mezzanine', 9), LevelDef('3', '3', 'Level 3', 12),
  LevelDef('4', '4', 'Level 4', 18), LevelDef('5', '5', 'Level 5', 24), LevelDef('5M', '5M', 'Level 5 mezzanine', 27),
  LevelDef('6', '6', 'Level 6', 30), LevelDef('7', '7', 'Level 7', 36), LevelDef('8', '8', 'Level 8', 42),
  LevelDef('9', '9', 'Level 9', 48), LevelDef('10', '10', 'Level 10', 54), LevelDef('11', '11', 'Level 11', 60),
  LevelDef('R', 'R', 'Rooftop garden', 66),
];
const _main = [2, 3, 5, 6, 7, 9, 10, 11, 12, 13, 14]; // full floors
const _mezz = [4, 8];
const _roof = 15;
const _base = [0, 1];
const _all = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
const double _r = auroraPxPerM / .7; // zoom ratio for this venue's scale

Map<String, double> _weights(String bld, int lv) => switch (lv) {
      2 => const {'services': .35, 'fashion': .2, 'food': .2, 'tech': .1, 'other': .15, 'books': 0.0},
      3 || 4 || 5 => const {'fashion': .55, 'other': .2, 'services': .1, 'food': .1, 'tech': .05, 'books': 0.0},
      6 || 7 => const {'tech': .35, 'fashion': .2, 'other': .2, 'services': .1, 'books': .1, 'food': .05},
      8 => const {'food': .6, 'other': .2, 'books': .2, 'fashion': 0.0, 'tech': 0.0, 'services': 0.0},
      9 || 10 || 11 => const {'other': .35, 'books': .2, 'fashion': .2, 'services': .15, 'tech': .1, 'food': 0.0},
      12 || 13 => const {'tech': .3, 'other': .3, 'food': .3, 'books': .1, 'fashion': 0.0, 'services': 0.0},
      _ => const {'food': .75, 'other': .25, 'fashion': 0.0, 'tech': 0.0, 'services': 0.0, 'books': 0.0},
    };

final spireSpec = KSpec(
  id: 'spire',
  name: 'Skyline Spire',
  keywords: 'tower vertical high-rise express escalator mezzanine rooftop roof garden lift banks',
  tagline: 'A 16-level tower: express escalators, mezzanines, split lift banks and a rooftop garden.',
  sizeText: '120 × 120 m',
  seed: 20261103,
  levels: _lv,
  ground: 2,
  basePx: .7,
  site: const [0, 0, 300, 300],
  buildings: const [
    KBld('T', 'Skyline Spire', [90, 90, 210, 210], _all, kind: 'tower', roof: 'garden'),
    KBld('P', 'Spire car park', [90, 90, 210, 210], _base, kind: 'parking', tappable: false),
  ],
  lines: const [
    // the ring around the atrium, with shops on its outer side
    KLine('T', _main, 122, 122, 178, 122, w: 10, rowA: 25, slot: 11.2),
    KLine('T', _main, 122, 178, 178, 178, w: 10, rowB: 25, slot: 11.2),
    KLine('T', _main, 122, 122, 122, 178, w: 10, rowA: 25, slot: 11.2),
    KLine('T', _main, 178, 122, 178, 178, w: 10, rowB: 25, slot: 11.2),
    // ground-floor entrance halls
    KLine('T', [2], 150, 90, 150, 122, w: 8), KLine('T', [2], 150, 178, 150, 210, w: 8),
    KLine('T', [2], 90, 150, 122, 150, w: 8), KLine('T', [2], 178, 150, 210, 150, w: 8),
    // mezzanines: a gallery on the north side, overlooking the atrium
    KLine('T', _mezz, 122, 122, 178, 122, w: 8, rowA: 25, slot: 11.2),
    KLine('T', _mezz, 122, 122, 122, 150, w: 8), KLine('T', _mezz, 178, 122, 178, 150, w: 8),
    // the rooftop garden, open to the sky
    KLine('T', [_roof], 122, 122, 178, 122, w: 10, out: true, rowA: 14, slot: 14),
    KLine('T', [_roof], 122, 178, 178, 178, w: 10, out: true),
    KLine('T', [_roof], 122, 122, 122, 178, w: 10, out: true), KLine('T', [_roof], 178, 122, 178, 178, w: 10, out: true),
    // basement parking aisles
    KLine('P', _base, 110, 110, 190, 110, w: 6, zone: 'P'), KLine('P', _base, 110, 190, 190, 190, w: 6, zone: 'P'),
    KLine('P', _base, 110, 110, 110, 190, w: 6, zone: 'P'), KLine('P', _base, 190, 110, 190, 190, w: 6, zone: 'P'),
    // the forecourt around the tower, and the street
    KLine(null, [2], 80, 80, 220, 80, w: 4, out: true), KLine(null, [2], 80, 220, 220, 220, w: 4, out: true),
    KLine(null, [2], 80, 80, 80, 220, w: 4, out: true), KLine(null, [2], 220, 80, 220, 220, w: 4, out: true),
    KLine(null, [2], 150, 220, 150, 258, w: 4, out: true), KLine(null, [2], 20, 258, 280, 258, w: 4, out: true),
  ],
  areas: [
    const KArea('T', [2], 'court', [130, 130, 170, 170]),
    const KArea('T', [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], 'void', [130, 130, 170, 170]),
    const KArea('T', [_roof], 'garden', [95, 183, 205, 206]),
    const KArea('T', [_roof], 'garden', [95, 128, 117, 178]),
    const KArea('T', [_roof], 'garden', [183, 128, 205, 178]),
  ],
  anchors: const [
    KAnchor('GDN', 'T', [132, 132, 168, 168], {_roof: ['Sky Garden', 'garden']}, [[150, 127]]),
    KAnchor('CIN', 'T', [183, 122, 208, 178], {12: ['Spire Cinemas', 'cinema'], 13: ['Spire IMAX', 'cinema']}, [[183, 150]]),
    KAnchor('FC', 'T', [92, 122, 117, 178], {14: ['Spire Food Court', 'food']}, [[117, 150]]),
    KAnchor('DS', 'T', [122, 183, 178, 208], {3: ['Spire Department Store', 'fashion'], 5: ['Spire Department Store · Home', 'other']}, [[150, 183]]),
  ],
  conns: const [
    KConn('L-LOW', 'lift', 'Low-rise lifts', ['T', 'P'], [0, 1, 2, 3, 5, 6, 7, 9], 104, 104),
    KConn('L-HIGH', 'lift', 'High-rise lifts', ['T'], [2, 10, 11, 12, 13, 14, 15], 196, 196),
    KConn('ST-N', 'stairs', 'Stairs north', ['T', 'P'], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], 196, 104),
    KConn('ST-S', 'stairs', 'Stairs south', ['T', 'P'], [0, 1, 2, 3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15], 104, 196),
    KConn('ESC', 'escalator', 'Atrium escalators', ['T'], _main, 170, 165),
    KConn('EXP-1', 'escalator', 'Express escalator G–5', ['T'], [2, 7], 135, 170),
    KConn('EXP-2', 'escalator', 'Express escalator 5–9', ['T'], [7, 12], 165, 133),
    KConn('ESC-R', 'escalator', 'Rooftop escalator', ['T'], [14, 15], 135, 135),
    KConn('R-2M', 'ramp', 'Ramp to the 2M mezzanine', ['T'], [3, 4], 126, 140),
    KConn('S-2M', 'stairs', 'Mezzanine stairs 2M', ['T'], [3, 4], 174, 140),
    KConn('R-5M', 'ramp', 'Ramp to the 5M mezzanine', ['T'], [7, 8], 126, 145),
    KConn('S-5M', 'stairs', 'Mezzanine stairs 5M', ['T'], [7, 8], 174, 145),
    KConn('P-RAMP', 'ramp', 'Car park ramp', ['P'], [0, 1], 190, 150),
  ],
  exits: const [
    KExit('X-N', 'North entrance', 'the north entrance', 2, 150, 90, 150, 80),
    KExit('X-S', 'South entrance', 'the south entrance', 2, 150, 210, 150, 220),
    KExit('X-W', 'West entrance', 'the west entrance', 2, 90, 150, 80, 150),
    KExit('X-E', 'East entrance', 'the east entrance', 2, 210, 150, 220, 150),
  ],
  zones: [
    for (final lv in _base)
      for (final (z, x) in const [('A', 130.0), ('B', 170.0)])
        KZone('P-${_lv[lv].short}$z', '${_lv[lv].short} · Zone $z', lv, x, 150, const [95, 95, 205, 205], 'P'),
  ],
  services: const [
    KSvc('G-ATM', 'atm', 'ATM', 'T', 2, 150, 122), KSvc('4-ATM', 'atm', 'ATM', 'T', 6, 150, 122),
    KSvc('7-ATM', 'atm', 'ATM', 'T', 10, 150, 122), KSvc('10-ATM', 'atm', 'ATM', 'T', 13, 150, 178),
    KSvc('G-INFO', 'info', 'Information desk', 'T', 2, 122, 150), KSvc('9-INFO', 'info', 'Information desk', 'T', 12, 122, 150),
    KSvc('EV-B1', 'ev', 'EV charging · Basement 1', 'P', 1, 150, 110),
  ],
  groundFx: const [
    KGround('road', [0, 265, 300, 300]), KGround('walk', [0, 252, 300, 265]), KGround('plazaG', [78, 78, 222, 222]),
  ],
  trees: const [([20, 20, 70, 240], 10), ([230, 20, 290, 240], 10)],
  pois: const [KPoi('BUS', 'g-bus', 'Bus stop', 'Transit stop', 60, 258)],
  wcEvery: 11,
  weights: _weights,
  buildingViews: const {'T': View(150, 150, 2 * _r)},
  pad: const [
    PadBtn('N', 'North', 'N', View(150, 105, 5 * _r)),
    PadBtn('W', 'West', 'W', View(105, 150, 5 * _r)),
    PadBtn('C', 'Atrium', 'AT', View(150, 150, 6.5 * _r), main: true),
    PadBtn('E', 'East', 'E', View(195, 150, 5 * _r)),
    PadBtn('S', 'South', 'S', View(150, 195, 5 * _r)),
  ],
  stack: const StackParams(cx: 150, cy: 150, s: 1.3, gapM: 22, yaw: stackYaw, ky: stackKy, kz: stackKz, mid: 7.5, labelAt: [80, 150]),
  siteView: const View(150, 165, 1),
  tripTarget: 'R-GDN',
  centres: {for (final lv in _all) lv: const [150.0, 122.0], 0: const [150.0, 110.0], 1: const [150.0, 110.0]},
  wingLabels: const [('ATRIUM', 150, 150, [3, 5, 6, 7, 9, 10, 11, 12, 13, 14])],
);

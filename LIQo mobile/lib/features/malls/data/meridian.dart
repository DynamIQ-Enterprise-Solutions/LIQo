// Meridian Twin Malls: two invented mall towers across a street, joined by
// bridges on levels 2, 4 and 5 only; a Fashion Hall joined to Building B on
// G, 2 and 3 only (its level 4 is reached by its own escalator); a shared
// two-level basement car park; and an elevated level-3 link to a train station.
import '../../../core/engine/constants.dart';
import '../../../core/engine/venue.dart';
import '../../../core/engine/kit/kit_spec.dart';

const _lv = [
  LevelDef('B2', 'B2', 'Basement 2', -10), LevelDef('B1', 'B1', 'Basement 1', -5), LevelDef('G', 'G', 'Ground floor', 0),
  LevelDef('2', '2', 'Level 2', 6), LevelDef('3', '3', 'Level 3', 12), LevelDef('4', '4', 'Level 4', 18),
  LevelDef('5', '5', 'Level 5', 24), LevelDef('6', '6', 'Level 6', 30),
];
const _a = [2, 3, 4, 5, 6]; // Building A: G-5
const _b = [2, 3, 4, 5, 6, 7]; // Building B: G-6
const _f = [2, 3, 4, 5]; // Fashion Hall: G-4
const _p = [0, 1];
const double _r = auroraPxPerM / .42;

Map<String, double> _weights(String bld, int lv) => bld == 'F'
    ? const {'fashion': .7, 'other': .15, 'services': .1, 'food': .05, 'tech': 0.0, 'books': 0.0}
    : switch (lv) {
        2 => const {'services': .3, 'food': .25, 'fashion': .2, 'tech': .1, 'other': .15, 'books': 0.0},
        3 || 4 => const {'fashion': .45, 'other': .2, 'services': .15, 'food': .1, 'tech': .05, 'books': .05},
        5 => const {'tech': .4, 'books': .15, 'other': .2, 'fashion': .15, 'services': .1, 'food': 0.0},
        _ => const {'food': .5, 'other': .25, 'tech': .1, 'books': .15, 'fashion': 0.0, 'services': 0.0},
      };

final meridianSpec = KSpec(
  id: 'meridian',
  name: 'Meridian Twin Malls',
  keywords: 'twin towers megamall bridge bridges train station rail fashion hall cinema street',
  tagline: 'Twin towers across a street, bridges on some floors only, a Fashion Hall and a train link.',
  sizeText: '560 × 270 m',
  seed: 20261102,
  levels: _lv,
  ground: 2,
  basePx: .42,
  site: const [0, 0, 680, 360],
  buildings: const [
    KBld('A', 'Building A', [60, 180, 280, 300], _a, roof: 'skylight'),
    KBld('B', 'Building B', [400, 180, 620, 300], _b, roof: 'skylight'),
    KBld('F', 'Fashion Hall', [420, 40, 600, 170], _f, roof: 'flat'),
    KBld('P', 'Car park', [60, 180, 620, 300], _p, kind: 'parking', tappable: false),
    KBld('S', 'Meridian Station', [30, 106, 310, 130], [4], kind: 'station'),
  ],
  lines: const [
    // Building A: two parallel corridors round an atrium
    KLine('A', _a, 100, 215, 280, 215, w: 10, rowA: 25, rowB: 20),
    KLine('A', _a, 100, 265, 280, 265, w: 10, rowA: 20, rowB: 25),
    KLine('A', _a, 140, 215, 140, 265, w: 8), KLine('A', _a, 200, 215, 200, 265, w: 8),
    KLine('A', [2], 140, 265, 140, 300, w: 8), // to the south entrance
    KLine('A', [4], 140, 180, 140, 215, w: 8), // to the station link
    // Building B
    KLine('B', _b, 400, 215, 580, 215, w: 10, rowA: 25, rowB: 20),
    KLine('B', _b, 400, 265, 580, 265, w: 10, rowA: 20, rowB: 25),
    KLine('B', _b, 480, 215, 480, 265, w: 8), KLine('B', _b, 540, 215, 540, 265, w: 8),
    KLine('B', [2], 540, 265, 540, 300, w: 8),
    KLine('B', [2, 3, 4], 490, 170, 490, 215, w: 8), // into the Fashion Hall, on G, 2 and 3 only
    // the Fashion Hall
    KLine('F', _f, 430, 105, 600, 105, w: 10, rowA: 50, rowB: 45, slot: 12),
    KLine('F', _f, 490, 105, 490, 170, w: 8),
    // a service passage from the corridor, between the shops, to the Fashion Hall stairs
    KLine('F', [2, 3, 4], 580, 105, 580, 162, w: 4),
    // the shared basement car park
    KLine('P', _p, 80, 210, 600, 210, w: 6, zone: 'P'), KLine('P', _p, 80, 270, 600, 270, w: 6, zone: 'P'),
    KLine('P', _p, 80, 210, 80, 270, w: 6, zone: 'P'), KLine('P', _p, 600, 210, 600, 270, w: 6, zone: 'P'),
    KLine('P', _p, 340, 210, 340, 270, w: 6, zone: 'P'),
    // the station platform, up on level 3 and open to the air
    KLine('S', [4], 50, 118, 290, 118, w: 8, out: true),
    // streets and sidewalks
    KLine(null, [2], 40, 312, 640, 312, w: 4, out: true), KLine(null, [2], 290, 160, 290, 312, w: 4, out: true),
    KLine(null, [2], 390, 20, 390, 312, w: 4, out: true), KLine(null, [2], 290, 240, 390, 240, w: 4, out: true),
    KLine(null, [2], 390, 20, 640, 20, w: 4, out: true), KLine(null, [2], 640, 20, 640, 312, w: 4, out: true),
    KLine(null, [2], 40, 118, 40, 312, w: 4, out: true),
  ],
  areas: const [
    KArea('A', [2], 'court', [150, 222, 190, 258]), KArea('A', [3, 4, 5, 6], 'void', [150, 222, 190, 258]),
    KArea('B', [2], 'court', [490, 222, 530, 258]), KArea('B', [3, 4, 5, 6, 7], 'void', [490, 222, 530, 258]),
  ],
  anchors: const [
    KAnchor('ADS', 'A', [60, 185, 100, 295], {
      2: ['Meridian Department Store', 'fashion'], 3: ['Meridian Dept. Store · Women', 'fashion'], 4: ['Meridian Dept. Store · Men', 'fashion'],
      5: ['Meridian Home', 'other'], 6: ['A Food Court', 'food'],
    }, [[100, 215], [100, 265]]),
    KAnchor('BAN', 'B', [580, 185, 620, 295], {
      2: ['FreshMart', 'food'], 3: ['Sportsline', 'fashion'], 4: ['Gadget Hub', 'tech'], 5: ['Meridian Bowling', 'cinema'],
      6: ['Meridian Food Hall', 'food'], 7: ['Meridian Cinemas', 'cinema'],
    }, [[580, 215], [580, 265]]),
  ],
  conns: const [
    KConn('A-L', 'lift', 'Lift A', ['A', 'P'], [0, 1, 2, 3, 4, 5, 6], 120, 204),
    KConn('A-S', 'stairs', 'Stairs A', ['A', 'P'], [0, 1, 2, 3, 4, 5, 6], 260, 204),
    KConn('B-L', 'lift', 'Lift B', ['B', 'P'], [0, 1, 2, 3, 4, 5, 6, 7], 560, 204),
    KConn('B-S', 'stairs', 'Stairs B', ['B', 'P'], [0, 1, 2, 3, 4, 5, 6, 7], 420, 204),
    KConn('A-E', 'escalator', 'Atrium escalators A', ['A'], _a, 165, 226),
    KConn('B-E', 'escalator', 'Atrium escalators B', ['B'], _b, 505, 226),
    KConn('F-E', 'escalator', 'Fashion Hall escalators', ['F'], _f, 560, 112),
    KConn('F-L', 'lift', 'Fashion Hall lift', ['F'], [2, 3, 4], 450, 162),
    KConn('F-S', 'stairs', 'Fashion Hall stairs', ['F'], [2, 3, 4], 580, 162),
    KConn('P-R', 'ramp', 'Car park ramp', ['P'], _p, 340, 240),
    KConn('S-S', 'stairs', 'Station stairs', ['S', ''], [2, 4], 45, 118),
    KConn('S-L', 'lift', 'Station lift', ['S', ''], [2, 4], 285, 118),
  ],
  links: const [
    KLink(3, 280, 215, 400, 215, 'the level 2 bridge', 'Bridge A→B (L2)'),
    KLink(5, 280, 265, 400, 265, 'the level 4 bridge', 'Bridge A→B (L4)'),
    KLink(6, 280, 215, 400, 215, 'the level 5 bridge', 'Bridge A→B (L5)'),
    KLink(4, 140, 180, 140, 118, 'the station link', 'Station link (L3)'),
  ],
  exits: const [
    KExit('X-AE', 'Building A east entrance', 'the east entrance of Building A', 2, 280, 215, 290, 215),
    KExit('X-AS', 'Building A south entrance', 'the south entrance of Building A', 2, 140, 300, 140, 312),
    KExit('X-BW', 'Building B west entrance', 'the west entrance of Building B', 2, 400, 215, 390, 215),
    KExit('X-BS', 'Building B south entrance', 'the south entrance of Building B', 2, 540, 300, 540, 312),
    KExit('X-FW', 'Fashion Hall west entrance', 'the Fashion Hall west entrance', 2, 430, 105, 390, 105),
    KExit('X-FE', 'Fashion Hall east entrance', 'the Fashion Hall east entrance', 2, 600, 105, 640, 105),
  ],
  zones: [
    for (final lv in _p)
      for (final (z, x) in const [('A', 200.0), ('B', 470.0)])
        KZone('P-${_lv[lv].short}$z', '${_lv[lv].short} · Zone $z', lv, x, 240, const [80, 210, 600, 270], 'P'),
  ],
  services: const [
    KSvc('A-INFO', 'info', 'Information desk · A', 'A', 2, 170, 215), KSvc('B-INFO', 'info', 'Information desk · B', 'B', 2, 510, 215),
    KSvc('A3-ATM', 'atm', 'ATM', 'A', 4, 240, 265), KSvc('B2-ATM', 'atm', 'ATM', 'B', 3, 440, 265),
    KSvc('B5-ATM', 'atm', 'ATM', 'B', 6, 440, 265), KSvc('F-ATM', 'atm', 'ATM', 'F', 2, 520, 105),
    KSvc('EV-B1', 'ev', 'EV charging · Basement 1', 'P', 1, 80, 240),
  ],
  groundFx: const [
    KGround('road', [296, 0, 384, 360]), KGround('road', [0, 320, 680, 360]), KGround('road', [0, 0, 680, 12]),
    KGround('plazaG', [60, 300, 280, 318]), KGround('plazaG', [400, 300, 620, 318]),
  ],
  trees: const [([10, 150, 34, 300], 6), ([650, 30, 675, 300], 8), ([400, 175, 620, 178], 0)],
  wcEvery: 13,
  weights: _weights,
  buildingViews: const {
    'A': View(190, 240, 2.2 * _r), 'B': View(510, 240, 2.2 * _r), 'F': View(510, 105, 2.2 * _r), 'S': View(170, 140, 2.2 * _r),
  },
  pad: const [
    PadBtn('A', 'Bldg A', 'A', View(190, 240, 5 * _r)),
    PadBtn('BR', 'Bridges', 'BR', View(340, 240, 5 * _r), main: true),
    PadBtn('B', 'Bldg B', 'B', View(510, 240, 5 * _r)),
    PadBtn('F', 'Fashion', 'FH', View(510, 105, 5 * _r)),
    PadBtn('ST', 'Station', 'ST', View(170, 130, 5 * _r)),
  ],
  stack: const StackParams(cx: 340, cy: 220, s: .5, gapM: 85, yaw: stackYaw, ky: stackKy, kz: stackKz, mid: 3.5, labelAt: [330, 310]),
  siteView: const View(340, 190, 1),
  tripTarget: '6-BAN',
  centres: const {
    0: [340, 240], 1: [340, 240], 2: [170, 215], 3: [170, 215], 4: [170, 215], 5: [170, 215], 6: [170, 215], 7: [510, 215],
  },
  wingLabels: const [
    ('BUILDING A', 190, 240, [2, 3, 4, 5, 6]), ('BUILDING B', 510, 240, [2, 3, 4, 5, 6, 7]), ('FASHION HALL', 510, 80, [2, 3, 4, 5]),
  ],
);

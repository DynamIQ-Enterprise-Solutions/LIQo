// Bayview Grand: an invented bayside mega-campus. A 700 m main mall with two
// parallel spines and three courts (the Grand Court under a glass atrium), an
// open-air entertainment wing on the bay, an arena, two parking buildings with
// ramps and level-2 bridges into the mall, covered walkways, a seaside
// promenade and a transport terminal.
import '../../../core/engine/constants.dart';
import '../../../core/engine/venue.dart';
import '../../../core/engine/kit/kit_spec.dart';

const _lv = [
  LevelDef('G', 'G', 'Ground floor', 0), LevelDef('2', '2', 'Level 2', 6), LevelDef('3', '3', 'Level 3', 12),
  LevelDef('4', '4', 'Level 4', 18), LevelDef('5', '5', 'Level 5', 24),
];
const _m = [0, 1, 2]; // Main Mall: G-3
const _up = [1, 2];
const _e = [0, 1]; // Entertainment Wing and Arena: G-2
const _p = [0, 1, 2, 3, 4]; // parking decks: G-5
const double _r = auroraPxPerM / .24;

Map<String, double> _weights(String bld, int lv) => switch (bld) {
      'E' => const {'food': .55, 'other': .2, 'fashion': .1, 'services': .1, 'tech': .05, 'books': 0.0},
      'A' => const {'food': .8, 'other': .2, 'fashion': 0.0, 'services': 0.0, 'tech': 0.0, 'books': 0.0},
      _ => switch (lv) {
          0 => const {'fashion': .25, 'food': .2, 'services': .25, 'tech': .12, 'other': .13, 'books': .05},
          1 => const {'fashion': .45, 'food': .06, 'services': .12, 'tech': .12, 'other': .19, 'books': .06},
          _ => const {'food': .35, 'tech': .2, 'other': .2, 'books': .1, 'fashion': .1, 'services': .05},
        },
    };

KZone _deck(String b, String name, int lv, String z, double x, double y) =>
    KZone('$b-${_lv[lv].short}$z', '$name · ${_lv[lv].name} · Zone $z', lv, x, y, const [0, 0, 0, 0], b);

final bayviewSpec = KSpec(
  id: 'bayview',
  name: 'Bayview Grand',
  tagline: 'A bayside campus: a 700 m mall, an open-air wing, an arena, parking buildings and a promenade.',
  sizeText: '1.3 × 0.75 km',
  keywords: 'bay seaside mall of asia moa campus arena promenade terminal transport open-air ice rink imax parking',
  seed: 20261101,
  levels: _lv,
  ground: 0,
  basePx: .24,
  site: const [0, 0, 1300, 760],
  buildings: const [
    KBld('M', 'Main Mall', [400, 250, 1080, 450], _m, roof: 'skylight'),
    KBld('E', 'Entertainment Wing', [200, 200, 340, 520], _e, kind: 'openair', roof: 'none'),
    KBld('A', 'Bayview Arena', [190, 20, 380, 150], _e, kind: 'arena', roof: 'dome'),
    KBld('NP', 'North Parking', [1110, 200, 1270, 330], _p, kind: 'parking'),
    KBld('SP', 'South Parking', [1110, 370, 1270, 500], _p, kind: 'parking'),
    KBld('T', 'Transport Terminal', [690, 586, 830, 614], [0], kind: 'station', roof: 'canopy', tappable: false), // its pin names it
  ],
  lines: const [
    // Main Mall: two spines, shops on both sides
    KLine('M', _m, 470, 300, 1080, 300, w: 14, rowA: 35, rowB: 31),
    KLine('M', _m, 470, 400, 1080, 400, w: 14, rowA: 31, rowB: 35),
    // the courts: straight through on the ground floor, round the atrium above
    KLine('M', [0], 530, 250, 530, 450, w: 12), KLine('M', _up, 530, 300, 530, 400, w: 12),
    KLine('M', [0], 750, 250, 750, 450, w: 14), KLine('M', [0], 700, 350, 800, 350, w: 12),
    KLine('M', _up, 710, 310, 790, 310, w: 8), KLine('M', _up, 710, 390, 790, 390, w: 8),
    KLine('M', _up, 710, 310, 710, 390, w: 8), KLine('M', _up, 790, 310, 790, 390, w: 8),
    KLine('M', _up, 750, 300, 750, 310, w: 10), KLine('M', _up, 750, 390, 750, 400, w: 10),
    KLine('M', [0], 970, 250, 970, 450, w: 12), KLine('M', _up, 970, 300, 970, 400, w: 12),
    // Entertainment Wing: open-air streets
    KLine('E', _e, 270, 200, 270, 520, w: 16, out: true, rowA: 40, rowB: 40, slot: 14),
    KLine('E', _e, 200, 330, 270, 330, w: 10, out: true),
    KLine('E', _e, 270, 430, 340, 430, w: 10, out: true),
    // the Arena's concourse ring, stalls on the inside
    KLine('A', _e, 210, 40, 360, 40, w: 10, rowB: 12),
    KLine('A', _e, 210, 130, 360, 130, w: 10, rowA: 12),
    KLine('A', _e, 210, 40, 210, 130, w: 10), KLine('A', _e, 360, 40, 360, 130, w: 10),
    // parking aisles
    KLine('NP', _p, 1125, 230, 1255, 230, w: 6, zone: 'NP'), KLine('NP', _p, 1125, 300, 1255, 300, w: 6, zone: 'NP'),
    KLine('NP', _p, 1125, 230, 1125, 300, w: 6, zone: 'NP'), KLine('NP', _p, 1255, 230, 1255, 300, w: 6, zone: 'NP'),
    KLine('SP', _p, 1125, 400, 1255, 400, w: 6, zone: 'SP'), KLine('SP', _p, 1125, 470, 1255, 470, w: 6, zone: 'SP'),
    KLine('SP', _p, 1125, 400, 1125, 470, w: 6, zone: 'SP'), KLine('SP', _p, 1255, 400, 1255, 470, w: 6, zone: 'SP'),
    // the outdoors: promenade, walks, covered walkways, drop-off, terminal, lot
    KLine(null, [0], 162, 12, 162, 740, w: 8, out: true),
    KLine(null, [0], 162, 12, 390, 12, w: 5, out: true), KLine(null, [0], 390, 12, 390, 240, w: 5, out: true),
    KLine(null, [0], 162, 85, 190, 85, w: 5, out: true), KLine(null, [0], 162, 330, 200, 330, w: 6, out: true),
    KLine(null, [0], 380, 240, 1092, 240, w: 6, out: true),
    KLine(null, [0], 380, 460, 1092, 460, w: 8, out: true, covered: true),
    KLine(null, [0], 380, 430, 380, 460, w: 6, out: true, covered: true),
    KLine(null, [0], 340, 430, 380, 430, w: 6, out: true, covered: true),
    KLine(null, [0], 270, 150, 270, 200, w: 8, out: true, covered: true),
    KLine(null, [0], 1092, 240, 1092, 460, w: 6, out: true),
    KLine(null, [0], 1092, 265, 1100, 265, w: 4, out: true), KLine(null, [0], 1092, 435, 1100, 435, w: 4, out: true),
    KLine(null, [0], 750, 460, 750, 670, w: 8, out: true, covered: true),
    KLine('T', [0], 690, 600, 830, 600, w: 6, out: true),
    KLine(null, [0], 300, 670, 1100, 670, w: 6, out: true, zone: 'lot'),
  ],
  areas: const [
    KArea('M', _m, 'boh', [470, 338, 1080, 362]),
    KArea('M', _m, 'court', [500, 293, 560, 407]),
    KArea('M', _m, 'court', [700, 293, 800, 407]),
    KArea('M', _m, 'court', [940, 293, 1000, 407]),
    KArea('M', _up, 'void', [720, 320, 780, 380]),
    KArea('A', _e, 'bowl', [230, 60, 340, 110]),
    KArea('A', _e, 'portal', [278, 45, 292, 60]), KArea('A', _e, 'portal', [278, 110, 292, 125]),
  ],
  anchors: const [
    KAnchor('WDS', 'M', [400, 255, 470, 445], {0: ['Bayview Department Store', 'fashion'], 1: ['Bayview Home & Living', 'other'], 2: ['Bayview Grand Cinemas', 'cinema']}, [[470, 300], [470, 400]]),
    KAnchor('EHM', 'M', [1010, 307, 1080, 393], {0: ['Hypermart Bayview', 'food'], 1: ['TechWorld Bayview', 'tech'], 2: ['Bayview Food Hall', 'food']}, [[1045, 307], [1045, 393]]),
    KAnchor('IMX', 'E', [205, 205, 262, 262], {0: ['Bay IMAX · Lobby', 'cinema'], 1: ['Bay IMAX', 'cinema']}, [[262, 233]]),
    KAnchor('RNK', 'E', [278, 455, 335, 515], {0: ['Bayview Ice Rink', 'arena'], 1: ['Rinkside Food Court', 'food']}, [[278, 485]]),
    KAnchor('ARENA', 'A', [232, 62, 338, 108], {0: ['Bayview Arena', 'arena'], 1: ['Bayview Arena · Upper tier', 'arena']}, [[285, 45], [285, 125]]),
  ],
  conns: const [
    // Main Mall
    KConn('M-EW', 'escalator', 'West Court escalators', ['M'], _m, 530, 330),
    KConn('M-EG', 'escalator', 'Grand Court escalators', ['M'], _m, 720, 310),
    KConn('M-EE', 'escalator', 'East Court escalators', ['M'], _m, 970, 370),
    KConn('M-L1', 'lift', 'West Court lift', ['M'], _m, 545, 375),
    KConn('M-L2', 'lift', 'Grand Court lift', ['M'], _m, 705, 395),
    KConn('M-L3', 'lift', 'East Court lift', ['M'], _m, 985, 330),
    KConn('M-S1', 'stairs', 'Stairs 1', ['M'], _m, 485, 350), KConn('M-S2', 'stairs', 'Stairs 2', ['M'], _m, 650, 350),
    KConn('M-S3', 'stairs', 'Stairs 3', ['M'], _m, 880, 350), KConn('M-S4', 'stairs', 'Stairs 4', ['M'], _m, 995, 350),
    // Entertainment Wing and Arena
    KConn('E-ESC', 'escalator', 'Wing escalators', ['E'], _e, 270, 300),
    KConn('E-L', 'lift', 'Wing lift', ['E'], _e, 285, 395), KConn('E-S', 'stairs', 'Wing stairs', ['E'], _e, 255, 395),
    KConn('A-S1', 'stairs', 'Arena stairs west', ['A'], _e, 222, 52), KConn('A-S2', 'stairs', 'Arena stairs east', ['A'], _e, 348, 118),
    KConn('A-L', 'lift', 'Arena lift', ['A'], _e, 348, 52), KConn('A-ESC', 'escalator', 'Arena escalators', ['A'], _e, 222, 118),
    // parking buildings: lift, stairs and the vehicle ramp (walkable)
    KConn('NP-L', 'lift', 'North Parking lift', ['NP'], _p, 1140, 215), KConn('NP-S', 'stairs', 'North Parking stairs', ['NP'], _p, 1240, 215),
    KConn('NP-R', 'ramp', 'North Parking ramp', ['NP'], _p, 1255, 265),
    KConn('SP-L', 'lift', 'South Parking lift', ['SP'], _p, 1140, 485), KConn('SP-S', 'stairs', 'South Parking stairs', ['SP'], _p, 1240, 485),
    KConn('SP-R', 'ramp', 'South Parking ramp', ['SP'], _p, 1255, 435),
  ],
  links: const [
    KLink(1, 1080, 300, 1125, 300, 'the bridge to North Parking', 'Bridge M→NP (L2)'),
    KLink(1, 1080, 400, 1125, 400, 'the bridge to South Parking', 'Bridge M→SP (L2)'),
  ],
  exits: const [
    KExit('X-MWN', 'West Court north doors', 'the West Court north doors', 0, 530, 250, 530, 240),
    KExit('X-MWS', 'West Court south doors', 'the West Court south doors', 0, 530, 450, 530, 460),
    KExit('X-MGN', 'Grand Court north doors', 'the Grand Court north doors', 0, 750, 250, 750, 240),
    KExit('X-MGS', 'Grand Entrance', 'the Grand Entrance', 0, 750, 450, 750, 460),
    KExit('X-MEN', 'East Court north doors', 'the East Court north doors', 0, 970, 250, 970, 240),
    KExit('X-MES', 'East Court south doors', 'the East Court south doors', 0, 970, 450, 970, 460),
    KExit('X-MN', 'Drop-off doors north', 'the north drop-off doors', 0, 1080, 300, 1092, 300),
    KExit('X-MS', 'Drop-off doors south', 'the south drop-off doors', 0, 1080, 400, 1092, 400),
    KExit('X-AN', 'Arena Gate 1', 'Arena Gate 1', 0, 285, 40, 285, 12),
    KExit('X-AW', 'Arena Gate 2', 'Arena Gate 2', 0, 210, 85, 190, 85),
    KExit('X-AS', 'Arena Gate 3', 'Arena Gate 3', 0, 270, 130, 270, 150),
    KExit('X-AE', 'Arena Gate 4', 'Arena Gate 4', 0, 360, 85, 390, 85),
    KExit('X-NP', 'North Parking entrance', 'the North Parking entrance', 0, 1125, 265, 1100, 265),
    KExit('X-SP', 'South Parking entrance', 'the South Parking entrance', 0, 1125, 435, 1100, 435),
  ],
  zones: [
    for (final lv in _p) ...[
      _deck('NP', 'North Parking', lv, 'A', 1160, 265), _deck('NP', 'North Parking', lv, 'B', 1220, 265),
      _deck('SP', 'South Parking', lv, 'A', 1160, 435), _deck('SP', 'South Parking', lv, 'B', 1220, 435),
    ],
    const KZone('LOT-S1', 'South lot · Zone 1', 0, 450, 685, [300, 640, 600, 700], 'lot'),
    const KZone('LOT-S2', 'South lot · Zone 2', 0, 860, 685, [800, 640, 1100, 700], 'lot'),
  ],
  services: [
    for (final lv in _m) ...[
      KSvc('${_lv[lv].short}-ATM-W', 'atm', 'ATM', 'M', lv, 600, 300),
      KSvc('${_lv[lv].short}-ATM-E', 'atm', 'ATM', 'M', lv, 880, 400),
    ],
    const KSvc('G-INFO', 'info', 'Information desk', 'M', 0, 750, 350),
    const KSvc('2-INFO', 'info', 'Information desk', 'M', 1, 710, 350),
    const KSvc('3-INFO', 'info', 'Information desk', 'M', 2, 710, 350),
    const KSvc('E-ATM', 'atm', 'ATM', 'E', 0, 270, 380),
    const KSvc('EV-NPG', 'ev', 'EV charging · North Parking', 'NP', 0, 1190, 230),
    const KSvc('EV-SPG', 'ev', 'EV charging · South Parking', 'SP', 0, 1190, 470),
  ],
  groundFx: const [
    KGround('water', [0, 0, 150, 760]), KGround('sand', [150, 0, 157, 760]),
    KGround('road', [0, 712, 1300, 760]), KGround('road', [1278, 0, 1300, 712]), KGround('road', [175, 0, 1278, 6]),
    KGround('road', [1095, 175, 1106, 520]),
    KGround('lot', [300, 640, 1100, 700]), KGround('plazaG', [380, 452, 1092, 540]), KGround('plazaG', [380, 234, 1092, 250]),
    KGround('plazaG', [170, 140, 380, 200]),
  ],
  trees: const [
    ([172, 180, 196, 700], 16), ([380, 520, 1092, 540], 22), ([1110, 520, 1270, 690], 14), ([400, 150, 1092, 228], 18), ([400, 40, 1270, 170], 20),
  ],
  labels: const [KLabel('THE BAY', 70, 380, 0, big: true), KLabel('Promenade', 162, 560, 1)],
  pois: const [KPoi('BUS', 'g-bus', 'Transport terminal', 'Terminal', 720, 600)],
  wcEvery: 15,
  weights: _weights,
  buildingViews: const {
    'M': View(750, 350, 1.9 * _r), 'E': View(270, 360, 2.6 * _r), 'A': View(285, 85, 2.6 * _r),
    'NP': View(1190, 265, 2.6 * _r), 'SP': View(1190, 435, 2.6 * _r), 'T': View(760, 600, 2.6 * _r),
  },
  pad: const [
    PadBtn('W', 'West', 'WC', View(530, 350, 5 * _r)),
    PadBtn('G', 'Grand', 'GC', View(750, 350, 6.5 * _r), main: true),
    PadBtn('E', 'East', 'EC', View(970, 350, 5 * _r)),
    PadBtn('X', 'Wing', 'EW', View(270, 360, 5 * _r)),
    PadBtn('A', 'Arena', 'AR', View(285, 85, 5 * _r)),
  ],
  stack: const StackParams(cx: 650, cy: 380, s: .2, gapM: 330, yaw: stackYaw, ky: stackKy, kz: stackKz, mid: 2, labelAt: [750, 480]),
  siteView: const View(650, 380, 1),
  tripTarget: 'G-ARENA',
  centres: const {0: [750, 350], 1: [750, 310], 2: [750, 310], 3: [1190, 265], 4: [1190, 265]},
  wingLabels: const [
    ('WEST COURT', 530, 350, [0, 1, 2]), ('GRAND COURT', 750, 350, [0, 1, 2]), ('EAST COURT', 970, 350, [0, 1, 2]),
  ],
);

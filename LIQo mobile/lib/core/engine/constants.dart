// Named limits of the routing engine and of the venue specs, from the demo
// app (lib/core/constants.dart there). What only the map drawing needs lives
// in features/map/services/map_constants.dart.
import 'dart:math' as math;

/// A normal walking pace, about 5 km/h (owner decision 2026-10-22; the demo walked at 1.2 m/s).
const double walkMps = 1.4, wheelchairMinWidthM = 1.2;
const Map<String, double> hopCost = {'escalator': 20, 'stairs': 26, 'lift': 40}; // metre-equivalents per level

/// The stacked (exploded) view's angle and squash, shared by every venue's spec.
const double stackYaw = -30 * math.pi / 180, stackKy = 0.38, stackKz = 0.9;

/// Parking availability (per cent free) that counts as good, or still OK.
const double availGood = 40, availOk = 15;

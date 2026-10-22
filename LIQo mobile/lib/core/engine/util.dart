import 'dart:math' as math;

import 'package:collection/collection.dart' show mergeSort;

double lerp(double a, double b, double t) => a + (b - a) * t;
double clampD(double v, double a, double b) => math.max(a, math.min(b, v));
double smooth(double t) {
  t = clampD(t, 0, 1);
  return t * t * (3 - 2 * t);
}

double hypot(double a, double b) => math.sqrt(a * a + b * b);

/// JS `Array.prototype.sort` is stable; Dart's `List.sort` is not. Ties must keep their order.
List<T> stableSorted<T>(Iterable<T> items, int Function(T, T) compare) {
  final l = items.toList();
  mergeSort(l, compare: compare);
  return l;
}

int cmpNum(num a, num b) => a < b ? -1 : (a > b ? 1 : 0);

/// JS `Math.round` (half rounds towards +infinity).
int jsRound(double v) => (v + 0.5).floor();

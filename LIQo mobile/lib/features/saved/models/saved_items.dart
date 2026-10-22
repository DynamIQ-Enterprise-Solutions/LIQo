// What Saved keeps, across every mall (owner decision 2026-10-22): starred places,
// saved routes (a destination and its route options) and the trip history.
import 'package:flutter/foundation.dart';

import '../../navigation/models/route_options.dart';

/// A starred place.
@immutable
class FavPlace {
  const FavPlace(this.mallId, this.placeId);
  final String mallId, placeId;

  Map<String, Object> toJson() => {'mall': mallId, 'place': placeId};
  static FavPlace? fromJson(Object? j) => j is Map && j['mall'] is String && j['place'] is String ? FavPlace(j['mall'] as String, j['place'] as String) : null;

  @override
  bool operator ==(Object other) => other is FavPlace && other.mallId == mallId && other.placeId == placeId;
  @override
  int get hashCode => Object.hash(mallId, placeId);
}

/// A saved route: where to go and how; it starts from wherever the shopper is when opened.
@immutable
class SavedRoute {
  const SavedRoute({required this.id, required this.mallId, required this.placeId, required this.placeName, required this.options, required this.wheelchair, required this.savedAt});
  final String id, mallId, placeId, placeName;
  final RouteOptions options;
  final bool wheelchair;
  final DateTime savedAt;

  Map<String, Object> toJson() => {
        'id': id, 'mall': mallId, 'place': placeId, 'name': placeName, 'options': options.toJson(), 'wheelchair': wheelchair, 'savedAt': savedAt.millisecondsSinceEpoch,
      };

  static SavedRoute? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['mall'] is! String || j['place'] is! String) return null;
    return SavedRoute(
      id: j['id'] as String,
      mallId: j['mall'] as String,
      placeId: j['place'] as String,
      placeName: j['name'] is String ? j['name'] as String : j['place'] as String,
      options: RouteOptions.fromJson(j['options']),
      wheelchair: j['wheelchair'] == true,
      savedAt: DateTime.fromMillisecondsSinceEpoch(j['savedAt'] is int ? j['savedAt'] as int : 0),
    );
  }
}

/// How a trip ended.
enum TripOutcome { inProgress, arrived, stopped }

/// One trip, started from the map (the demo trip included; evacuations are not recorded).
@immutable
class TripRecord {
  const TripRecord({required this.id, required this.mallId, required this.placeId, required this.placeName, required this.startedAt, this.endedAt, this.outcome = TripOutcome.inProgress, required this.options, this.wheelchair = false});
  final String id, mallId, placeId, placeName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final TripOutcome outcome;
  final RouteOptions options;
  final bool wheelchair;

  TripRecord finish(TripOutcome o, DateTime at) =>
      TripRecord(id: id, mallId: mallId, placeId: placeId, placeName: placeName, startedAt: startedAt, endedAt: at, outcome: o, options: options, wheelchair: wheelchair);

  Map<String, Object?> toJson() => {
        'id': id, 'mall': mallId, 'place': placeId, 'name': placeName, 'startedAt': startedAt.millisecondsSinceEpoch, 'endedAt': endedAt?.millisecondsSinceEpoch,
        'outcome': outcome.name, 'options': options.toJson(), 'wheelchair': wheelchair,
      };

  static TripRecord? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['mall'] is! String || j['place'] is! String || j['startedAt'] is! int) return null;
    return TripRecord(
      id: j['id'] as String,
      mallId: j['mall'] as String,
      placeId: j['place'] as String,
      placeName: j['name'] is String ? j['name'] as String : j['place'] as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(j['startedAt'] as int),
      endedAt: j['endedAt'] is int ? DateTime.fromMillisecondsSinceEpoch(j['endedAt'] as int) : null,
      outcome: TripOutcome.values.where((o) => o.name == j['outcome']).firstOrNull ?? TripOutcome.stopped,
      options: RouteOptions.fromJson(j['options']),
      wheelchair: j['wheelchair'] == true,
    );
  }
}

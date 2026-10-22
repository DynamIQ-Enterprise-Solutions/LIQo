import 'package:flutter/foundation.dart';

import '../../../core/engine/routing.dart';

/// Route options (the board's Route Options screen): what a route minimises, and
/// the lifts, escalators or stairs it avoids. Saved as defaults; changing them
/// during a trip works the route out again (owner decision 2026-10-22).
@immutable
class RouteOptions {
  const RouteOptions({this.metric = RouteOpts.fastest, this.avoidStairs = false, this.avoidEscalators = false});

  /// RouteOpts.fastest | RouteOpts.shortest
  final String metric;
  final bool avoidStairs, avoidEscalators;

  /// The hop types a route must not use (wheelchair mode handles its own).
  Set<String> get avoid => {if (avoidStairs) 'stairs', if (avoidEscalators) 'escalator'};

  RouteOptions copyWith({String? metric, bool? avoidStairs, bool? avoidEscalators}) =>
      RouteOptions(metric: metric ?? this.metric, avoidStairs: avoidStairs ?? this.avoidStairs, avoidEscalators: avoidEscalators ?? this.avoidEscalators);

  Map<String, Object> toJson() => {'metric': metric, 'avoidStairs': avoidStairs, 'avoidEscalators': avoidEscalators};

  factory RouteOptions.fromJson(Object? json) {
    if (json is! Map) return const RouteOptions();
    return RouteOptions(
      metric: json['metric'] == RouteOpts.shortest ? RouteOpts.shortest : RouteOpts.fastest,
      avoidStairs: json['avoidStairs'] == true,
      avoidEscalators: json['avoidEscalators'] == true,
    );
  }

  @override
  bool operator ==(Object other) => other is RouteOptions && other.metric == metric && other.avoidStairs == avoidStairs && other.avoidEscalators == avoidEscalators;

  @override
  int get hashCode => Object.hash(metric, avoidStairs, avoidEscalators);
}

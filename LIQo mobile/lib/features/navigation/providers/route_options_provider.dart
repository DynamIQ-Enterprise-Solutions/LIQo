import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/keys.dart';
import '../../../core/storage/store.dart';
import '../models/route_options.dart';

/// The route options, saved as the shopper's defaults.
class RouteOptionsNotifier extends Notifier<RouteOptions> {
  @override
  RouteOptions build() => RouteOptions.fromJson(ref.read(storeProvider).json(Keys.routeOptions));

  void set(RouteOptions o) {
    if (o == state) return;
    state = o;
    ref.read(storeProvider).setJson(Keys.routeOptions, o.toJson());
  }

  void setMetric(String m) => set(state.copyWith(metric: m));
  void setAvoidStairs(bool v) => set(state.copyWith(avoidStairs: v));
  void setAvoidEscalators(bool v) => set(state.copyWith(avoidEscalators: v));
}

final routeOptionsProvider = NotifierProvider<RouteOptionsNotifier, RouteOptions>(RouteOptionsNotifier.new);

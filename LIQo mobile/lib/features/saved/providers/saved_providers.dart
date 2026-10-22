import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/storage/keys.dart';
import '../../../core/storage/store.dart';
import '../../navigation/models/route_options.dart';
import '../models/saved_items.dart';

List<T> _readList<T>(Store store, String key, T? Function(Object?) parse) {
  final j = store.json(key);
  return j is List ? j.map(parse).whereType<T>().toList() : <T>[];
}

/// Starred places, in every mall.
class FavouritesNotifier extends Notifier<List<FavPlace>> {
  @override
  List<FavPlace> build() => _readList(ref.read(storeProvider), Keys.favourites, FavPlace.fromJson);

  bool isFav(String mallId, String placeId) => state.contains(FavPlace(mallId, placeId));

  void toggle(String mallId, String placeId) {
    final f = FavPlace(mallId, placeId);
    state = state.contains(f) ? [for (final x in state) if (x != f) x] : [...state, f];
    ref.read(storeProvider).setJson(Keys.favourites, [for (final x in state) x.toJson()]);
  }
}

final favouritesProvider = NotifierProvider<FavouritesNotifier, List<FavPlace>>(FavouritesNotifier.new);

/// Saved routes, newest first.
class SavedRoutesNotifier extends Notifier<List<SavedRoute>> {
  @override
  List<SavedRoute> build() => _readList(ref.read(storeProvider), Keys.savedRoutes, SavedRoute.fromJson);

  void _save() => ref.read(storeProvider).setJson(Keys.savedRoutes, [for (final r in state) r.toJson()]);

  SavedRoute? find(String mallId, String placeId, RouteOptions options, bool wheelchair) =>
      state.where((r) => r.mallId == mallId && r.placeId == placeId && r.options == options && r.wheelchair == wheelchair).firstOrNull;

  /// Saves the route, or removes it when it is already saved.
  void toggle({required String mallId, required String placeId, required String placeName, required RouteOptions options, required bool wheelchair}) {
    final had = find(mallId, placeId, options, wheelchair);
    if (had != null) {
      remove(had.id);
      return;
    }
    final now = ref.read(clockProvider)();
    state = [
      // unique even when two are saved in the same instant
      SavedRoute(id: 'r${now.microsecondsSinceEpoch}-$mallId-$placeId-${state.length}', mallId: mallId, placeId: placeId, placeName: placeName, options: options, wheelchair: wheelchair, savedAt: now),
      ...state,
    ];
    _save();
  }

  void remove(String id) {
    state = [for (final r in state) if (r.id != id) r];
    _save();
  }
}

final savedRoutesProvider = NotifierProvider<SavedRoutesNotifier, List<SavedRoute>>(SavedRoutesNotifier.new);

/// Every trip started, newest first, the last [cap] kept. A trip still "in progress"
/// when the app starts was cut off: it counts as stopped.
class HistoryNotifier extends Notifier<List<TripRecord>> {
  static const cap = 100;

  @override
  List<TripRecord> build() {
    final store = ref.read(storeProvider);
    var list = _readList(store, Keys.history, TripRecord.fromJson);
    if (list.any((t) => t.outcome == TripOutcome.inProgress)) {
      list = [for (final t in list) t.outcome == TripOutcome.inProgress ? t.finish(TripOutcome.stopped, t.endedAt ?? t.startedAt) : t];
      store.setJson(Keys.history, [for (final t in list) t.toJson()]);
    }
    return list;
  }

  void _save() => ref.read(storeProvider).setJson(Keys.history, [for (final t in state) t.toJson()]);

  /// A trip begins; returns its record's id.
  String start({required String mallId, required String placeId, required String placeName, required RouteOptions options, required bool wheelchair}) {
    final now = ref.read(clockProvider)();
    final id = 't${now.microsecondsSinceEpoch}-${state.length}';
    state = [
      TripRecord(id: id, mallId: mallId, placeId: placeId, placeName: placeName, startedAt: now, options: options, wheelchair: wheelchair),
      ...state,
    ].take(cap).toList();
    _save();
    return id;
  }

  /// A trip ends: arrived, or stopped (stopped by the shopper, replaced by another trip, or the mall switched).
  void finish(String id, TripOutcome outcome) {
    final i = state.indexWhere((t) => t.id == id);
    if (i < 0 || state[i].outcome != TripOutcome.inProgress) return;
    final now = ref.read(clockProvider)();
    state = [for (final t in state) t.id == id ? t.finish(outcome, now) : t];
    _save();
  }

  void clear() {
    state = const [];
    _save();
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, List<TripRecord>>(HistoryNotifier.new);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/util.dart';
import '../../../core/storage/keys.dart';
import '../../../core/storage/store.dart';

/// Places picked from search in one mall, latest first (the board's Recent Searches).
class RecentsNotifier extends Notifier<List<String>> {
  RecentsNotifier(this.mallId);
  final String mallId;
  static const max = 8;

  @override
  List<String> build() {
    final j = ref.read(storeProvider).json(Keys.recent(mallId));
    return j is List ? j.whereType<String>().toList() : <String>[];
  }

  void add(String placeId) {
    state = [placeId, ...state.where((x) => x != placeId)].take(max).toList();
    ref.read(storeProvider).setJson(Keys.recent(mallId), state);
  }

  void clear() {
    state = const [];
    ref.read(storeProvider).setJson(Keys.recent(mallId), state);
  }
}

final recentsProvider = NotifierProvider.family<RecentsNotifier, List<String>, String>(RecentsNotifier.new);

/// How often each place in one mall was opened or navigated to on this phone
/// ("Most visited"; the popular places across all shoppers need the backend).
class VisitsNotifier extends Notifier<Map<String, int>> {
  VisitsNotifier(this.mallId);
  final String mallId;

  @override
  Map<String, int> build() {
    final j = ref.read(storeProvider).json(Keys.visits(mallId));
    return j is Map ? {for (final e in j.entries) if (e.key is String && e.value is int) e.key as String: e.value as int} : <String, int>{};
  }

  void visit(String placeId) {
    state = {...state, placeId: (state[placeId] ?? 0) + 1};
    ref.read(storeProvider).setJson(Keys.visits(mallId), state);
  }

  /// The most visited place ids, most first (ties: the first visited).
  List<String> top(int n) => [for (final x in stableSorted(state.entries, (a, b) => b.value.compareTo(a.value)).take(n)) x.key];
}

final visitsProvider = NotifierProvider.family<VisitsNotifier, Map<String, int>, String>(VisitsNotifier.new);

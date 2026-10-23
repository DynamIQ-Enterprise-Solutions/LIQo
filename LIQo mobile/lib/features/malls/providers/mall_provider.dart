import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/venue.dart';
import '../../../core/storage/keys.dart';
import '../../../core/storage/store.dart';
import 'malls_provider.dart';

/// The mall the shopper is in (chosen on the picker, switched from the header);
/// null until one is chosen, or when it is no longer on the phone. Saved between launches.
class MallNotifier extends Notifier<String?> {
  @override
  String? build() {
    final id = ref.read(storeProvider).get(Keys.mall);
    return ref.read(mallsProvider).saved.containsKey(id) ? id : null;
  }

  /// Use [switchMall] from the screens: it ends the trip first.
  void set(String id) {
    if (id == state) return;
    state = id;
    ref.read(storeProvider).set(Keys.mall, id);
  }

  /// No mall (the current one was deleted, or could not be read).
  void clear() {
    state = null;
    ref.read(storeProvider).remove(Keys.mall);
  }
}

final mallProvider = NotifierProvider<MallNotifier, String?>(MallNotifier.new);

/// A saved mall's venue, built from its package. Only for malls on the phone
/// ([MallsState.isSaved]); asking for another is a programming error.
final venueProvider = Provider.family<Venue, String>((ref, id) {
  final v = ref.watch(mallsProvider.select((s) => s.venues[id]));
  if (v == null) throw StateError('Mall $id is not on this phone');
  return v;
});

/// The current mall's venue.
final currentVenueProvider = Provider<Venue?>((ref) {
  final id = ref.watch(mallProvider);
  return id == null ? null : ref.watch(mallsProvider.select((s) => s.venues[id]));
});

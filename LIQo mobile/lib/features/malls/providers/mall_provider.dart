import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/venue.dart';
import '../../../core/storage/keys.dart';
import '../../../core/storage/store.dart';
import '../data/registry.dart';

/// The mall the shopper is in (chosen on the picker, switched from the header);
/// null until one is chosen. Saved between launches.
class MallNotifier extends Notifier<String?> {
  @override
  String? build() {
    final id = ref.read(storeProvider).get(Keys.mall);
    return venueRegistry.any((e) => e.id == id) ? id : null;
  }

  /// Use [switchMall] from the screens: it ends the trip first.
  void set(String id) {
    if (id == state) return;
    state = id;
    ref.read(storeProvider).set(Keys.mall, id);
  }
}

final mallProvider = NotifierProvider<MallNotifier, String?>(MallNotifier.new);

/// A mall's venue, built once and kept.
final venueProvider = Provider.family<Venue, String>((ref, id) => venueRegistry.firstWhere((e) => e.id == id).build());

/// The current mall's venue.
final currentVenueProvider = Provider<Venue?>((ref) {
  final id = ref.watch(mallProvider);
  return id == null ? null : ref.watch(venueProvider(id));
});

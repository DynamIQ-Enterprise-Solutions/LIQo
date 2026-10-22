import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/providers/nav_provider.dart';
import 'mall_provider.dart';

/// Changes the mall. The trip in progress ends (it counts as stopped) and the
/// position is cleared (owner decision 2026-10-22: switching resets).
void switchMall(WidgetRef ref, String id) {
  final current = ref.read(mallProvider);
  if (current == id) return;
  if (current != null) ref.read(navProvider.notifier).endForSwitch();
  ref.read(mallProvider.notifier).set(id);
}

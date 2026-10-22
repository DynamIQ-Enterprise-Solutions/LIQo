import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/keys.dart';
import '../../../core/storage/store.dart';

@immutable
class Boot {
  const Boot({this.splashDone = false, this.onboardingSeen = false});

  /// The splash has shown for its minimum time and the malls are built (this launch).
  final bool splashDone;

  /// The three onboarding slides were seen (first launch only).
  final bool onboardingSeen;
}

class BootNotifier extends Notifier<Boot> {
  @override
  Boot build() => Boot(onboardingSeen: ref.read(storeProvider).get(Keys.onboardingSeen) == '1');

  void splashDone() => state = Boot(splashDone: true, onboardingSeen: state.onboardingSeen);

  void onboardingDone() {
    ref.read(storeProvider).set(Keys.onboardingSeen, '1');
    state = Boot(splashDone: state.splashDone, onboardingSeen: true);
  }
}

final bootProvider = NotifierProvider<BootNotifier, Boot>(BootNotifier.new);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/words.dart';
import 'settings_provider.dart';

/// The wording in the chosen language.
final wordsProvider = Provider<Words>((ref) => Words(ref.watch(settingsProvider.select((s) => s.lang))));

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/toast.dart';
import '../../navigation/providers/nav_provider.dart';
import '../../settings/providers/words_provider.dart';
import 'mall_provider.dart';
import 'malls_provider.dart';

/// Changes the mall to one on the phone. The trip in progress ends (it counts as
/// stopped) and the position is cleared (owner decision 2026-10-22: switching resets).
/// Opening a saved mall asks the server what's new for it (owner decision 2026-10-23).
void switchMall(WidgetRef ref, String id) {
  final current = ref.read(mallProvider);
  if (current == id) return;
  if (current != null) ref.read(navProvider.notifier).endForSwitch();
  ref.read(mallProvider.notifier).set(id);
  ref.read(mallsProvider.notifier).checkForUpdates();
}

/// Opens a mall from a list: downloads it first when it isn't on the phone (asking on mobile
/// data, owner decision 2026-10-23), says why when that fails, then switches to it.
/// True when the mall is now open.
Future<bool> openMall(BuildContext context, WidgetRef ref, String id) async {
  final malls = ref.read(mallsProvider.notifier);
  if (!ref.read(mallsProvider).isSaved(id)) {
    var r = await malls.download(id);
    if (r == DownloadFailure.needsMobileOk) {
      if (!context.mounted) return false;
      final size = ref.read(mallsProvider).directory?.branch(id)?.package?.sizeBytes ?? 0;
      final ok = await confirmMobileDownload(context, ref, size);
      if (!ok) return false;
      r = await malls.download(id, mobileOk: true);
    }
    if (r != null) {
      if (context.mounted) showToast(context, downloadFailureText(ref, r));
      return false;
    }
  }
  switchMall(ref, id);
  return true;
}

/// "Download 12 MB on mobile data?"
Future<bool> confirmMobileDownload(BuildContext context, WidgetRef ref, int bytes) async {
  final w = ref.read(wordsProvider);
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(w.tr('Download on mobile data?')),
      content: Text(w.tr('This mall\'s map is ${formatSize(bytes)}. You\'re on mobile data, not Wi-Fi.')),
      actions: [
        TextButton(key: const ValueKey('mobile-no'), onPressed: () => Navigator.of(context).pop(false), child: Text(w.tr('Not now'))),
        FilledButton(key: const ValueKey('mobile-yes'), onPressed: () => Navigator.of(context).pop(true), child: Text(w.tr('Download'))),
      ],
    ),
  );
  return r ?? false;
}

String downloadFailureText(WidgetRef ref, DownloadFailure f) => ref.read(wordsProvider).tr(switch (f) {
      DownloadFailure.offline => 'No connection. Try again when you\'re online.',
      DownloadFailure.needsMobileOk => 'Not downloaded.',
      DownloadFailure.server || DownloadFailure.corrupt => 'The download didn\'t work. Please try again.',
      DownloadFailure.newerFormat => 'Update LIQo to get this mall\'s map.',
      DownloadFailure.storage => 'Not enough space on your phone for this map.',
    });

/// "12 MB", "850 KB".
String formatSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    final mb = bytes / (1024 * 1024);
    return '${mb >= 10 ? mb.round() : mb.toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}

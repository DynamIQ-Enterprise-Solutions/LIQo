// "Update LIQo": shown over everything when the server retires this app version
// (rare, for serious problems; owner decision 2026-10-23).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/theme.dart';
import '../../settings/providers/words_provider.dart';

class UpdateAppView extends ConsumerWidget {
  const UpdateAppView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider);
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const ValueKey('update-app'),
        backgroundColor: p.bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.system_update_outlined, size: 56, color: p.brand2),
                const SizedBox(height: 16),
                Semantics(header: true, child: Text(w.tr('Please update LIQo'), textAlign: TextAlign.center, style: ts(22, w: FontWeight.w800, color: p.ink))),
                const SizedBox(height: 8),
                Text(
                  w.tr('This version of LIQo can no longer be used. Get the latest version from your app store.'),
                  textAlign: TextAlign.center,
                  style: ts(14.5, color: p.muted),
                ),
                const SizedBox(height: 12),
                Text(w.tr('Version $appVersion'), style: ts(12.5, color: p.muted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

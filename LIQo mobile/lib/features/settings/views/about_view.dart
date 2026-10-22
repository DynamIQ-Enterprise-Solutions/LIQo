// About LIQo: the wordmark, the tagline, the version, what LIQo is, and the
// licences (Manrope's included).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/brand.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/page.dart';
import '../providers/words_provider.dart';

class AboutView extends ConsumerWidget {
  const AboutView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider);
    return AppPage(
      title: w.tr('About LIQo'),
      children: [
        const SizedBox(height: 12),
        const Center(child: FittedBox(fit: BoxFit.scaleDown, child: BrandLockup(size: 48))),
        const SizedBox(height: 10),
        Center(child: Text(w.tr('Version $appVersion'), style: ts(13, color: p.muted))),
        const SizedBox(height: 20),
        Text(
          w.tr('LIQo finds your way inside the mall: search for a store, see whether it is open, and follow the directions floor by floor. The three malls in the app are samples until your mall is on LIQo.'),
          style: ts(15, color: p.ink, height: 1.5),
        ),
        const SizedBox(height: 20),
        CardX(children: [
          RowX(
            key: const ValueKey('licences'),
            onTap: () => showLicensePage(context: context, applicationName: 'LIQo', applicationVersion: appVersion, applicationLegalese: brandTagline),
            title: w.tr('Licences'),
            trail: Icon(Icons.chevron_right, color: p.muted),
            last: true,
          ),
        ]),
      ],
    );
  }
}

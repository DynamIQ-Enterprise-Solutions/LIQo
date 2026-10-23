import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/skeleton.dart';
import 'ai_service.dart';
import 'credit_bar.dart';

// The AI parts of the Settings page (Round 15; tiles since 2026-10-23): which
// IQGateway model reads floor plans (from the gateway's own list), and the
// credit wallet. The page's one Save button saves the model.

/// The model picker. [choice] is the unsaved pick (null = unchanged).
/// Owner decision 2026-10-23: the list opens just under the field, as wide as
/// it and about five rows tall (it scrolls), so the tile stays visible; the
/// field shows the model and its maker on two lines.
class AiModelField extends ConsumerWidget {
  const AiModelField({super.key, required this.current, required this.choice, required this.onChanged});

  final String? current;
  final String? choice;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    return ref.watch(aiModelsProvider).when(
          loading: () => const Shimmer(child: SkeletonForm(fields: 1)),
          error: (e, _) => AiRetry(text: formatApiError(e), onRetry: () => ref.invalidate(aiModelsProvider)),
          data: (d) {
            final (models, _) = d;
            final offered = models.any((m) => m.id == current);
            final value = choice ?? current;
            final picked = models.cast<AiModel?>().firstWhere((m) => m!.id == value, orElse: () => null);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Model for reading plans', style: ts(11, w: FontWeight.w700, color: p.ink)),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, c) => MenuAnchor(
                    alignmentOffset: const Offset(0, 4),
                    style: MenuStyle(
                      backgroundColor: WidgetStatePropertyAll(p.panel),
                      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
                      minimumSize: WidgetStatePropertyAll(Size(c.maxWidth, 0)),
                      maximumSize: WidgetStatePropertyAll(Size(c.maxWidth, 240)),
                      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
                      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: p.line))),
                    ),
                    menuChildren: [
                      if (models.isEmpty) MenuItemButton(onPressed: null, child: Text('The gateway listed no models', style: ts(12, color: p.muted))),
                      for (final m in models)
                        MenuItemButton(
                          key: ValueKey('ai-model-${m.id}'),
                          onPressed: () => onChanged(m.id == current ? null : m.id),
                          trailingIcon: m.id == value ? Icon(Icons.check, size: 16, color: p.brand) : null,
                          child: SizedBox(
                            width: (c.maxWidth - 60).clamp(80, double.infinity).toDouble(),
                            child: Text(
                              '${m.label}${m.provider == null ? '' : ' · ${m.provider}'}',
                              overflow: TextOverflow.ellipsis,
                              style: ts(12, w: m.id == value ? FontWeight.w700 : FontWeight.w400, color: p.ink),
                            ),
                          ),
                        ),
                    ],
                    builder: (context, menu, _) => Material(
                      color: p.panel,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: menu.isOpen ? p.brand : p.fieldLine)),
                      child: InkWell(
                        key: const ValueKey('ai-model-field'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => menu.isOpen ? menu.close() : menu.open(),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: picked == null
                                    ? Text(
                                        value ?? (models.isEmpty ? 'The gateway listed no models' : 'Choose a model…'),
                                        overflow: TextOverflow.ellipsis,
                                        style: ts(13, color: value == null ? p.hint : p.ink),
                                      )
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(picked.label, key: const ValueKey('ai-model-name'), overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w700, color: p.ink)),
                                          if (picked.provider != null) Text(picked.provider!, overflow: TextOverflow.ellipsis, style: ts(11, color: p.muted)),
                                        ],
                                      ),
                              ),
                              Icon(menu.isOpen ? Icons.expand_less : Icons.expand_more, size: 20, color: p.slate),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('The chat models IQGateway offers this key; only these can read a plan.', style: ts(11, color: p.muted)),
                if (current == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('No model is chosen yet, so plans cannot be read.', key: const ValueKey('ai-no-model'), style: ts(12, color: p.warn)),
                  )
                else if (!offered)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('The saved model ($current) is no longer offered by the gateway. Choose another.', style: ts(12, color: p.warn)),
                  ),
              ],
            );
          },
        );
  }
}

/// The wallet: the credit status bar, or why there is none.
class AiCredits extends StatelessWidget {
  const AiCredits({super.key, required this.status});

  final AiStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Credits', style: ts(11, w: FontWeight.w700, color: p.ink)),
        const SizedBox(height: 6),
        if (s.quota != null && !s.quota!.isEmpty) ...[
          CreditBar(quota: s.quota!),
          // Round 19: what mall admins hold and what is left to give (Analytics has the detail).
          if (s.quota!.given != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Given to mall admins ${credits(s.quota!.given!)} · Free to give ${credits(s.quota!.free ?? 0)}',
                key: const ValueKey('ai-given-free'),
                style: ts(12, color: (s.quota!.overGiven ?? 0) > 0 ? p.danger : p.muted),
              ),
            ),
        ] else
          Text(s.quotaError ?? 'The gateway did not report a balance.', style: ts(12, color: s.quotaError == null ? p.muted : p.warn)),
        const SizedBox(height: 8),
        Text('Only the gateway wallet limits AI reading. Every reading is in the audit log with its cost.', style: ts(11, color: p.sideNote)),
      ],
    );
  }
}

/// Shown when the gateway key is not on the server.
class AiNotConfigured extends StatelessWidget {
  const AiNotConfigured({super.key});

  @override
  Widget build(BuildContext context) => Text(
        'The IQGateway key is not on the server yet. Add IQ_GATEWAY_KEY to the backend .env file and restart the server; the key never goes into this app.',
        key: const ValueKey('ai-not-configured'),
        style: ts(12, color: context.pal.warn),
      );
}

/// A load problem with a way to try again.
class AiRetry extends StatelessWidget {
  const AiRetry({super.key, required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: ts(12, color: p.warn)),
        const SizedBox(height: 8),
        AppButton(label: 'Try again', small: true, onPressed: onRetry),
      ],
    );
  }
}

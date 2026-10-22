import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/field_builder.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/skeleton.dart';
import 'ai_service.dart';
import 'credit_bar.dart';

/// Settings: which IQGateway model reads floor plans, and the credit wallet
/// (Round 15, owner decision: ask the gateway which models exist, then choose).
class AiSettingsCard extends ConsumerStatefulWidget {
  const AiSettingsCard({super.key});

  @override
  ConsumerState<AiSettingsCard> createState() => _AiSettingsCardState();
}

class _AiSettingsCardState extends ConsumerState<AiSettingsCard> {
  String? _choice;
  bool _busy = false;

  Future<void> _save() async {
    final model = _choice;
    if (model == null) return;
    setState(() => _busy = true);
    try {
      await AiService().setModel(model);
      ref.invalidate(aiStatusProvider);
      ref.invalidate(aiModelsProvider);
      setState(() => _choice = null);
      ref.read(messagesProvider.notifier).showSuccess('AI model saved. New readings use $model.');
    } catch (e) {
      ref.read(messagesProvider.notifier).showError(formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final status = ref.watch(aiStatusProvider);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHead(title: 'AI floor-plan reading', subtitle: 'Through IQGateway'),
          CardBody(
            child: status.when(
              loading: () => const Shimmer(child: SkeletonForm(fields: 2)),
              error: (e, _) => _Problem(text: formatApiError(e), onRetry: () => ref.invalidate(aiStatusProvider)),
              data: (s) {
                if (!s.configured) {
                  return Text(
                    'The IQGateway key is not on the server yet. Add IQ_GATEWAY_KEY to the backend .env file and restart the server; the key never goes into this app.',
                    key: const ValueKey('ai-not-configured'),
                    style: ts(13, color: p.warn),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ModelPicker(
                      current: s.model,
                      choice: _choice,
                      busy: _busy,
                      onChanged: (v) => setState(() => _choice = v),
                      onSave: _save,
                    ),
                    const SizedBox(height: 16),
                    Text('Credits', style: ts(12, w: FontWeight.w700, color: p.ink)),
                    const SizedBox(height: 6),
                    if (s.quota != null && !s.quota!.isEmpty)
                      CreditBar(quota: s.quota!)
                    else
                      Text(s.quotaError ?? 'The gateway did not report a balance.', style: ts(12, color: s.quotaError == null ? p.muted : p.warn)),
                    const SizedBox(height: 6),
                    Text('Only the gateway wallet limits AI reading. Every reading is in the audit log with its cost.', style: ts(11, color: p.sideNote)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelPicker extends ConsumerWidget {
  const _ModelPicker({required this.current, required this.choice, required this.busy, required this.onChanged, required this.onSave});

  final String? current;
  final String? choice;
  final bool busy;
  final ValueChanged<String?> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    return ref.watch(aiModelsProvider).when(
          loading: () => const Shimmer(child: SkeletonForm(fields: 1)),
          error: (e, _) => _Problem(text: formatApiError(e), onRetry: () => ref.invalidate(aiModelsProvider)),
          data: (d) {
            final (models, _) = d;
            final offered = models.any((m) => m.id == current);
            final spec = FieldSpec(
              name: 'ai_model',
              label: 'Model for reading plans',
              kind: FieldKind.select,
              hint: models.isEmpty ? 'The gateway listed no models' : 'Choose a model…',
              options: [
                for (final m in models) SelectOption(m.id, '${m.label}${m.provider == null ? '' : ' · ${m.provider}'}'),
              ],
              help: 'The chat models IQGateway offers this key; only these can read a plan.',
            );
            final value = choice ?? current;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldBuilder(spec: spec, value: value, onChanged: (v) => onChanged(v as String?)),
                if (current == null)
                  Text('No model is chosen yet, so plans cannot be read.', key: const ValueKey('ai-no-model'), style: ts(12, color: p.warn))
                else if (!offered)
                  Text('The saved model ($current) is no longer offered by the gateway. Choose another.', style: ts(12, color: p.warn)),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    AppButton(
                      label: busy ? 'Saving…' : 'Save model',
                      primary: true,
                      onPressed: busy || choice == null || choice == current ? () {} : onSave,
                    ),
                  ],
                ),
              ],
            );
          },
        );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.text, required this.onRetry});

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

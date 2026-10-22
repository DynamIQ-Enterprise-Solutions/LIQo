import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/field_builder.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/skeleton.dart';
import '../ai/ai_settings_card.dart';

class SettingsRule {
  const SettingsRule({required this.min, required this.max, required this.label});

  final int min;
  final int max;
  final String label;
}

class SettingsData {
  const SettingsData({required this.values, required this.rules});

  final Map<String, String> values;
  final Map<String, SettingsRule> rules;

  factory SettingsData.fromJson(Map<String, dynamic> j) => SettingsData(
        values: (j['settings'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString())),
        rules: (j['rules'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, SettingsRule(min: v['min'] as int, max: v['max'] as int, label: v['label'] as String)),
        ),
      );
}

class SettingsService {
  SettingsService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<SettingsData> get() async {
    final r = await _client.dio.get('/settings');
    return SettingsData.fromJson(r.data as Map<String, dynamic>);
  }

  Future<SettingsData> update(Map<String, int> values) async {
    final r = await _client.dio.put('/settings', data: values);
    return SettingsData.fromJson(r.data as Map<String, dynamic>);
  }
}

final settingsProvider = FutureProvider.autoDispose<SettingsData>((ref) => SettingsService().get());

const _help = {
  'min_password_length': 'Applied when anyone sets a new password.',
  'ai_file_size_mb': 'Largest blueprint file the AI conversion will accept.',
  'default_announcement_days': 'Pre-filled duration for new announcements.',
  'session_timeout_hours': 'How long a sign-in stays valid.',
  'max_login_attempts': 'Wrong passwords in a row before the account is locked for 15 minutes.',
};

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final Map<String, Object?> _values = {};
  final Map<String, String?> _errors = {};
  bool _busy = false;

  Future<void> _save(SettingsData data) async {
    final specs = _specs(data);
    final errors = <String, String?>{};
    for (final s in specs) {
      final e = s.validate(_values[s.name] ?? data.values[s.name]);
      if (e != null) errors[s.name] = e;
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    if (errors.isNotEmpty) return;

    final payload = <String, int>{};
    for (final s in specs) {
      final v = (_values[s.name] ?? data.values[s.name]).toString();
      payload[s.name] = int.parse(v.trim());
    }
    setState(() => _busy = true);
    try {
      await SettingsService().update(payload);
      ref.invalidate(settingsProvider);
      _values.clear();
      ref.read(messagesProvider.notifier).showSuccess('Settings saved.');
    } catch (e) {
      ref.read(messagesProvider.notifier).showError(formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<FieldSpec> _specs(SettingsData d) => [
        for (final e in d.rules.entries)
          FieldSpec(
            name: e.key,
            label: e.value.label,
            kind: FieldKind.integer,
            required: true,
            min: e.value.min,
            max: e.value.max,
            help: '${_help[e.key] ?? ''} Allowed: ${e.value.min}–${e.value.max}.',
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final data = ref.watch(settingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHead(
          eyebrow: 'Superadmin / Settings',
          title: 'Platform settings',
          subtitle: 'Global defaults enforced by the server for everyone.',
        ),
        data.when(
          loading: () => ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: const Shimmer(child: SkeletonCard(child: SkeletonForm(fields: 6)))),
          error: (e, _) => AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatApiError(e), style: ts(12, color: p.warn)),
                const SizedBox(height: 10),
                AppButton(label: 'Try again', primary: true, onPressed: () => ref.invalidate(settingsProvider)),
              ],
            ),
          ),
          data: (d) => ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const CardHead(title: 'Limits and defaults', subtitle: 'Changes apply immediately'),
                      CardBody(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final s in _specs(d))
                              FieldBuilder(
                                key: ValueKey('${s.name}-${d.values[s.name]}'),
                                spec: s,
                                value: _values[s.name] ?? d.values[s.name],
                                error: _errors[s.name],
                                onChanged: (v) => setState(() {
                                  _values[s.name] = v;
                                  _errors.remove(s.name);
                                }),
                              ),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 9,
                              runSpacing: 9,
                              children: [
                                AppButton(
                                  label: 'Discard changes',
                                  onPressed: () => setState(() {
                                    _values.clear();
                                    _errors.clear();
                                  }),
                                ),
                                AppButton(
                                  label: _busy ? 'Saving…' : 'Save settings',
                                  primary: true,
                                  onPressed: _busy ? () {} : () => _save(d),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Round 15: the model that reads floor plans, and the credit wallet.
                const AiSettingsCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

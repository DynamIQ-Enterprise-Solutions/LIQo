import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/skeleton.dart';
import '../ai/ai_service.dart';
import '../ai/ai_settings_card.dart';
import 'settings_tiles.dart';

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

/// Owner decision 2026-10-23: two columns (AI floor-plan reading on the left;
/// Sign-in & security and General in one card on the right) from 760 px of
/// content, else one; a column is never wider than [_tileMax].
const _tileMax = 560.0;
const _gap = 16.0;
int settingsColumns(double width) => width >= 760 ? 2 : 1;

/// Platform settings (owner decision 2026-10-23: topic tiles, one save bar).
class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  /// Unsaved numbers, as typed or stepped.
  final Map<String, Object?> _values = {};
  final Map<String, String?> _errors = {};

  /// Bumped by − / + so the box shows the new number.
  final Map<String, int> _revision = {};

  /// The unsaved model pick (null = unchanged).
  String? _model;
  bool _busy = false;

  // The tile's short name, so a message reads like the setting on screen.
  FieldSpec _spec(String key, SettingsRule r) => FieldSpec(name: key, label: settingInfo[key]?.name ?? r.label, kind: FieldKind.integer, required: true, min: r.min, max: r.max);

  String _text(SettingsData d, String key) => '${_values[key] ?? d.values[key] ?? ''}';

  bool _changed(SettingsData d, String key) {
    final now = _text(d, key).trim();
    final saved = (d.values[key] ?? '').trim();
    final a = int.tryParse(now);
    return a == null ? now != saved : a != int.tryParse(saved);
  }

  int _changes(SettingsData d, String? currentModel) => d.rules.keys.where((k) => _changed(d, k)).length + (_model != null && _model != currentModel ? 1 : 0);

  void _discard() => setState(() {
        _values.clear();
        _errors.clear();
        for (final k in _revision.keys) {
          _revision[k] = _revision[k]! + 1;
        }
        _model = null;
      });

  Future<void> _save(SettingsData d, String? currentModel) async {
    final errors = <String, String?>{};
    for (final e in d.rules.entries) {
      final err = _spec(e.key, e.value).validate(_text(d, e.key));
      if (err != null) errors[e.key] = err;
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    if (errors.isNotEmpty) return;
    final numbers = d.rules.keys.any((k) => _changed(d, k));
    final model = _model != null && _model != currentModel ? _model : null;
    setState(() => _busy = true);
    final m = ref.read(messagesProvider.notifier);
    try {
      if (numbers) {
        await SettingsService().update({for (final k in d.rules.keys) k: int.parse(_text(d, k).trim())});
        _values.clear();
        ref.invalidate(settingsProvider);
      }
      if (model != null) {
        await AiService().setModel(model);
        _model = null;
        ref.invalidate(aiStatusProvider);
        ref.invalidate(aiModelsProvider);
      }
      m.showSuccess(model == null ? 'Settings saved.' : 'Settings saved. New readings use $model.');
    } catch (e) {
      m.showError(formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stepper(SettingsData d, String key) {
    final rule = d.rules[key]!;
    final info = settingInfo[key] ?? SettingInfo(SettingsTopic.other, rule.label, '', 'Server setting');
    return NumberStepper(
      key: ValueKey('setting-$key'),
      spec: _spec(key, rule),
      info: info,
      text: _text(d, key),
      revision: _revision[key] ?? 0,
      changed: _changed(d, key),
      error: _errors[key],
      onChanged: (v) => setState(() {
        _values[key] = v;
        _errors.remove(key);
      }),
      onStep: (to) => setState(() {
        _values[key] = '$to';
        _errors.remove(key);
        _revision[key] = (_revision[key] ?? 0) + 1;
      }),
    );
  }

  List<Widget> _tiles(SettingsData d, AsyncValue<AiStatus> status) {
    List<String> keysOf(SettingsTopic t) => [
          for (final k in d.rules.keys)
            if ((settingInfo[k]?.topic ?? SettingsTopic.other) == t) k
        ];
    return [
      // Owner decision 2026-10-23: AI reading on the left.
      TopicTile(
        key: const ValueKey('tile-ai'),
        title: 'AI floor-plan reading',
        subtitle: 'Through IQGateway',
        icon: Icons.auto_awesome_outlined,
        children: [
          ...status.when(
            loading: () => [const Shimmer(child: SkeletonForm(fields: 2))],
            error: (e, _) => [AiRetry(text: formatApiError(e), onRetry: () => ref.invalidate(aiStatusProvider))],
            data: (s) => s.configured
                ? [
                    AiModelField(current: s.model, choice: _model, onChanged: (v) => setState(() => _model = v)),
                    AiCredits(status: s),
                  ]
                : [const AiNotConfigured()],
          ),
          for (final k in keysOf(SettingsTopic.ai)) _stepper(d, k),
        ],
      ),
      // Owner decision 2026-10-23: one card on the right with Sign-in & security,
      // then General (the announcement length and any setting the page does not know yet).
      SectionedTile(
        key: const ValueKey('tile-rules'),
        sections: [
          TileSection(
            key: const ValueKey('tile-security'),
            title: 'Sign-in & security',
            subtitle: 'Passwords and sign-ins',
            icon: Icons.lock_outline,
            children: [for (final k in keysOf(SettingsTopic.security)) _stepper(d, k)],
          ),
          TileSection(
            key: const ValueKey('tile-general'),
            title: 'General',
            subtitle: 'Announcements and other defaults',
            icon: Icons.tune,
            children: [
              for (final k in [...keysOf(SettingsTopic.announcements), ...keysOf(SettingsTopic.other)]) _stepper(d, k)
            ],
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final data = ref.watch(settingsProvider);
    final status = ref.watch(aiStatusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHead(
          eyebrow: 'Superadmin / Settings',
          title: 'Platform settings',
          subtitle: 'Global defaults enforced by the server for everyone.',
        ),
        LayoutBuilder(builder: (context, c) {
          final cols = settingsColumns(c.maxWidth);
          final tileW = math.min(_tileMax, (c.maxWidth - _gap * (cols - 1)) / cols);
          final gridW = tileW * cols + _gap * (cols - 1);
          Widget grid(List<Widget> tiles) => Wrap(
                spacing: _gap,
                runSpacing: _gap,
                children: [for (final t in tiles) SizedBox(width: tileW, child: t)],
              );
          return Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: gridW,
              child: data.when(
                loading: () => Shimmer(
                    child: grid([
                  for (final f in const [4, 4]) SkeletonCard(child: SkeletonForm(fields: f))
                ])),
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
                data: (d) {
                  final current = status.valueOrNull?.model;
                  final n = _changes(d, current);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      grid(_tiles(d, status)),
                      if (n > 0) ...[
                        const SizedBox(height: _gap),
                        _SaveBar(changes: n, busy: _busy, onDiscard: _discard, onSave: () => _save(d, current)),
                      ],
                    ],
                  );
                },
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Shown only when something changed: how many, Discard and Save settings.
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.changes, required this.busy, required this.onDiscard, required this.onSave});

  final int changes;
  final bool busy;
  final VoidCallback onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      key: const ValueKey('settings-save-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Text(changes == 1 ? '1 change not saved yet' : '$changes changes not saved yet', key: const ValueKey('settings-changes'), style: ts(12, w: FontWeight.w700, color: p.ink)),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              AppButton(key: const ValueKey('settings-discard'), label: 'Discard', onPressed: busy ? () {} : onDiscard),
              AppButton(key: const ValueKey('settings-save'), label: busy ? 'Saving…' : 'Save settings', primary: true, onPressed: busy ? () {} : onSave),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/forms/field_builder.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/widgets/common.dart';

// Platform settings as topic tiles (owner decision 2026-10-23, layout B): the
// settings grouped by topic, each number with − / + and its unit.

enum SettingsTopic { security, announcements, ai, other }

/// Where a setting sits on the page and how it reads. The server still checks
/// the ranges; a setting not listed here goes to the "Other" tile.
class SettingInfo {
  const SettingInfo(this.topic, this.name, this.unit, this.hint);

  final SettingsTopic topic;
  final String name;
  final String unit;
  final String hint;
}

const settingInfo = <String, SettingInfo>{
  'min_password_length': SettingInfo(SettingsTopic.security, 'Password length', 'characters', 'When anyone sets a new password'),
  'session_timeout_hours': SettingInfo(SettingsTopic.security, 'Session timeout', 'hours', 'How long a sign-in stays valid'),
  'max_login_attempts': SettingInfo(SettingsTopic.security, 'Failed sign-ins', 'tries', 'Then the account locks for 15 minutes'),
  'default_announcement_days': SettingInfo(SettingsTopic.announcements, 'Default length', 'days', 'Pre-filled for new announcements'),
  'ai_file_size_mb': SettingInfo(SettingsTopic.ai, 'Largest plan file', 'MB', 'Bigger plan files are refused'),
  // Round 19: AI credits per mall admin.
  'ai_start_credits': SettingInfo(SettingsTopic.ai, 'Starting credits', 'credits', 'Each new mall admin starts with this'),
  'ai_credit_cap': SettingInfo(SettingsTopic.ai, 'Most credits per admin', 'credits', 'No mall admin can hold more'),
};

/// A topic tile: a card with its title, then its settings separated by soft lines.
class TopicTile extends StatelessWidget {
  const TopicTile({super.key, required this.title, required this.subtitle, required this.icon, required this.children});

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHead(title: title, subtitle: subtitle, trailing: Icon(icon, size: 18, color: p.slate)),
          CardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, c) in children.indexed) ...[
                  if (i > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Container(height: 1, color: p.softLine)),
                  c,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One headed part of a [SectionedTile].
class TileSection {
  const TileSection({required this.key, required this.title, required this.subtitle, required this.icon, required this.children});

  final Key key;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;
}

/// One card holding several topics, each with its own head (owner decision
/// 2026-10-23: Sign-in & security and General share the right-hand card).
class SectionedTile extends StatelessWidget {
  const SectionedTile({super.key, required this.sections});

  final List<TileSection> sections;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, s) in sections.indexed) ...[
            if (i > 0) Container(height: 1, color: p.line),
            Column(
              key: s.key,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardHead(title: s.title, subtitle: s.subtitle, trailing: Icon(s.icon, size: 18, color: p.slate)),
                CardBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (j, c) in s.children.indexed) ...[
                        if (j > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Container(height: 1, color: p.softLine)),
                        c,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One number setting: its name (with a dot when changed), a one-line hint
/// with the allowed range, and − [box] + with the unit.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.spec,
    required this.info,
    required this.text,
    required this.revision,
    required this.changed,
    required this.error,
    required this.onChanged,
    required this.onStep,
  });

  final FieldSpec spec;
  final SettingInfo info;

  /// What the box holds now (typed or stepped).
  final String text;

  /// Changes when − / + set a new value, so the box shows it.
  final int revision;
  final bool changed;
  final String? error;
  final ValueChanged<Object?> onChanged;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final v = int.tryParse(text.trim());
    final min = spec.min?.toInt();
    final max = spec.max?.toInt();
    final canDown = v != null && (min == null || v > min);
    final canUp = v != null && (max == null || v < max);
    Widget step(String key, IconData icon, String tip, bool on, int to) => SizedBox(
          width: 32,
          height: 34,
          child: IconButton(
            key: ValueKey('${spec.name}-$key'),
            tooltip: tip,
            padding: EdgeInsets.zero,
            iconSize: 16,
            style: IconButton.styleFrom(
              backgroundColor: p.boxBg,
              disabledBackgroundColor: p.boxBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: p.pick(p.line, p.fieldLine))),
            ),
            icon: Icon(icon, color: on ? p.ink : p.faint),
            onPressed: on ? () => onStep(to) : null,
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(child: Text(info.name, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w700, color: p.ink))),
            if (changed)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(key: ValueKey('${spec.name}-changed'), width: 7, height: 7, decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle)),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text('${info.hint} · ${spec.min}–${spec.max}', style: ts(11, color: p.muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            step('down', Icons.remove, 'Less', canDown, (v ?? 0) - 1),
            SizedBox(
              width: 72,
              child: FieldBuilder(
                key: ValueKey('${spec.name}-box-$revision'),
                spec: spec,
                value: text,
                bare: true,
                onChanged: onChanged,
              ),
            ),
            step('up', Icons.add, 'More', canUp, (v ?? 0) + 1),
            Text(info.unit, style: ts(12, color: p.slate)),
          ],
        ),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(error!, style: ts(11, color: p.warn))),
      ],
    );
  }
}

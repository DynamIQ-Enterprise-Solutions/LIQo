import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../forms/field_builder.dart';
import '../forms/field_spec.dart';
import '../models/opening_hours.dart';
import 'common.dart';
import 'detail_widgets.dart';

/// Opening hours on a branch or store page (Round 21): a summary, and for
/// those who may change them an inline editor with one row per weekday and a
/// list of special days. [onSave] receives null for "no hours set".
class HoursCard extends StatefulWidget {
  const HoursCard({
    super.key,
    required this.hours,
    required this.canEdit,
    required this.onSave,
    this.subtitle,
    this.emptyText = 'No opening hours yet.',
    this.oldNote,
  });

  final OpeningHours? hours;
  final bool canEdit;
  final Future<void> Function(OpeningHours? hours) onSave;
  final String? subtitle;
  final String emptyText;

  /// The old free-text hours, shown as a read-only note (kept until the hours are entered).
  final String? oldNote;

  @override
  State<HoursCard> createState() => _HoursCardState();
}

class _DayDraft {
  _DayDraft(this.day, DayHours? h)
      : open = h != null,
        from = h?.open ?? '10:00',
        to = h?.close ?? '21:00';
  final int day;
  bool open;
  String from;
  String to;
}

class _SpecialDraft {
  _SpecialDraft([SpecialDay? s])
      : date = s?.date,
        closed = s?.closed ?? true,
        from = s?.open ?? '10:00',
        to = s?.close ?? '21:00',
        note = s?.note ?? '';
  String? date;
  bool closed;
  String from;
  String to;
  String note;
}

class _HoursCardState extends State<HoursCard> {
  bool _editing = false;
  bool _busy = false;
  String? _error;
  late List<_DayDraft> _days;
  late List<_SpecialDraft> _specials;

  void _start() {
    final h = widget.hours;
    setState(() {
      _days = [for (var d = 1; d <= 7; d++) _DayDraft(d, h?.dayOf(d))];
      _specials = [for (final s in h?.specials ?? const <SpecialDay>[]) _SpecialDraft(s)];
      _error = null;
      _editing = true;
    });
  }

  /// The hours typed, or an error message.
  (OpeningHours?, String?) _collect() {
    final week = <DayHours>[];
    for (final d in _days) {
      if (!d.open) continue;
      final name = weekdayNames[d.day - 1];
      if (!isTime(d.from) || !isTime(d.to)) return (null, '$name: use times like 09:30 (24-hour), or 24:00 for midnight.');
      if (d.from.trim() == d.to.trim()) return (null, '$name: opening and closing times must differ.');
      week.add(DayHours(day: d.day, open: d.from.trim(), close: d.to.trim()));
    }
    final specials = <SpecialDay>[];
    final dates = <String>{};
    for (final s in _specials) {
      final date = s.date;
      if (date == null || date.isEmpty) return (null, 'Choose a date for every special day.');
      if (!dates.add(date)) return (null, '$date is listed twice.');
      if (s.note.trim().length > 40) return (null, '$date: keep the note under 40 characters.');
      final note = s.note.trim().isEmpty ? null : s.note.trim();
      if (s.closed) {
        specials.add(SpecialDay(date: date, closed: true, note: note));
      } else {
        if (!isTime(s.from) || !isTime(s.to)) return (null, '$date: use times like 09:30 (24-hour), or 24:00 for midnight.');
        if (s.from.trim() == s.to.trim()) return (null, '$date: opening and closing times must differ.');
        specials.add(SpecialDay(date: date, open: s.from.trim(), close: s.to.trim(), note: note));
      }
    }
    specials.sort((a, b) => a.date.compareTo(b.date));
    return (OpeningHours(week: week, specials: specials), null);
  }

  Future<void> _save({bool clear = false}) async {
    final (hours, error) = clear ? (null, null) : _collect();
    if (error != null) return setState(() => _error = error);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(hours);
      if (mounted) setState(() => _editing = false);
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _time(String name, String value, ValueChanged<String> onChanged) => SizedBox(
        width: 84,
        child: FieldBuilder(
          spec: FieldSpec(name: name, label: name, hint: '10:00', maxLength: 5),
          value: value,
          bare: true,
          onChanged: (v) => onChanged((v as String?) ?? ''),
        ),
      );

  Widget _toggle(String name, String label, bool value, ValueChanged<bool> onChanged) => FieldBuilder(
        spec: FieldSpec(name: name, label: label, kind: FieldKind.toggle),
        value: value,
        bare: true,
        onChanged: (v) => onChanged(v == true),
      );

  Widget _editor(Pal p) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Philippine time, 24-hour. A closing time at or before the opening time runs past midnight; 24:00 is midnight.', style: ts(11.5, color: p.muted)),
          const SizedBox(height: 10),
          for (final d in _days)
            Padding(
              key: ValueKey('hours-day-${d.day}'),
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(width: 88, child: Text(weekdayNames[d.day - 1], style: ts(13, w: FontWeight.w600, color: p.ink))),
                  SizedBox(width: 160, child: _toggle('open-${d.day}', d.open ? 'Open' : 'Closed', d.open, (v) => setState(() => d.open = v))),
                  if (d.open) ...[
                    _time('from-${d.day}', d.from, (v) => d.from = v),
                    Text('to', style: ts(12, color: p.muted)),
                    _time('to-${d.day}', d.to, (v) => d.to = v),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 10),
          Text('SPECIAL DAYS', style: ts(10.5, w: FontWeight.w800, color: p.muted, ls: 1.2)),
          const SizedBox(height: 6),
          if (_specials.isEmpty) Text('Holidays and other dates with different hours.', style: ts(12, color: p.muted)),
          for (var i = 0; i < _specials.length; i++)
            Padding(
              key: ValueKey('hours-special-$i'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    child: FieldBuilder(
                      spec: FieldSpec(name: 'date-$i', label: 'Date', kind: FieldKind.date),
                      value: _specials[i].date,
                      bare: true,
                      onChanged: (v) => setState(() => _specials[i].date = v as String?),
                    ),
                  ),
                  SizedBox(width: 160, child: _toggle('closed-$i', 'Closed', _specials[i].closed, (v) => setState(() => _specials[i].closed = v))),
                  if (!_specials[i].closed) ...[
                    _time('sfrom-$i', _specials[i].from, (v) => _specials[i].from = v),
                    Text('to', style: ts(12, color: p.muted)),
                    _time('sto-$i', _specials[i].to, (v) => _specials[i].to = v),
                  ],
                  SizedBox(
                    width: 170,
                    child: FieldBuilder(
                      spec: FieldSpec(name: 'note-$i', label: 'Note', hint: 'Note (e.g. Holiday)', maxLength: 40),
                      value: _specials[i].note,
                      bare: true,
                      onChanged: (v) => _specials[i].note = (v as String?) ?? '',
                    ),
                  ),
                  AppButton(label: 'Remove', small: true, icon: Icons.close, onPressed: () => setState(() => _specials.removeAt(i))),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(label: 'Add a special day', small: true, icon: Icons.event_outlined, onPressed: () => setState(() => _specials.add(_SpecialDraft()))),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: ts(12, color: p.warn))),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(label: _busy ? 'Saving…' : 'Save hours', primary: true, small: true, onPressed: _busy ? () {} : () => _save()),
              AppButton(label: 'Cancel', small: true, onPressed: _busy ? () {} : () => setState(() => _editing = false)),
              if (widget.hours != null) AppButton(label: 'Clear all hours', small: true, onPressed: _busy ? () {} : () => _save(clear: true)),
            ],
          ),
        ],
      );

  Widget _summary(Pal p) {
    final h = widget.hours;
    final note = widget.oldNote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (h == null)
          Text(widget.emptyText, style: ts(12, color: p.muted))
        else ...[
          for (final line in weekLines(h)) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(line, style: ts(13, color: p.ink))),
          if (h.specials.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('SPECIAL DAYS', style: ts(10.5, w: FontWeight.w800, color: p.muted, ls: 1.2)),
            const SizedBox(height: 4),
            for (final s in h.specials) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(specialText(s), style: ts(12.5, color: p.ink))),
          ],
        ],
        if (note != null && note.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          DetailRow('Old hours note', note),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return DetailCard(
      title: 'Opening hours',
      subtitle: widget.subtitle,
      trailing: widget.canEdit && !_editing ? AppButton(label: 'Edit hours', small: true, icon: Icons.schedule_outlined, onPressed: _start) : null,
      child: _editing ? _editor(p) : _summary(p),
    );
  }
}

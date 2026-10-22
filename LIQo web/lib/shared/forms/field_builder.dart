import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../models/paged.dart';
import 'field_spec.dart';
import 'lookup_picker.dart';

/// The one place a [FieldSpec] becomes a widget.
class FieldBuilder extends StatelessWidget {
  const FieldBuilder({
    super.key,
    required this.spec,
    required this.value,
    required this.onChanged,
    this.error,
    this.values = const {},
    this.note,
  });

  final FieldSpec spec;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final String? error;

  /// All current form values, for dependent lookups.
  final Map<String, Object?> values;

  /// A line under the field, such as the result of a live duplicate check.
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (spec.kind != FieldKind.toggle) ...[
            Row(
              children: [
                Flexible(child: Text(spec.label, overflow: TextOverflow.ellipsis, style: ts(11, w: FontWeight.w700, color: p.ink))),
                if (spec.required) Text(' *', style: ts(11, w: FontWeight.w700, color: p.brand)),
              ],
            ),
            const SizedBox(height: 6),
          ],
          _control(context),
          if (spec.help != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(spec.help!, style: ts(11, color: p.muted)),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(error!, style: ts(11, color: p.warn)),
            ),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 6), child: note),
        ],
      ),
    );
  }

  Widget _control(BuildContext context) {
    final p = context.pal;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: c),
        );
    final decoration = InputDecoration(
      isDense: true,
      hintText: spec.hint,
      hintStyle: ts(13, color: p.hint),
      contentPadding: const EdgeInsets.all(10),
      border: border(p.pick(p.line, p.fieldLine)),
      enabledBorder: border(p.pick(p.line, p.fieldLine)),
      focusedBorder: border(p.brand),
      errorBorder: border(p.warn),
      filled: spec.readOnly,
      fillColor: p.boxBg,
    );

    switch (spec.kind) {
      case FieldKind.text:
      case FieldKind.email:
      case FieldKind.password:
      case FieldKind.multiline:
      case FieldKind.integer:
      case FieldKind.decimal:
        return _TextControl(
          key: ValueKey('${spec.name}-text'),
          spec: spec,
          value: value?.toString() ?? '',
          decoration: decoration,
          onChanged: onChanged,
        );
      case FieldKind.toggle:
        return Row(
          children: [
            Switch(
              value: value == true,
              onChanged: spec.readOnly ? null : (v) => onChanged(v),
              activeThumbColor: p.brand,
            ),
            const SizedBox(width: 8),
            Text(spec.label, style: ts(13, color: p.ink)),
          ],
        );
      case FieldKind.select:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: p.panel,
            border: Border.all(color: p.fieldLine),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: spec.options.any((o) => o.value == value) ? value as String : null,
              hint: Text(spec.hint ?? 'Choose…', style: ts(13, color: p.hint)),
              isExpanded: true,
              isDense: true,
              style: ts(13, color: p.ink),
              dropdownColor: p.panel,
              items: [for (final o in spec.options) DropdownMenuItem(value: o.value, child: Text(o.label))],
              onChanged: spec.readOnly ? null : (v) => onChanged(v),
            ),
          ),
        );
      case FieldKind.lookup:
      case FieldKind.multiLookup:
        final multi = spec.kind == FieldKind.multiLookup;
        final selected = (value as List<LookupItem>?) ?? const [];
        final parentValue = spec.lookupParentField == null ? null : values[spec.lookupParentField!];
        final parentId = parentValue is List<LookupItem> && parentValue.isNotEmpty ? parentValue.first.id : null;
        final needsParent = spec.lookupParentField != null && parentId == null;
        return LookupPicker(
          lookup: spec.lookup!,
          multi: multi,
          selected: selected,
          parentId: parentId,
          enabled: !spec.readOnly && !needsParent,
          placeholder: needsParent ? 'Choose ${spec.lookupParentField} first' : (spec.hint ?? 'Choose…'),
          onChanged: onChanged,
        );
      case FieldKind.date:
        return _DateControl(value: value as String?, decoration: decoration, onChanged: onChanged, readOnly: spec.readOnly);
    }
  }
}

class _TextControl extends StatefulWidget {
  const _TextControl({super.key, required this.spec, required this.value, required this.decoration, required this.onChanged});

  final FieldSpec spec;
  final String value;
  final InputDecoration decoration;
  final ValueChanged<Object?> onChanged;

  @override
  State<_TextControl> createState() => _TextControlState();
}

class _TextControlState extends State<_TextControl> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = widget.spec;
    final numeric = s.kind == FieldKind.integer || s.kind == FieldKind.decimal;
    return TextField(
      controller: _c,
      readOnly: s.readOnly,
      obscureText: s.kind == FieldKind.password,
      maxLines: s.kind == FieldKind.multiline ? 4 : 1,
      maxLength: s.maxLength,
      keyboardType: s.kind == FieldKind.email
          ? TextInputType.emailAddress
          : s.kind == FieldKind.integer
              ? TextInputType.number
              : s.kind == FieldKind.decimal
                  ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                  : s.kind == FieldKind.multiline
                      ? TextInputType.multiline
                      : TextInputType.text,
      inputFormatters: [
        if (s.kind == FieldKind.integer) FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
        if (s.kind == FieldKind.decimal) FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
      ],
      style: ts(13, color: p.ink),
      decoration: widget.decoration.copyWith(counterText: ''),
      onChanged: (v) => widget.onChanged(numeric ? v : v),
    );
  }
}

class _DateControl extends StatelessWidget {
  const _DateControl({required this.value, required this.decoration, required this.onChanged, required this.readOnly});

  final String? value;
  final InputDecoration decoration;
  final ValueChanged<Object?> onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: readOnly
          ? null
          : () async {
              final now = DateTime.now();
              final initial = value == null ? now : DateTime.tryParse(value!) ?? now;
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 5),
              );
              if (picked != null) {
                // Date-only: yyyy-MM-dd, never a timestamp.
                onChanged('${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
              }
            },
      child: InputDecorator(
        decoration: decoration.copyWith(suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16)),
        child: Text(value ?? 'Pick a date', style: ts(13, color: value == null ? p.hint : p.ink)),
      ),
    );
  }
}

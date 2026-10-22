/// Describes one form field. Views declare specs; `FieldBuilder` turns them
/// into widgets and validators, so a view never builds a TextFormField itself.
enum FieldKind {
  text,
  email,
  password,
  multiline,
  integer,
  decimal,
  toggle,
  select,
  lookup,
  multiLookup,
  date,
}

class SelectOption {
  const SelectOption(this.value, this.label);

  final String value;
  final String label;
}

class FieldSpec {
  const FieldSpec({
    required this.name,
    required this.label,
    this.kind = FieldKind.text,
    this.required = false,
    this.maxLength,
    this.min,
    this.max,
    this.hint,
    this.help,
    this.options = const [],
    this.lookup,
    this.lookupParentField,
    this.readOnly = false,
  });

  final String name;
  final String label;
  final FieldKind kind;
  final bool required;
  final int? maxLength;
  final num? min;
  final num? max;
  final String? hint;
  final String? help;

  /// For [FieldKind.select].
  final List<SelectOption> options;

  /// For lookup kinds: the `/lookups/:name` to search.
  final String? lookup;

  /// For lookup kinds: another field whose value is sent as `parentId`.
  final String? lookupParentField;

  final bool readOnly;

  /// Validation derived from the spec. Returns an error message or null.
  String? validate(Object? raw) {
    final isEmpty = raw == null ||
        (raw is String && raw.trim().isEmpty) ||
        (raw is List && raw.isEmpty);
    if (required && isEmpty) return '$label is required.';
    if (isEmpty) return null;

    switch (kind) {
      case FieldKind.text:
      case FieldKind.multiline:
      case FieldKind.password:
        final s = raw as String;
        if (maxLength != null && s.length > maxLength!) return '$label must be at most $maxLength characters.';
        return null;
      case FieldKind.email:
        final s = (raw as String).trim();
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return 'Enter a valid email address.';
        if (maxLength != null && s.length > maxLength!) return '$label must be at most $maxLength characters.';
        return null;
      case FieldKind.integer:
        final n = int.tryParse(raw.toString().trim());
        if (n == null) return '$label must be a whole number.';
        if (min != null && n < min!) return '$label must be at least $min.';
        if (max != null && n > max!) return '$label must be at most $max.';
        return null;
      case FieldKind.decimal:
        final n = double.tryParse(raw.toString().trim());
        if (n == null) return '$label must be a number.';
        if (min != null && n < min!) return '$label must be at least $min.';
        if (max != null && n > max!) return '$label must be at most $max.';
        return null;
      default:
        return null;
    }
  }

  /// Converts the widget value to what the API expects.
  Object? toApi(Object? raw) {
    if (raw == null) return null;
    switch (kind) {
      case FieldKind.integer:
        final s = raw.toString().trim();
        return s.isEmpty ? null : int.tryParse(s);
      case FieldKind.decimal:
        final s = raw.toString().trim();
        return s.isEmpty ? null : double.tryParse(s);
      case FieldKind.text:
      case FieldKind.multiline:
      case FieldKind.email:
        final s = (raw as String).trim();
        return s.isEmpty ? null : s;
      default:
        return raw;
    }
  }
}

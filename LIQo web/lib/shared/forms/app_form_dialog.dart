import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';
import 'field_builder.dart';
import 'field_spec.dart';

/// A dialog built from a list of [FieldSpec]s.
///
/// `onSubmit` receives API-ready values. If it throws, the error text is shown
/// and the dialog stays open. Returns true when the submit succeeded.
Future<bool> showAppForm({
  required BuildContext context,
  required String title,
  required List<FieldSpec> fields,
  required Future<void> Function(Map<String, Object?> values) onSubmit,
  Map<String, Object?> initial = const {},
  String subtitle = '',
  String submitLabel = 'Save',
  String cancelLabel = 'Cancel',
  double maxWidth = 460,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: context.pal.scrim,
    barrierDismissible: false,
    builder: (ctx) {
      final p = ctx.pal;
      return Dialog(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: ts(21, w: FontWeight.w800, color: p.ink, height: 1.25)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(subtitle, style: ts(12, color: p.muted)),
                  ],
                  const SizedBox(height: 20),
                  AppFormBody(
                    fields: fields,
                    initial: initial,
                    onSubmit: onSubmit,
                    submitLabel: submitLabel,
                    cancelLabel: cancelLabel,
                    onCancel: () => Navigator.of(ctx).pop(false),
                    onDone: () => Navigator.of(ctx).pop(true),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  return ok == true;
}

/// The fields, the error line and the Cancel / Submit buttons of a form.
/// Used by [showAppForm] and inline inside detail panels.
class AppFormBody extends StatefulWidget {
  const AppFormBody({
    super.key,
    required this.fields,
    required this.onSubmit,
    required this.onCancel,
    required this.onDone,
    this.initial = const {},
    this.submitLabel = 'Save',
    this.cancelLabel = 'Cancel',
  });

  final List<FieldSpec> fields;
  final Map<String, Object?> initial;
  final Future<void> Function(Map<String, Object?> values) onSubmit;
  final VoidCallback onCancel;

  /// Called after [onSubmit] succeeded.
  final VoidCallback onDone;
  final String submitLabel;
  final String cancelLabel;

  @override
  State<AppFormBody> createState() => _AppFormBodyState();
}

class _AppFormBodyState extends State<AppFormBody> {
  late final Map<String, Object?> _values = {
    for (final f in widget.fields) f.name: widget.initial[f.name],
  };
  final Map<String, String?> _errors = {};
  bool _busy = false;
  String? _formError;

  Future<void> _submit() async {
    if (_busy) return;
    final errors = <String, String?>{};
    for (final f in widget.fields) {
      final e = f.validate(_values[f.name]);
      if (e != null) errors[f.name] = e;
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      final api = {for (final f in widget.fields) f.name: f.toApi(_values[f.name])};
      await widget.onSubmit(api);
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _formError = formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final f in widget.fields)
          FieldBuilder(
            spec: f,
            value: _values[f.name],
            values: _values,
            error: _errors[f.name],
            onChanged: (v) => setState(() {
              _values[f.name] = v;
              _errors.remove(f.name);
              // Clear dependent lookups when the parent changes.
              for (final other in widget.fields) {
                if (other.lookupParentField == f.name) _values[other.name] = null;
              }
            }),
          ),
        if (_formError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 16, color: p.warn),
                const SizedBox(width: 6),
                Expanded(child: Text(_formError!, style: ts(12, color: p.warn))),
              ],
            ),
          ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 9,
          runSpacing: 9,
          children: [
            AppButton(label: widget.cancelLabel, onPressed: _busy ? () {} : widget.onCancel),
            AppButton(
              label: _busy ? 'Saving…' : widget.submitLabel,
              primary: true,
              onPressed: _busy ? () {} : _submit,
            ),
          ],
        ),
      ],
    );
  }
}

/// Yes/no confirmation. Cancel is the default (Enter does nothing destructive).
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final p = ctx.pal;
      return AlertDialog(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title, style: ts(16, w: FontWeight.w800, color: p.ink)),
        content: Text(message, style: ts(13, color: p.muted)),
        actions: [
          AppButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop(false)),
          AppButton(label: confirmLabel, primary: true, onPressed: () => Navigator.of(ctx).pop(true)),
        ],
      );
    },
  );
  return ok == true;
}

/// Shows a value once (temporary passwords) with a copy button.
Future<void> showOneTimeSecret(
  BuildContext context, {
  required String title,
  required String message,
  required String secret,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final p = ctx.pal;
      return AlertDialog(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title, style: ts(16, w: FontWeight.w800, color: p.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: ts(13, color: p.muted)),
            const SizedBox(height: 14),
            OneTimeSecretBox(secret),
          ],
        ),
        actions: [AppButton(label: 'Done', primary: true, onPressed: () => Navigator.of(ctx).pop())],
      );
    },
  );
}

/// A secret shown once (a temporary password): the value, Copy, and the warning.
class OneTimeSecretBox extends StatelessWidget {
  const OneTimeSecretBox(this.secret, {super.key});

  final String secret;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: p.boxBg,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              SelectableText(secret, style: ts(16, w: FontWeight.w800, color: p.ink, ls: 1)),
              _CopyButton(secret),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text('This is shown only once. Share it with the person securely.', style: ts(11, color: p.warn)),
      ],
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton(this.text);

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: _copied ? 'Copied' : 'Copy',
      small: true,
      icon: _copied ? Icons.check : Icons.copy_outlined,
      onPressed: () async {
        await copyToClipboard(widget.text);
        if (mounted) setState(() => _copied = true);
      },
    );
  }
}

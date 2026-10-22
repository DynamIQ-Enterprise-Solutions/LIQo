import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'blueprint_panel.dart';
import 'maps_service.dart';
import 'pdf_document.dart';
import 'picture_convert.dart';

/// The steps of uploading a plan, shared by the Blueprint panel and the
/// "no map yet" screen (Round 17). PDF → the chosen page as PNG; TIFF, WebP,
/// BMP, GIF and HEIC → PNG in the browser; SVG, DXF and DWG go up as they are.
/// Errors are thrown for the caller to show; [onBusy] names the current step.
class PlanUpload {
  PlanUpload(this.context, this.ref, {required this.onBusy});

  final BuildContext context;
  final WidgetRef ref;
  final void Function(String? label) onBusy;

  /// Lets the person pick a file, converts it if needed and uploads it.
  /// Null when nothing was picked or a PDF page choice was cancelled.
  Future<BackdropInfo?> pickAndUpload(int branchId) async {
    final picked = await ref.read(planFilePickerProvider)();
    if (picked == null) return null;
    onBusy('Uploading…');
    try {
      var (bytes, name) = picked;
      final ext = extensionOf(name);
      final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
      if (ext == 'pdf') {
        final page = await _pdfPage(bytes);
        if (page == null) return null;
        bytes = page.$1;
        name = '$base (page ${page.$2}).png';
      } else if (convertedPictureTypes.contains(ext)) {
        onBusy('Converting picture…');
        bytes = await ref.read(pictureConverterProvider)(bytes, ext);
        name = '$base.png';
      } else if (drawingTypes.contains(ext)) {
        onBusy(ext == 'dwg' ? 'Converting drawing…' : 'Reading drawing…');
      }
      if (!drawingTypes.contains(ext)) onBusy('Uploading…');
      final info = await MapsService().uploadBackdrop(branchId, bytes, name);
      ref.invalidate(backdropsProvider(branchId));
      return info;
    } on UnsupportedError catch (e) {
      throw ShownError(e.message ?? 'This file can be opened only in the browser.');
    } finally {
      onBusy(null);
    }
  }

  /// A DXF or DWG that does not say its unit: asks for it. Returns the plan with
  /// its exact scale, the plan unchanged when no unit is needed, or null for "Later".
  Future<BackdropInfo?> resolveUnit(int branchId, BackdropInfo info) async {
    if (!info.needsUnit) return info;
    if (!context.mounted) return null;
    final unit = await showDialog<String>(context: context, builder: (_) => DrawingUnitPicker(fileName: info.originalName));
    if (unit == null) return null;
    final updated = await MapsService().setBackdropUnit(branchId, info.id, unit);
    ref.invalidate(backdropsProvider(branchId));
    return updated;
  }

  /// Opens a PDF, lets the person pick a page, and turns that page into a PNG.
  Future<(Uint8List, int)?> _pdfPage(Uint8List bytes) async {
    onBusy('Opening PDF…');
    final PdfDocument doc;
    try {
      doc = await ref.read(pdfOpenerProvider)(bytes);
    } on UnsupportedError {
      rethrow;
    } catch (_) {
      throw const ShownError('This PDF could not be opened. It may be damaged or password protected.');
    }
    try {
      if (doc.pageCount < 1) throw const ShownError('This PDF has no pages.');
      var page = 1;
      if (doc.pageCount > 1) {
        if (!context.mounted) return null;
        final chosen = await showDialog<int>(context: context, builder: (_) => PdfPagePicker(doc: doc));
        if (chosen == null) return null;
        page = chosen;
      }
      onBusy('Preparing page $page…');
      return (await doc.render(page, maxSide: pdfPageSide), page);
    } finally {
      doc.dispose();
    }
  }
}

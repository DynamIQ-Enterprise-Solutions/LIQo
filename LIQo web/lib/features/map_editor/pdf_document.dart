import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pdf_open.dart';

/// A PDF floor plan opened in the browser (Round 15: PDF plans are turned into
/// a picture page by page before upload; the server only takes PNG and JPG).
abstract class PdfDocument {
  int get pageCount;

  /// Page [page] (1-based) as a PNG whose long side is [maxSide] pixels.
  Future<Uint8List> render(int page, {required int maxSide});

  void dispose();
}

typedef PdfOpener = Future<PdfDocument> Function(Uint8List bytes);

/// How PDFs are opened. Tests replace it with a fake.
final pdfOpenerProvider = Provider<PdfOpener>((ref) => openPdfBytes);

/// Long side of the picture made from a PDF page: detailed enough for small
/// labels, small enough for the upload limits (10 000 px, 50 megapixels).
const pdfPageSide = 5000;

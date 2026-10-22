import 'dart:typed_data';

import 'pdf_document.dart';

/// PDFs are opened only in the browser (pdf.js); elsewhere this is unavailable.
Future<PdfDocument> openPdfBytes(Uint8List bytes) async => throw UnsupportedError('PDF plans can be opened only in the browser.');

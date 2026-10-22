import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'pdf_document.dart';

// pdf.js 5.7.284, bundled in web/pdfjs (no outside script is loaded). Only the
// few calls used here are typed.

extension type _PdfJs._(JSObject _) implements JSObject {
  @JS('GlobalWorkerOptions')
  external _WorkerOptions get workerOptions;
  external _LoadingTask getDocument(JSObject params);
}

extension type _WorkerOptions._(JSObject _) implements JSObject {
  external set workerSrc(String v);
}

extension type _LoadingTask._(JSObject _) implements JSObject {
  external JSPromise<_PdfDoc> get promise;
}

extension type _PdfDoc._(JSObject _) implements JSObject {
  external int get numPages;
  external JSPromise<_PdfPage> getPage(int n);
  external JSPromise<JSAny?> destroy();
}

extension type _PdfPage._(JSObject _) implements JSObject {
  external _Viewport getViewport(JSObject params);
  external _RenderTask render(JSObject params);
  external void cleanup();
}

extension type _Viewport._(JSObject _) implements JSObject {
  external double get width;
  external double get height;
}

extension type _RenderTask._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> get promise;
}

@JS('Object')
extension type _Obj._(JSObject _) implements JSObject {
  external _Obj();
}

extension on JSObject {
  external void operator []=(String key, JSAny? value);
}

_PdfJs? _lib;

/// The bundled pdf.js, loaded on first use, with paths from the page's base URL
/// (route paths like /mall-admin/map-editor must not change where it is found).
Future<_PdfJs> _pdfjs() async {
  final cached = _lib;
  if (cached != null) return cached;
  final base = Uri.parse(web.document.baseURI).resolve('pdfjs/');
  final lib = await importModule(base.resolve('pdf.min.js').toString().toJS).toDart as _PdfJs;
  lib.workerOptions.workerSrc = base.resolve('pdf.worker.min.js').toString();
  return _lib = lib;
}

class _BrowserPdf implements PdfDocument {
  _BrowserPdf(this._doc);

  final _PdfDoc _doc;

  @override
  int get pageCount => _doc.numPages;

  @override
  Future<Uint8List> render(int page, {required int maxSide}) async {
    final p = await _doc.getPage(page).toDart;
    try {
      final one = p.getViewport(_Obj()..['scale'] = 1.toJS);
      final scale = maxSide / (one.width > one.height ? one.width : one.height);
      final vp = p.getViewport(_Obj()..['scale'] = scale.toJS);
      final canvas = web.HTMLCanvasElement()
        ..width = vp.width.floor()
        ..height = vp.height.floor();
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      // Paper white under the drawing: many CAD exports have no background.
      ctx.fillStyle = 'white'.toJS;
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      await p.render(_Obj()
            ..['canvas'] = canvas
            ..['canvasContext'] = ctx
            ..['viewport'] = vp)
          .promise
          .toDart;
      final done = Completer<web.Blob?>();
      canvas.toBlob(((web.Blob? b) => done.complete(b)).toJS, 'image/png');
      final blob = await done.future;
      if (blob == null) throw StateError('The page could not be turned into a picture.');
      final buf = await blob.arrayBuffer().toDart;
      return buf.toDart.asUint8List();
    } finally {
      p.cleanup();
    }
  }

  @override
  void dispose() {
    _doc.destroy();
  }
}

Future<PdfDocument> openPdfBytes(Uint8List bytes) async {
  final lib = await _pdfjs();
  final base = Uri.parse(web.document.baseURI).resolve('pdfjs/');
  final params = _Obj()
    ..['data'] = bytes.toJS
    ..['cMapUrl'] = base.resolve('cmaps/').toString().toJS
    ..['cMapPacked'] = true.toJS
    ..['standardFontDataUrl'] = base.resolve('standard_fonts/').toString().toJS
    ..['wasmUrl'] = base.resolve('wasm/').toString().toJS
    ..['isEvalSupported'] = false.toJS;
  final doc = await lib.getDocument(params).promise.toDart;
  return _BrowserPdf(doc);
}

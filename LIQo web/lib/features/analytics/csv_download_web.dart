import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Hands a text file to the browser as a download.
void downloadText(String filename, String text, {String mime = 'text/csv;charset=utf-8'}) {
  final blob = web.Blob(<JSAny>[text.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}

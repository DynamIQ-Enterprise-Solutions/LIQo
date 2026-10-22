import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

// Our own helper in web/plan_convert/convert.js (Round 16). It loads the bundled
// decoders (UTIF.js, libheif-js) on first use; nothing comes from outside.

extension type _Converter._(JSObject _) implements JSObject {
  external JSPromise<JSUint8Array> toPng(JSUint8Array bytes, String ext);
}

_Converter? _module;

Future<Uint8List> convertPictureToPng(Uint8List bytes, String ext) async {
  final module = _module ??= await importModule(Uri.parse(web.document.baseURI).resolve('plan_convert/convert.js').toString().toJS).toDart as _Converter;
  try {
    final out = await module.toPng(bytes.toJS, ext).toDart;
    return out.toDart;
  } catch (e) {
    throw StateError('This .$ext picture could not be read. Save it as PNG or JPG and upload that.');
  }
}

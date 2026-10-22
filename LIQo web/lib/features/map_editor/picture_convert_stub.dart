import 'dart:typed_data';

/// Pictures are converted only in the browser; elsewhere this is unavailable.
Future<Uint8List> convertPictureToPng(Uint8List bytes, String ext) async => throw UnsupportedError('This picture type can be converted only in the browser.');

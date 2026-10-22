import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'picture_convert_open.dart';

/// Picture types the server does not take, turned into PNG in the browser
/// first (Round 16). PNG and JPG go up as they are; PDF has its own page picker.
const convertedPictureTypes = {'tif', 'tiff', 'webp', 'bmp', 'gif', 'heic', 'heif'};

/// Drawings the server reads itself (lines kept for exact walls).
const drawingTypes = {'svg', 'dxf', 'dwg'};

/// Every extension the plan picker offers.
const planFileTypes = ['png', 'jpg', 'jpeg', 'pdf', ...convertedPictureTypes, ...drawingTypes];

/// Picture bytes of a type in [convertedPictureTypes] → PNG bytes.
typedef PictureConverter = Future<Uint8List> Function(Uint8List bytes, String ext);

/// How pictures are converted. Tests replace it with a fake.
final pictureConverterProvider = Provider<PictureConverter>((ref) => convertPictureToPng);

/// A chosen plan file: its bytes and name, or null when nothing was picked.
typedef PlanFilePicker = Future<(Uint8List, String)?> Function();

/// How the plan file is chosen. Tests replace it with a fake.
final planFilePickerProvider = Provider<PlanFilePicker>((ref) => () async {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: planFileTypes);
      final file = picked.firstOrNull;
      if (file == null) return null;
      return (await file.readAsBytes(), file.name);
    });

/// The lowercase extension of a file name ('' when there is none).
String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

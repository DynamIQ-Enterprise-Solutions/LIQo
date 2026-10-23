// Where downloaded packages and the directory are kept on the phone. A write
// goes to a temporary file first and is then renamed into place, so a crash or
// a full disk mid-write never leaves a half-written package behind: the old
// copy stays until the new one is complete.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// The phone ran out of space (or could not write) while saving.
class StorageException implements Exception {
  const StorageException(this.cause);
  final Object cause;
  @override
  String toString() => 'StorageException($cause)';
}

abstract class BlobStore {
  Future<Uint8List?> read(String key);

  /// Saves [bytes] under [key], replacing what was there only once the new copy is complete.
  Future<void> write(String key, Uint8List bytes);
  Future<void> delete(String key);

  /// Bytes kept under keys starting with [prefix].
  Future<int> sizeOf(String prefix);
}

/// In memory: tests, and a fallback when the phone's storage can't be opened.
class MemoryBlobStore implements BlobStore {
  MemoryBlobStore([Map<String, Uint8List>? initial]) : _m = {...?initial};
  final Map<String, Uint8List> _m;
  @override
  Future<Uint8List?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, Uint8List bytes) async => _m[key] = bytes;
  @override
  Future<void> delete(String key) async => _m.remove(key);
  @override
  Future<int> sizeOf(String prefix) async => _m.entries.where((e) => e.key.startsWith(prefix)).fold<int>(0, (n, e) => n + e.value.length);
}

/// Files in the app's own support folder (not visible to the user, kept until uninstall).
class FileBlobStore implements BlobStore {
  FileBlobStore(this.root);
  final Directory root;

  static Future<FileBlobStore> open() async => FileBlobStore(Directory('${(await getApplicationSupportDirectory()).path}/liqo'));

  File _file(String key) => File('${root.path}/$key');

  @override
  Future<Uint8List?> read(String key) async {
    final f = _file(key);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final f = _file(key), tmp = File('${f.path}.part');
    try {
      await tmp.parent.create(recursive: true);
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      throw StorageException(e);
    }
  }

  @override
  Future<void> delete(String key) async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<int> sizeOf(String prefix) async {
    final dir = _file(prefix);
    if (await dir.exists() && (await dir.stat()).type == FileSystemEntityType.directory) {
      var n = 0;
      await for (final e in Directory(dir.path).list(recursive: true)) {
        if (e is File) n += await e.length();
      }
      return n;
    }
    return await dir.exists() ? dir.length() : 0;
  }
}

/// The store; main() opens the phone's folder, tests use [MemoryBlobStore].
final blobStoreProvider = Provider<BlobStore>((ref) => MemoryBlobStore());

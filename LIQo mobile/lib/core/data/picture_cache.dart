// Post pictures and store logos kept on the phone (owner decision 2026-10-23):
// up to 50 MB, the least recently shown dropped first. Offline, a picture that
// isn't kept shows the drawn placeholder instead (the caller's fallback).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../storage/store.dart';
import 'blob_store.dart';
import 'shopper_api.dart' show sha256Hex;

typedef PictureFetch = Future<Uint8List> Function(String url);

Future<Uint8List> httpFetch(String url) async {
  final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) throw Exception('picture ${r.statusCode}');
  return r.bodyBytes;
}

class PictureCache {
  PictureCache(this._blobs, this._store, this._fetch, {this.limit = 50 * 1024 * 1024});
  final BlobStore _blobs;
  final Store _store;
  final PictureFetch _fetch;

  /// The most bytes kept.
  final int limit;

  static const indexKey = 'pictureIndex';
  final _mem = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List?>>{};

  static String keyOf(String url) => 'pictures/${sha256Hex(utf8.encode(url))}';

  /// key -> (bytes, last shown in ms)
  Map<String, (int, int)> _index() {
    final j = _store.json(indexKey);
    if (j is! Map) return {};
    return {
      for (final e in j.entries)
        if (e.value is List && (e.value as List).length == 2) e.key.toString(): ((e.value as List)[0] as int, (e.value as List)[1] as int),
    };
  }

  void _save(Map<String, (int, int)> ix) => _store.setJson(indexKey, {for (final e in ix.entries) e.key: [e.value.$1, e.value.$2]});

  /// Bytes kept now.
  int get size => _index().values.fold(0, (n, v) => n + v.$1);

  /// The picture at [url]: from memory, the phone, or the network (then kept). Null when it can't be had.
  Future<Uint8List?> get(String url) => _pending[url] ??= _get(url).whenComplete(() {
        _pending.remove(url); // a block, not an arrow: returning the future itself would wait on itself
      });

  Future<Uint8List?> _get(String url) async {
    final key = keyOf(url), now = DateTime.now().millisecondsSinceEpoch;
    final hit = _mem[key] ?? await _blobs.read(key);
    if (hit != null) {
      _mem[key] = hit;
      final ix = _index();
      ix[key] = (hit.length, now);
      _save(ix);
      return hit;
    }
    final Uint8List bytes;
    try {
      bytes = await _fetch(url);
    } catch (e) {
      debugPrint('LIQo: picture not loaded ($e)');
      return null;
    }
    if (bytes.length > limit) return bytes; // too big to keep: shown once
    try {
      await _blobs.write(key, bytes);
    } catch (_) {
      return bytes; // shown, not kept
    }
    _mem[key] = bytes;
    final ix = _index()..[key] = (bytes.length, now);
    // the least recently shown go first, until it fits
    final order = ix.entries.toList()..sort((a, b) => a.value.$2.compareTo(b.value.$2));
    var total = ix.values.fold(0, (n, v) => n + v.$1);
    for (final e in order) {
      if (total <= limit) break;
      if (e.key == key) continue;
      total -= e.value.$1;
      ix.remove(e.key);
      _mem.remove(e.key);
      await _blobs.delete(e.key);
    }
    _save(ix);
    return bytes;
  }
}

/// The pictures; tests replace the fetch.
final pictureFetchProvider = Provider<PictureFetch>((ref) => httpFetch);
final pictureCacheProvider = Provider<PictureCache>((ref) => PictureCache(ref.read(blobStoreProvider), ref.read(storeProvider), ref.read(pictureFetchProvider)));

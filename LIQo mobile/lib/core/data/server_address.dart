// Where the shopper server is (docs/shopper-package-format.md §12). Until a
// domain gives it a fixed address, the server's address changes at every
// restart, so the app reads it from a small file on the web app's fixed address
// (owner decision 2026-10-23): when the app opens, and again whenever the
// server can't be reached. The last good address is remembered for when the
// file can't be read. A build may instead name the address itself (SHOPPER_API).
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/store.dart';
import 'shopper_api.dart' show OfflineException;

/// Reads the address file's body (tests replace it).
typedef ConfigFetch = Future<String> Function(Uri url);

Future<String> httpConfigFetch(Uri url) async {
  final r = await http.get(url, headers: {'Cache-Control': 'no-cache'}).timeout(const Duration(seconds: 15));
  if (r.statusCode != 200) throw Exception('address file ${r.statusCode}');
  return utf8.decode(r.bodyBytes);
}

/// [s] if it is a plain https://host (no path, query, port or trailing slash), else null.
String? plainApiBase(Object? s) {
  if (s is! String) return null;
  final u = Uri.tryParse(s);
  if (u == null || u.scheme != 'https' || u.host.isEmpty || u.hasPort || u.userInfo.isNotEmpty) return null;
  if (u.path.isNotEmpty || u.hasQuery || u.hasFragment) return null;
  return s == 'https://${u.host}' ? s : null;
}

class ServerAddress {
  /// An address read from the file at [configUrl], remembered in [store].
  ServerAddress.fromFile(String configUrl, Store this._store, [this._fetch = httpConfigFetch]) : _config = Uri.parse(configUrl), _fixed = null;

  /// An address set at build time ('' when the build has none: every call is offline).
  ServerAddress.fixed(String base) : _fixed = base, _config = null, _store = null, _fetch = httpConfigFetch;

  final String? _fixed;
  final Uri? _config;
  final Store? _store;
  final ConfigFetch _fetch;

  static const rememberedKey = 'shopperApiBase';

  String? _current;
  Future<String?>? _reading;

  /// The address can change (it comes from the file).
  bool get changes => _config != null;

  /// The address to use: read from the file the first time, then kept for this session.
  Future<String> get() async {
    if (_fixed != null) {
      if (_fixed.isEmpty) throw const OfflineException('no server address');
      return _fixed;
    }
    final a = _current ?? await reread() ?? _store!.get(rememberedKey);
    if (a == null) throw const OfflineException('the server address could not be read');
    return _current = a;
  }

  /// Reads the file again (the server couldn't be reached at the address in use). Returns the
  /// address it holds, or null when it can't be read; calls at the same time share one read.
  Future<String?> reread() => _reading ??= _read().whenComplete(() {
        _reading = null; // a block, not an arrow: returning the future itself would wait on itself
      });

  Future<String?> _read() async {
    if (_config == null) return null;
    try {
      final j = jsonDecode(await _fetch(_config));
      final a = plainApiBase(j is Map ? j['apiBase'] : null);
      if (a == null) return null;
      _current = a;
      _store!.set(rememberedKey, a);
      return a;
    } catch (_) {
      return null; // offline, or the file is unreadable: the address in use (or remembered) stays
    }
  }
}

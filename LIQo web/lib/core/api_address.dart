import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'config.dart';

/// The server's address read at run time (owner decision 2026-10-23: until a
/// domain gives the server a fixed address, each server start publishes it in
/// a small file on the web app's own fixed address, `/config/api.json`:
/// `{"apiBase": "https://….trycloudflare.com", "updatedAt": "…"}`).
/// The last address read is remembered, for when the file cannot be read.

const _prefsKey = 'api.base';

/// The address in a config file's JSON, or null when it is missing or not a plain https (or local http) address.
String? apiBaseFromConfig(Object? json) {
  if (json is! Map) return null;
  final raw = json['apiBase'];
  if (raw is! String) return null;
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasAuthority || uri.hasQuery || uri.hasFragment) return null;
  final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
  if (uri.scheme != 'https' && !(local && uri.scheme == 'http')) return null;
  final path = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
  return '${uri.scheme}://${uri.authority}$path';
}

class ApiAddress {
  ApiAddress._();

  static SharedPreferences? _prefs;

  /// Reads the address file (when this build uses one) and points the API client at it.
  static Future<void> resolve(SharedPreferences prefs) async {
    if (AppConfig.apiConfigUrl.isEmpty) return;
    _prefs = prefs;
    ApiClient.instance.onUnreachable = refresh;
    final remembered = prefs.getString(_prefsKey);
    if (remembered != null) ApiClient.instance.setBase(remembered);
    await refresh();
  }

  /// Reads the file again. Returns true when the address changed.
  static Future<bool> refresh() async {
    if (AppConfig.apiConfigUrl.isEmpty) return false;
    try {
      final r = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)))
          .get<Object?>(AppConfig.apiConfigUrl, queryParameters: {'t': DateTime.now().millisecondsSinceEpoch});
      final base = apiBaseFromConfig(r.data);
      if (base == null || base == ApiClient.instance.base) return false;
      ApiClient.instance.setBase(base);
      await _prefs?.setString(_prefsKey, base);
      return true;
    } catch (_) {
      return false;
    }
  }
}

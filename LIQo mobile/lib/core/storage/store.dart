// Where settings, favourites, saved routes, history and recent places are kept
// between app launches (from the demo's state/store.dart). Trips in progress,
// positions and reported problems are never saved.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class Store {
  String? get(String key);
  void set(String key, String value);
  void remove(String key);

  /// A saved JSON value, or null when missing or unreadable.
  Object? json(String key) {
    final s = get(key);
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  void setJson(String key, Object? value) => set(key, jsonEncode(value));
}

/// In memory only: tests, and a fallback while the phone's storage is unavailable.
class MemoryStore extends Store {
  MemoryStore([Map<String, String>? initial]) : _m = {...?initial};
  final Map<String, String> _m;
  @override
  String? get(String key) => _m[key];
  @override
  void set(String key, String value) => _m[key] = value;
  @override
  void remove(String key) => _m.remove(key);
}

/// The phone's shared preferences, loaded once at start.
class PrefsStore extends Store {
  final SharedPreferences _p;
  PrefsStore._(this._p);
  static Future<PrefsStore> open() async => PrefsStore._(await SharedPreferences.getInstance());
  @override
  String? get(String key) => _p.getString(key);
  @override
  void set(String key, String value) => _p.setString(key, value);
  @override
  void remove(String key) => _p.remove(key);
}

/// The store; main() overrides it with the phone's preferences, tests with a [MemoryStore].
final storeProvider = Provider<Store>((ref) => MemoryStore());

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Provided from main() so the session can be restored before the first frame.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden in main()');
});

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.mustChangePassword,
  });

  final int id;
  final String email;
  final String fullName;
  final String role;
  final bool isActive;
  final bool mustChangePassword;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as int,
        email: j['email'] as String,
        fullName: j['fullName'] as String,
        role: j['role'] as String,
        isActive: j['isActive'] as bool? ?? true,
        mustChangePassword: j['mustChangePassword'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'fullName': fullName,
        'role': role,
        'isActive': isActive,
        'mustChangePassword': mustChangePassword,
      };

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return email.substring(0, 1).toUpperCase();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class SessionState {
  const SessionState({this.user, this.token, this.expiredNotice = false});

  final AuthUser? user;
  final String? token;

  /// True right after an automatic logout, so the login page can explain why.
  final bool expiredNotice;

  bool get isSignedIn => user != null && token != null;

  SessionState copyWith({AuthUser? user, String? token, bool? expiredNotice}) => SessionState(
        user: user ?? this.user,
        token: token ?? this.token,
        expiredNotice: expiredNotice ?? this.expiredNotice,
      );
}

const _kToken = 'session.token';
const _kUser = 'session.user';

class SessionNotifier extends Notifier<SessionState> {
  Timer? _expiryTimer;

  @override
  SessionState build() {
    final prefs = ref.watch(sharedPrefsProvider);
    final client = ApiClient.instance;
    client.tokenProvider = () => state.token;
    client.onUnauthenticated = () => signOut(expired: true);

    ref.onDispose(() => _expiryTimer?.cancel());

    final token = prefs.getString(_kToken);
    final userJson = prefs.getString(_kUser);
    if (token != null && userJson != null && !_isExpired(token)) {
      _scheduleExpiry(token);
      return SessionState(
        token: token,
        user: AuthUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>),
      );
    }
    return const SessionState();
  }

  Future<void> signIn({required String token, required AuthUser user}) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString(_kToken, token);
    await prefs.setString(_kUser, jsonEncode(user.toJson()));
    _scheduleExpiry(token);
    state = SessionState(token: token, user: user);
  }

  Future<void> updateUser(AuthUser user) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString(_kUser, jsonEncode(user.toJson()));
    state = state.copyWith(user: user);
  }

  Future<void> signOut({bool expired = false}) async {
    _expiryTimer?.cancel();
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
    state = SessionState(expiredNotice: expired);
  }

  void _scheduleExpiry(String token) {
    _expiryTimer?.cancel();
    final exp = _expiryOf(token);
    if (exp == null) return;
    // Fire a little early so the logout request still carries a valid token.
    final delay = exp.difference(DateTime.now()) - const Duration(seconds: 2);
    if (delay.isNegative) {
      signOut(expired: true);
      return;
    }
    _expiryTimer = Timer(delay, () => signOut(expired: true));
  }

  static bool _isExpired(String token) {
    final exp = _expiryOf(token);
    return exp == null || exp.isBefore(DateTime.now());
  }

  static DateTime? _expiryOf(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload['exp'];
      if (exp is! int) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (e) {
      debugPrint('token parse failed: $e');
      return null;
    }
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

/// Convenience: the signed-in user or null.
final currentUserProvider = Provider<AuthUser?>((ref) => ref.watch(sessionProvider).user);

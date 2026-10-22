import '../../core/api_client.dart';
import '../../core/session.dart';

class LoginResult {
  const LoginResult({required this.token, required this.user});

  final String token;
  final AuthUser user;
}

/// Thin, stateless calls to /api/auth. Errors are thrown as-is; the caller
/// turns them into text with formatApiError().
class AuthService {
  AuthService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<LoginResult> login(String email, String password) async {
    final r = await _client.dio.post('/auth/login', data: {'email': email, 'password': password});
    final data = r.data as Map<String, dynamic>;
    return LoginResult(
      token: data['token'] as String,
      user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
    );
  }

  Future<AuthUser> me() async {
    final r = await _client.dio.get('/auth/me');
    return AuthUser.fromJson((r.data as Map<String, dynamic>)['user'] as Map<String, dynamic>);
  }

  Future<AuthUser> changePassword(String currentPassword, String newPassword) async {
    final r = await _client.dio.post(
      '/auth/change-password',
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    return AuthUser.fromJson((r.data as Map<String, dynamic>)['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      await _client.dio.post('/auth/logout');
    } catch (_) {
      // Best effort: the local session is cleared regardless.
    }
  }
}

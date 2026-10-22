import 'package:dio/dio.dart';

import 'config.dart';

/// The one HTTP client for the app.
///
/// The token and the "session expired" handler are injected as callbacks, so
/// this file never imports state management or auth code.
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  String? Function() tokenProvider = () => null;
  void Function()? onUnauthenticated;

  late final Dio dio = Dio(
    BaseOptions(
      baseUrl: '${AppConfig.apiBase}/api',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = tokenProvider();
          if (token != null && !options.headers.containsKey('Authorization')) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (err, handler) {
          final path = err.requestOptions.path;
          final isLogin = path.endsWith('/auth/login');
          if (err.response?.statusCode == 401 && !isLogin) {
            onUnauthenticated?.call();
          }
          handler.next(err);
        },
      ),
    );
}

/// Turns any error into a short message a person can read.
/// Backend `{error}` text wins; then a friendly line per status; never raw
/// exception text.
/// A message already written for people (for example one a service returned);
/// [formatApiError] shows it as it is.
class ShownError implements Exception {
  const ShownError(this.message);

  final String message;

  @override
  String toString() => message;
}

String formatApiError(Object error) {
  if (error is ShownError) return error.message;
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String && (data['error'] as String).isNotEmpty) {
      return data['error'] as String;
    }
    switch (error.response?.statusCode) {
      case 400:
        return 'Some of the information is not valid.';
      case 401:
        return 'Please sign in again.';
      case 403:
        return 'You do not have access to this.';
      case 404:
        return 'That item could not be found.';
      case 409:
        return 'This conflicts with an existing record.';
      case 429:
        return 'Too many requests. Please wait a moment.';
      case 500:
        return 'The server ran into a problem. Please try again.';
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The server took too long to respond.';
      case DioExceptionType.connectionError:
        return 'Cannot reach the server. Is the backend running?';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}

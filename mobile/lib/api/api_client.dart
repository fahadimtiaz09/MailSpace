// api_client.dart — the ONLY place in the app that talks to the MailSpace server.
//
// Screens never use Dio directly. They call functions here, for example:
//   final user = await ApiClient.instance.login('nimra', 'password123');
//
// How login works with our Flask backend:
//   1. The server keeps the login in a cookie called "session".
//   2. For every POST / PATCH / DELETE the server also wants the header
//      "X-CSRFToken", whose value is in a cookie called "csrf_token".
//   3. A browser does this by itself. In the app we save cookies on the phone
//      (PersistCookieJar) and add the header ourselves (the interceptor below).

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../models/user.dart';

/// Thrown when the server says no (wrong password, username taken, ...).
/// [message] is the server's own text, ready to show on screen.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  /// 401 = not logged in (or a temporary account that has expired).
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();

  /// Use this everywhere: ApiClient.instance.login(...)
  static final ApiClient instance = ApiClient._();

  static const String baseUrl = 'https://mail.fahadimtiaz.site/api';

  late final Dio _dio;
  CookieJar? _cookieJar;
  bool _ready = false;

  /// Call once in main() before runApp().
  Future<void> init() async {
    if (_ready) return;

    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      // Render's free server "sleeps" and can take ~50 seconds to wake up.
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json'},
    ));

    // Cookies are saved in a file on the phone, so the user stays logged in
    // after closing the app. (Chrome / web cannot do this; there we skip it.
    // On web, use fake data until the app runs on a phone or emulator.)
    if (!kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      _cookieJar = PersistCookieJar(storage: FileStorage('${dir.path}/.cookies/'));
      _dio.interceptors.add(CookieManager(_cookieJar!));
    }

    // Adds X-CSRFToken to every request that changes data.
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (options.method != 'GET' && _cookieJar != null) {
          final cookies = await _cookieJar!.loadForRequest(Uri.parse(baseUrl));
          for (final c in cookies) {
            if (c.name == 'csrf_token') {
              options.headers['X-CSRFToken'] = c.value;
            }
          }
        }
        handler.next(options);
      },
    ));

    _ready = true;
  }

  // ---------------------------------------------------------------------------
  // Small helpers. Every request goes through _send, which turns server errors
  // into ApiException with the server's message.
  // ---------------------------------------------------------------------------

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return response.data;
    } on DioException catch (e) {
      final data = e.response?.data;
      String message;
      if (data is Map && data['error'] is String) {
        message = data['error'] as String;
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        message = 'The server is taking too long. Please try again.';
      } else if (e.type == DioExceptionType.connectionError) {
        message = 'No internet connection.';
      } else {
        message = 'Something went wrong. Please try again.';
      }
      throw ApiException(message, statusCode: e.response?.statusCode);
    }
  }

  Future<dynamic> _get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<dynamic> _post(String path, [Object? body]) =>
      _send(() => _dio.post(path, data: body ?? {}));

  /// Makes sure we have a csrf_token cookie before the first POST.
  /// Any GET gives us one; /auth/me is cheap.
  Future<void> _ensureCsrf() async {
    if (_cookieJar == null) return;
    final cookies = await _cookieJar!.loadForRequest(Uri.parse(baseUrl));
    if (cookies.any((c) => c.name == 'csrf_token')) return;
    try {
      await _get('/auth/me');
    } on ApiException {
      // 401 is expected when logged out — the cookie is set anyway.
    }
  }

  // ---------------------------------------------------------------------------
  // Auth  (backend/routes/auth.py)
  // ---------------------------------------------------------------------------

  /// Who is logged in? Returns null if nobody (or the session expired).
  /// Call this when the app starts to decide: Welcome screen or Inbox.
  Future<User?> me() async {
    try {
      final data = await _get('/auth/me');
      return User.fromJson(data['user'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.isUnauthorized) return null;
      rethrow;
    }
  }

  /// [login] can be the username ("nimra") or the full address
  /// ("nimra@fahadimtiaz.site"). The backend field is called "login".
  Future<User> login(String login, String password) async {
    await _ensureCsrf();
    final data = await _post('/auth/login', {
      'login': login.trim(),
      'password': password,
    });
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// [accountType] must be 'regular', 'temp15' or 'temp30'.
  /// Recovery email and security question are optional.
  Future<User> signup({
    required String username,
    required String password,
    String accountType = 'regular',
    String? recoveryEmail,
    String? securityQuestion,
    String? securityAnswer,
  }) async {
    await _ensureCsrf();
    final data = await _post('/auth/signup', {
      'username': username.trim().toLowerCase(),
      'password': password,
      'account_type': accountType,
      if (recoveryEmail != null && recoveryEmail.isNotEmpty) 'recovery_email': recoveryEmail,
      if (securityQuestion != null && securityQuestion.isNotEmpty) 'security_question': securityQuestion,
      if (securityAnswer != null && securityAnswer.isNotEmpty) 'security_answer': securityAnswer,
    });
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      await _post('/auth/logout');
    } finally {
      // Forget the cookies on the phone even if the server didn't answer.
      await _cookieJar?.deleteAll();
    }
  }
}

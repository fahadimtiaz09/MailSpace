// api_client.dart — the ONLY place in the app that talks to the MailSpace server.
//
// Screens never use Dio directly. They call functions here, for example:
//   final user = await ApiClient.instance.login('username', 'password');
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

import '../models/domain.dart';
import '../models/message.dart';
import '../models/user.dart';

/// Step 1 of "Forgot password": which recovery methods the account has.
class ForgotInfo {
  final String login;             // the username
  final String? recoveryEmail;    // masked, e.g. n•••@gmail.com (null = none)
  final String? securityQuestion; // null = none

  ForgotInfo({required this.login, this.recoveryEmail, this.securityQuestion});
}

/// A file chosen in Compose, ready to upload.
class UploadFile {
  final String path;
  final String name;
  final int size;
  UploadFile({required this.path, required this.name, required this.size});
}

/// One page of a folder: the messages plus page numbers (20 per page).
class MessagePage {
  final List<Message> messages;
  final int page;
  final int totalPages;
  final int total;

  MessagePage({required this.messages, required this.page, required this.totalPages, required this.total});

  bool get hasMore => page < totalPages;
}

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

  Future<dynamic> _patch(String path, [Object? body]) =>
      _send(() => _dio.patch(path, data: body ?? {}));

  Future<dynamic> _delete(String path) => _send(() => _dio.delete(path));

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

  /// [login] can be the username ("username") or the full address
  /// ("username@fahadimtiaz.site"). The backend field is called "login".
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

  // ---------------------------------------------------------------------------
  // Messages  (backend/routes/messages.py)
  // ---------------------------------------------------------------------------

  /// One page (20 messages) of a folder, newest first.
  /// [folder]: inbox, sent, drafts, starred, spam, trash.  [q]: search text.
  Future<MessagePage> getMessages({String folder = 'inbox', int page = 1, String? q}) async {
    final data = await _get('/messages', query: {
      'folder': folder,
      'page': page,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    });
    return MessagePage(
      messages: (data['messages'] as List)
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList(),
      page: (data['page'] as num).toInt(),
      totalPages: (data['total_pages'] as num).toInt(),
      total: (data['total'] as num).toInt(),
    );
  }

  /// Numbers for the folder list: {'inbox': 3, 'drafts': 1, 'spam': 0}
  /// (inbox and spam = unread only).
  Future<Map<String, int>> getCounts() async {
    final data = await _get('/messages/counts') as Map;
    return data.map((key, value) => MapEntry(key.toString(), (value as num).toInt()));
  }

  /// Opens one message (with body and attachments). Also marks it read.
  Future<Message> getMessage(String id) async {
    final data = await _get('/messages/$id');
    return Message.fromJson(data['message'] as Map<String, dynamic>);
  }

  /// [action]: star, unstar, read, unread, trash, restore, spam, not_spam, delete_forever
  Future<void> updateMessage(String id, String action) async {
    await _patch('/messages/$id', {'action': action});
  }

  /// Downloads an attachment into the phone's temporary folder and returns
  /// the file path (then the screen opens it with the phone's own viewer).
  /// The login cookie goes with the request, so only people in the
  /// conversation can download it.
  Future<String> downloadAttachment(Attachment a) async {
    final dir = await getTemporaryDirectory();
    final safeName = a.filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = '${dir.path}/${a.id}_$safeName';
    await _send(() => _dio.download('/attachments/${a.id}', path));
    return path;
  }

  /// Sends an email. [to] is one or more addresses separated by commas.
  /// Files go as multipart form data (like a website form with files).
  /// Returns the server's message, e.g. "Message sent".
  Future<String> sendMessage({
    required String from,
    required String to,
    required String subject,
    required String body,
    List<UploadFile> files = const [],
    String? draftId,
  }) async {
    final form = FormData.fromMap({
      'from': from,
      'to': to,
      'subject': subject,
      'body': body,
      if (draftId != null) 'draft_id': draftId,
    });
    for (final f in files) {
      form.files.add(MapEntry('attachments', await MultipartFile.fromFile(f.path, filename: f.name)));
    }
    final data = await _post('/messages/send', form);
    return (data is Map && data['message'] is String) ? data['message'] as String : 'Message sent';
  }

  /// Saves (or updates) a draft. Attachments are not saved in drafts.
  /// Returns the draft id — pass it back next time to update the same draft.
  Future<String> saveDraft({
    required String to,
    required String subject,
    required String body,
    String? draftId,
  }) async {
    final data = await _post('/drafts', {
      'to': to,
      'subject': subject,
      'body': body,
      if (draftId != null) 'draft_id': draftId,
    });
    return data['draft_id'] as String;
  }

  // ---------------------------------------------------------------------------
  // Domains  (backend/routes/domains.py)
  // ---------------------------------------------------------------------------

  /// Addresses for the From box: main address + custom-domain addresses.
  Future<List<String>> getFromAddresses() async {
    final data = await _get('/domains/from-addresses');
    return (data['addresses'] as List).map((e) => e.toString()).toList();
  }

  Future<List<Domain>> getDomains() async {
    final data = await _get('/domains');
    return (data['domains'] as List).map((d) => Domain.fromJson(d as Map<String, dynamic>)).toList();
  }

  Future<Domain> addDomain(String name) async {
    final data = await _post('/domains', {'name': name.trim()});
    return Domain.fromJson(data['domain'] as Map<String, dynamic>);
  }

  /// Asks the server to look up the TXT record. If it isn't there yet,
  /// this throws ApiException with the server's explanation.
  Future<Domain> verifyDomain(String domainId) async {
    final data = await _post('/domains/$domainId/verify');
    return Domain.fromJson(data['domain'] as Map<String, dynamic>);
  }

  Future<void> removeDomain(String domainId) async {
    await _delete('/domains/$domainId');
  }

  /// [localPart] is the part before @, e.g. "info".
  Future<DomainAddress> addAddress(String domainId, String localPart) async {
    final data = await _post('/domains/$domainId/addresses', {'local_part': localPart.trim().toLowerCase()});
    return DomainAddress.fromJson(data['address'] as Map<String, dynamic>);
  }

  Future<void> deleteAddress(String domainId, String addressId) async {
    await _delete('/domains/$domainId/addresses/$addressId');
  }

  // ---------------------------------------------------------------------------
  // Settings + Forgot password  (backend/routes/auth.py)
  // ---------------------------------------------------------------------------

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await _post('/auth/change-password', {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  /// Sets the recovery email and/or the security question.
  /// Needs the current password. Leave a value null to keep it as it is.
  Future<void> setRecovery({
    required String currentPassword,
    String? recoveryEmail,
    String? securityQuestion,
    String? securityAnswer,
  }) async {
    await _post('/auth/recovery', {
      'current_password': currentPassword,
      if (recoveryEmail != null) 'recovery_email': recoveryEmail,
      if (securityQuestion != null) 'security_question': securityQuestion,
      if (securityAnswer != null) 'security_answer': securityAnswer,
    });
  }

  Future<ForgotInfo> forgotStart(String login) async {
    await _ensureCsrf();
    final data = await _post('/auth/forgot/start', {'login': login.trim()});
    return ForgotInfo(
      login: data['login'] as String,
      recoveryEmail: data['recovery_email'] as String?,
      securityQuestion: data['security_question'] as String?,
    );
  }

  /// Emails a 6-digit code. Returns the masked address it was sent to.
  Future<String> forgotSendCode(String login) async {
    await _ensureCsrf();
    final data = await _post('/auth/forgot/send-code', {'login': login});
    return (data['sent_to'] as String?) ?? 'your recovery email';
  }

  /// [method] is 'email' (send [code]) or 'question' (send [answer]).
  Future<void> forgotReset({
    required String login,
    required String method,
    required String newPassword,
    String? code,
    String? answer,
  }) async {
    await _ensureCsrf();
    await _post('/auth/forgot/reset', {
      'login': login,
      'method': method,
      'new_password': newPassword,
      if (code != null) 'code': code,
      if (answer != null) 'answer': answer,
    });
  }
}

// user.dart — one MailSpace account, as the server sends it from
// /api/auth/me, /api/auth/login and /api/auth/signup  (public_user() in auth.py).

class User {
  final String id;
  final String username;
  final String email;            // e.g. username@fahadimtiaz.site
  final String accountType;      // 'regular', 'temp15' or 'temp30'
  final String role;             // 'user' or 'admin'
  final DateTime? createdAt;
  final DateTime? expiresAt;     // only for temporary accounts
  final String? recoveryEmail;   // already masked by the server: n•••@gmail.com
  final String? securityQuestion;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.accountType,
    required this.role,
    this.createdAt,
    this.expiresAt,
    this.recoveryEmail,
    this.securityQuestion,
  });

  bool get isTemporary => accountType != 'regular';
  bool get isAdmin => role == 'admin';

  /// Days left for a temporary account (null for regular accounts).
  int? get daysLeft {
    if (expiresAt == null) return null;
    final left = expiresAt!.difference(DateTime.now()).inDays;
    return left < 0 ? 0 : left;
  }

  /// "DM" style initials for the avatar circle.
  String get initials =>
      username.length >= 2 ? username.substring(0, 2).toUpperCase() : username.toUpperCase();

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      accountType: json['account_type'] as String? ?? 'regular',
      role: json['role'] as String? ?? 'user',
      createdAt: _date(json['created_at']),
      expiresAt: _date(json['expires_at']),
      recoveryEmail: json['recovery_email'] as String?,
      securityQuestion: json['security_question'] as String?,
    );
  }
}

DateTime? _date(dynamic value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value)?.toLocal() : null;

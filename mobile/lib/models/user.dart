// user.dart — one DoMailit account, as the server sends it from
// /api/auth/me, /api/auth/login and /api/auth/signup  (public_user() in auth.py).

class User {
  final String id;
  final String username;
  final String email;            // e.g. username@domailit.com
  final String accountType;      // 'regular', 'temp15' or 'temp30'
  final String role;             // 'user' or 'admin'
  final DateTime? createdAt;
  final DateTime? expiresAt;     // only for temporary accounts
  final String? recoveryEmail;   // already masked by the server: n•••@gmail.com
  final String? securityQuestion;
  final String? displayName;     // "Nimra Noor" — shown to people you email
  final String? avatar;          // /api/avatar/<id>?v=… (null = no picture)
  final bool showOnline;         // false = appear offline to everyone (no one can call you)
  final String plan;             // 'free' or 'premium'
  final DateTime? premiumUntil;  // when Premium ends (null for Free / admins)
  final String? verified;        // 'premium' / 'team' = verified badge, null = none

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
    this.displayName,
    this.avatar,
    this.showOnline = true,
    this.plan = 'free',
    this.premiumUntil,
    this.verified,
  });

  bool get isTemporary => accountType != 'regular';
  bool get isAdmin => role == 'admin';
  bool get isPremium => plan == 'premium';

  /// Days left for a temporary account (null for regular accounts).
  int? get daysLeft {
    if (expiresAt == null) return null;
    final left = expiresAt!.difference(DateTime.now()).inDays;
    return left < 0 ? 0 : left;
  }

  /// "DM" style initials for the avatar circle.
  String get initials {
    final words = (displayName ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length >= 2) return (words[0][0] + words[1][0]).toUpperCase();
    if (words.length == 1 && words[0].length >= 2) return words[0].substring(0, 2).toUpperCase();
    return username.length >= 2 ? username.substring(0, 2).toUpperCase() : username.toUpperCase();
  }

  /// The name to show: your display name, or the username.
  String get shownName => (displayName ?? '').trim().isNotEmpty ? displayName!.trim() : username;

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
      displayName: json['display_name'] as String?,
      avatar: json['avatar'] as String?,
      showOnline: json['show_online'] as bool? ?? true,
      plan: json['plan'] as String? ?? 'free',
      premiumUntil: _date(json['premium_until']),
      verified: json['verified'] as String?,
    );
  }
}

DateTime? _date(dynamic value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value)?.toLocal() : null;


/// One account signed in on this phone (Gmail-style switcher), from /api/auth/accounts.
class SignedInAccount {
  final String id;
  final String email;
  final String username;
  final String? displayName;
  final String? avatar;
  final bool active;           // the account in use right now

  SignedInAccount({
    required this.id,
    required this.email,
    required this.username,
    this.displayName,
    this.avatar,
    required this.active,
  });

  String get name => displayName ?? username;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
  }

  factory SignedInAccount.fromJson(Map<String, dynamic> json) => SignedInAccount(
        id: json['id'] as String,
        email: json['email'] as String? ?? '',
        username: json['username'] as String? ?? '',
        displayName: json['display_name'] as String?,
        avatar: json['avatar'] as String?,
        active: json['active'] as bool? ?? false,
      );
}

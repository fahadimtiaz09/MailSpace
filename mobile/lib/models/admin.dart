// admin.dart — data shown in the Admin console (backend/routes/admin.py).

DateTime? _date(dynamic v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

/// One page of any admin list (25 per page).
class AdminPage<T> {
  final List<T> items;
  final int page;
  final int totalPages;
  final int total;
  AdminPage({required this.items, required this.page, required this.totalPages, required this.total});
  bool get hasMore => page < totalPages;
}

/// The numbers on the Overview tab.
class AdminStats {
  final int users, admins, temporary, messages, domains, addresses, reviews, flagged;
  AdminStats({
    required this.users,
    required this.admins,
    required this.temporary,
    required this.messages,
    required this.domains,
    required this.addresses,
    required this.reviews,
    required this.flagged,
  });

  factory AdminStats.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return AdminStats(
      users: n('users'),
      admins: n('admins'),
      temporary: n('temporary'),
      messages: n('messages'),
      domains: n('domains'),
      addresses: n('addresses'),
      reviews: n('reviews'),
      flagged: n('flagged'),
    );
  }
}

class AdminUser {
  final String id, username, email, role, accountType, status;
  final DateTime? createdAt, expiresAt;
  final int inboxCount;

  AdminUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.accountType,
    required this.status,
    this.createdAt,
    this.expiresAt,
    required this.inboxCount,
  });

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'] as String,
        username: j['username'] as String,
        email: j['email'] as String,
        role: j['role'] as String? ?? 'user',
        accountType: j['account_type'] as String? ?? 'regular',
        status: j['status'] as String? ?? 'active',
        createdAt: _date(j['created_at']),
        expiresAt: _date(j['expires_at']),
        inboxCount: (j['inbox_count'] as num?)?.toInt() ?? 0,
      );
}

class AdminAttachment {
  final String? id; // only after the message is opened
  final String filename;
  final int size;
  AdminAttachment({this.id, required this.filename, required this.size});

  factory AdminAttachment.fromJson(Map<String, dynamic> j) => AdminAttachment(
        id: j['id'] as String?,
        filename: j['filename'] as String? ?? 'file',
        size: (j['size'] as num?)?.toInt() ?? 0,
      );
}

/// A message in the admin list (no body). After "Open and log" it also has [body].
class AdminMessage {
  final String id, from, subject;
  final List<String> to;
  final DateTime? createdAt;
  final List<AdminAttachment> attachments;
  final bool hasAttachments, external, flagged;
  final List<String> flagWords;
  final String? body;

  AdminMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.subject,
    this.createdAt,
    this.attachments = const [],
    this.hasAttachments = false,
    this.external = false,
    this.flagged = false,
    this.flagWords = const [],
    this.body,
  });

  factory AdminMessage.fromJson(Map<String, dynamic> j) {
    final files = (j['attachments'] as List? ?? [])
        .map((a) => AdminAttachment.fromJson(a as Map<String, dynamic>))
        .toList();
    return AdminMessage(
      id: j['id'] as String,
      from: j['from'] as String? ?? '',
      to: (j['to'] as List? ?? []).map((e) => e.toString()).toList(),
      subject: j['subject'] as String? ?? '',
      createdAt: _date(j['created_at']),
      attachments: files,
      hasAttachments: j['has_attachments'] as bool? ?? files.isNotEmpty,
      external: j['external'] as bool? ?? false,
      flagged: j['flagged'] as bool? ?? false,
      flagWords: (j['flag_words'] as List? ?? []).map((e) => e.toString()).toList(),
      body: j['body'] as String?,
    );
  }
}

class AuditEntry {
  final String adminEmail, action, targetEmail, reason;
  final DateTime? createdAt;
  AuditEntry({
    required this.adminEmail,
    required this.action,
    required this.targetEmail,
    required this.reason,
    this.createdAt,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        adminEmail: j['admin_email'] as String? ?? '',
        action: j['action'] as String? ?? '',
        targetEmail: j['target_email'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        createdAt: _date(j['created_at']),
      );

  String get actionText => switch (action) {
        'view_message' => 'Viewed message',
        'download_attachment' => 'Downloaded file',
        _ => action,
      };
}

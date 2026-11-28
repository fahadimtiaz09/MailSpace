// message.dart — one email in a folder.
// The list (/api/messages) sends the short version (list_item() in messages.py).
// Opening a message (/api/messages/<id>) also sends body and attachments.
// (Used from week 2; added now so both of you agree on the field names.)

class Attachment {
  final String id;
  final String filename;
  final int size; // bytes

  Attachment({required this.id, required this.filename, required this.size});

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
        filename: json['filename'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

class Message {
  final String id;
  final String folder;          // inbox, sent, drafts, starred, spam, trash
  final String from;
  final String? fromName;        // "Fahad Imtiaz" (null = only the address is known)
  final String? fromVerified;    // 'premium' / 'team' = verified badge next to the sender
  final List<String> to;
  final String subject;
  final String snippet;         // short preview for the list
  final DateTime? createdAt;
  final bool isRead;
  final bool isStarred;
  final bool hasAttachments;

  // Only filled when a single message is opened:
  final String? body;
  final String? bodyHtml;       // email design (logos, header, footer) — already cleaned by the server
  final bool canForward;        // false when the person who wrote it switched forwarding off
  final bool senderBlocked;     // you blocked this sender (their mail goes to Spam)
  final bool canReport;         // mail someone else sent you → Block / Report are offered
  final List<Attachment> attachments;

  Message({
    required this.id,
    required this.folder,
    required this.from,
    this.fromName,
    this.fromVerified,
    required this.to,
    required this.subject,
    required this.snippet,
    this.createdAt,
    required this.isRead,
    required this.isStarred,
    required this.hasAttachments,
    this.body,
    this.bodyHtml,
    this.canForward = true,
    this.senderBlocked = false,
    this.canReport = false,
    this.attachments = const [],
  });

  /// A copy with a few fields changed — used when the user stars a message
  /// or opens it, so the list updates straight away.
  Message copyWith({bool? isRead, bool? isStarred, bool? senderBlocked}) => Message(
        id: id,
        folder: folder,
        from: from,
        fromName: fromName,
        fromVerified: fromVerified,
        to: to,
        subject: subject,
        snippet: snippet,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        isStarred: isStarred ?? this.isStarred,
        hasAttachments: hasAttachments,
        body: body,
        bodyHtml: bodyHtml,
        canForward: canForward,
        senderBlocked: senderBlocked ?? this.senderBlocked,
        canReport: canReport,
        attachments: attachments,
      );

  factory Message.fromJson(Map<String, dynamic> json) {
    final rawTo = json['to'];
    return Message(
      id: json['id'] as String,
      folder: json['folder'] as String? ?? 'inbox',
      from: json['from'] as String? ?? '',
      fromName: json['from_name'] as String?,
      fromVerified: json['from_verified'] as String?,
      to: rawTo is List ? rawTo.map((e) => e.toString()).toList() : [if (rawTo != null) rawTo.toString()],
      subject: json['subject'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      createdAt: json['created_at'] is String ? DateTime.tryParse(json['created_at'])?.toLocal() : null,
      isRead: json['is_read'] as bool? ?? true,
      isStarred: json['is_starred'] as bool? ?? false,
      hasAttachments: json['has_attachments'] as bool? ?? false,
      body: json['body'] as String?,
      bodyHtml: json['body_html'] as String?,
      canForward: json['can_forward'] as bool? ?? true,
      senderBlocked: json['sender_blocked'] as bool? ?? false,
      canReport: json['can_report'] as bool? ?? false,
      attachments: (json['attachments'] as List? ?? [])
          .map((a) => Attachment.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

// message_row.dart — one row in a message list (Inbox, Search).
// avatar · sender · time · subject · preview · star
// Unread rows are bold with a light grey background (like the wireframe).

import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme.dart';
import 'brand.dart';

class MessageRow extends StatelessWidget {
  final Message message;
  final bool showRecipient; // Sent / Drafts show "To: …" instead of the sender
  final VoidCallback onTap;
  final VoidCallback? onStar;

  const MessageRow({
    super.key,
    required this.message,
    required this.onTap,
    this.onStar,
    this.showRecipient = false,
  });

  @override
  Widget build(BuildContext context) {
    final m = message;
    final unread = !m.isRead;
    final who = showRecipient ? 'To: ${m.to.isEmpty ? '(no recipient)' : m.to.join(', ')}' : m.from;
    final weight = unread ? FontWeight.w700 : FontWeight.w400;

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(6, 12, onStar == null ? 16 : 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // blue dot = unread (like the website)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 17, right: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: unread ? AppColors.primary : Colors.transparent,
                ),
              ),
              Avatar(
                seed: showRecipient && m.to.isNotEmpty ? m.to.first : m.from,
                text: initialsOf(showRecipient && m.to.isNotEmpty ? m.to.first : m.from),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, fontWeight: weight)),
                        ),
                        const SizedBox(width: 8),
                        Text(shortTime(m.createdAt),
                            style: TextStyle(fontSize: 12, fontWeight: weight, color: AppColors.muted)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(m.subject.isEmpty ? '(no subject)' : m.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, fontWeight: weight)),
                        ),
                        if (m.hasAttachments)
                          Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.attach_file, size: 16, color: AppColors.muted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(m.snippet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: AppColors.muted)),
                  ],
                ),
              ),
              if (onStar != null)
                IconButton(
                  tooltip: m.isStarred ? 'Unstar' : 'Star',
                  onPressed: onStar,
                  icon: Icon(m.isStarred ? Icons.star : Icons.star_border,
                      color: m.isStarred ? AppColors.warning : AppColors.faint),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// "sarah@fahadimtiaz.site" → "SA"
  static String initialsOf(String address) {
    final name = address.split('@').first.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (name.isEmpty) return '?';
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// today → 10:42 · yesterday → Yesterday · this week → Mon · older → 3 Nov
  static String shortTime(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1];
    return '${t.day} ${months[t.month - 1]}';
  }

  /// "11 Nov 2026, 10:42"
  static String fullTime(DateTime? t) {
    if (t == null) return '';
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]} ${t.year}, $hh:$mm';
  }

  static const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
}

import 'package:flutter/material.dart';

import '../data/club_presence.dart';
import '../services/chat_service.dart';

/// Lets a member set their own availability for one club.
///
/// A sheet rather than a dialog: it is a short list of mutually exclusive
/// choices picked with the thumb, and it should feel like changing a setting,
/// not confirming something.
Future<void> showClubPresencePicker({
  required BuildContext context,
  required String groupId,
  required ClubPresence current,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) =>
        _PresenceSheet(groupId: groupId, current: current),
  );
}

class _PresenceSheet extends StatelessWidget {
  const _PresenceSheet({required this.groupId, required this.current});

  final String groupId;
  final ClubPresence current;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chat = ChatService();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
            child: Text(
              'Your availability',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              'Only for this club — your other clubs are unaffected.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          ),
          const Divider(height: 1),
          for (final p in ClubPresence.values)
            ListTile(
              leading: PresenceDot(
                presence: p,
                size: 16,
                ringColor: cs.surface,
              ),
              title: Text(
                p.label,
                style: TextStyle(
                  fontWeight: p == current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              subtitle: Text(
                p.hint,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              trailing: p == current
                  ? Icon(Icons.check, color: cs.primary, size: 20)
                  : null,
              onTap: () async {
                // Grabbed before the sheet closes: this context is gone by
                // the time the write resolves, but the messenger is not.
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                try {
                  await chat.setMyClubPresence(groupId, p.id);
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Could not update your availability.'),
                    ),
                  );
                }
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

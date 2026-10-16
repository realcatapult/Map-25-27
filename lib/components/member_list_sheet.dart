import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/club_presence.dart';
import '../services/chat_service.dart';
import 'club_presence_picker.dart';
import '../services/friend_service.dart';
import 'user_profile_sheet.dart';

/// The member list for a club, grouped by role the way Discord's sidebar is.
///
/// Grouping by role rather than listing alphabetically is the point: in a
/// club the question is usually "who runs this?", and a flat list buries the
/// three names that answer it among forty that do not.
Future<void> showMemberList({
  required BuildContext context,
  required String groupId,
  required Map<String, dynamic> groupData,
  required String groupName,
  Color? accent,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MemberListSheet(
      groupId: groupId,
      groupData: groupData,
      groupName: groupName,
      accent: accent,
    ),
  );
}

class _MemberListSheet extends StatefulWidget {
  const _MemberListSheet({
    required this.groupId,
    required this.groupData,
    required this.groupName,
    this.accent,
  });

  final String groupId;

  /// Starting snapshot. The sheet then watches the group document so a
  /// member changing their availability shows up without reopening.
  final Map<String, dynamic> groupData;
  final String groupName;
  final Color? accent;

  @override
  State<_MemberListSheet> createState() => _MemberListSheetState();
}

class _MemberListSheetState extends State<_MemberListSheet> {
  final ChatService _chat = ChatService();
  final FriendService _friends = FriendService();

  final Map<String, Map<String, dynamic>?> _profiles = {};
  bool _loading = true;

  /// Created once, so every row shares the same subscription.
  late final Stream<List<Friendship>> _friendsStream = _friends
      .watchMyFriendships()
      .asBroadcastStream();

  /// Officers before members, so the people who can act are at the top.
  static const List<String> _roleOrder = [
    'President',
    'Co-President',
    'Officer',
    'Member',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final members = List<String>.from(widget.groupData['members'] ?? const []);
    // In parallel: these are independent reads, and awaiting them in a loop
    // made the sheet wait for one round trip per member.
    final loaded = await Future.wait(
      members.map((e) async => (e, await _friends.profileFor(e))),
    );
    if (!mounted) return;
    setState(() {
      for (final (email, profile) in loaded) {
        _profiles[email] = profile;
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _chat.watchGroup(widget.groupId),
      builder: (context, snap) {
        final live = snap.data?.data() as Map<String, dynamic>?;
        return _buildSheet(context, live ?? widget.groupData);
      },
    );
  }

  Widget _buildSheet(BuildContext context, Map<String, dynamic> groupData) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Same reasoning as the profile sheet: club colours are often too dark
    // to read as an icon tint on this surface.
    final raw = widget.accent ?? cs.primary;
    final hsl = HSLColor.fromColor(raw);
    final accent = isDark && hsl.lightness < 0.5
        ? hsl.withLightness(0.72).toColor()
        : (!isDark && hsl.lightness > 0.7
              ? hsl.withLightness(0.4).toColor()
              : raw);
    final me = (_friends.myEmail ?? '').toLowerCase();
    final members = List<String>.from(groupData['members'] ?? const []);

    // Bucket by role, then order the buckets.
    final byRole = <String, List<String>>{};
    for (final email in members) {
      final role = _chat.groupRoleName(groupData, email);
      byRole.putIfAbsent(role, () => []).add(email);
    }
    final orderedRoles = byRole.keys.toList()
      ..sort((a, b) {
        final ia = _roleOrder.indexOf(a);
        final ib = _roleOrder.indexOf(b);
        // Unknown custom roles sort after the built-ins, alphabetically.
        if (ia == -1 && ib == -1) return a.compareTo(b);
        if (ia == -1) return 1;
        if (ib == -1) return -1;
        return ia.compareTo(ib);
      });
    for (final list in byRole.values) {
      list.sort(
        (a, b) => _name(a).toLowerCase().compareTo(_name(b).toLowerCase()),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _header(members.length, cs),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  for (final role in orderedRoles) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                      child: Text(
                        '${role.toUpperCase()} — ${byRole[role]!.length}',
                        style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final email in byRole[role]!)
                      _memberRow(email, role, accent, cs, groupData, me),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(int count, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Members',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$count in ${widget.groupName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _memberRow(
    String email,
    String role,
    Color accent,
    ColorScheme cs,
    Map<String, dynamic> groupData,
    String me,
  ) {
    final profile = _profiles[email];
    final photoUrl = profile?['profilePicture'] as String?;
    final isMe = email.toLowerCase() == me;
    final presence = ClubPresence.fromId(
      _chat.clubPresenceId(groupData, email),
    );

    return ListTile(
      // The dot rides the avatar, so availability reads while scanning the
      // list rather than only after opening someone.
      leading: AvatarWithPresence(
        presence: presence,
        ringColor: cs.surface,
        avatar: CircleAvatar(
          radius: 19,
          backgroundColor: cs.surfaceContainerHighest,
          backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
              ? CachedNetworkImageProvider(photoUrl, maxWidth: 120)
              : null,
          child: (photoUrl == null || photoUrl.isEmpty)
              ? Icon(Icons.person, size: 20, color: cs.onSurfaceVariant)
              : null,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              _name(email),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 6),
            Text(
              'you',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
      subtitle: Text(
        isMe ? '${presence.label}  •  tap to change' : presence.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: isMe ? accent : cs.onSurfaceVariant,
          fontWeight: isMe ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      // Friendship state lives on the row so the list answers "who do I
      // already know?" without opening each profile.
      trailing: isMe ? null : _stateDot(email, accent, cs),
      // Your own row is where you would look for your own status, so it sets
      // availability; everyone else's opens their profile.
      onTap: () => isMe
          ? showClubPresencePicker(
              context: context,
              groupId: widget.groupId,
              current: presence,
            )
          : showUserProfile(
              context: context,
              email: email,
              groupData: groupData,
              accent: accent,
            ),
    );
  }

  Widget _stateDot(String email, Color accent, ColorScheme cs) {
    // One listener for all my friendships, not one per row: a forty-member
    // club was opening forty Firestore streams.
    return StreamBuilder<List<Friendship>>(
      stream: _friendsStream,
      builder: (context, snap) {
        final me = _friends.myEmail ?? '';
        final match = (snap.data ?? const <Friendship>[]).firstWhere(
          (f) => f.users.contains(email.toLowerCase()),
          orElse: () => const Friendship(
            id: '',
            users: [],
            requestedBy: '',
            status: 'none',
          ),
        );
        final state = match.id.isEmpty ? FriendState.none : match.stateFor(me);
        final (IconData icon, Color color, String tip) = switch (state) {
          FriendState.friends => (Icons.how_to_reg, accent, 'Friends'),
          FriendState.outgoing => (
            Icons.hourglass_empty,
            cs.onSurfaceVariant,
            'Request sent',
          ),
          FriendState.incoming => (
            Icons.person_add_alt_1,
            accent,
            'Wants to be friends',
          ),
          _ => (Icons.chevron_right, cs.onSurfaceVariant, ''),
        };
        return Tooltip(
          message: tip,
          child: Icon(icon, size: 18, color: color),
        );
      },
    );
  }

  String _name(String email) =>
      FriendService.displayNameFrom(_profiles[email], email);
}

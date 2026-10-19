import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../Pages/direct_message_page.dart';
import '../data/club_presence.dart';
import '../services/chat_service.dart';
import '../services/friend_service.dart';

/// A member's profile card, in the Discord shape: a colour banner, the avatar
/// breaking the banner's lower edge, then name, handle, role, and the actions
/// you came for.
///
/// Opens as a bottom sheet because it is summoned from a list and dismissed
/// immediately after one decision — a full route would be too much ceremony.
Future<void> showUserProfile({
  required BuildContext context,
  required String email,
  Map<String, dynamic>? groupData,
  Color? accent,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _UserProfileSheet(email: email, groupData: groupData, accent: accent),
  );
}

class _UserProfileSheet extends StatefulWidget {
  const _UserProfileSheet({required this.email, this.groupData, this.accent});

  final String email;
  final Map<String, dynamic>? groupData;
  final Color? accent;

  @override
  State<_UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends State<_UserProfileSheet> {
  final FriendService _friends = FriendService();
  final ChatService _chat = ChatService();

  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _busy = false;

  /// Addresses stay hidden until asked for. On a profile you reach from a
  /// club member list, the useful identity is the name and the role.
  bool _showEmail = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _friends.profileFor(widget.email);
    if (!mounted) return;
    setState(() {
      _profile = p;
      _loading = false;
    });
  }

  bool get _isMe =>
      widget.email.toLowerCase() == (_friends.myEmail ?? '').toLowerCase();

  Future<void> _openDm() async {
    setState(() => _busy = true);
    try {
      final threadId = await _chat.getOrCreateDirectMessage(widget.email);
      if (!mounted) return;
      Navigator.pop(context);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DirectMessagePage(threadId: threadId, otherEmail: widget.email),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that conversation.')),
      );
    }
  }

  Future<void> _act(Future<void> Function() action, String failure) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A club colour nudged into a usable contrast range for the sheet it is
  /// drawn on. Theme colours are picked to carry white app-bar text, so many
  /// are too dark to use raw as a fill or a label.
  Color _readable(Color c, bool isDark) {
    final hsl = HSLColor.fromColor(c);
    if (isDark && hsl.lightness < 0.5) {
      return hsl
          .withLightness(0.72)
          .withSaturation(hsl.saturation.clamp(0.35, 1.0))
          .toColor();
    }
    if (!isDark && hsl.lightness > 0.7) {
      return hsl.withLightness(0.4).toColor();
    }
    return c;
  }

  /// Black or white, whichever the fill can actually carry.
  Color _onColor(Color fill) =>
      ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
      ? Colors.white
      : Colors.black;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Banner keeps the club's real colour; everything that carries text or
    // acts as a control uses the readable version.
    final banner = widget.accent ?? cs.primary;
    final accent = _readable(banner, isDark);
    final name = FriendService.displayNameFrom(_profile, widget.email);
    final photoUrl = _profile?['profilePicture'] as String?;
    final rawBio = _profile?['bio'];
    final bio = (rawBio is String && rawBio.trim().isNotEmpty)
        ? rawBio.trim()
        : null;
    final role = widget.groupData == null
        ? null
        : _chat.groupRoleName(widget.groupData!, widget.email);
    // Only meaningful in a club context; a profile opened from the friends
    // list has no club to be available in.
    final presence = widget.groupData == null
        ? null
        : ClubPresence.fromId(
            _chat.clubPresenceId(widget.groupData!, widget.email),
          );

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _banner(banner, photoUrl, cs, presence),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (_showEmail)
                    Text(
                      widget.email,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () => setState(() => _showEmail = true),
                      child: Text(
                        'Show email',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  if (bio != null) ...[
                    const SizedBox(height: 14),
                    _label('ABOUT ME', cs),
                    const SizedBox(height: 5),
                    Text(
                      bio,
                      style: const TextStyle(fontSize: 13.5, height: 1.4),
                    ),
                  ],
                  if (role != null) ...[
                    const SizedBox(height: 14),
                    _label('ROLE', cs),
                    const SizedBox(height: 6),
                    _roleChip(role, accent),
                  ],
                  if (presence != null) ...[
                    const SizedBox(height: 14),
                    _label('AVAILABILITY', cs),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        PresenceDot(
                          presence: presence,
                          size: 12,
                          ringColor: cs.surface,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          presence.label,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            presence.hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_loading) ...[
                    const SizedBox(height: 18),
                    const Center(
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ] else if (!_isMe) ...[
                    const SizedBox(height: 18),
                    _actions(accent, cs),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Banner plus overlapping avatar. The overlap is the whole point of the
  /// Discord card: it ties identity to the colour strip instead of stacking
  /// two unrelated blocks.
  Widget _banner(
    Color accent,
    String? photoUrl,
    ColorScheme cs,
    ClubPresence? presence,
  ) {
    return SizedBox(
      height: 112,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 76,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, accent.withValues(alpha: 0.55)],
              ),
            ),
          ),
          Positioned(
            left: 20,
            top: 32,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cs.surface,
                shape: BoxShape.circle,
              ),
              child: AvatarWithPresence(
                presence: presence ?? ClubPresence.fallback,
                dotSize: presence == null ? 0 : 20,
                ringColor: cs.surface,
                avatar: CircleAvatar(
                  radius: 36,
                  backgroundColor: cs.surfaceContainerHighest,
                  backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                      ? CachedNetworkImageProvider(photoUrl, maxWidth: 240)
                      : null,
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? Icon(Icons.person, size: 34, color: cs.onSurfaceVariant)
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, ColorScheme cs) => Text(
    text,
    style: TextStyle(
      fontSize: 10.5,
      letterSpacing: 0.7,
      fontWeight: FontWeight.w800,
      color: cs.onSurfaceVariant,
    ),
  );

  Widget _roleChip(String role, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            role,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  /// Message is always available. The friend button reads the live friendship
  /// so it reflects what the other person has done without a refresh.
  Widget _actions(Color accent, ColorScheme cs) {
    return StreamBuilder<Friendship?>(
      stream: _friends.watchFriendshipWith(widget.email),
      builder: (context, snap) {
        final me = _friends.myEmail ?? '';
        final f = snap.data;
        final state = f?.stateFor(me) ?? FriendState.none;

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _openDm,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Message'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: _onColor(accent),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _friendButton(state, f, cs)),
              ],
            ),
            if (state == FriendState.incoming) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _act(
                          () => _friends.respond(f!.id, accept: false),
                          'Could not decline.',
                        ),
                  child: const Text('Decline request'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _friendButton(FriendState state, Friendship? f, ColorScheme cs) {
    switch (state) {
      case FriendState.friends:
        return OutlinedButton.icon(
          onPressed: _busy ? null : () => _confirmRemove(f!),
          icon: const Icon(Icons.how_to_reg, size: 18),
          label: const Text('Friends'),
        );
      case FriendState.outgoing:
        return OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _act(() => _friends.remove(f!.id), 'Could not cancel.'),
          icon: const Icon(Icons.hourglass_empty, size: 18),
          label: const Text('Pending'),
        );
      case FriendState.incoming:
        return FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _act(
                  () => _friends.respond(f!.id, accept: true),
                  'Could not accept.',
                ),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Accept'),
        );
      case FriendState.declined:
      case FriendState.none:
        return OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _act(
                  () => _friends.sendRequest(widget.email),
                  'Could not send the request.',
                ),
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: const Text('Add friend'),
        );
    }
  }

  Future<void> _confirmRemove(Friendship f) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text(
          'You and ${FriendService.displayNameFrom(_profile, widget.email)} '
          'will no longer be friends.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await _act(() => _friends.remove(f.id), 'Could not remove.');
    }
  }
}

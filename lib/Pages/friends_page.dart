import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../components/user_profile_sheet.dart';
import '../services/chat_service.dart';
import '../services/friend_service.dart';
import 'direct_message_page.dart';
import '../theme/app_theme.dart';

/// Friends, incoming requests, and requests you have sent.
///
/// Three tabs rather than one list, because the three carry different
/// urgency: a request waiting on you is a task, a request you sent is just
/// information, and your friends are a directory.
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage>
    with SingleTickerProviderStateMixin {
  final FriendService _friends = FriendService();
  final ChatService _chat = ChatService();

  late final TabController _tabs = TabController(length: 3, vsync: this);
  final Map<String, Map<String, dynamic>?> _profiles = {};

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool _resolving = false;

  /// Loads any profiles we have not seen yet, in one batch and one setState.
  Future<void> _ensureProfiles(Iterable<String> emails) async {
    final missing = emails
        .where((e) => e.isNotEmpty && !_profiles.containsKey(e))
        .toSet();
    if (missing.isEmpty || _resolving) return;
    _resolving = true;
    try {
      final loaded = await Future.wait(
        missing.map((e) async => (e, await _friends.profileFor(e))),
      );
      if (!mounted) return;
      setState(() {
        for (final (email, profile) in loaded) {
          _profiles[email] = profile;
        }
      });
    } finally {
      _resolving = false;
    }
  }

  Future<void> _addByEmail() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a friend'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Their email',
            hintText: 'name@example.com',
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (email == null || email.trim().isEmpty) return;

    final target = email.trim().toLowerCase();
    try {
      // Refuse unknown addresses up front rather than creating a request
      // nobody can ever accept.
      final profile = await _friends.profileFor(target);
      if (profile == null) {
        throw Exception('Nobody is signed up with that email.');
      }
      await _friends.sendRequest(target);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Friend request sent.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _friends.myEmail ?? '';

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        title: const Text('Friends'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'Requests'),
            Tab(text: 'Sent'),
          ],
        ),
      ),
      body: StreamBuilder<List<Friendship>>(
        stream: _friends.watchMyFriendships(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Could not load friends.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snap.data!;
          final friends = all
              .where((f) => f.stateFor(me) == FriendState.friends)
              .toList();
          final incoming = all
              .where((f) => f.stateFor(me) == FriendState.incoming)
              .toList();
          final outgoing = all
              .where((f) => f.stateFor(me) == FriendState.outgoing)
              .toList();

          // Deferred: kicking off loads during build and calling setState
          // from them is what made this list thrash.
          final needed = all.map((f) => f.otherThan(me)).toList();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _ensureProfiles(needed);
          });

          return TabBarView(
            controller: _tabs,
            children: [
              _list(
                friends,
                me,
                empty: 'No friends yet.\nAdd someone from a club member list.',
                trailing: (f, other) => _friendRowActions(f, other),
              ),
              _list(
                incoming,
                me,
                empty: 'No requests waiting on you.',
                trailing: (f, other) => _requestActions(f),
              ),
              _list(
                outgoing,
                me,
                empty: 'You have not sent any requests.',
                trailing: (f, other) => TextButton(
                  onPressed: () => _friends.remove(f.id),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addByEmail,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add'),
      ),
    );
  }

  Widget _list(
    List<Friendship> items,
    String me, {
    required String empty,
    required Widget Function(Friendship f, String other) trailing,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            empty,
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.45,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final sorted = items.toList()
      ..sort(
        (a, b) => _name(
          a.otherThan(me),
        ).toLowerCase().compareTo(_name(b.otherThan(me)).toLowerCase()),
      );

    return ListView.separated(
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final f = sorted[i];
        final other = f.otherThan(me);
        final profile = _profiles[other];
        final photoUrl = profile?['profilePicture'] as String?;
        final cs = Theme.of(context).colorScheme;

        return ListTile(
          leading: CircleAvatar(
            radius: 21,
            backgroundColor: cs.surfaceContainerHighest,
            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                ? CachedNetworkImageProvider(photoUrl, maxWidth: 140)
                : null,
            child: (photoUrl == null || photoUrl.isEmpty)
                ? Icon(Icons.person, size: 22, color: cs.onSurfaceVariant)
                : null,
          ),
          title: Text(
            _name(other),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          // The name is the identity here; an address under every row is
          // noise, and it is on the profile for anyone who wants it.
          subtitle: Text(
            _profiles.containsKey(other) && _profiles[other] == null
                ? 'No profile yet'
                : 'Friend',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          trailing: trailing(f, other),
          onTap: () => showUserProfile(context: context, email: other),
        );
      },
    );
  }

  Widget _friendRowActions(Friendship f, String other) {
    return IconButton(
      tooltip: 'Message',
      icon: const Icon(Icons.chat_bubble_outline, size: 20),
      onPressed: () async {
        try {
          final threadId = await _chat.getOrCreateDirectMessage(other);
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  DirectMessagePage(threadId: threadId, otherEmail: other),
            ),
          );
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open that conversation.')),
          );
        }
      },
    );
  }

  /// Accept and decline sit side by side: an incoming request is a decision,
  /// and burying either behind a menu makes the list a chore.
  Widget _requestActions(Friendship f) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Decline',
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => _friends.respond(f.id, accept: false),
        ),
        IconButton(
          tooltip: 'Accept',
          icon: const Icon(Icons.check, size: 20),
          color: Theme.of(context).colorScheme.primary,
          onPressed: () => _friends.respond(f.id, accept: true),
        ),
      ],
    );
  }

  String _name(String email) =>
      FriendService.displayNameFrom(_profiles[email], email);
}

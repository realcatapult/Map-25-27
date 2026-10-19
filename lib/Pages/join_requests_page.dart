import 'package:flutter/material.dart';

import '../components/user_profile_sheet.dart';
import '../services/join_request_service.dart';
import '../services/profile_cache.dart';
import '../theme/app_theme.dart';

/// An officer's queue of people asking to join.
///
/// Pending requests come first and carry the two buttons; decided ones stay
/// below as a record, so a president can see who was turned away and by whom
/// rather than wondering whether they imagined it.
class JoinRequestsPage extends StatefulWidget {
  const JoinRequestsPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<JoinRequestsPage> createState() => _JoinRequestsPageState();
}

class _JoinRequestsPageState extends State<JoinRequestsPage> {
  final JoinRequestService _service = JoinRequestService();
  bool _busy = false;

  Future<void> _decide(JoinRequest r, {required bool approve}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final name = ProfileCache.instance.nameFor(r.email);
    try {
      if (approve) {
        await _service.approve(widget.groupId, r.email);
      } else {
        await _service.decline(widget.groupId, r.email);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(approve ? '$name joined the club' : 'Declined $name'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save that decision.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        title: const Text('Join Requests'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(26),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 9),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.groupName,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<JoinRequest>>(
        stream: _service.watchRequests(widget.groupId),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Could not load requests.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snap.data!;
          final pending = all.where((r) => r.isPending).toList();
          final decided = all.where((r) => !r.isPending).toList();

          if (all.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nobody is waiting to join.\n'
                  'Requests appear here when someone asks from Discover.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.45, color: cs.onSurfaceVariant),
                ),
              ),
            );
          }

          ProfileCache.instance.warm(all.map((r) => r.email));

          return ListView(
            children: [
              if (pending.isNotEmpty) ...[
                _heading('WAITING ON YOU — ${pending.length}', cs),
                for (final r in pending) _pendingRow(r, cs),
              ],
              if (decided.isNotEmpty) ...[
                _heading('DECIDED', cs),
                for (final r in decided) _decidedRow(r, cs),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _heading(String text, ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.7,
        fontWeight: FontWeight.w800,
        color: cs.onSurfaceVariant,
      ),
    ),
  );

  Widget _pendingRow(JoinRequest r, ColorScheme cs) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.surfaceContainerHighest,
        child: Icon(Icons.person_outline, color: cs.onSurfaceVariant),
      ),
      title: Text(
        ProfileCache.instance.nameFor(r.email),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          if (r.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '“${r.message}”',
                style: TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurface,
                ),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Decline',
            icon: const Icon(Icons.close, size: 20),
            onPressed: _busy ? null : () => _decide(r, approve: false),
          ),
          IconButton(
            tooltip: 'Approve',
            icon: const Icon(Icons.check, size: 20),
            color: cs.primary,
            onPressed: _busy ? null : () => _decide(r, approve: true),
          ),
        ],
      ),
      onTap: () => showUserProfile(context: context, email: r.email),
    );
  }

  Widget _decidedRow(JoinRequest r, ColorScheme cs) {
    final approved = r.status == 'approved';
    return ListTile(
      dense: true,
      leading: Icon(
        approved ? Icons.check_circle_outline : Icons.block,
        size: 20,
        color: approved ? Colors.green : cs.onSurfaceVariant,
      ),
      title: Text(
        ProfileCache.instance.nameFor(r.email),
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        approved
            ? 'Approved${r.decidedBy == null ? '' : ' by ${r.decidedBy}'}'
            : 'Declined${r.decidedBy == null ? '' : ' by ${r.decidedBy}'}',
        style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
      ),
    );
  }
}

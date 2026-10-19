import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../Pages/chat_room_page.dart';
import '../services/ai_service.dart';
import '../services/join_request_service.dart';
import '../theme/app_theme.dart';

/// Guided club matchmaking.
///
/// A conversation rather than a search box, because the thing a new student
/// cannot do is name what they want — the whole problem is not knowing what
/// the clubs are. So it asks a question they can answer, then does the
/// translating.
Future<void> showClubMatcher(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ClubMatcherSheet(),
  );
}

enum _Step { ask, describe, thinking, results, declined }

class _ClubMatcherSheet extends StatefulWidget {
  const _ClubMatcherSheet();

  @override
  State<_ClubMatcherSheet> createState() => _ClubMatcherSheetState();
}

class _ClubMatcherSheetState extends State<_ClubMatcherSheet> {
  final AiService _ai = AiService();
  final TextEditingController _input = TextEditingController();

  _Step _step = _Step.ask;
  List<({String id, String reason})> _matches = const [];
  Map<String, Map<String, dynamic>> _clubsById = {};

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _findMatches() async {
    final wanted = _input.text.trim();
    if (wanted.isEmpty) return;

    setState(() => _step = _Step.thinking);

    // Real clubs only: public ones, which are the ones a newcomer can
    // actually act on.
    final snap = await FirebaseFirestore.instance
        .collection('groups')
        .where('isPublic', isEqualTo: true)
        .get();

    final clubs = snap.docs.map((d) {
      final data = d.data();
      return {
        'id': d.id,
        'name': (data['name'] as String?) ?? 'Club',
        'overview': (data['overview'] as String?) ?? '',
        'keywords': List<String>.from(data['keywords'] ?? const []),
      };
    }).toList();

    _clubsById = {for (final c in clubs) c['id'] as String: c};

    final result = await _ai.matchClubs(wanted: wanted, clubs: clubs);

    if (!mounted) return;
    setState(() {
      _matches = result;
      _step = _Step.results;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _header(cs),
            const SizedBox(height: 16),
            _body(cs),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.brass, AppColors.brassLight],
            ),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.auto_awesome,
            size: 19,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Club finder',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Text(
                'Describe it and I will find the closest match',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(ColorScheme cs) {
    switch (_step) {
      case _Step.ask:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bubble('Do you want to find a club?', cs),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => setState(() => _step = _Step.describe),
                    child: const Text('Yes'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _step = _Step.declined),
                    child: const Text('No'),
                  ),
                ),
              ],
            ),
          ],
        );

      case _Step.declined:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bubble(
              'No problem. Browse the clubs below whenever you feel like it.',
              cs,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        );

      case _Step.describe:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bubble(
              'What kind of club are you after? Describe it however makes '
              'sense — an activity, a subject, or just a vibe.',
              cs,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _input,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'something with coding, but not super competitive',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _findMatches(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _findMatches,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Find matches'),
              ),
            ),
          ],
        );

      case _Step.thinking:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                'Reading through the clubs…',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );

      case _Step.results:
        if (_matches.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bubble(
                'Nothing here is a close match for that. Try describing it '
                'differently, or have a look through the full list.',
                cs,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _step = _Step.describe),
                      child: const Text('Try again'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Browse all'),
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bubble(
              _matches.length == 1
                  ? 'One club looks like a fit:'
                  : 'These look like the closest fits:',
              cs,
            ),
            const SizedBox(height: 12),
            for (final m in _matches) _matchCard(m, cs),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => setState(() => _step = _Step.describe),
                child: const Text('Describe something else'),
              ),
            ),
          ],
        );
    }
  }

  Widget _bubble(String text, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4)),
    );
  }

  /// A match is only useful if you can act on it, so the card carries the
  /// request button rather than sending you back to hunt for the club.
  Widget _matchCard(({String id, String reason}) m, ColorScheme cs) {
    final club = _clubsById[m.id];
    if (club == null) return const SizedBox.shrink();
    final name = club['name'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome, size: 13, color: AppColors.brass),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  m.reason,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ChatRoomPage(groupId: m.id, groupName: name),
                      ),
                    );
                  },
                  child: const Text('Look'),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await JoinRequestService().request(m.id);
                      messenger.showSnackBar(
                        SnackBar(content: Text('Request sent to $name')),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            e.toString().replaceFirst('Exception: ', ''),
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Request'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

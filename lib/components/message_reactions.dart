import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Message reactions, shared by group chats and direct messages.
///
/// The model is Instagram's: nothing is shown until someone reacts, picking
/// one is a long press, and an existing reaction reads as a small badge
/// tucked into the bubble's edge. The previous design rendered every
/// available emoji as a pill under every message, which meant the loudest
/// thing in the transcript was a control nobody had used.
class MessageReactions {
  /// Six is Instagram's count — enough range to feel expressive, few enough
  /// to stay a single row at phone width and be picked without reading.
  static const List<String> palette = <String>[
    '❤️', // red heart
    '\u{1F602}', // tears of joy
    '\u{1F62E}', // open mouth
    '\u{1F622}', // crying
    '\u{1F525}', // fire
    '\u{1F44D}', // thumbs up
  ];

  /// Double-tap applies this one, matching the gesture people already expect.
  static const String quick = '❤️';

  static String key(String emoji, String email) => '$emoji::$email';

  /// Counts per emoji, highest first, so the badge leads with the reaction
  /// that actually carried the room.
  static List<({String emoji, int count})> tally(List<String> keys) {
    final counts = <String, int>{};
    for (final k in keys) {
      final emoji = k.split('::').first;
      if (emoji.isEmpty) continue;
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final out =
        counts.entries.map((e) => (emoji: e.key, count: e.value)).toList()
          ..sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  static bool mine(List<String> keys, String emoji, String email) =>
      keys.contains(key(emoji, email));

  static Set<String> myEmojis(List<String> keys, String email) => keys
      .where((k) => k.endsWith('::$email'))
      .map((k) => k.split('::').first)
      .toSet();
}

/// The compact badge shown on a message that has reactions.
///
/// Sized to overlap the bubble's bottom edge, which is what makes it read as
/// attached to the message rather than as another line of content.
class ReactionBadge extends StatelessWidget {
  const ReactionBadge({
    super.key,
    required this.reactionKeys,
    required this.currentUserEmail,
    required this.onToggle,
    this.onMore,
  });

  final List<String> reactionKeys;
  final String currentUserEmail;

  /// Tapping a pill toggles that specific emoji, so adding your thumbs-up to
  /// someone else's is one tap rather than a trip through the picker.
  final ValueChanged<String> onToggle;

  /// Opens the full picker, for adding a reaction nobody has used yet.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final tally = MessageReactions.tally(reactionKeys);
    if (tally.isEmpty) return const SizedBox.shrink();

    final mine = MessageReactions.myEmojis(reactionKeys, currentUserEmail);

    // One pill per emoji, each with its own count. A single merged badge
    // could not answer "how many thumbs up?", which is the whole question
    // a reaction count exists to answer.
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final t in tally)
          _Pill(
            emoji: t.emoji,
            count: t.count,
            isMine: mine.contains(t.emoji),
            onTap: () {
              HapticFeedback.selectionClick();
              onToggle(t.emoji);
            },
          ),
        if (onMore != null)
          _Pill(
            emoji: null,
            count: 0,
            isMine: false,
            onTap: () {
              HapticFeedback.selectionClick();
              onMore!();
            },
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.emoji,
    required this.count,
    required this.isMine,
    required this.onTap,
  });

  /// null renders the "add another" pill.
  final String? emoji;
  final int count;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Your own reaction is tinted and outlined, so you can see at a glance
    // which of these you are part of.
    final bg = isMine
        ? cs.primary.withValues(alpha: isDark ? 0.26 : 0.14)
        : (isDark ? cs.surfaceContainerHigh : Colors.white);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: emoji == null ? 6 : 7,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isMine
                ? cs.primary.withValues(alpha: 0.7)
                : cs.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.35),
            width: isMine ? 1.2 : 1,
          ),
          // Offset and blur, so the pill reads as sitting above the bubble
          // rather than glowing on it.
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.12),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: emoji == null
            ? Icon(
                Icons.add_reaction_outlined,
                size: 13,
                color: cs.onSurfaceVariant,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji!, style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isMine ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// An extra choice shown under the emoji row, such as Unsend.
class MessageAction {
  const MessageAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

/// The long-press picker: a floating row of emoji anchored to the message.
///
/// Opens as a popup rather than inline so it never reflows the transcript
/// underneath the finger that summoned it.
Future<void> showReactionPicker({
  required BuildContext context,
  required Offset globalPosition,
  required Set<String> selected,
  required ValueChanged<String> onPick,
  List<MessageAction> actions = const [],
}) async {
  HapticFeedback.mediumImpact();

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final screen = overlay?.size ?? MediaQuery.of(context).size;

  const rowWidth = 300.0;
  final rowHeight = 54.0 + (actions.isEmpty ? 0 : 6 + 44.0 * actions.length);

  // Keep the row on screen when the message is near an edge, and place it
  // above the touch point so the finger is not covering the choices.
  final left = (globalPosition.dx - rowWidth / 2).clamp(
    12.0,
    (screen.width - rowWidth - 12).clamp(12.0, double.infinity),
  );
  final top = (globalPosition.dy - rowHeight - 18).clamp(
    MediaQuery.of(context).padding.top + 8,
    screen.height - rowHeight - 12,
  );

  await showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.12),
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, _, _) {
      // Exponential ease-out from an already-visible default: the row grows
      // from the message rather than fading in from nothing.
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutExpo,
      );
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: rowWidth,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.82, end: 1).animate(curved),
              alignment: Alignment.bottomCenter,
              child: FadeTransition(
                opacity: curved,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PickerRow(
                      selected: selected,
                      onPick: (emoji) {
                        Navigator.of(context).pop();
                        onPick(emoji);
                      },
                    ),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _ActionList(
                        actions: actions,
                        onTap: (action) {
                          Navigator.of(context).pop();
                          action.onTap();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({required this.selected, required this.onPick});

  final Set<String> selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerHigh : Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: MessageReactions.palette.map((emoji) {
            final isOn = selected.contains(emoji);
            return InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onPick(emoji);
              },
              customBorder: const CircleBorder(),
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: isOn
                    ? BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Text(emoji, style: const TextStyle(fontSize: 25)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ActionList extends StatelessWidget {
  const _ActionList({required this.actions, required this.onTap});

  final List<MessageAction> actions;
  final ValueChanged<MessageAction> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? cs.surfaceContainerHigh : Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: actions.map((action) {
          final color = action.destructive ? cs.error : cs.onSurface;
          return InkWell(
            onTap: () => onTap(action),
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(action.icon, size: 20, color: color),
                    const SizedBox(width: 12),
                    Text(
                      action.label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Wraps a message bubble with the reaction gestures.
///
/// Long press opens the picker; double tap applies the heart. Both are
/// additive — the bubble's own tap behaviour (replies, threads) is untouched.
class ReactableMessage extends StatelessWidget {
  const ReactableMessage({
    super.key,
    required this.child,
    required this.reactionKeys,
    required this.currentUserEmail,
    required this.onToggle,
    this.onLongPressExtra,
    this.alignEnd = false,
    this.actions = const [],
  });

  /// Shown under the emoji row on long press.
  final List<MessageAction> actions;

  final Widget child;
  final List<String> reactionKeys;
  final String currentUserEmail;
  final ValueChanged<String> onToggle;

  /// Some surfaces already use long press for their own menu; this runs
  /// after the picker is dismissed without a choice.
  final VoidCallback? onLongPressExtra;

  /// Badge hugs the bubble's outer corner, which flips for your own messages.
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final hasReactions = reactionKeys.isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onDoubleTap: () {
        HapticFeedback.lightImpact();
        onToggle(MessageReactions.quick);
      },
      onLongPressStart: (details) => showReactionPicker(
        context: context,
        globalPosition: details.globalPosition,
        selected: MessageReactions.myEmojis(reactionKeys, currentUserEmail),
        onPick: onToggle,
        actions: actions,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Reserve the overlap so the badge cannot cover the last line of
          // text, and so bubbles with and without reactions keep an even
          // rhythm in the list.
          Padding(
            padding: EdgeInsets.only(bottom: hasReactions ? 11 : 0),
            child: child,
          ),
          if (hasReactions)
            Positioned(
              bottom: 0,
              left: alignEnd ? null : 10,
              right: alignEnd ? 10 : null,
              child: ReactionBadge(
                reactionKeys: reactionKeys,
                currentUserEmail: currentUserEmail,
                onToggle: onToggle,
                onMore: () => showReactionPicker(
                  context: context,
                  globalPosition: _badgeAnchor(context),
                  selected: MessageReactions.myEmojis(
                    reactionKeys,
                    currentUserEmail,
                  ),
                  onPick: onToggle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Offset _badgeAnchor(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return const Offset(0, 0);
    return box.localToGlobal(Offset(box.size.width / 2, box.size.height));
  }
}

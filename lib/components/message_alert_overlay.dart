import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../Pages/chat_room_page.dart';
import '../Pages/direct_message_page.dart';
import '../services/message_alerts.dart';
import '../services/profile_cache.dart';

/// Lets the toast push a route even though it sits outside the route tree.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// The toast that slides down when a message arrives while you are elsewhere.
///
/// Sits above the whole app rather than inside a screen, so it behaves the
/// same whichever tab you are on, and never pushes layout around.
class MessageAlertOverlay extends StatefulWidget {
  const MessageAlertOverlay({super.key});

  @override
  State<MessageAlertOverlay> createState() => _MessageAlertOverlayState();
}

class _MessageAlertOverlayState extends State<MessageAlertOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    MessageAlerts.instance.addListener(_onAlert);
  }

  void _onAlert() {
    if (!mounted) return;
    setState(() {});
    if (MessageAlerts.instance.current != null) {
      _controller.forward(from: 0);
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    MessageAlerts.instance.removeListener(_onAlert);
    _controller.dispose();
    super.dispose();
  }

  /// Opens the conversation the message came from.
  void _open(AlertSource source) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => source.isGroup
            ? ChatRoomPage(groupId: source.id, groupName: source.name)
            : DirectMessagePage(
                threadId: source.id,
                otherEmail: source.otherEmail,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alert = MessageAlerts.instance.current;
    // Nothing to show and nothing animating out: render no-op rather than an
    // invisible box that still takes part in hit testing.
    if (alert == null && _controller.isDismissed) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final photo = alert == null
        ? null
        : ProfileCache.instance.photoFor(alert.senderEmail);

    // Exponential ease-out from above the top edge, so it reads as arriving
    // rather than fading in from nowhere.
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutExpo,
      reverseCurve: Curves.easeIn,
    );

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.4),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(
          opacity: curved,
          child: alert == null
              ? const SizedBox.shrink()
              : Material(
                  color: isDark ? cs.surfaceContainerHigh : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  elevation: 8,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      MessageAlerts.instance.dismiss();
                      _open(alert.source);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: cs.surfaceContainerHighest,
                            backgroundImage: (photo != null && photo.isNotEmpty)
                                ? CachedNetworkImageProvider(
                                    photo,
                                    maxWidth: 120,
                                  )
                                : null,
                            child: (photo == null || photo.isEmpty)
                                ? Icon(
                                    Icons.person,
                                    size: 19,
                                    color: cs.onSurfaceVariant,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  alert.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  alert.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.3,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(
                                      alert.source.isGroup
                                          ? Icons.groups
                                          : Icons.alternate_email,
                                      size: 11,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        alert.source.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: cs.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            visualDensity: VisualDensity.compact,
                            color: cs.onSurfaceVariant,
                            onPressed: MessageAlerts.instance.dismiss,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

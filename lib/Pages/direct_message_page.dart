import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:login_ui/components/message_reactions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:login_ui/services/chat_service.dart';
import 'package:login_ui/theme/app_theme.dart';
import 'package:login_ui/components/skeleton_loader.dart';
import 'package:login_ui/components/jarvis_avatar.dart';
import 'package:login_ui/components/user_profile_sheet.dart';
import 'package:login_ui/services/profile_cache.dart';
import 'package:login_ui/services/message_alerts.dart';
import 'package:login_ui/services/ai_service.dart';

class DirectMessagePage extends StatefulWidget {
  final String threadId;
  final String otherEmail;

  const DirectMessagePage({
    super.key,
    required this.threadId,
    required this.otherEmail,
  });

  @override
  State<DirectMessagePage> createState() => _DirectMessagePageState();
}

class _DirectMessagePageState extends State<DirectMessagePage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiService _aiService = AiService();
  bool _jarvisThinking = false;

  @override
  void initState() {
    super.initState();
    ProfileCache.instance.addListener(_onProfilesChanged);
    ActiveChat.enter('dm:' + widget.threadId);
  }

  void _onProfilesChanged() {
    if (mounted) setState(() {});
  }

  /// Answers an "@jarvis ..." line in this thread.
  ///
  /// The reply is posted as a real message from the bot address rather than
  /// held in memory, so both people see it and it survives reopening the
  /// thread — the same way it works in a club room.
  Future<void> _handleJarvis(String question) async {
    setState(() => _jarvisThinking = true);
    try {
      final recent = await _chatService.getRecentDirectMessages(
        widget.threadId,
        limit: 10,
      );
      final reply = question.isEmpty
          ? 'Hi! Ask me anything after "@jarvis".'
          : await _aiService.askJarvis(question, recentMessages: recent);
      await _chatService.postJarvisDirectMessage(widget.threadId, reply);
    } catch (e) {
      debugPrint('Jarvis DM reply failed: $e');
      await _chatService.postJarvisDirectMessage(
        widget.threadId,
        'Sorry, I could not answer that right now. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _jarvisThinking = false);
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    try {
      await _chatService.sendDirectMessage(widget.threadId, text);
      _messageController.clear();
      // Your own line posts first either way, so the thread reads in order.
      final question = Jarvis.extractQuestion(text);
      if (question != null) _handleJarvis(question);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            // reverse:true puts the newest message at offset 0.
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sending message: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        title: GestureDetector(
          onTap: () =>
              showUserProfile(context: context, email: widget.otherEmail),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                ProfileCache.instance.nameFor(widget.otherEmail),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                widget.otherEmail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: NeonBackground(
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _chatService.getDirectMessages(widget.threadId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SkeletonChat();
                    }

                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Text(
                          'No messages yet. Say hello!',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      );
                    }

                    final messages = snapshot.data!.docs;

                    // Reversed so the thread opens on the latest message.
                    final ordered = messages.reversed.toList();

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: ordered.length + (_jarvisThinking ? 1 : 0),
                      itemBuilder: (context, rawIndex) {
                        // Index 0 is the newest under reverse:true, so the
                        // thinking row belongs at the front.
                        if (_jarvisThinking && rawIndex == 0) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const JarvisAvatar(radius: 14),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    height: 13,
                                    width: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Jarvis is thinking...',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final index = _jarvisThinking ? rawIndex - 1 : rawIndex;
                        final doc = ordered[index];
                        final message = doc.data() as Map<String, dynamic>;
                        final messageId = doc.id;
                        final text = message['text'] ?? '';
                        final senderEmail = message['senderEmail'] ?? '';
                        final isJarvis = Jarvis.isJarvis(senderEmail);
                        final isMe = senderEmail == currentUserEmail;
                        final timestamp = (message['timestamp'] as Timestamp?)
                            ?.toDate();
                        final reactionKeys = List<String>.from(
                          message['reactions'] ?? const <String>[],
                        );

                        void toggle(String emoji) {
                          _chatService.toggleDirectMessageReaction(
                            widget.threadId,
                            messageId,
                            emoji,
                          );
                        }

                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ReactableMessage(
                            reactionKeys: reactionKeys,
                            currentUserEmail: currentUserEmail ?? '',
                            onToggle: toggle,
                            alignEnd: isMe,
                            // A Jarvis turn is labelled, so a bot reply is
                            // never mistaken for the other person speaking.
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isJarvis)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 4,
                                      left: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const JarvisAvatar(radius: 9),
                                        const SizedBox(width: 6),
                                        Text(
                                          Jarvis.displayName,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.brass,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width * 0.7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? colorScheme.primary
                                        : (isDark
                                              ? colorScheme.surfaceContainerHigh
                                              : colorScheme.surface),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        text,
                                        style: TextStyle(
                                          color: isMe
                                              ? colorScheme.onPrimary
                                              : colorScheme.onSurface,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (timestamp != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatTime(timestamp),
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: isMe
                                                ? colorScheme.onPrimary
                                                      .withValues(alpha: 0.7)
                                                : colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceContainerHigh
                      : colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? colorScheme.surfaceContainerHigh
                              : colorScheme.surfaceContainerLow,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                        style: TextStyle(color: colorScheme.onSurface),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: colorScheme.primary,
                      child: IconButton(
                        icon: Icon(
                          Icons.send,
                          color: colorScheme.onPrimary,
                          size: 20,
                        ),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    ActiveChat.leave('dm:' + widget.threadId);
    ProfileCache.instance.removeListener(_onProfilesChanged);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

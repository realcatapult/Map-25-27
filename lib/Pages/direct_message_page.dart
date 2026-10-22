import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:login_ui/components/image_source_sheet.dart';
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
  final ImagePicker _imagePicker = ImagePicker();
  bool _jarvisThinking = false;
  bool _isSendingImage = false;

  /// The other person's receipt, so we can mark our own messages seen.
  DateTime? _theirLastRead;

  @override
  void initState() {
    super.initState();
    ProfileCache.instance.addListener(_onProfilesChanged);
    ActiveChat.enter('dm:${widget.threadId}');

    // Being here is what "read" means.
    _chatService.markDirectThreadRead(widget.threadId);

    _threadSub = _chatService.watchDirectThread(widget.threadId).listen((doc) {
      final map = doc.data()?['lastRead'];
      if (map is! Map) return;
      final theirs = map[widget.otherEmail];
      if (!mounted) return;
      setState(() {
        _theirLastRead = theirs is Timestamp ? theirs.toDate() : null;
      });
    });
  }

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _threadSub;

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
      _scrollToLatest();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sending message: $e')));
      }
    }
  }

  void _scrollToLatest() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        // reverse:true puts the newest message at offset 0.
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendImage() async {
    final source = await showImageSourceSheet(context);
    if (source == null) return;

    try {
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (image == null) return;
      setState(() => _isSendingImage = true);

      final imageUrl = await _chatService.uploadDirectMessageImage(
        File(image.path),
        widget.threadId,
      );
      // Anything typed goes along as the caption.
      final caption = _messageController.text.trim();
      await _chatService.sendDirectMessage(
        widget.threadId,
        caption,
        imageUrl: imageUrl,
      );
      _messageController.clear();
      _scrollToLatest();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sending image: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSendingImage = false);
    }
  }

  Future<void> _unsend(String messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsend message?'),
        content: const Text('This removes the message for both of you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unsend'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _chatService.unsendDirectMessage(widget.threadId, messageId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not unsend: $e')));
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
              // Address deliberately omitted: the header names the person,
              // and their profile is one tap away if you need the rest.
              const Text(
                'Tap for profile',
                style: TextStyle(color: Colors.white70, fontSize: 10.5),
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
                        final imageUrl = message['imageUrl'] as String?;
                        final senderEmail = message['senderEmail'] ?? '';
                        final isJarvis = Jarvis.isJarvis(senderEmail);
                        final isMe = senderEmail == currentUserEmail;
                        final timestamp = (message['timestamp'] as Timestamp?)
                            ?.toDate();

                        if (message['unsent'] == true) {
                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              child: Text(
                                isMe
                                    ? 'You unsent a message'
                                    : '${ProfileCache.instance.nameFor(senderEmail)} unsent a message',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          );
                        }
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

                        // Only the latest of my own messages carries a
                        // receipt, and only once they have actually read it.
                        final isMyLatest =
                            isMe &&
                            !ordered
                                .take(index)
                                .any(
                                  (d) =>
                                      (d.data()
                                          as Map<
                                            String,
                                            dynamic
                                          >)['senderEmail'] ==
                                      currentUserEmail,
                                );
                        final seen =
                            isMyLatest &&
                            timestamp != null &&
                            _theirLastRead != null &&
                            !_theirLastRead!.isBefore(timestamp);

                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ReactableMessage(
                            reactionKeys: reactionKeys,
                            currentUserEmail: currentUserEmail ?? '',
                            onToggle: toggle,
                            alignEnd: isMe,
                            actions: [
                              if (isMe)
                                MessageAction(
                                  icon: Icons.undo,
                                  label: 'Unsend',
                                  destructive: true,
                                  onTap: () => _unsend(messageId),
                                ),
                            ],
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
                                      if (imageUrl != null) ...[
                                        GestureDetector(
                                          onTap: () => showDialog(
                                            context: context,
                                            builder: (context) => Dialog(
                                              child: InteractiveViewer(
                                                child: CachedNetworkImage(
                                                  imageUrl: imageUrl,
                                                ),
                                              ),
                                            ),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: CachedNetworkImage(
                                              imageUrl: imageUrl,
                                              width: 200,
                                              fit: BoxFit.cover,
                                              memCacheWidth: 600,
                                              placeholder: (context, url) =>
                                                  const SizedBox(
                                                    width: 200,
                                                    height: 200,
                                                    child: Center(
                                                      child:
                                                          CircularProgressIndicator(),
                                                    ),
                                                  ),
                                            ),
                                          ),
                                        ),
                                        if (text.isNotEmpty)
                                          const SizedBox(height: 8),
                                      ],
                                      if (text.isNotEmpty)
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
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _formatTime(timestamp),
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: isMe
                                                    ? colorScheme.onPrimary
                                                          .withValues(
                                                            alpha: 0.7,
                                                          )
                                                    : colorScheme
                                                          .onSurfaceVariant,
                                              ),
                                            ),
                                            // Receipt rides the timestamp of
                                            // my newest message only.
                                            if (seen) ...[
                                              const SizedBox(width: 5),
                                              Icon(
                                                Icons.done_all,
                                                size: 11,
                                                color: colorScheme.onPrimary
                                                    .withValues(alpha: 0.85),
                                              ),
                                              const SizedBox(width: 2),
                                              Text(
                                                'Seen',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  color: colorScheme.onPrimary
                                                      .withValues(alpha: 0.85),
                                                ),
                                              ),
                                            ],
                                          ],
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
                    _isSendingImage
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: Icon(
                              Icons.add_photo_alternate_outlined,
                              color: colorScheme.primary,
                            ),
                            tooltip: 'Send a picture',
                            onPressed: _sendImage,
                          ),
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
    _threadSub?.cancel();
    ActiveChat.leave('dm:${widget.threadId}');
    ProfileCache.instance.removeListener(_onProfilesChanged);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

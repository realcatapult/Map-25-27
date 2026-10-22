import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:login_ui/Pages/direct_message_page.dart';
import 'package:login_ui/Pages/group_roles_page.dart';
import 'package:login_ui/components/jarvis_avatar.dart';
import 'package:login_ui/components/message_reactions.dart';
import 'package:login_ui/components/member_list_sheet.dart';
import 'package:login_ui/services/profile_cache.dart';
import 'package:login_ui/services/message_alerts.dart';
import 'package:login_ui/components/user_profile_sheet.dart';
import 'package:login_ui/Pages/club_day_page.dart';
import 'package:login_ui/Pages/club_stats_page.dart';
import 'package:login_ui/Pages/join_requests_page.dart';
import 'package:login_ui/services/join_request_service.dart';
import 'package:login_ui/data/interests_catalog.dart';
import 'package:login_ui/data/club_roles.dart';
import 'package:login_ui/services/ai_service.dart';
import 'package:login_ui/services/chat_service.dart';
import 'package:login_ui/theme/app_theme.dart';
import 'package:login_ui/components/skeleton_loader.dart';

class ChatRoomPage extends StatefulWidget {
  final String groupId;
  final String groupName;

  const ChatRoomPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final ChatService _chatService = ChatService();
  final AiService _aiService = AiService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final Map<String, String?> _profilePictureCache = {};

  bool _isSending = false;
  bool _jarvisThinking = false;
  Map<String, dynamic>? _replyContext;
  String? _activeThreadRootId;

  IconData _iconFromName(String name) {
    switch (name) {
      case 'sports':
        return Icons.sports_basketball;
      case 'school':
        return Icons.school;
      case 'chat':
        return Icons.chat_bubble;
      case 'star':
        return Icons.star;
      default:
        return Icons.group;
    }
  }

  /// Real name where we have one. The cache resolves it in the background
  /// and notifies, so a header that starts as the email's local part becomes
  /// the person's actual name a moment later.
  String _displayName(String email) {
    if (Jarvis.isJarvis(email)) return Jarvis.displayName;
    if (!email.contains('@')) return email;
    return ProfileCache.instance.nameFor(email);
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<String?> _getProfilePicture(String email) async {
    if (_profilePictureCache.containsKey(email)) {
      return _profilePictureCache[email];
    }
    final url = await _chatService.getProfilePicture(email);
    _profilePictureCache[email] = url;
    return url;
  }

  List<QueryDocumentSnapshot> _filteredMessages(
    List<QueryDocumentSnapshot> docs,
  ) {
    if (_activeThreadRootId == null) return docs;
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return doc.id == _activeThreadRootId ||
          data['threadRootId'] == _activeThreadRootId;
    }).toList();
  }

  int _replyCountForMessage(
    String messageId,
    List<QueryDocumentSnapshot> docs,
  ) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['threadRootId'] == messageId;
    }).length;
  }

  void _setReplyContext(String messageId, Map<String, dynamic> message) {
    final preview = ((message['text'] as String?) ?? '').trim();
    final sender = (message['senderEmail'] as String?) ?? '';
    setState(() {
      _replyContext = {
        'id': messageId,
        'threadRootId': (message['threadRootId'] as String?) ?? messageId,
        'preview': preview.isEmpty ? 'Attachment' : preview,
        'sender': sender,
      };
    });
  }

  void _clearReplyContext() {
    setState(() {
      _replyContext = null;
    });
  }

  void _openThread(String rootMessageId) {
    setState(() {
      _activeThreadRootId = rootMessageId;
    });
  }

  void _closeThread() {
    setState(() {
      _activeThreadRootId = null;
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          // reverse:true puts the newest message at offset 0.
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _closeInputDialog(BuildContext dialogContext) async {
    FocusScope.of(dialogContext).unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!dialogContext.mounted) return;
    Navigator.of(dialogContext).pop();
  }

  Future<void> _showAddEventDialog(String groupName) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = const TimeOfDay(hour: 18, minute: 0);
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Event name',
                    hintText: 'e.g. Club meeting',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Today'),
                        onPressed: () => setDialogState(() {
                          selectedDate = DateTime.now();
                        }),
                      ),
                      ActionChip(
                        label: const Text('Tomorrow'),
                        onPressed: () => setDialogState(() {
                          selectedDate = DateTime.now().add(
                            const Duration(days: 1),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date'),
                  subtitle: Text(
                    '${selectedDate.month}/${selectedDate.day}/${selectedDate.year}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(
                        const Duration(days: 365 * 5),
                      ),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedDate = picked;
                      });
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Time'),
                  subtitle: Text(selectedTime.format(context)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedTime = picked;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _closeInputDialog(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final title = titleController.text.trim();
                      if (title.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter an event name to continue.'),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      final eventDateTime = DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                        selectedTime.hour,
                        selectedTime.minute,
                      );
                      try {
                        await _chatService.addGroupEvent(
                          widget.groupId,
                          groupName,
                          title,
                          descriptionController.text.trim(),
                          eventDateTime,
                        );
                        if (!mounted || !dialogContext.mounted) return;
                        await _closeInputDialog(dialogContext);
                        _scrollToBottom();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Event added to calendar and chat'),
                          ),
                        );
                      } catch (e) {
                        if (!mounted || !dialogContext.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error adding event: $e')),
                        );
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    titleController.dispose();
    descriptionController.dispose();
  }

  Future<void> _showCreateContentSheet() async {
    Map<String, dynamic>? groupData;
    try {
      final groupSnapshot = await _chatService.getGroup(widget.groupId);
      groupData = groupSnapshot.data() as Map<String, dynamic>?;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load group permissions: $error')),
      );
      return;
    }
    if (groupData == null || !mounted) return;

    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final canManageEvents = _chatService.hasGroupPermission(
      groupData,
      email,
      'manage_events',
    );
    final canPostAnnouncements = _chatService.hasGroupPermission(
      groupData,
      email,
      'post_announcements',
    );
    final selectedAction = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text('Share with your club'),
              subtitle: Text('Choose what you want to post.'),
            ),
            if (canManageEvents)
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('Create an event'),
                subtitle: const Text('Add it to the calendar and chat.'),
                onTap: () => Navigator.pop(context, 'event'),
              ),
            if (canPostAnnouncements)
              ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: const Text('Post an announcement'),
                subtitle: const Text('Share an update in the chat.'),
                onTap: () => Navigator.pop(context, 'announcement'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;

    if (selectedAction == 'event') {
      await _showAddEventDialog(widget.groupName);
    } else if (selectedAction == 'announcement') {
      await _showAnnouncementDialog();
    }
  }

  Future<void> _showAnnouncementDialog() async {
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    bool isSaving = false;
    String? validationMessage;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Post an announcement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (validationMessage != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              TextField(
                controller: titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Headline',
                  hintText: 'What should everyone know?',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Details',
                  hintText: 'Add the important details',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _closeInputDialog(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (titleController.text.trim().isEmpty ||
                          messageController.text.trim().isEmpty) {
                        setDialogState(() {
                          validationMessage =
                              'Add a headline and details to continue.';
                        });
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      try {
                        await _chatService.postAnnouncement(
                          widget.groupId,
                          title: titleController.text,
                          message: messageController.text,
                        );
                        if (!mounted || !dialogContext.mounted) return;
                        await _closeInputDialog(dialogContext);
                        _scrollToBottom();
                      } catch (error) {
                        if (!mounted || !dialogContext.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Could not post announcement: $error',
                            ),
                          ),
                        );
                        setDialogState(() => isSaving = false);
                      }
                    },
              icon: const Icon(Icons.send_outlined),
              label: const Text('Post'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    messageController.dispose();
  }

  Future<void> _showGroupSettingsDialog(
    Map<String, dynamic> groupData,
    List<String> members,
    String createdBy,
    bool canManageSettings,
  ) async {
    if (!canManageSettings) return;

    String whoCanPost = groupData['whoCanPost'] ?? 'all';
    int themeColor = groupData['themeColor'] ?? Colors.grey[900]!.toARGB32();
    String themeIcon = groupData['themeIcon'] ?? 'group';
    final bool isPublic = groupData['isPublic'] as bool? ?? false;
    final String publicRequestStatus =
        (groupData['publicRequestStatus'] as String?) ?? 'none';
    final keywordsController = TextEditingController(
      text: List<String>.from(
        groupData['keywords'] ?? const <String>[],
      ).join(', '),
    );
    final roomNumberController = TextEditingController(
      text: (groupData['roomNumber'] as String?) ?? '',
    );
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Group Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Club visibility'),
                  subtitle: Text(
                    isPublic
                        ? 'This club is public and joinable from discovery.'
                        : publicRequestStatus == 'pending'
                        ? 'Public listing request is waiting for school admin approval.'
                        : publicRequestStatus == 'rejected'
                        ? 'A school admin rejected the last public listing request.'
                        : 'This club is private and hidden from discovery.',
                  ),
                  trailing: _buildVisibilityActionChip(
                    context,
                    isPublic: isPublic,
                    publicRequestStatus: publicRequestStatus,
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: whoCanPost,
                  decoration: const InputDecoration(labelText: 'Who can post'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All members')),
                    DropdownMenuItem(
                      value: 'admins',
                      child: Text('Members with posting permission'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => whoCanPost = value);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: roomNumberController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Club meeting room',
                    hintText: 'e.g. Room 204',
                    helperText: 'Shown on club listings and event details.',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                if (createdBy == FirebaseAuth.instance.currentUser?.email) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('Roles & permissions'),
                      subtitle: Text(
                        '${(groupData['roles'] as List?)?.length ?? ClubRole.builtInRoles.length} roles · Assign titles and access',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupRolesPage(
                              groupId: widget.groupId,
                              members: members,
                              groupData: groupData,
                              ownerEmail: createdBy,
                            ),
                          ),
                        );
                        if (context.mounted) setDialogState(() {});
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Theme color',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children:
                      [
                        AppColors.navy,
                        AppColors.brass,
                        Colors.blue,
                        Colors.green,
                        Colors.orange,
                      ].map((color) {
                        final isSelected = themeColor == color.toARGB32();
                        return GestureDetector(
                          onTap: () => setDialogState(
                            () => themeColor = color.toARGB32(),
                          ),
                          child: CircleAvatar(
                            radius: isSelected ? 16 : 14,
                            backgroundColor: color,
                            child: isSelected
                                ? const Icon(Icons.check, color: Colors.white)
                                : null,
                          ),
                        );
                      }).toList(),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Theme icon',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['group', 'sports', 'school', 'chat', 'star'].map((
                    name,
                  ) {
                    return ChoiceChip(
                      label: Icon(_iconFromName(name)),
                      selected: themeIcon == name,
                      onSelected: (_) => setDialogState(() => themeIcon = name),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: keywordsController,
                  decoration: const InputDecoration(
                    labelText: 'Club keywords',
                    hintText: 'Math, Chemistry, STEM, Law...',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: InterestsCatalog.all.take(18).map((keyword) {
                    return ActionChip(
                      label: Text(keyword),
                      onPressed: () {
                        final existing = keywordsController.text
                            .split(',')
                            .map((value) => value.trim())
                            .where((value) => value.isNotEmpty)
                            .toList();
                        if (existing.any(
                          (value) =>
                              value.toLowerCase() == keyword.toLowerCase(),
                        )) {
                          return;
                        }
                        setDialogState(() {
                          existing.add(keyword);
                          keywordsController.text = existing.join(', ');
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _closeInputDialog(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final keywords = InterestsCatalog.normalize(
                  keywordsController.text
                      .split(',')
                      .map((value) => value.trim())
                      .toList(),
                );
                try {
                  await _chatService.updateGroupSettings(
                    widget.groupId,
                    whoCanPost: whoCanPost,
                    themeColor: themeColor,
                    themeIcon: themeIcon,
                    keywords: keywords,
                    roomNumber: roomNumberController.text,
                  );
                  if (!mounted || !dialogContext.mounted) return;
                  await _closeInputDialog(dialogContext);
                } catch (error) {
                  if (!mounted || !dialogContext.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not save group settings: $error'),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    keywordsController.dispose();
    roomNumberController.dispose();
  }

  Widget _buildVisibilityActionChip(
    BuildContext context, {
    required bool isPublic,
    required String publicRequestStatus,
  }) {
    if (isPublic) {
      return ActionChip(
        label: const Text('Make private'),
        onPressed: () async {
          await _chatService.setGroupPrivate(widget.groupId);
          if (!context.mounted) return;
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Club removed from discovery.')),
          );
        },
      );
    }

    if (publicRequestStatus == 'pending') {
      return ActionChip(
        label: const Text('Cancel request'),
        onPressed: () async {
          await _chatService.cancelPublicApprovalRequest(widget.groupId);
          if (!context.mounted) return;
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Public listing request cancelled.')),
          );
        },
      );
    }

    return ActionChip(
      label: const Text('Request approval'),
      onPressed: () async {
        await _chatService.requestPublicApproval(widget.groupId);
        if (!context.mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'School admin approval requested for public listing.',
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDirectMessage(String otherEmail) async {
    try {
      final threadId = await _chatService.getOrCreateDirectMessage(otherEmail);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              DirectMessagePage(threadId: threadId, otherEmail: otherEmail),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error opening DM: $e')));
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    try {
      await _chatService.sendMessage(
        widget.groupId,
        text,
        replyToMessageId: _replyContext?['id'] as String?,
        replyToText: _replyContext?['preview'] as String?,
        replyToSender: _replyContext?['sender'] as String?,
        threadRootId:
            (_replyContext?['threadRootId'] as String?) ?? _activeThreadRootId,
      );
      _messageController.clear();
      _clearReplyContext();
      _scrollToBottom();

      final question = Jarvis.extractQuestion(text);
      if (question != null) {
        _handleJarvis(question);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sending message: $e')));
    }
  }

  Future<void> _handleJarvis(String question) async {
    setState(() => _jarvisThinking = true);
    _scrollToBottom();

    try {
      final chatContext = await _chatService.getRecentGroupMessages(
        widget.groupId,
        limit: 10,
      );
      final reply = question.isEmpty
          ? 'Hi! Ask me anything after "@jarvis".'
          : await _aiService.askJarvis(question, recentMessages: chatContext);
      await _chatService.postJarvisMessage(widget.groupId, reply);
    } catch (e) {
      debugPrint('Jarvis in-chat reply failed: $e');
      await _chatService.postJarvisMessage(
        widget.groupId,
        'Sorry, I could not answer that right now. Please try again.',
      );
    } finally {
      if (!mounted) return;
      setState(() => _jarvisThinking = false);
      _scrollToBottom();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // Phone photos are often 5MB+; this keeps uploads quick and cheap.
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (image == null) return;
      setState(() => _isSending = true);

      final imageUrl = await _chatService.uploadImage(
        File(image.path),
        widget.groupId,
      );
      await _chatService.sendMessage(
        widget.groupId,
        '',
        imageUrl: imageUrl,
        type: 'image',
        replyToMessageId: _replyContext?['id'] as String?,
        replyToText: _replyContext?['preview'] as String?,
        replyToSender: _replyContext?['sender'] as String?,
        threadRootId:
            (_replyContext?['threadRootId'] as String?) ?? _activeThreadRootId,
      );
      _clearReplyContext();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sending image: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;
      final pickedFile = result.files.single;
      if (pickedFile.path == null) return;

      setState(() => _isSending = true);
      final uploaded = await _chatService.uploadGroupFile(
        File(pickedFile.path!),
        widget.groupId,
        pickedFile.name,
      );
      await _chatService.sendMessage(
        widget.groupId,
        '',
        type: 'file',
        file: uploaded,
        replyToMessageId: _replyContext?['id'] as String?,
        replyToText: _replyContext?['preview'] as String?,
        replyToSender: _replyContext?['sender'] as String?,
        threadRootId:
            (_replyContext?['threadRootId'] as String?) ?? _activeThreadRootId,
      );
      _clearReplyContext();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sending file: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Image'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showImageSourceDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('File'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.poll_outlined),
              title: const Text('Poll'),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (!mounted) return;
                // Open poll composer on next frame after sheet has fully closed.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _showPollComposer();
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPollComposer() async {
    final pageContext = context;
    final questionController = TextEditingController();
    final optionsController = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: pageContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogStateContext, setDialogState) => AlertDialog(
          title: const Text('Create Poll'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: questionController,
                decoration: const InputDecoration(labelText: 'Question'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: optionsController,
                decoration: const InputDecoration(
                  labelText: 'Options',
                  hintText: 'One option per line',
                ),
                minLines: 3,
                maxLines: 5,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _closeInputDialog(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final question = questionController.text.trim();
                      final options = optionsController.text
                          .split('\n')
                          .map((value) => value.trim())
                          .where((value) => value.isNotEmpty)
                          .toList();
                      if (question.isEmpty || options.length < 2) return;
                      setDialogState(() => isSaving = true);
                      try {
                        await _chatService.sendPoll(
                          widget.groupId,
                          question: question,
                          options: options,
                        );
                        if (!mounted || !dialogStateContext.mounted) return;
                        await _closeInputDialog(dialogContext);
                        _scrollToBottom();
                      } catch (e) {
                        if (!mounted || !dialogStateContext.mounted) return;
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(content: Text('Error creating poll: $e')),
                        );
                        if (dialogStateContext.mounted) {
                          setDialogState(() => isSaving = false);
                        }
                      }
                    },
              child: const Text('Post poll'),
            ),
          ],
        ),
      ),
    );

    questionController.dispose();
    optionsController.dispose();
  }

  Future<void> _showMessageActions({
    required String messageId,
    required Map<String, dynamic> message,
    required int replyCount,
    required bool canModerateMessages,
  }) async {
    // An unsent message is only a placeholder; there is nothing to act on.
    if (message['unsent'] == true) return;

    final myEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    final reactionKeys = List<String>.from(
      message['reactions'] ?? const <String>[],
    );
    final mine = MessageReactions.myEmojis(reactionKeys, myEmail);
    final isMyMessage = myEmail.isNotEmpty && message['senderEmail'] == myEmail;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: MessageReactions.palette.map((emoji) {
                  final isOn = mine.contains(emoji);
                  return InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      Navigator.pop(context);
                      _chatService.toggleMessageReaction(
                        widget.groupId,
                        messageId,
                        emoji,
                      );
                    },
                    child: Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: isOn
                          ? BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            )
                          : null,
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                _setReplyContext(messageId, message);
              },
            ),
            if (replyCount > 0 || message['threadRootId'] != null)
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: const Text('View thread'),
                onTap: () {
                  Navigator.pop(context);
                  _openThread(
                    (message['threadRootId'] as String?) ?? messageId,
                  );
                },
              ),
            if (canModerateMessages)
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: const Text('Pin message'),
                onTap: () async {
                  Navigator.pop(context);
                  await _chatService.pinMessage(
                    widget.groupId,
                    messageId,
                    message,
                  );
                },
              ),
            if (isMyMessage)
              ListTile(
                leading: Icon(
                  Icons.undo,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Unsend',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _unsendMessage(messageId);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsentBubble(String label, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Future<void> _unsendMessage(String messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsend message?'),
        content: const Text(
          'This removes the message for everyone in the chat.',
        ),
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
      await _chatService.unsendMessage(widget.groupId, messageId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not unsend: $e')));
    }
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text(
          'Are you sure you want to leave this group? You will need a join code to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _chatService.leaveGroup(widget.groupId);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Left group')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error leaving group: $e')));
    }
  }

  Widget _buildClubPostCard(
    Map<String, dynamic> message,
    Color accentColor,
    String roomNumber,
  ) {
    final isEvent = message['type'] == 'event';
    final eventDate = (message['eventDate'] as Timestamp?)?.toDate();
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isEvent ? Icons.event_outlined : Icons.campaign_outlined,
                size: 17,
                color: accentColor,
              ),
              const SizedBox(width: 6),
              Text(
                isEvent ? 'CLUB EVENT' : 'ANNOUNCEMENT',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (message['title'] as String?) ?? 'Club update',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (eventDate != null) ...[
            const SizedBox(height: 4),
            Text(
              '${eventDate.month}/${eventDate.day}/${eventDate.year} · ${_formatTime(eventDate)}',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          if (isEvent) ...[
            const SizedBox(height: 4),
            Text(
              'Hosted by ${widget.groupName}',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            if (roomNumber.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Room $roomNumber',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
          if ((message['text'] as String? ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              (message['text'] as String).trim(),
              style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReplyPreview(
    Map<String, dynamic> message,
    Color textColor,
    Color mutedColor, {
    bool originalUnsent = false,
  }) {
    final replyText = originalUnsent
        ? 'Message unsent'
        : (message['replyToText'] as String?) ?? '';
    final replySender = (message['replyToSender'] as String?) ?? '';
    if (replyText.isEmpty && replySender.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _displayName(replySender),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: mutedColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            replyText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildFileAttachment(
    BuildContext context,
    Map<String, dynamic> fileData,
    Color textColor,
    Color mutedColor,
  ) {
    final fileName = (fileData['name'] as String?) ?? 'Attachment';
    final fileUrl = (fileData['url'] as String?) ?? '';
    final fileSize = _formatFileSize(fileData['sizeBytes'] as int?);
    final extension = (fileData['extension'] as String?) ?? '';

    return InkWell(
      onTap: fileUrl.isEmpty
          ? null
          : () async {
              await Clipboard.setData(ClipboardData(text: fileUrl));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Attachment link copied.')),
              );
            },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.insert_drive_file_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (fileSize.isNotEmpty || extension.isNotEmpty)
                    Text(
                      [
                        if (extension.isNotEmpty) extension.toUpperCase(),
                        if (fileSize.isNotEmpty) fileSize,
                      ].join(' • '),
                      style: TextStyle(fontSize: 11, color: mutedColor),
                    ),
                ],
              ),
            ),
            Icon(Icons.copy, size: 16, color: mutedColor),
          ],
        ),
      ),
    );
  }

  Widget _buildPollCard(
    String messageId,
    Map<String, dynamic> poll,
    String currentUserEmail,
    Color accentColor,
    Color textColor,
    Color mutedColor,
  ) {
    final question = (poll['question'] as String?) ?? 'Poll';
    final options = List<Map<String, dynamic>>.from(
      (poll['options'] as List? ?? const <dynamic>[]).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final votes = Map<String, dynamic>.from(poll['votes'] ?? const {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...options.map((option) {
          final optionId = option['id'] as String? ?? '';
          final label = option['label'] as String? ?? 'Option';
          final voters = List<String>.from(votes[optionId] ?? const <String>[]);
          final isSelected = voters.contains(currentUserEmail);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => _chatService.togglePollVote(
                widget.groupId,
                messageId,
                optionId,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor.withValues(alpha: 0.14)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? accentColor.withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label, style: TextStyle(color: textColor)),
                    ),
                    Text(
                      '${voters.length}',
                      style: TextStyle(
                        color: isSelected ? accentColor : mutedColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTappableAvatar(
    String email,
    bool isDark,
    ColorScheme colorScheme,
    Map<String, dynamic>? groupData,
    Color accent,
  ) {
    return GestureDetector(
      onTap: () => showUserProfile(
        context: context,
        email: email,
        groupData: groupData,
        accent: accent,
      ),
      child: _buildAvatar(email, isDark, colorScheme),
    );
  }

  Widget _buildAvatar(String email, bool isDark, ColorScheme colorScheme) {
    if (Jarvis.isJarvis(email)) {
      return const JarvisAvatar(radius: 16);
    }

    return FutureBuilder<String?>(
      future: _getProfilePicture(email),
      builder: (context, snapshot) {
        return CircleAvatar(
          radius: 16,
          backgroundColor: isDark
              ? colorScheme.surfaceContainerHigh
              : colorScheme.surfaceContainerHighest,
          backgroundImage: snapshot.hasData && snapshot.data != null
              ? CachedNetworkImageProvider(snapshot.data!, maxWidth: 120)
              : null,
          child: snapshot.hasData && snapshot.data != null
              ? null
              : Text(
                  email.isNotEmpty ? email[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email;
    final currentUserEmailSafe = currentUserEmail ?? '';
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<DocumentSnapshot>(
      stream: _chatService.watchGroup(widget.groupId),
      builder: (context, groupSnapshot) {
        final groupData = groupSnapshot.data?.data() as Map<String, dynamic>?;
        final members = List<String>.from(groupData?['members'] ?? []);
        final createdBy = groupData?['createdBy'] ?? '';
        final whoCanPost = groupData?['whoCanPost'] ?? 'all';
        final themeColorValue =
            groupData?['themeColor'] ?? Colors.grey[900]!.toARGB32();
        final themeIconName = groupData?['themeIcon'] ?? 'group';
        final themeColor = Color(themeColorValue);
        final canManageSettings =
            groupData != null &&
            _chatService.hasGroupPermission(
              groupData,
              currentUserEmailSafe,
              'manage_settings',
            );
        final canManageMessages =
            groupData != null &&
            _chatService.hasGroupPermission(
              groupData,
              currentUserEmailSafe,
              'manage_messages',
            );
        final canManageEvents =
            groupData != null &&
            _chatService.hasGroupPermission(
              groupData,
              currentUserEmailSafe,
              'manage_events',
            );
        final canPostAnnouncements =
            groupData != null &&
            _chatService.hasGroupPermission(
              groupData,
              currentUserEmailSafe,
              'post_announcements',
            );
        final canManageCheckIns =
            groupData != null &&
            _chatService.hasGroupPermission(
              groupData,
              currentUserEmailSafe,
              'manage_check_ins',
            );
        final canSend =
            whoCanPost == 'all' ||
            (groupData != null &&
                _chatService.hasGroupPermission(
                  groupData,
                  currentUserEmailSafe,
                  'send_messages',
                ));
        final brightness = ThemeData.estimateBrightnessForColor(themeColor);
        final onThemeColor = brightness == Brightness.dark
            ? Colors.white
            : Colors.black;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: themeColor,
            flexibleSpace: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    themeColor,
                    Color.lerp(themeColor, AppColors.deepBlue, 0.5) ??
                        themeColor,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: onThemeColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _iconFromName(themeIconName),
                      color: onThemeColor,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.groupName,
                        style: TextStyle(color: onThemeColor, fontSize: 18),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${members.length} members',
                  style: TextStyle(
                    color: onThemeColor.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            iconTheme: IconThemeData(color: onThemeColor),
            actions: [
              IconButton(
                icon: const Icon(Icons.people_outline),
                tooltip: 'Members',
                onPressed: () => showMemberList(
                  context: context,
                  groupId: widget.groupId,
                  groupData: groupData ?? const <String, dynamic>{},
                  groupName: widget.groupName,
                  accent: themeColor,
                ),
              ),
              if (canManageCheckIns)
                IconButton(
                  icon: const Icon(Icons.how_to_reg),
                  tooltip: 'Club Day',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClubDayPage(
                        groupId: widget.groupId,
                        groupName: widget.groupName,
                        isAdmin: canManageCheckIns,
                      ),
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More',
                onSelected: (value) {
                  switch (value) {
                    case 'stats':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ClubStatsPage(
                            groupId: widget.groupId,
                            groupName: widget.groupName,
                          ),
                        ),
                      );
                      break;
                    case 'create':
                      _showCreateContentSheet();
                      break;
                    case 'settings':
                      _showGroupSettingsDialog(
                        groupData ?? const <String, dynamic>{},
                        members,
                        createdBy,
                        canManageSettings,
                      );
                      break;
                    case 'requests':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => JoinRequestsPage(
                            groupId: widget.groupId,
                            groupName: widget.groupName,
                          ),
                        ),
                      );
                      break;
                    case 'home':
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      break;
                    case 'leave':
                      _leaveGroup();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (canManageSettings)
                    PopupMenuItem(
                      value: 'requests',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.how_to_reg_outlined),
                        title: const Text('Join requests'),
                        trailing: StreamBuilder<int>(
                          stream: JoinRequestService().watchPendingCount(
                            widget.groupId,
                          ),
                          builder: (context, s) {
                            final n = s.data ?? 0;
                            if (n == 0) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '$n',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  if (canManageCheckIns)
                    const PopupMenuItem(
                      value: 'stats',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.insert_chart_outlined),
                        title: Text('Club statistics'),
                      ),
                    ),
                  if (canManageEvents || canPostAnnouncements)
                    const PopupMenuItem(
                      value: 'create',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.add_circle_outline),
                        title: Text('Event or announcement'),
                      ),
                    ),
                  if (canManageSettings)
                    const PopupMenuItem(
                      value: 'settings',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.settings),
                        title: Text('Group settings'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'home',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.home_outlined),
                      title: Text('Back to home'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'leave',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.exit_to_app, color: Colors.red),
                      title: Text(
                        'Leave group',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () {
                  final joinCode = groupData?['joinCode'] ?? 'N/A';
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Group Info'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Join Code:',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                joinCode,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: joinCode),
                                  );
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Join code copied!'),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Share this code with others to let them join the group.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Members',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...members.map((member) {
                            final isSelf = member == currentUserEmailSafe;
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(member),
                                      Text(
                                        _chatService.groupRoleName(
                                          groupData ?? const {},
                                          member,
                                        ),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isSelf)
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _openDirectMessage(member);
                                    },
                                    child: const Text('Message'),
                                  ),
                              ],
                            );
                          }),
                        ],
                      ),
                      actions: [
                        if (canManageEvents)
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _showAddEventDialog(widget.groupName);
                            },
                            child: const Text('Create Event'),
                          ),
                        if (canPostAnnouncements)
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _showAnnouncementDialog();
                            },
                            child: const Text('Post Announcement'),
                          ),
                        if (canManageSettings)
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _showGroupSettingsDialog(
                                groupData,
                                members,
                                createdBy,
                                canManageSettings,
                              );
                            },
                            child: const Text('Manage Group'),
                          ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _leaveGroup();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('Leave Group'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          body: GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            behavior: HitTestBehavior.translucent,
            child: NeonBackground(
              child: Column(
                children: [
                  if ((groupData?['pinnedMessageId'] as String?) != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: themeColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.push_pin, size: 18, color: themeColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pinned message',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (groupData?['pinnedMessageText']
                                          as String?) ??
                                      '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _openThread(
                              (groupData?['pinnedMessageId'] as String?)!,
                            ),
                            child: const Text('Open'),
                          ),
                          if (canManageMessages)
                            IconButton(
                              onPressed: () => _chatService.clearPinnedMessage(
                                widget.groupId,
                              ),
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _chatService.getMessages(widget.groupId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const SkeletonChat();
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Error: ${snapshot.error}'),
                          );
                        }

                        final allMessages =
                            snapshot.data?.docs ??
                            const <QueryDocumentSnapshot>[];
                        // A reply stores a copy of the text it answers, so
                        // that copy must be hidden once the original is unsent.
                        final unsentIds = {
                          for (final doc in allMessages)
                            if ((doc.data()
                                    as Map<String, dynamic>)['unsent'] ==
                                true)
                              doc.id,
                        };
                        final messages = _filteredMessages(allMessages);
                        if (messages.isEmpty) {
                          return Center(
                            child: Text(
                              _activeThreadRootId == null
                                  ? 'No messages yet. Start the conversation!'
                                  : 'No replies in this thread yet.',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }

                        // Reversed so the room opens on the latest message and
                        // new ones arrive at the resting edge.
                        final ordered = messages.reversed.toList();

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          // A thumb-drag down the transcript puts the
                          // keyboard away, as in Discord and iMessage.
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.all(16),
                          findChildIndexCallback: (key) {
                            if (key is! ValueKey<String>) return null;
                            final index = ordered.indexWhere(
                              (message) => message.id == key.value,
                            );
                            return index < 0 ? null : index;
                          },
                          itemCount: ordered.length + (_jarvisThinking ? 1 : 0),
                          itemBuilder: (context, rawIndex) {
                            // Index 0 is the newest under reverse:true, so the
                            // thinking row belongs at the front.
                            if (_jarvisThinking && rawIndex == 0) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const JarvisAvatar(radius: 16),
                                    const SizedBox(width: 8),
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? colorScheme.surfaceContainerHigh
                                            : colorScheme.surface,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Jarvis is thinking...',
                                            style: TextStyle(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            // The thinking row occupies index 0 while it is
                            // visible, so shift past it.
                            final index = _jarvisThinking
                                ? rawIndex - 1
                                : rawIndex;
                            final messageDoc = ordered[index];
                            final message =
                                messageDoc.data() as Map<String, dynamic>;
                            final messageId = messageDoc.id;
                            final messageType =
                                (message['type'] as String?) ?? 'text';
                            final isClubPost =
                                messageType == 'event' ||
                                messageType == 'announcement';
                            final text = (message['text'] as String?) ?? '';
                            final imageUrl = message['imageUrl'] as String?;
                            final senderEmail =
                                (message['senderEmail'] as String?) ?? '';
                            final isMe = senderEmail == currentUserEmail;
                            final timestamp =
                                (message['timestamp'] as Timestamp?)?.toDate();
                            final fileData = message['file'] == null
                                ? null
                                : Map<String, dynamic>.from(
                                    message['file'] as Map,
                                  );
                            final pollData = message['poll'] == null
                                ? null
                                : Map<String, dynamic>.from(
                                    message['poll'] as Map,
                                  );
                            final reactionKeys = List<String>.from(
                              message['reactions'] ?? const <String>[],
                            );
                            final replyCount = _replyCountForMessage(
                              messageId,
                              allMessages,
                            );
                            final bubbleTextColor = isClubPost
                                ? colorScheme.onSurface
                                : isMe
                                ? onThemeColor
                                : colorScheme.onSurface;
                            final bubbleMutedColor = isClubPost
                                ? colorScheme.onSurfaceVariant
                                : isMe
                                ? onThemeColor.withValues(alpha: 0.72)
                                : colorScheme.onSurfaceVariant;

                            if (message['unsent'] == true) {
                              return Align(
                                key: ValueKey(messageId),
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: _buildUnsentBubble(
                                  isMe
                                      ? 'You unsent a message'
                                      : '${_displayName(senderEmail)} unsent a message',
                                  colorScheme,
                                ),
                              );
                            }

                            return AnimatedEntrance(
                              key: ValueKey(messageId),
                              child: Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Row(
                                  mainAxisAlignment: isMe
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!isMe) ...[
                                      _buildTappableAvatar(
                                        senderEmail,
                                        isDark,
                                        colorScheme,
                                        groupData,
                                        themeColor,
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Flexible(
                                      child: GestureDetector(
                                        onLongPress: () => _showMessageActions(
                                          messageId: messageId,
                                          message: message,
                                          replyCount: replyCount,
                                          canModerateMessages:
                                              canManageMessages,
                                        ),
                                        onDoubleTap: () {
                                          HapticFeedback.lightImpact();
                                          _chatService.toggleMessageReaction(
                                            widget.groupId,
                                            messageId,
                                            MessageReactions.quick,
                                          );
                                        },
                                        child: Column(
                                          crossAxisAlignment: isMe
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 10,
                                                  ),
                                              constraints: BoxConstraints(
                                                maxWidth:
                                                    MediaQuery.of(
                                                      context,
                                                    ).size.width *
                                                    0.74,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isClubPost
                                                    ? colorScheme.surface
                                                    : isMe
                                                    ? themeColor
                                                    : (isDark
                                                          ? colorScheme
                                                                .surfaceContainerHigh
                                                          : colorScheme
                                                                .surface),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: isClubPost
                                                    ? Border.all(
                                                        color: themeColor
                                                            .withValues(
                                                              alpha: 0.35,
                                                            ),
                                                      )
                                                    : null,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  // The name is a link to the
                                                  // person, as in Discord.
                                                  if (!isMe)
                                                    GestureDetector(
                                                      onTap:
                                                          Jarvis.isJarvis(
                                                            senderEmail,
                                                          )
                                                          ? null
                                                          : () => showUserProfile(
                                                              context: context,
                                                              email:
                                                                  senderEmail,
                                                              groupData:
                                                                  groupData,
                                                              accent:
                                                                  themeColor,
                                                            ),
                                                      child: Text(
                                                        _displayName(
                                                          senderEmail,
                                                        ),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              Jarvis.isJarvis(
                                                                senderEmail,
                                                              )
                                                              ? AppColors.brass
                                                              : colorScheme
                                                                    .onSurfaceVariant,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  if (!isMe)
                                                    const SizedBox(height: 4),
                                                  if (!isClubPost)
                                                    _buildReplyPreview(
                                                      message,
                                                      bubbleTextColor,
                                                      bubbleMutedColor,
                                                      originalUnsent: unsentIds
                                                          .contains(
                                                            message['replyToMessageId'],
                                                          ),
                                                    ),
                                                  if (isClubPost)
                                                    _buildClubPostCard(
                                                      message,
                                                      themeColor,
                                                      (groupData?['roomNumber']
                                                                  as String? ??
                                                              '')
                                                          .trim(),
                                                    ),
                                                  if (!isClubPost &&
                                                      pollData != null)
                                                    _buildPollCard(
                                                      messageId,
                                                      pollData,
                                                      currentUserEmailSafe,
                                                      themeColor,
                                                      bubbleTextColor,
                                                      bubbleMutedColor,
                                                    ),
                                                  if (!isClubPost &&
                                                      fileData != null) ...[
                                                    _buildFileAttachment(
                                                      context,
                                                      fileData,
                                                      bubbleTextColor,
                                                      bubbleMutedColor,
                                                    ),
                                                    if (text.isNotEmpty)
                                                      const SizedBox(height: 8),
                                                  ],
                                                  if (!isClubPost &&
                                                      imageUrl != null) ...[
                                                    GestureDetector(
                                                      onTap: () {
                                                        showDialog(
                                                          context: context,
                                                          builder: (context) => Dialog(
                                                            child: InteractiveViewer(
                                                              child:
                                                                  Image.network(
                                                                    imageUrl,
                                                                  ),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                      child: ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        child: CachedNetworkImage(
                                                          imageUrl: imageUrl,
                                                          width: 200,
                                                          fit: BoxFit.cover,
                                                          memCacheWidth: 600,
                                                          placeholder:
                                                              (
                                                                context,
                                                                url,
                                                              ) => const SizedBox(
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
                                                  if (!isClubPost &&
                                                      text.isNotEmpty &&
                                                      pollData == null)
                                                    Text(
                                                      text,
                                                      style: TextStyle(
                                                        color: bubbleTextColor,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  if (timestamp != null) ...[
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      _formatTime(timestamp),
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: bubbleMutedColor,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (replyCount > 0 &&
                                                _activeThreadRootId == null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 6,
                                                  left: 4,
                                                  right: 4,
                                                ),
                                                child: InkWell(
                                                  onTap: () =>
                                                      _openThread(messageId),
                                                  child: Text(
                                                    '$replyCount repl${replyCount == 1 ? 'y' : 'ies'}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: themeColor,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (reactionKeys.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 4,
                                                ),
                                                child: ReactionBadge(
                                                  reactionKeys: reactionKeys,
                                                  currentUserEmail:
                                                      currentUserEmailSafe,
                                                  onToggle: (emoji) =>
                                                      _chatService
                                                          .toggleMessageReaction(
                                                            widget.groupId,
                                                            messageId,
                                                            emoji,
                                                          ),
                                                  onMore: () =>
                                                      _showMessageActions(
                                                        messageId: messageId,
                                                        message: message,
                                                        replyCount: replyCount,
                                                        canModerateMessages:
                                                            canManageMessages,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 8),
                                      _buildTappableAvatar(
                                        senderEmail,
                                        isDark,
                                        colorScheme,
                                        groupData,
                                        themeColor,
                                      ),
                                    ],
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
                      color:
                          (isDark
                                  ? colorScheme.surfaceContainerHigh
                                  : colorScheme.surface)
                              .withValues(alpha: 0.92),
                      border: Border(
                        top: BorderSide(
                          color: AppColors.cyan.withValues(alpha: 0.18),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_activeThreadRootId != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.forum_outlined, size: 18),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text('Replying in thread'),
                                ),
                                TextButton(
                                  onPressed: _closeThread,
                                  child: const Text('Exit'),
                                ),
                              ],
                            ),
                          ),
                        if (_replyContext != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Replying to ${_displayName((_replyContext?['sender'] as String?) ?? '')}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (_replyContext?['preview']
                                                as String?) ??
                                            '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: _clearReplyContext,
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.add_circle_outline,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              onPressed: _isSending || !canSend
                                  ? null
                                  : _showAttachmentSheet,
                            ),
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                decoration: InputDecoration(
                                  hintText: canSend
                                      ? 'Type a message...'
                                      : "You don't have permission to post",
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
                                textCapitalization:
                                    TextCapitalization.sentences,
                                enabled: !_isSending && canSend,
                                onSubmitted: (_) =>
                                    canSend ? _sendMessage() : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            CircleAvatar(
                              backgroundColor: themeColor,
                              child: _isSending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(
                                        Icons.send,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      onPressed: canSend ? _sendMessage : null,
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // Sender names arrive asynchronously; rebuild when they land so a header
    // showing the email's local part becomes the real name.
    ProfileCache.instance.addListener(_onProfilesChanged);
    ActiveChat.enter('group:${widget.groupId}');
  }

  void _onProfilesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ActiveChat.leave('group:${widget.groupId}');
    ProfileCache.instance.removeListener(_onProfilesChanged);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

// Chat list page
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:login_ui/services/chat_service.dart';
import 'package:login_ui/Pages/chat_room_page.dart';
import 'package:login_ui/Pages/friends_page.dart';
import 'package:login_ui/Pages/direct_message_page.dart';
import 'package:login_ui/Pages/admin_activity_page.dart';
import 'package:login_ui/Pages/support_chat_page.dart';
import 'package:login_ui/components/jarvis_avatar.dart';
import 'package:login_ui/data/interests_catalog.dart';
import 'package:login_ui/theme/app_theme.dart';
import 'package:login_ui/components/skeleton_loader.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _membersController = TextEditingController();
  final TextEditingController _joinCodeController = TextEditingController();
  final TextEditingController _overviewController = TextEditingController();
  final TextEditingController _keywordsController = TextEditingController();
  final TextEditingController _roomNumberController = TextEditingController();
  bool _isCreating = false;
  bool _isPublic = true;
  String _whoCanPost = 'all';
  int _themeColor = AppColors.navy.toARGB32();
  String _themeIcon = 'group';
  XFile? _bannerImageFile;

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

  void _showCreateGroupDialog() {
    _bannerImageFile = null;
    _keywordsController.clear();
    _roomNumberController.clear();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Group Chat'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _groupNameController,
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                    hintText: 'e.g., Team Practice',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _overviewController,
                  decoration: const InputDecoration(
                    labelText: 'Club Overview',
                    hintText: 'Brief description of your club...',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _roomNumberController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Club meeting room (optional)',
                    hintText: 'e.g. Room 204',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _keywordsController,
                  decoration: const InputDecoration(
                    labelText: 'Club Keywords',
                    hintText: 'Math, Chemistry, STEM, Law...',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: InterestsCatalog.all.take(14).map((keyword) {
                    return ActionChip(
                      label: Text(keyword),
                      onPressed: () {
                        final existing = _keywordsController.text
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
                        existing.add(keyword);
                        setDialogState(() {
                          _keywordsController.text = existing.join(', ');
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // Banner image picker
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 80,
                    );
                    if (picked != null) {
                      setDialogState(() {
                        _bannerImageFile = picked;
                      });
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[400]!),
                    ),
                    child: _bannerImageFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_bannerImageFile!.path),
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate,
                                size: 32,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add Banner Image',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _membersController,
                  decoration: const InputDecoration(
                    labelText: 'Member Emails',
                    hintText: 'email1@example.com, email2@example.com',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Separate emails with commas',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Request Public Listing'),
                  subtitle: const Text(
                    'Clubs start private and hidden until an admin approves discovery.',
                  ),
                  value: _isPublic,
                  onChanged: (value) {
                    setDialogState(() {
                      _isPublic = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _whoCanPost,
                  decoration: const InputDecoration(labelText: 'Who can post'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All members')),
                    DropdownMenuItem(
                      value: 'admins',
                      child: Text('Members with posting permission'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      _whoCanPost = value;
                    });
                  },
                ),
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
                        final isSelected = _themeColor == color.toARGB32();
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              _themeColor = color.toARGB32();
                            });
                          },
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
                    final isSelected = _themeIcon == name;
                    return ChoiceChip(
                      label: Icon(_iconFromName(name)),
                      selected: isSelected,
                      onSelected: (_) {
                        setDialogState(() {
                          _themeIcon = name;
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _isCreating
                  ? null
                  : () async {
                      if (_groupNameController.text.isNotEmpty) {
                        setDialogState(() {
                          _isCreating = true;
                        });

                        final members = _membersController.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();
                        final keywords = InterestsCatalog.normalize(
                          _keywordsController.text
                              .split(',')
                              .map((value) => value.trim())
                              .toList(),
                        );

                        try {
                          final groupId = await _chatService.createGroupChat(
                            _groupNameController.text,
                            members,
                            _isPublic,
                            _whoCanPost,
                            _themeColor,
                            _themeIcon,
                            keywords,
                            roomNumber: _roomNumberController.text,
                          );

                          // Upload banner if selected
                          String? bannerUrl;
                          if (_bannerImageFile != null) {
                            bannerUrl = await _chatService.uploadGroupBanner(
                              File(_bannerImageFile!.path),
                              groupId,
                            );
                          }

                          // Save overview and banner URL
                          final overview = _overviewController.text.trim();
                          if (overview.isNotEmpty || bannerUrl != null) {
                            await _chatService.updateGroupSettings(
                              groupId,
                              overview: overview.isNotEmpty ? overview : null,
                              bannerUrl: bannerUrl,
                            );
                          }

                          if (context.mounted) {
                            Navigator.pop(context);
                            _groupNameController.clear();
                            _membersController.clear();
                            _overviewController.clear();
                            _keywordsController.clear();
                            _roomNumberController.clear();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _isPublic
                                      ? 'Group created privately. An admin can publish it from group settings.'
                                      : 'Private group created.',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        } finally {
                          setDialogState(() {
                            _isCreating = false;
                          });
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy),
              child: _isCreating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showJoinGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _joinCodeController,
              decoration: const InputDecoration(
                labelText: 'Join Code',
                hintText: 'Enter 6-character code',
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the group join code',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_joinCodeController.text.length == 6) {
                try {
                  await _chatService.joinGroupWithCode(
                    _joinCodeController.text,
                  );
                  if (mounted) {
                    Navigator.pop(context);
                    _joinCodeController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Joined group!')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            child: const Text('Join', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        title: const Text(
          'Messages',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline, color: Colors.white),
            tooltip: 'Friends',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FriendsPage()),
            ),
          ),
          FutureBuilder<bool>(
            future: _chatService.isCurrentUserSchoolAdmin(),
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(
                  Icons.admin_panel_settings,
                  color: Colors.white,
                ),
                tooltip: 'Admin: Club Activity',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminActivityPage(),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: NeonBackground(
        child: StreamBuilder<QuerySnapshot>(
          stream: _chatService.getDirectMessageThreads(),
          builder: (context, dmSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: _chatService.getUserGroups(),
              builder: (context, groupSnapshot) {
                if (dmSnapshot.connectionState == ConnectionState.waiting ||
                    groupSnapshot.connectionState == ConnectionState.waiting) {
                  return const SkeletonList();
                }

                if (dmSnapshot.hasError) {
                  return Center(child: Text('Error: ${dmSnapshot.error}'));
                }

                if (groupSnapshot.hasError) {
                  return Center(child: Text('Error: ${groupSnapshot.error}'));
                }

                final dmDocs = dmSnapshot.data?.docs ?? [];
                final groupDocs = groupSnapshot.data?.docs ?? [];

                // The list can legitimately be empty before joining a group.

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Direct Messages — always shown (Jarvis is pinned here).
                    Text(
                      'Direct Messages',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Pinned Jarvis assistant chat.
                    AnimatedEntrance(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.secondary.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          leading: const JarvisAvatar(radius: 22),
                          title: Text(
                            'Jarvis',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            'Your AI assistant',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SupportChatPage(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    if (dmDocs.isNotEmpty) ...[
                      ...dmDocs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final participants = List<String>.from(
                          data['participants'] ?? [],
                        );
                        final currentEmail =
                            FirebaseAuth.instance.currentUser?.email ?? '';
                        final other = participants.firstWhere(
                          (email) => email != currentEmail,
                          orElse: () => 'Unknown',
                        );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primary,
                              child: Icon(
                                Icons.person,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                            title: Text(
                              other,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DirectMessagePage(
                                    threadId: doc.id,
                                    otherEmail: other,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                    // Group chats, all of them real Firestore groups.
                    ...[
                      Text(
                        'Group Chats',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...groupDocs.map((group) {
                        final groupData = group.data() as Map<String, dynamic>;
                        final groupName = groupData['name'] ?? 'Unnamed Group';
                        final members = List<String>.from(
                          groupData['members'] ?? [],
                        );
                        final isPublic =
                            groupData['isPublic'] as bool? ?? false;
                        final themeColorValue =
                            groupData['themeColor'] ??
                            Colors.grey[800]!.toARGB32();
                        final themeIconName = groupData['themeIcon'] ?? 'group';
                        final themeColor = Color(themeColorValue);
                        final icon = _iconFromName(themeIconName);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: themeColor,
                              child: Icon(icon, color: Colors.white),
                            ),
                            title: Text(
                              groupName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              '${members.length} members • ${isPublic ? 'Discoverable' : 'Private'}',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatRoomPage(
                                    groupId: group.id,
                                    groupName: groupName,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      }),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'join',
            onPressed: _showJoinGroupDialog,
            backgroundColor: colorScheme.secondary,
            child: Icon(Icons.login, color: colorScheme.onSecondary),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'create',
            onPressed: _showCreateGroupDialog,
            backgroundColor: colorScheme.primary,
            child: Icon(Icons.add, color: colorScheme.onPrimary),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _membersController.dispose();
    _joinCodeController.dispose();
    _overviewController.dispose();
    _keywordsController.dispose();
    _roomNumberController.dispose();
    super.dispose();
  }
}

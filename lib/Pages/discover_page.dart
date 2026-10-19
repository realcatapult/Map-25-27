import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:login_ui/services/chat_service.dart';
import 'package:login_ui/Pages/chat_room_page.dart';
import 'package:login_ui/theme/app_theme.dart';
import 'package:login_ui/components/skeleton_loader.dart';

// ── Placeholder demo data ──────────────────────────────────────────────────
class DemoClub {
  final String name;
  final String description;
  final IconData logoIcon;
  final Color logoColor;
  final List<Color> bannerGradient;
  final List<String> keywords;
  final String firstStep;
  final String? bannerImage;

  const DemoClub({
    required this.name,
    required this.description,
    required this.logoIcon,
    required this.logoColor,
    required this.bannerGradient,
    required this.keywords,
    required this.firstStep,
    this.bannerImage,
  });
}

const List<DemoClub> demoClubs = [
  DemoClub(
    name: 'Photography Club',
    description:
        'Capture moments and explore the art of photography with fellow enthusiasts. Weekly photo walks, editing workshops, and gallery showcases.',
    logoIcon: Icons.camera_alt,
    logoColor: Color(0xFF1565C0),
    bannerGradient: [Color(0xFF1565C0), Color(0xFF42A5F5)],
    keywords: ['Photography', 'Art', 'Design', 'Culture'],
    firstStep: 'Join a weekly photo walk.',
    bannerImage: 'lib/images/PhotoBanner.jpeg',
  ),
  DemoClub(
    name: 'Coding Club',
    description:
        'Build projects, learn new technologies, and collaborate with passionate developers. Hackathons, code reviews, and mentorship sessions every week.',
    logoIcon: Icons.code,
    logoColor: Color(0xFF2E7D32),
    bannerGradient: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
    keywords: ['Coding', 'STEM', 'AI', 'Engineering'],
    firstStep: 'Explore a project with other members.',
    bannerImage: 'lib/images/codingclub.jpeg',
  ),
  DemoClub(
    name: 'Chess Club',
    description:
        'Sharpen your strategic thinking and compete in weekly tournaments. All skill levels welcome — beginners receive free coaching from experienced players.',
    logoIcon: Icons.extension,
    logoColor: Color(0xFF6A1B9A),
    bannerGradient: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
    keywords: ['Chess', 'Math', 'Strategy'],
    firstStep: 'Get free coaching from experienced players.',
    bannerImage: 'lib/images/chess.jpeg',
  ),
  DemoClub(
    name: 'Hiking & Outdoors',
    description:
        'Explore scenic trails and connect with nature lovers. Weekend hikes, camping trips, and survival skill workshops held throughout the year.',
    logoIcon: Icons.terrain,
    logoColor: Color(0xFFE65100),
    bannerGradient: [Color(0xFFE65100), Color(0xFFFF8A65)],
    keywords: ['Outdoors', 'Environment', 'Health'],
    firstStep: 'Join a weekend hike.',
  ),
  DemoClub(
    name: 'Art & Design Club',
    description:
        'Express your creativity through painting, sketching, and digital design. Monthly exhibitions, live critique sessions, and collaborative murals.',
    logoIcon: Icons.palette,
    logoColor: Color(0xFFC62828),
    bannerGradient: [Color(0xFFC62828), Color(0xFFEF9A9A)],
    keywords: ['Art', 'Design', 'Culture'],
    firstStep: 'Take part in a collaborative mural.',
  ),
  DemoClub(
    name: 'Music Lounge',
    description:
        'Jam with friends, explore new sounds, and share playlists. Live open mic nights and collaborative studio sessions every month.',
    logoIcon: Icons.music_note,
    logoColor: Color(0xFF8E24AA),
    bannerGradient: [Color(0xFF8E24AA), Color(0xFFBA68C8)],
    keywords: ['Music', 'Culture', 'Performance'],
    firstStep: 'Share a playlist or join an open mic.',
  ),
  DemoClub(
    name: 'Entrepreneurship Club',
    description:
        'Pitch ideas, build business plans, and network with aspiring founders. Weekly workshops on startups, fundraising, and product design.',
    logoIcon: Icons.business,
    logoColor: Color(0xFF37474F),
    bannerGradient: [Color(0xFF37474F), Color(0xFF90A4AE)],
    keywords: ['Business', 'Entrepreneurship', 'Marketing', 'Finance'],
    firstStep: 'Check out a startup or product workshop.',
  ),
  DemoClub(
    name: 'Cooking Club',
    description:
        'Share recipes, host cook-alongs, and explore world cuisines together. Perfect for food lovers who want to cook, taste, and learn.',
    logoIcon: Icons.restaurant,
    logoColor: Color(0xFFEF6C00),
    bannerGradient: [Color(0xFFEF6C00), Color(0xFFFFCC80)],
    keywords: ['Cooking', 'Culture', 'Health'],
    firstStep: 'Try a recipe at a cook-along.',
  ),
];
// ──────────────────────────────────────────────────────────────────────────

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    final chatService = ChatService();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        title: const Text(
          'Discover Clubs',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: NeonBackground(
        child: StreamBuilder<QuerySnapshot>(
          stream: chatService.getPublicGroups(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SkeletonList();
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final docs = snapshot.data?.docs ?? [];

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.waving_hand_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'New to clubs?',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Start with an activity that sounds fun. Read '
                              'what a club does before deciding whether to '
                              'join—there’s no need to know anyone already.',
                              style: TextStyle(
                                height: 1.4,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // ── Sample ideas, not clubs a student can join ──
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Sample club ideas',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'These examples show the kinds of activities clubs might '
                    'offer. Real clubs at your school appear below.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ...demoClubs.map((club) => DemoClubCard(club: club)),

                // ── Live clubs from Firestore ──
                if (docs.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 10),
                    child: Text(
                      'All Clubs',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return ClubCard(
                      groupId: doc.id,
                      data: data,
                      chatService: chatService,
                    );
                  }),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Demo Club Card ─────────────────────────────────────────────────────────
class DemoClubCard extends StatelessWidget {
  final DemoClub club;
  final String? matchedKeyword;

  const DemoClubCard({super.key, required this.club, this.matchedKeyword});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner with logo overlaid at bottom-left
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: club.bannerImage != null
                    ? Image.asset(
                        club.bannerImage!,
                        width: double.infinity,
                        height: 120,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: double.infinity,
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: club.bannerGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
              ),
              // Club logo badge
              Positioned(
                bottom: -24,
                left: 16,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(club.logoIcon, color: club.logoColor, size: 32),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (matchedKeyword != null)
                      _KeywordPill(
                        label: 'Recommended: $matchedKeyword',
                        emphasize: true,
                      ),
                    ...club.keywords
                        .take(2)
                        .map((keyword) => _KeywordPill(label: keyword)),
                  ],
                ),
              ),
            ],
          ),
          // Club details
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 32, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        club.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Chip(
                      label: Text('Sample'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  club.description,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 17,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'A first thing to try: ${club.firstStep}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// ──────────────────────────────────────────────────────────────────────────

/// Reusable club card widget used in both DiscoverPage and SearchPage.
class ClubCard extends StatelessWidget {
  final String groupId;
  final Map<String, dynamic> data;
  final ChatService chatService;
  final String? matchedKeyword;

  const ClubCard({
    super.key,
    required this.groupId,
    required this.data,
    required this.chatService,
    this.matchedKeyword,
  });

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? 'Club') as String;
    final overview = (data['overview'] ?? '') as String;
    final roomNumber = (data['roomNumber'] as String?)?.trim() ?? '';
    final bannerUrl = data['bannerUrl'] as String?;
    final members = List<String>.from(data['members'] ?? []);
    final memberCount = members.length;
    final keywords = List<String>.from(data['keywords'] ?? const <String>[]);
    final currentEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    final isMember = members.contains(currentEmail);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: bannerUrl != null
                ? Image.network(
                    bannerUrl,
                    width: double.infinity,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _placeholderBanner(),
                  )
                : _placeholderBanner(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (matchedKeyword != null)
                  _KeywordPill(
                    label: 'Recommended: $matchedKeyword',
                    emphasize: true,
                  ),
                ...keywords
                    .take(3)
                    .map((keyword) => _KeywordPill(label: keyword)),
              ],
            ),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    isMember
                        ? OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatRoomPage(
                                    groupId: groupId,
                                    groupName: name,
                                  ),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.brass),
                            ),
                            child: const Text(
                              'Open',
                              style: TextStyle(color: AppColors.brass),
                            ),
                          )
                        : ElevatedButton(
                            onPressed: () async {
                              try {
                                await chatService.joinGroupById(groupId);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('You joined $name!'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                            ),
                            child: const Text(
                              'Join',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                  ],
                ),
                if (overview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    overview,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 13,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (roomNumber.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Meets in Room $roomNumber',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.people, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      '$memberCount member${memberCount == 1 ? '' : 's'}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.lock_open, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      'Public',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderBanner() {
    return Container(
      width: double.infinity,
      height: 120,
      color: Colors.grey[800],
      child: const Icon(Icons.group, size: 48, color: Colors.white54),
    );
  }
}

class _KeywordPill extends StatelessWidget {
  final String label;
  final bool emphasize;

  const _KeywordPill({required this.label, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: emphasize
            ? colorScheme.primary.withValues(alpha: 0.16)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasize
              ? colorScheme.primary.withValues(alpha: 0.4)
              : colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: emphasize ? colorScheme.primary : colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

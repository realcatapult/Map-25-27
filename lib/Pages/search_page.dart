import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:login_ui/services/chat_service.dart';
import 'package:login_ui/Pages/chat_room_page.dart';
import 'package:login_ui/Pages/discover_page.dart';
import 'package:login_ui/theme/app_theme.dart';
import 'package:login_ui/components/skeleton_loader.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _results = [];
  List<QueryDocumentSnapshot> _liveClubs = [];
  List<String> _userInterests = [];
  bool _isLoading = false;
  bool _isLoadingClubs = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoadingClubs = true;
    });

    final publicGroupsFuture = _chatService.getPublicGroups().first;
    final interestsFuture = _chatService.getCurrentUserInterests();

    final snapshot = await publicGroupsFuture;
    final interests = await interestsFuture;

    if (!mounted) return;

    setState(() {
      _liveClubs = snapshot.docs;
      _userInterests = interests;
      _isLoadingClubs = false;
    });
  }

  Future<void> _search(String query) async {
    final trimmedQuery = query.trim();

    setState(() {
      _query = query;
      _isLoading = trimmedQuery.isNotEmpty;
      _results = [];
    });

    if (trimmedQuery.isEmpty) return;

    final results = await _chatService.searchPublicGroups(trimmedQuery);
    final lowerQuery = trimmedQuery.toLowerCase();

    final matchingDemoClubs = demoClubs.where((club) {
      final name = club.name.toLowerCase();
      final description = club.description.toLowerCase();
      final keywordHit = club.keywords.any(
        (keyword) => keyword.toLowerCase().contains(lowerQuery),
      );
      return name.contains(lowerQuery) ||
          description.contains(lowerQuery) ||
          keywordHit;
    }).toList();

    final rankedDemoClubs = matchingDemoClubs.toList()
      ..sort((a, b) {
        final aName = a.name.toLowerCase();
        final bName = b.name.toLowerCase();
        final aStartsWith = aName.startsWith(lowerQuery) ? 0 : 1;
        final bStartsWith = bName.startsWith(lowerQuery) ? 0 : 1;
        if (aStartsWith != bStartsWith) {
          return aStartsWith.compareTo(bStartsWith);
        }

        final aExact = aName == lowerQuery ? 0 : 1;
        final bExact = bName == lowerQuery ? 0 : 1;
        if (aExact != bExact) return aExact.compareTo(bExact);

        final aDistance = (aName.length - lowerQuery.length).abs();
        final bDistance = (bName.length - lowerQuery.length).abs();
        return aDistance.compareTo(bDistance);
      });

    final rankedResults = <dynamic>[];
    rankedResults.addAll(rankedDemoClubs);

    for (final doc in results) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] ?? '').toString().toLowerCase();
      final overview = (data['overview'] ?? '').toString().toLowerCase();
      final keywords = List<String>.from(
        data['keywords'] ?? const <String>[],
      ).map((value) => value.toLowerCase()).toList();
      if (name.contains(lowerQuery) ||
          overview.contains(lowerQuery) ||
          keywords.any((keyword) => keyword.contains(lowerQuery))) {
        rankedResults.add(doc);
      }
    }

    if (!mounted) return;
    setState(() {
      _results = rankedResults;
      _isLoading = false;
    });
  }

  List<_RankedClub> _buildRecommendedClubs() {
    final ranked = <_RankedClub>[];

    for (final club in demoClubs) {
      final matchKeyword = _firstInterestKeywordMatch(
        _userInterests,
        club.keywords,
      );
      final score = _recommendationScore(matchedKeyword: matchKeyword);
      ranked.add(
        _RankedClub(item: club, matchedKeyword: matchKeyword, score: score),
      );
    }

    for (final doc in _liveClubs) {
      final data = doc.data() as Map<String, dynamic>;
      final keywords = List<String>.from(data['keywords'] ?? const <String>[]);
      final matchKeyword = _firstInterestKeywordMatch(_userInterests, keywords);
      final score = _recommendationScore(matchedKeyword: matchKeyword);

      ranked.add(
        _RankedClub(item: doc, matchedKeyword: matchKeyword, score: score),
      );
    }

    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked;
  }

  int _recommendationScore({required String? matchedKeyword}) {
    return matchedKeyword == null ? 0 : 1000;
  }

  String? _firstInterestKeywordMatch(
    List<String> interests,
    List<String> keywords,
  ) {
    if (interests.isEmpty || keywords.isEmpty) return null;

    for (final interest in interests) {
      for (final keyword in keywords) {
        if (interest.toLowerCase() == keyword.toLowerCase()) {
          return keyword;
        }
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final recommended = _buildRecommendedClubs();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        title: const Text('Search', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: NeonBackground(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                autofocus: false,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Search for clubs...',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _search('');
                          },
                        )
                      : null,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: _search,
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DiscoverPage()),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.explore,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Discover Clubs',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Browse all public clubs open to join',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white54,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: CircularProgressIndicator(),
                )
              else if (_query.isNotEmpty)
                Expanded(
                  child: _results.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No clubs found for "$_query"',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final item = _results[index];

                            if (item is DemoClub) {
                              final matched = _firstInterestKeywordMatch(
                                _userInterests,
                                item.keywords,
                              );
                              return DemoClubCard(
                                club: item,
                                matchedKeyword: matched,
                              );
                            }

                            final doc = item as QueryDocumentSnapshot;
                            final data = doc.data() as Map<String, dynamic>;
                            final currentEmail =
                                FirebaseAuth.instance.currentUser?.email ?? '';
                            final members = List<String>.from(
                              data['members'] ?? [],
                            );
                            final isMember = members.contains(currentEmail);
                            final matched = _firstInterestKeywordMatch(
                              _userInterests,
                              List<String>.from(
                                data['keywords'] ?? const <String>[],
                              ),
                            );

                            return GestureDetector(
                              onTap: isMember
                                  ? () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChatRoomPage(
                                          groupId: doc.id,
                                          groupName:
                                              (data['name'] ?? 'Club')
                                                  as String,
                                        ),
                                      ),
                                    )
                                  : null,
                              child: ClubCard(
                                groupId: doc.id,
                                data: data,
                                chatService: _chatService,
                                matchedKeyword: matched,
                              ),
                            );
                          },
                        ),
                )
              else
                Expanded(
                  child: _isLoadingClubs
                      ? const SkeletonList()
                      : ListView(
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Recommended clubs',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              _userInterests.isEmpty
                                  ? 'Pick interests in Settings to personalize this list.'
                                  : 'Clubs matching your interests appear first.',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ...recommended.map((entry) {
                              if (entry.item is DemoClub) {
                                return DemoClubCard(
                                  club: entry.item as DemoClub,
                                  matchedKeyword: entry.matchedKeyword,
                                );
                              }

                              final doc = entry.item as QueryDocumentSnapshot;
                              final data = doc.data() as Map<String, dynamic>;
                              return ClubCard(
                                groupId: doc.id,
                                data: data,
                                chatService: _chatService,
                                matchedKeyword: entry.matchedKeyword,
                              );
                            }),
                          ],
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankedClub {
  final dynamic item;
  final String? matchedKeyword;
  final int score;

  const _RankedClub({
    required this.item,
    required this.matchedKeyword,
    required this.score,
  });
}

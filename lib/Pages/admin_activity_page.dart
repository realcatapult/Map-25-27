import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:login_ui/services/auth_service.dart';
import 'package:login_ui/services/chat_service.dart';
import 'package:login_ui/components/skeleton_loader.dart';
import '../theme/app_theme.dart';

class AdminActivityPage extends StatefulWidget {
  final bool bypassAccessCheck;

  const AdminActivityPage({super.key, this.bypassAccessCheck = false});

  @override
  State<AdminActivityPage> createState() => _AdminActivityPageState();
}

class _AdminActivityPageState extends State<AdminActivityPage> {
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final Map<String, bool> _reviewing = {};
  final Map<int, bool> _demoReviewing = {};
  final Map<int, String> _demoReviewStatus = {};
  final Map<int, String> _demoRejectionReason = {};
  bool _isSigningIn = false;
  static const List<Map<String, String>> _demoPendingApprovals = [
    {
      'name': 'Robotics League',
      'createdBy': 'coach@school.edu',
      'overview': 'Competitive robotics projects and weekly build sessions.',
      'members': '22',
      'keywords': 'STEM, Robotics, Engineering',
    },
    {
      'name': 'Campus Debate Union',
      'createdBy': 'debatelead@school.edu',
      'overview': 'Public speaking and policy debate prep for tournaments.',
      'members': '18',
      'keywords': 'Debate, Public Speaking, Policy',
    },
    {
      'name': 'Environmental Action Crew',
      'createdBy': 'ecoadvisor@school.edu',
      'overview':
          'Recycling drives, clean-up events, and sustainability campaigns.',
      'members': '27',
      'keywords': 'Environment, Service, Sustainability',
    },
  ];

  Future<void> _signInAsAdmin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter admin email and password.')),
      );
      return;
    }

    setState(() {
      _isSigningIn = true;
    });

    try {
      await _authService.signInWithEmailPassword(email, password);
      final isAdmin = await _chatService.isCurrentUserSchoolAdmin();
      if (!isAdmin) {
        await _authService.signOut();
        throw Exception('This account is not marked as a school admin.');
      }
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  Future<void> _reviewGroup(
    String groupId, {
    required bool approve,
    String? rejectionReason,
  }) async {
    setState(() {
      _reviewing[groupId] = true;
    });

    try {
      await _chatService.reviewPublicApproval(
        groupId,
        approve: approve,
        rejectionReason: rejectionReason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Club approved for discovery.'
                : 'Club public listing request rejected.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error reviewing club: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _reviewing.remove(groupId);
        });
      }
    }
  }

  Future<String?> _promptRejectionReason(String clubName) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reject Club Request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add a reason that $clubName owner will see.'),
              const SizedBox(height: 10),
              TextField(
                controller: reasonController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText:
                      'Example: Please add a staff advisor and clear activity plan.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(reasonController.text.trim()),
              child: const Text('Submit Reject'),
            ),
          ],
        );
      },
    );
    reasonController.dispose();
    return reason;
  }

  Future<void> _reviewDemoGroup(
    int index, {
    required bool approve,
    String? rejectionReason,
  }) async {
    setState(() {
      _demoReviewing[index] = true;
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() {
        _demoReviewStatus[index] = approve ? 'approved' : 'rejected';
        if (approve) {
          _demoRejectionReason.remove(index);
        } else {
          _demoRejectionReason[index] = rejectionReason ?? 'Needs review';
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Demo club approved for discovery.'
                : 'Demo club rejected. Reason saved for owner view.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _demoReviewing.remove(index);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentUser = FirebaseAuth.instance.currentUser;

    if (widget.bypassAccessCheck && currentUser == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          flexibleSpace: const GradientAppBarBackground(),
          backgroundColor: colorScheme.primary,
          iconTheme: IconThemeData(color: colorScheme.onPrimary),
          title: Text(
            'Admin Login',
            style: TextStyle(color: colorScheme.onPrimary),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Sign in with a school admin account to review club approvals.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Admin email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => _isSigningIn ? null : _signInAsAdmin(),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isSigningIn ? null : _signInAsAdmin,
                    child: _isSigningIn
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Login as Admin'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return FutureBuilder<bool>(
      future: _chatService.isCurrentUserSchoolAdmin(),
      builder: (context, accessSnapshot) {
        if (accessSnapshot.connectionState == ConnectionState.waiting) {
          return const SkeletonScreen();
        }

        if (accessSnapshot.data != true) {
          return Scaffold(
            appBar: AppBar(
              flexibleSpace: const GradientAppBarBackground(),
              title: const Text('Club Activity'),
            ),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Only school admins can review club activity and approve public discovery.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            flexibleSpace: const GradientAppBarBackground(),
            backgroundColor: colorScheme.primary,
            iconTheme: IconThemeData(color: colorScheme.onPrimary),
            title: Text(
              'Club Activity Admin',
              style: TextStyle(color: colorScheme.onPrimary),
            ),
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: _chatService.getAllGroupsForAdmin(),
            builder: (context, allGroupsSnapshot) {
              if (allGroupsSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const SkeletonList();
              }

              if (allGroupsSnapshot.hasError) {
                return Center(child: Text('Error: ${allGroupsSnapshot.error}'));
              }

              final groups = allGroupsSnapshot.data?.docs ?? [];
              final pendingCount = groups.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return (data['publicRequestStatus'] as String? ?? 'none') ==
                    'pending';
              }).length;
              final publicCount = groups.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['isPublic'] as bool? ?? false;
              }).length;
              final privateCount = groups.length - publicCount;

              return StreamBuilder<QuerySnapshot>(
                stream: _chatService.getPendingPublicApprovalGroups(),
                builder: (context, pendingSnapshot) {
                  if (pendingSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const SkeletonList();
                  }

                  if (pendingSnapshot.hasError) {
                    return Center(
                      child: Text('Error: ${pendingSnapshot.error}'),
                    );
                  }

                  final pendingGroups = pendingSnapshot.data?.docs ?? [];

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          _SummaryCard(
                            label: 'Pending',
                            count: pendingCount,
                            color: const Color(0xFFF57F17),
                            icon: Icons.pending_actions,
                          ),
                          const SizedBox(width: 8),
                          _SummaryCard(
                            label: 'Public',
                            count: publicCount,
                            color: const Color(0xFF2E7D32),
                            icon: Icons.public,
                          ),
                          const SizedBox(width: 8),
                          _SummaryCard(
                            label: 'Private',
                            count: privateCount,
                            color: const Color(0xFF546E7A),
                            icon: Icons.lock,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pending Public Approval',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Approve clubs here before they appear in Discover and Search for students to join.',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (pendingGroups.isEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'No live requests yet. Demo requests are shown below.',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  ..._demoPendingApprovals.asMap().entries.map((
                                    entry,
                                  ) {
                                    final index = entry.key;
                                    final demo = entry.value;
                                    final keywordList = demo['keywords']!
                                        .split(',')
                                        .map((e) => e.trim())
                                        .toList();
                                    final isReviewingDemo =
                                        _demoReviewing[index] == true;
                                    final demoStatus =
                                        _demoReviewStatus[index] ?? 'pending';
                                    final demoRejectionReason =
                                        _demoRejectionReason[index];
                                    return Container(
                                      margin: const EdgeInsets.only(top: 12),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  demo['name']!,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      demoStatus == 'approved'
                                                      ? const Color(0xFFE8F5E9)
                                                      : demoStatus == 'rejected'
                                                      ? const Color(0xFFFFEBEE)
                                                      : const Color(0xFFFFF3E0),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  demoStatus == 'approved'
                                                      ? 'Approved'
                                                      : demoStatus == 'rejected'
                                                      ? 'Rejected'
                                                      : 'Pending',
                                                  style: TextStyle(
                                                    color:
                                                        demoStatus == 'approved'
                                                        ? const Color(
                                                            0xFF2E7D32,
                                                          )
                                                        : demoStatus ==
                                                              'rejected'
                                                        ? const Color(
                                                            0xFFC62828,
                                                          )
                                                        : const Color(
                                                            0xFFF57F17,
                                                          ),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Created by ${demo['createdBy']}',
                                          ),
                                          const SizedBox(height: 4),
                                          Text('${demo['members']} members'),
                                          const SizedBox(height: 8),
                                          Text(
                                            demo['overview']!,
                                            style: TextStyle(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: keywordList
                                                .map(
                                                  (keyword) => Chip(
                                                    label: Text(keyword),
                                                  ),
                                                )
                                                .toList(),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton(
                                                  onPressed:
                                                      isReviewingDemo ||
                                                          demoStatus !=
                                                              'pending'
                                                      ? null
                                                      : () async {
                                                          final reason =
                                                              await _promptRejectionReason(
                                                                demo['name']!,
                                                              );
                                                          if (reason == null) {
                                                            return;
                                                          }
                                                          if (reason
                                                              .trim()
                                                              .isEmpty) {
                                                            if (!mounted) {
                                                              return;
                                                            }
                                                            ScaffoldMessenger.of(
                                                              this.context,
                                                            ).showSnackBar(
                                                              const SnackBar(
                                                                content: Text(
                                                                  'Enter a rejection reason for the club owner.',
                                                                ),
                                                              ),
                                                            );
                                                            return;
                                                          }
                                                          await _reviewDemoGroup(
                                                            index,
                                                            approve: false,
                                                            rejectionReason:
                                                                reason,
                                                          );
                                                        },
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                        foregroundColor:
                                                            Colors.red,
                                                      ),
                                                  child: const Text('Reject'),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: ElevatedButton(
                                                  onPressed:
                                                      isReviewingDemo ||
                                                          demoStatus !=
                                                              'pending'
                                                      ? null
                                                      : () => _reviewDemoGroup(
                                                          index,
                                                          approve: true,
                                                        ),
                                                  child: isReviewingDemo
                                                      ? const SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                        )
                                                      : const Text(
                                                          'Approve Public',
                                                        ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (demoStatus == 'rejected' &&
                                              demoRejectionReason != null) ...[
                                            const SizedBox(height: 10),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFEBEE),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'Owner-visible rejection reason: $demoRejectionReason',
                                                style: const TextStyle(
                                                  color: Color(0xFFB71C1C),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              )
                            else
                              ...pendingGroups.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final groupId = doc.id;
                                final name =
                                    (data['name'] as String?) ?? 'Unnamed Club';
                                final overview =
                                    (data['overview'] as String?) ?? '';
                                final createdBy =
                                    (data['createdBy'] as String?) ?? 'Unknown';
                                final keywords = List<String>.from(
                                  data['keywords'] ?? const <String>[],
                                );
                                final members = List<String>.from(
                                  data['members'] ?? const <String>[],
                                );
                                final isReviewing = _reviewing[groupId] == true;

                                return Container(
                                  margin: const EdgeInsets.only(top: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFF3E0),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: const Text(
                                              'Pending',
                                              style: TextStyle(
                                                color: Color(0xFFF57F17),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text('Created by $createdBy'),
                                      const SizedBox(height: 4),
                                      Text('${members.length} members'),
                                      if (overview.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          overview,
                                          style: TextStyle(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                      if (keywords.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: keywords.take(6).map((
                                            keyword,
                                          ) {
                                            return Chip(label: Text(keyword));
                                          }).toList(),
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: isReviewing
                                                  ? null
                                                  : () async {
                                                      final reason =
                                                          await _promptRejectionReason(
                                                            name,
                                                          );
                                                      if (reason == null) {
                                                        return;
                                                      }
                                                      if (reason
                                                          .trim()
                                                          .isEmpty) {
                                                        if (!mounted) return;
                                                        ScaffoldMessenger.of(
                                                          this.context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'Enter a rejection reason for the club owner.',
                                                            ),
                                                          ),
                                                        );
                                                        return;
                                                      }
                                                      await _reviewGroup(
                                                        groupId,
                                                        approve: false,
                                                        rejectionReason: reason,
                                                      );
                                                    },
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.red,
                                              ),
                                              child: const Text('Reject'),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: isReviewing
                                                  ? null
                                                  : () => _reviewGroup(
                                                      groupId,
                                                      approve: true,
                                                    ),
                                              child: isReviewing
                                                  ? const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.white,
                                                          ),
                                                    )
                                                  : const Text(
                                                      'Approve Public',
                                                    ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

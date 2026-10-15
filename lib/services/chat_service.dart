import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:math';
import 'dart:io';

import 'package:login_ui/data/club_roles.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  static const String demoUserEmail = 'demo@groupapp.com';
  static const String _defaultReminderWindow = '24h';
  static const Set<String> _adminPermissions = {
    'manage_settings',
    'manage_events',
    'manage_messages',
    'manage_check_ins',
  };

  bool hasGroupPermission(
    Map<String, dynamic> groupData,
    String email,
    String permission,
  ) {
    if (email.isEmpty || email == groupData['createdBy']) {
      return email.isNotEmpty;
    }

    final memberPermissions = groupData['memberPermissions'];
    if (memberPermissions is Map) {
      final permissions = memberPermissions[email];
      return permissions is List && permissions.contains(permission);
    }

    return List<String>.from(
      groupData['admins'] ?? const <String>[],
    ).contains(email);
  }

  String groupRoleName(Map<String, dynamic> groupData, String email) {
    if (email == groupData['createdBy']) return 'President';

    final memberRoles = groupData['memberRoles'];
    final roleId = memberRoles is Map ? memberRoles[email] : null;
    final roles = groupData['roles'];
    if (roleId is String && roles is List) {
      for (final role in roles.whereType<Map>()) {
        if (role['id'] == roleId && role['name'] is String) {
          return role['name'] as String;
        }
      }
    }

    if (memberRoles is Map && roleId != null) return 'Member';
    if (List<String>.from(
      groupData['admins'] ?? const <String>[],
    ).contains(email)) {
      return 'Officer';
    }
    return 'Member';
  }

  // Generate a random 6-character join code
  String _generateJoinCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(
      6,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  // Create a new group chat with join code
  Future<String> createGroupChat(
    String groupName,
    List<String> memberEmails,
    bool isPublic,
    String whoCanPost,
    int themeColor,
    String themeIcon,
    List<String>? keywords,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');
    if (currentUser.email == null) throw Exception('No email for user');

    final joinCode = _generateJoinCode();
    final members = <String>{
      currentUser.email!,
      ...memberEmails.where((email) => email.isNotEmpty),
      demoUserEmail,
    }.toList();

    final groupDoc = await _firestore.collection('groups').add({
      'name': groupName,
      'createdBy': currentUser.email,
      'createdAt': FieldValue.serverTimestamp(),
      'members': members,
      'joinCode': joinCode,
      // New clubs start private and undiscoverable until a group admin
      // explicitly enables discovery from settings.
      'isPublic': false,
      'requestedPublicOnCreate': isPublic,
      'publicRequestStatus': isPublic ? 'pending' : 'none',
      if (isPublic) 'publicRequestSubmittedAt': FieldValue.serverTimestamp(),
      'admins': [currentUser.email],
      'roles': ClubRole.builtInRoles.map((role) => role.toMap()).toList(),
      'memberRoles': {
        for (final email in members)
          email: email == currentUser.email ? 'president' : 'member',
      },
      'memberPermissions': {
        for (final email in members)
          email: email == currentUser.email
              ? ClubRole.builtInRoles.first.permissions.toList()
              : <String>[],
      },
      'whoCanPost': whoCanPost,
      'themeColor': themeColor,
      'themeIcon': themeIcon,
      'keywords': keywords ?? const <String>[],
      'defaultReminderWindow': _defaultReminderWindow,
    });

    return groupDoc.id;
  }

  // Join a group with join code
  Future<void> joinGroupWithCode(String joinCode) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    final querySnapshot = await _firestore
        .collection('groups')
        .where('joinCode', isEqualTo: joinCode.toUpperCase())
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) {
      throw Exception('Invalid join code');
    }

    final groupDoc = querySnapshot.docs.first;
    final members = List<String>.from(groupDoc.data()['members'] ?? []);

    if (members.contains(currentUser.email)) {
      throw Exception('You are already in this group');
    }

    await _firestore.collection('groups').doc(groupDoc.id).update({
      'members': FieldValue.arrayUnion([currentUser.email]),
    });
  }

  // Get all groups the current user is a member of
  Stream<QuerySnapshot> getUserGroups() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.empty();
    }

    return _firestore
        .collection('groups')
        .where('members', arrayContains: currentUser.email)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Send a message to a group
  Future<void> sendMessage(
    String groupId,
    String message, {
    String? imageUrl,
    String type = 'text',
    Map<String, dynamic>? file,
    Map<String, dynamic>? poll,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSender,
    String? threadRootId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    final groupDoc = await _firestore.collection('groups').doc(groupId).get();
    final groupData = groupDoc.data();
    if (groupData != null) {
      final whoCanPost = groupData['whoCanPost'] ?? 'all';
      if (whoCanPost == 'admins' &&
          !hasGroupPermission(
            groupData,
            currentUser.email ?? '',
            'send_messages',
          )) {
        throw Exception('You do not have permission to post in this group');
      }
      if (type == 'announcement' &&
          !hasGroupPermission(
            groupData,
            currentUser.email ?? '',
            'post_announcements',
          )) {
        throw Exception('You do not have permission to post announcements');
      }
    }

    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .add({
          'type': type,
          'text': message,
          'senderEmail': currentUser.email,
          'timestamp': FieldValue.serverTimestamp(),
          if (imageUrl != null) 'imageUrl': imageUrl,
          if (file != null) 'file': file,
          if (poll != null) 'poll': poll,
          if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
          if (replyToText != null) 'replyToText': replyToText,
          if (replyToSender != null) 'replyToSender': replyToSender,
          if (threadRootId != null) 'threadRootId': threadRootId,
          'reactions': const <String>[],
        });
  }

  // Upload image to Firebase Storage and return URL
  Future<String> uploadImage(File imageFile, String groupId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${currentUser.uid}.jpg';
    final ref = _storage.ref().child('chat_images/$groupId/$fileName');

    await ref.putFile(imageFile);
    return await ref.getDownloadURL();
  }

  Future<Map<String, dynamic>> uploadGroupFile(
    File file,
    String groupId,
    String originalName,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${currentUser.uid}_$originalName';
    final ref = _storage.ref().child('chat_files/$groupId/$fileName');

    await ref.putFile(file);
    final url = await ref.getDownloadURL();
    final extension = originalName.contains('.')
        ? originalName.split('.').last.toLowerCase()
        : '';

    return {
      'name': originalName,
      'url': url,
      'extension': extension,
      'sizeBytes': await file.length(),
    };
  }

  // Upload profile picture and return URL
  Future<String> uploadProfilePicture(File imageFile) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    final fileName = '${currentUser.uid}.jpg';
    final ref = _storage.ref().child('profile_pictures/$fileName');

    await ref.putFile(imageFile);
    return await ref.getDownloadURL();
  }

  // Update user profile picture URL
  Future<void> updateProfilePicture(String imageUrl) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    await _firestore.collection('users').doc(currentUser.uid).set({
      'email': currentUser.email,
      'profilePicture': imageUrl,
    }, SetOptions(merge: true));
  }

  Future<void> setCurrentUserSchoolAdmin(bool isSchoolAdmin) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    await _firestore.collection('users').doc(currentUser.uid).set({
      'email': currentUser.email,
      'schoolAdmin': isSchoolAdmin,
    }, SetOptions(merge: true));
  }

  // Get user profile picture
  Future<String?> getProfilePicture(String email) async {
    final querySnapshot = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      return querySnapshot.docs.first.data()['profilePicture'] as String?;
    }
    return null;
  }

  // Get messages for a group
  Stream<QuerySnapshot> getMessages(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // Get group details
  Future<DocumentSnapshot> getGroup(String groupId) {
    return _firestore.collection('groups').doc(groupId).get();
  }

  // Watch group details
  Stream<DocumentSnapshot> watchGroup(String groupId) {
    return _firestore.collection('groups').doc(groupId).snapshots();
  }

  // Update group settings
  Future<void> updateGroupSettings(
    String groupId, {
    bool? isPublic,
    String? whoCanPost,
    int? themeColor,
    String? themeIcon,
    String? bannerUrl,
    String? overview,
    List<String>? keywords,
  }) async {
    final updates = <String, dynamic>{};
    if (isPublic != null) updates['isPublic'] = isPublic;
    if (whoCanPost != null) updates['whoCanPost'] = whoCanPost;
    if (themeColor != null) updates['themeColor'] = themeColor;
    if (themeIcon != null) updates['themeIcon'] = themeIcon;
    if (bannerUrl != null) updates['bannerUrl'] = bannerUrl;
    if (overview != null) updates['overview'] = overview;
    if (keywords != null) updates['keywords'] = keywords;

    if (updates.isNotEmpty) {
      await _firestore.collection('groups').doc(groupId).update(updates);
    }
  }

  Future<bool> isCurrentUserSchoolAdmin() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;

    final tokenResult = await currentUser.getIdTokenResult(true);
    final claimValue = tokenResult.claims?['schoolAdmin'];
    if (claimValue == true) {
      return true;
    }

    final doc = await _firestore.collection('users').doc(currentUser.uid).get();
    return doc.data()?['schoolAdmin'] as bool? ?? false;
  }

  Stream<QuerySnapshot> getPendingPublicApprovalGroups() {
    return _firestore
        .collection('groups')
        .where('publicRequestStatus', isEqualTo: 'pending')
        .orderBy('publicRequestSubmittedAt', descending: false)
        .snapshots();
  }

  Stream<QuerySnapshot> getAllGroupsForAdmin() {
    return _firestore
        .collection('groups')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> requestPublicApproval(String groupId) async {
    await _firestore.collection('groups').doc(groupId).update({
      'isPublic': false,
      'requestedPublicOnCreate': true,
      'publicRequestStatus': 'pending',
      'publicRequestSubmittedAt': FieldValue.serverTimestamp(),
      'publicReviewedAt': FieldValue.delete(),
      'publicReviewedBy': FieldValue.delete(),
      'publicRejectionReason': FieldValue.delete(),
    });
  }

  Future<void> cancelPublicApprovalRequest(String groupId) async {
    await _firestore.collection('groups').doc(groupId).update({
      'isPublic': false,
      'requestedPublicOnCreate': false,
      'publicRequestStatus': 'none',
      'publicRequestSubmittedAt': FieldValue.delete(),
      'publicReviewedAt': FieldValue.delete(),
      'publicReviewedBy': FieldValue.delete(),
      'publicRejectionReason': FieldValue.delete(),
    });
  }

  Future<void> setGroupPrivate(String groupId) async {
    await _firestore.collection('groups').doc(groupId).update({
      'isPublic': false,
      'requestedPublicOnCreate': false,
      'publicRequestStatus': 'none',
      'publicRequestSubmittedAt': FieldValue.delete(),
      'publicReviewedAt': FieldValue.delete(),
      'publicReviewedBy': FieldValue.delete(),
      'publicRejectionReason': FieldValue.delete(),
    });
  }

  Future<void> reviewPublicApproval(
    String groupId, {
    required bool approve,
    String? rejectionReason,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.email == null) {
      throw Exception('Not logged in');
    }

    final isSchoolAdmin = await isCurrentUserSchoolAdmin();
    if (!isSchoolAdmin) {
      throw Exception('Only school admins can approve club discovery');
    }

    await _firestore.collection('groups').doc(groupId).update({
      'isPublic': approve,
      'requestedPublicOnCreate': approve,
      'publicRequestStatus': approve ? 'approved' : 'rejected',
      'publicReviewedAt': FieldValue.serverTimestamp(),
      'publicReviewedBy': currentUser.email,
      'publicRejectionReason': approve
          ? FieldValue.delete()
          : (rejectionReason ?? 'Needs review'),
    });
  }

  // Upload group banner image and return URL
  Future<String> uploadGroupBanner(File imageFile, String groupId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    final fileName = '${DateTime.now().millisecondsSinceEpoch}_banner.jpg';
    final ref = _storage.ref().child('group_banners/$groupId/$fileName');
    await ref.putFile(imageFile);
    return await ref.getDownloadURL();
  }

  // Stream of all public groups for Discover page
  Stream<QuerySnapshot> getPublicGroups() {
    return _firestore
        .collection('groups')
        .where('isPublic', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Join a public group directly by ID (no join code needed)
  Future<void> joinGroupById(String groupId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    final groupDoc = await _firestore.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) throw Exception('Group not found');

    final data = groupDoc.data()!;
    if (!(data['isPublic'] as bool? ?? false)) {
      throw Exception('This group is private');
    }

    final members = List<String>.from(data['members'] ?? []);
    if (members.contains(currentUser.email)) {
      throw Exception('You are already in this group');
    }

    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([currentUser.email]),
    });
  }

  // Search public groups by name (client-side filter)
  Future<List<QueryDocumentSnapshot>> searchPublicGroups(String query) async {
    final snapshot = await _firestore
        .collection('groups')
        .where('isPublic', isEqualTo: true)
        .get();

    final lowerQuery = query.toLowerCase();
    return snapshot.docs.where((doc) {
      final data = doc.data();
      final name = (data['name'] ?? '').toString().toLowerCase();
      final overview = (data['overview'] ?? '').toString().toLowerCase();
      final keywords = List<String>.from(
        data['keywords'] ?? const <String>[],
      ).map((value) => value.toLowerCase()).toList();
      final keywordMatch = keywords.any(
        (keyword) => keyword.contains(lowerQuery),
      );
      return name.contains(lowerQuery) ||
          overview.contains(lowerQuery) ||
          keywordMatch;
    }).toList();
  }

  // Update group admins
  Future<void> updateGroupAdmins(String groupId, List<String> admins) async {
    await _firestore.collection('groups').doc(groupId).update({
      'admins': admins,
    });
  }

  Future<void> updateGroupRoles(
    String groupId, {
    required List<ClubRole> roles,
    required Map<String, String> memberRoles,
    required List<String> members,
    required String ownerEmail,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser?.email != ownerEmail) {
      throw Exception('Only the club president can manage roles');
    }

    final roleIds = roles.map((role) => role.id).toSet();
    if (!ClubRole.builtInRoles.every((role) => roleIds.contains(role.id))) {
      throw Exception('Built-in club roles cannot be removed');
    }

    final normalizedAssignments = <String, String>{
      for (final email in members)
        email: email == ownerEmail
            ? 'president'
            : (roleIds.contains(memberRoles[email])
                  ? memberRoles[email]!
                  : 'member'),
    };
    final rolesById = {for (final role in roles) role.id: role};
    final permissionsByMember = <String, List<String>>{
      for (final entry in normalizedAssignments.entries)
        entry.key: rolesById[entry.value]!.permissions.toList()..sort(),
    };
    final admins = <String>{
      ownerEmail,
      for (final entry in permissionsByMember.entries)
        if (entry.value.any(_adminPermissions.contains)) entry.key,
    }.toList();

    await _firestore.collection('groups').doc(groupId).update({
      'roles': roles.map((role) => role.toMap()).toList(),
      'memberRoles': normalizedAssignments,
      'memberPermissions': permissionsByMember,
      'admins': admins,
    });
  }

  String _directMessageId(String emailA, String emailB) {
    final ids = [emailA.toLowerCase(), emailB.toLowerCase()]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  Future<String> getOrCreateDirectMessage(String otherEmail) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');
    if (currentUser.email == null) throw Exception('No email for user');

    final docId = _directMessageId(currentUser.email!, otherEmail);
    final docRef = _firestore.collection('directMessages').doc(docId);
    final doc = await docRef.get();
    if (!doc.exists) {
      await docRef.set({
        'participants': [currentUser.email, otherEmail],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return docId;
  }

  Stream<QuerySnapshot> getDirectMessages(String threadId) {
    return _firestore
        .collection('directMessages')
        .doc(threadId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  Future<void> sendDirectMessage(String threadId, String message) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');
    if (currentUser.email == null) throw Exception('No email for user');

    await _firestore
        .collection('directMessages')
        .doc(threadId)
        .collection('messages')
        .add({
          'type': 'text',
          'text': message,
          'senderEmail': currentUser.email,
          'timestamp': FieldValue.serverTimestamp(),
          'reactions': const <String>[],
        });
  }

  /// Toggles a reaction on a direct message. Mirrors
  /// [toggleMessageReaction]; reactions are 'emoji::email' strings so a
  /// toggle is one arrayUnion or arrayRemove.
  Future<void> toggleDirectMessageReaction(
    String threadId,
    String messageId,
    String emoji,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.email == null) {
      throw Exception('Not logged in');
    }

    final docRef = _firestore
        .collection('directMessages')
        .doc(threadId)
        .collection('messages')
        .doc(messageId);
    final snapshot = await docRef.get();
    final data = snapshot.data();
    if (data == null) throw Exception('Message not found');

    final key = _reactionKey(emoji, currentUser.email!);
    final reactions = List<String>.from(data['reactions'] ?? const <String>[]);

    await docRef.update({
      'reactions': reactions.contains(key)
          ? FieldValue.arrayRemove([key])
          : FieldValue.arrayUnion([key]),
    });
  }

  /// Posts a Jarvis reply into a direct-message thread.
  ///
  /// Jarvis is a virtual participant, so the asking person's client writes
  /// the reply on its behalf — the rules allow the bot address as a sender
  /// precisely because there is no server doing it.
  Future<void> postJarvisDirectMessage(String threadId, String text) async {
    await _firestore
        .collection('directMessages')
        .doc(threadId)
        .collection('messages')
        .add({
          'type': 'summary',
          'text': text,
          'senderEmail': jarvisEmail,
          'timestamp': FieldValue.serverTimestamp(),
          'reactions': const <String>[],
        });
  }

  /// Recent turns of a DM thread, oldest first, as context for Jarvis.
  Future<List<Map<String, String>>> getRecentDirectMessages(
    String threadId, {
    int limit = 10,
  }) async {
    final snapshot = await _firestore
        .collection('directMessages')
        .doc(threadId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.reversed.map((doc) {
      final data = doc.data();
      return {
        'sender': (data['senderEmail'] as String?) ?? '',
        'text': (data['text'] as String?) ?? '',
      };
    }).toList();
  }

  Stream<QuerySnapshot> getDirectMessageThreads() {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.email == null) {
      return Stream.empty();
    }

    return _firestore
        .collection('directMessages')
        .where('participants', arrayContains: currentUser.email)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Leave a group
  Future<void> leaveGroup(String groupId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayRemove([currentUser.email]),
    });
  }

  // Get user data (first name, last name)
  Future<Map<String, dynamic>?> getUserData(String email) async {
    final querySnapshot = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      return querySnapshot.docs.first.data();
    }
    return null;
  }

  // Update user data (first name, last name)
  Future<void> updateUserData(String firstName, String lastName) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    await _firestore.collection('users').doc(currentUser.uid).set({
      'email': currentUser.email,
      'firstName': firstName,
      'lastName': lastName,
    }, SetOptions(merge: true));
  }

  Future<List<String>> getCurrentUserInterests() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return const [];

    final doc = await _firestore.collection('users').doc(currentUser.uid).get();
    final data = doc.data();
    if (data == null) return const [];

    return List<String>.from(data['interests'] ?? const <String>[]);
  }

  Future<bool> shouldShowInterestsOnboarding() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;

    final doc = await _firestore.collection('users').doc(currentUser.uid).get();
    final data = doc.data();
    if (data == null) return true;

    final seen = data['interestsOnboardingSeen'] as bool? ?? false;
    final interests = List<String>.from(data['interests'] ?? const <String>[]);
    return !seen || interests.isEmpty;
  }

  Future<void> updateCurrentUserInterests(List<String> interests) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    await _firestore.collection('users').doc(currentUser.uid).set({
      'email': currentUser.email,
      'interests': interests,
      'interestsOnboardingSeen': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static const String jarvisEmail = 'jarvis@assistant.ai';

  /// Posts a message into a group as the Jarvis assistant. Bypasses the
  /// "who can post" restriction because it's the assistant replying, not a user.
  Future<void> postJarvisMessage(String groupId, String text) async {
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .add({
          'type': 'summary',
          'text': text,
          'senderEmail': jarvisEmail,
          'timestamp': FieldValue.serverTimestamp(),
          'reactions': const <String>[],
        });
  }

  Future<void> sendPoll(
    String groupId, {
    required String question,
    required List<String> options,
  }) async {
    final trimmedOptions = options
        .map((option) => option.trim())
        .where((option) => option.isNotEmpty)
        .toList();
    if (trimmedOptions.length < 2) {
      throw Exception('Polls need at least two options');
    }

    final pollOptions = <Map<String, dynamic>>[];
    final votes = <String, List<String>>{};
    for (var index = 0; index < trimmedOptions.length; index++) {
      final id = 'option_$index';
      pollOptions.add({'id': id, 'label': trimmedOptions[index]});
      votes[id] = <String>[];
    }

    await sendMessage(
      groupId,
      question,
      type: 'poll',
      poll: {'question': question, 'options': pollOptions, 'votes': votes},
    );
  }

  Future<void> togglePollVote(
    String groupId,
    String messageId,
    String optionId,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.email == null) {
      throw Exception('Not logged in');
    }

    final docRef = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId);
    final snapshot = await docRef.get();
    final data = snapshot.data();
    if (data == null) throw Exception('Poll not found');

    final poll = Map<String, dynamic>.from(data['poll'] ?? const {});
    final rawVotes = Map<String, dynamic>.from(poll['votes'] ?? const {});
    final nextVotes = <String, List<String>>{};
    for (final entry in rawVotes.entries) {
      nextVotes[entry.key] = List<String>.from(entry.value ?? const <String>[]);
    }

    for (final key in nextVotes.keys) {
      nextVotes[key] = nextVotes[key]!
          .where((email) => email != currentUser.email)
          .toList();
    }

    final currentOptionVotes = nextVotes[optionId] ?? <String>[];
    final hadVote = List<String>.from(
      rawVotes[optionId] ?? const <String>[],
    ).contains(currentUser.email);
    if (!hadVote) {
      currentOptionVotes.add(currentUser.email!);
    }
    nextVotes[optionId] = currentOptionVotes;

    poll['votes'] = nextVotes;
    await docRef.update({'poll': poll});
  }

  String _reactionKey(String emoji, String email) => '$emoji::$email';

  Future<void> toggleMessageReaction(
    String groupId,
    String messageId,
    String emoji,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.email == null) {
      throw Exception('Not logged in');
    }

    final docRef = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId);
    final snapshot = await docRef.get();
    final data = snapshot.data();
    if (data == null) throw Exception('Message not found');

    final key = _reactionKey(emoji, currentUser.email!);
    final reactions = List<String>.from(data['reactions'] ?? const <String>[]);
    final contains = reactions.contains(key);

    await docRef.update({
      'reactions': contains
          ? FieldValue.arrayRemove([key])
          : FieldValue.arrayUnion([key]),
    });
  }

  Future<void> pinMessage(
    String groupId,
    String messageId,
    Map<String, dynamic> message,
  ) async {
    await _firestore.collection('groups').doc(groupId).update({
      'pinnedMessageId': messageId,
      'pinnedMessageText': (message['text'] as String?) ?? '',
      'pinnedMessageSender': (message['senderEmail'] as String?) ?? '',
      'pinnedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clearPinnedMessage(String groupId) async {
    await _firestore.collection('groups').doc(groupId).update({
      'pinnedMessageId': FieldValue.delete(),
      'pinnedMessageText': FieldValue.delete(),
      'pinnedMessageSender': FieldValue.delete(),
      'pinnedAt': FieldValue.delete(),
    });
  }

  /// Returns the last [limit] messages in a group (oldest first) as simple
  /// {sender, text} maps, for giving Jarvis conversation context.
  Future<List<Map<String, String>>> getRecentGroupMessages(
    String groupId, {
    int limit = 10,
  }) async {
    final snapshot = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();

    final docs = snapshot.docs.reversed;
    return docs.map((doc) {
      final data = doc.data();
      final sender = (data['senderEmail'] as String?) ?? 'unknown';
      final text = (data['text'] as String?) ?? '';
      return {'sender': sender, 'text': text};
    }).toList();
  }

  Future<void> addGroupEvent(
    String groupId,
    String groupName,
    String title,
    String description,
    DateTime date,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    if (title.trim().isEmpty) throw Exception('Event title is required');
    final groupRef = _firestore.collection('groups').doc(groupId);
    final groupSnapshot = await groupRef.get();
    final groupData = groupSnapshot.data();
    if (groupData == null ||
        !hasGroupPermission(
          groupData,
          currentUser.email ?? '',
          'manage_events',
        )) {
      throw Exception('You do not have permission to manage events');
    }

    final eventRef = groupRef.collection('events').doc();
    final messageRef = groupRef.collection('messages').doc();
    final eventDate = Timestamp.fromDate(date);
    final batch = _firestore.batch();
    batch.set(eventRef, {
      'title': title.trim(),
      'description': description.trim(),
      'date': eventDate,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': currentUser.email,
      'groupId': groupId,
      'groupName': groupName,
      'checkInEnabled': false,
    });
    batch.set(messageRef, {
      'type': 'event',
      'text': description.trim(),
      'title': title.trim(),
      'eventId': eventRef.id,
      'eventDate': eventDate,
      'senderEmail': currentUser.email,
      'timestamp': FieldValue.serverTimestamp(),
      'reactions': const <String>[],
    });
    await batch.commit();
  }

  Future<void> postAnnouncement(
    String groupId, {
    required String title,
    required String message,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');
    if (title.trim().isEmpty || message.trim().isEmpty) {
      throw Exception('Add a title and announcement before posting');
    }

    final groupRef = _firestore.collection('groups').doc(groupId);
    final groupSnapshot = await groupRef.get();
    final groupData = groupSnapshot.data();
    if (groupData == null ||
        !hasGroupPermission(
          groupData,
          currentUser.email ?? '',
          'post_announcements',
        )) {
      throw Exception('You do not have permission to post announcements');
    }

    await groupRef.collection('messages').add({
      'type': 'announcement',
      'title': title.trim(),
      'text': message.trim(),
      'senderEmail': currentUser.email,
      'timestamp': FieldValue.serverTimestamp(),
      'reactions': const <String>[],
    });
  }

  // Open or close QR check-in for an event. These bounds are advisory on the
  // client; checkInMember re-checks them against server time.
  Future<void> setEventCheckIn(
    String groupId,
    String eventId, {
    required bool enabled,
    DateTime? opensAt,
    DateTime? closesAt,
  }) async {
    final updates = <String, dynamic>{'checkInEnabled': enabled};
    if (opensAt != null) {
      updates['checkInOpensAt'] = Timestamp.fromDate(opensAt);
    }
    if (closesAt != null) {
      updates['checkInClosesAt'] = Timestamp.fromDate(closesAt);
    }
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .update(updates);
  }

  Stream<QuerySnapshot> watchEventCheckIns(String groupId, String eventId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .collection('checkIns')
        .orderBy('checkedInAt', descending: true)
        .snapshots();
  }

  // Group members with no check-in yet, for the manual-add list.
  Future<List<String>> getUncheckedMembers(
    String groupId,
    String eventId,
  ) async {
    final groupDoc = await _firestore.collection('groups').doc(groupId).get();
    final members = List<String>.from(groupDoc.data()?['members'] ?? []);
    final checkIns = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .collection('checkIns')
        .get();
    const emptyEmail = '';
    final present = checkIns.docs
        .map((d) => (d.data()['email'] as String?) ?? emptyEmail)
        .toSet();
    return members.where((m) => !present.contains(m)).toList()..sort();
  }

  Future<List<Map<String, dynamic>>> getGroupEvents(String groupId) async {
    final snapshot = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .orderBy('date', descending: false)
        .get();

    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getUpcomingEventReminders(
    List<Map<String, String>> groups,
  ) async {
    final now = DateTime.now();
    final reminderCutoff = now.add(const Duration(days: 2));
    final reminders = <Map<String, dynamic>>[];

    for (final group in groups) {
      final groupId = group['id'] ?? '';
      if (groupId.isEmpty) continue;

      final events = await getGroupEvents(groupId);
      for (final event in events) {
        final dateValue = event['date'];
        final eventDate = dateValue is Timestamp
            ? dateValue.toDate()
            : (dateValue is DateTime ? dateValue : null);
        if (eventDate == null) continue;
        if (eventDate.isBefore(now) || eventDate.isAfter(reminderCutoff)) {
          continue;
        }

        reminders.add({
          'type': 'eventReminder',
          'groupId': groupId,
          'groupName': group['name'] ?? 'Group',
          'title': event['title'] ?? 'Upcoming event',
          'description': event['description'] ?? '',
          'date': Timestamp.fromDate(eventDate),
          'timestamp': Timestamp.fromDate(eventDate),
        });
      }
    }

    reminders.sort((a, b) {
      final aTime = a['date'] as Timestamp?;
      final bTime = b['date'] as Timestamp?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return aTime.compareTo(bTime);
    });

    return reminders;
  }

  Future<Map<String, dynamic>?> _latestGroupMessage(
    String groupId,
    String groupName,
  ) async {
    final snapshot = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final data = snapshot.docs.first.data();
    return {
      'type': 'group',
      'groupId': groupId,
      'groupName': groupName,
      'text': data['text'] ?? '',
      'imageUrl': data['imageUrl'],
      'senderEmail': data['senderEmail'] ?? '',
      'timestamp': data['timestamp'],
    };
  }

  Future<Map<String, dynamic>?> _latestDirectMessage(
    String threadId,
    String otherEmail,
  ) async {
    final snapshot = await _firestore
        .collection('directMessages')
        .doc(threadId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final data = snapshot.docs.first.data();
    return {
      'type': 'dm',
      'threadId': threadId,
      'otherEmail': otherEmail,
      'text': data['text'] ?? '',
      'imageUrl': data['imageUrl'],
      'senderEmail': data['senderEmail'] ?? '',
      'timestamp': data['timestamp'],
    };
  }

  Future<List<Map<String, dynamic>>> getRecentNotifications(
    List<Map<String, String>> groups,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.email == null) {
      return [];
    }

    final List<Map<String, dynamic>> items = [];

    for (final group in groups) {
      final groupId = group['id'] ?? '';
      if (groupId.isEmpty) continue;
      final groupName = group['name'] ?? 'Group';
      final latest = await _latestGroupMessage(groupId, groupName);
      if (latest != null) {
        items.add(latest);
      }
    }

    items.addAll(await getUpcomingEventReminders(groups));

    final threadSnapshot = await _firestore
        .collection('directMessages')
        .where('participants', arrayContains: currentUser.email)
        .orderBy('createdAt', descending: true)
        .get();

    for (final doc in threadSnapshot.docs) {
      final data = doc.data();
      final participants = List<String>.from(data['participants'] ?? []);
      final otherEmail = participants.firstWhere(
        (email) => email != currentUser.email,
        orElse: () => 'Unknown',
      );
      final latest = await _latestDirectMessage(doc.id, otherEmail);
      if (latest != null) {
        items.add(latest);
      }
    }

    items.sort((a, b) {
      final aTime = a['timestamp'] as Timestamp?;
      final bTime = b['timestamp'] as Timestamp?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return items;
  }
}

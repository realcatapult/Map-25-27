import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class JoinRequest {
  const JoinRequest({
    required this.id,
    required this.groupId,
    required this.email,
    required this.uid,
    required this.status,
    this.message,
    this.requestedAt,
    this.decidedBy,
  });

  factory JoinRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return JoinRequest(
      id: doc.id,
      groupId: (d['groupId'] as String?) ?? '',
      email: (d['email'] as String?) ?? '',
      uid: (d['uid'] as String?) ?? '',
      status: (d['status'] as String?) ?? 'pending',
      message: d['message'] as String?,
      requestedAt: (d['requestedAt'] as Timestamp?)?.toDate(),
      decidedBy: d['decidedBy'] as String?,
    );
  }

  final String id;
  final String groupId;
  final String email;
  final String uid;
  final String status;
  final String? message;
  final DateTime? requestedAt;
  final String? decidedBy;

  bool get isPending => status == 'pending';
}

/// Asking to join a club, and an officer deciding.
///
/// Stored as `groups/{groupId}/joinRequests/{email}` — the email as the
/// document id, so a person cannot queue up ten requests for the same club
/// and an officer's inbox cannot be flooded. Approving is the only path that
/// adds someone to `members`, which is what makes a club closed rather than
/// merely unlisted.
class JoinRequestService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get myEmail => _auth.currentUser?.email;

  CollectionReference<Map<String, dynamic>> _col(String groupId) =>
      _db.collection('groups').doc(groupId).collection('joinRequests');

  /// Requests to join, or throws with a reason the UI can show directly.
  Future<void> request(String groupId, {String? message}) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) throw Exception('Not signed in.');

    final group = await _db.collection('groups').doc(groupId).get();
    if (!group.exists) throw Exception('That club no longer exists.');

    final members = List<String>.from(group.data()?['members'] ?? const []);
    if (members.contains(email)) {
      throw Exception('You are already in this club.');
    }

    final ref = _col(groupId).doc(email);
    final existing = await ref.get();
    if (existing.exists &&
        (existing.data()?['status'] as String?) == 'pending') {
      throw Exception('You have already asked to join. Waiting on an officer.');
    }

    await ref.set({
      'groupId': groupId,
      'email': email,
      'uid': user.uid,
      'status': 'pending',
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim(),
      'requestedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancel(String groupId) async {
    final email = myEmail;
    if (email == null) return;
    await _col(groupId).doc(email).delete();
  }

  /// Requests for one club, newest first, for the officer's review screen.
  Stream<List<JoinRequest>> watchRequests(String groupId) => _col(groupId)
      .orderBy('requestedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(JoinRequest.fromDoc).toList());

  /// Just the pending count, for the badge on the officer's button.
  Stream<int> watchPendingCount(String groupId) => _col(
    groupId,
  ).where('status', isEqualTo: 'pending').snapshots().map((s) => s.docs.length);

  Stream<JoinRequest?> watchMyRequest(String groupId) {
    final email = myEmail;
    if (email == null) return Stream.value(null);
    return _col(groupId)
        .doc(email)
        .snapshots()
        .map((d) => d.exists ? JoinRequest.fromDoc(d) : null);
  }

  /// Approve: adds the person to the club and marks the request.
  ///
  /// Two writes rather than one batch on purpose — the membership change is
  /// the part that matters, so it goes first and is not held hostage to the
  /// bookkeeping write succeeding.
  Future<void> approve(String groupId, String email) async {
    final me = myEmail;
    if (me == null) throw Exception('Not signed in.');

    await _db.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([email]),
    });

    await _col(groupId).doc(email).set({
      'status': 'approved',
      'decidedBy': me,
      'decidedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> decline(String groupId, String email) async {
    final me = myEmail;
    if (me == null) throw Exception('Not signed in.');

    await _col(groupId).doc(email).set({
      'status': 'declined',
      'decidedBy': me,
      'decidedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

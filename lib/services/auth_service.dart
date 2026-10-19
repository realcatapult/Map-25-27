import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Sign in with email and password
  Future<void> signInWithEmailPassword(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw e.message ?? 'An error occurred';
    }
  }

  /// Signs up and creates the matching profile document.
  ///
  /// The profile is not optional. Everything that looks a person up — member
  /// lists, profile cards, friend requests, checking someone in by email —
  /// queries `users` by email, so an account without a profile document is
  /// invisible to the rest of the app. Previously a document was only
  /// written if the person happened to pick a profile picture during signup.
  Future<void> signUpWithEmailPassword(
    String email,
    String password, {
    String firstName = '',
    String lastName = '',
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = credential.user?.uid;
      if (uid == null) return;

      await _db.collection('users').doc(uid).set({
        'email': email,
        if (firstName.isNotEmpty) 'firstName': firstName,
        if (lastName.isNotEmpty) 'lastName': lastName,
        'createdAt': FieldValue.serverTimestamp(),
        'interestsOnboardingSeen': false,
      }, SetOptions(merge: true));
    } on FirebaseAuthException catch (e) {
      throw e.message ?? 'An error occurred';
    }
  }

  /// Backfills a profile for an account that signed up before the document
  /// was created automatically. Safe to call on every sign-in: it merges, and
  /// never overwrites a name the person has since set.
  Future<void> ensureProfileExists() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (snap.exists && (snap.data()?['email'] as String?)?.isNotEmpty == true) {
      return;
    }
    await ref.set({'email': user.email}, SetOptions(merge: true));
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}

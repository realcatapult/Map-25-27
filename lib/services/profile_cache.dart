import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// One place that knows how to turn an email into a person.
///
/// Chat headers, message senders, member lists, profile cards and the
/// attendance sheet all need the same three things — a display name, a photo
/// and a bio — and all of them used to query `users` separately. That meant
/// the same lookup running once per widget, often inside a build. This holds
/// the answers for the session and tells listeners when a new one arrives.
class ProfileCache extends ChangeNotifier {
  ProfileCache._();
  static final ProfileCache instance = ProfileCache._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Map<String, Map<String, dynamic>?> _byEmail = {};
  final Set<String> _inFlight = {};

  /// Cached profile, or null if we have not fetched it yet. Never blocks.
  Map<String, dynamic>? peek(String email) => _byEmail[email.toLowerCase()];

  bool isKnown(String email) => _byEmail.containsKey(email.toLowerCase());

  /// Display name, falling back to the email's local part while the real
  /// name is still loading, and to the full address if there is no profile.
  /// Requests the profile on first ask, so callers can use this straight
  /// from a build and simply rebuild when [notifyListeners] fires.
  String nameFor(String email) {
    final profile = resolve(email);
    if (profile != null) {
      final name = [
        profile['firstName'],
        profile['lastName'],
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
      if (name.isNotEmpty) return name;
    }
    // Known-but-nameless, or not loaded yet: the local part reads better
    // than the whole address in a chat header.
    return email.contains('@') ? email.split('@').first : email;
  }

  String? photoFor(String email) =>
      resolve(email)?['profilePicture'] as String?;

  String? bioFor(String email) {
    final bio = resolve(email)?['bio'];
    return (bio is String && bio.trim().isNotEmpty) ? bio.trim() : null;
  }

  /// Returns what we have and starts a fetch if this email is new.
  Map<String, dynamic>? resolve(String email) {
    final key = email.toLowerCase();
    if (_byEmail.containsKey(key)) return _byEmail[key];
    _fetch(key);
    return null;
  }

  Future<void> _fetch(String key) async {
    if (_inFlight.contains(key)) return;
    _inFlight.add(key);
    try {
      final q = await _db
          .collection('users')
          .where('email', isEqualTo: key)
          .limit(1)
          .get();
      _byEmail[key] = q.docs.isEmpty
          ? null
          : {'uid': q.docs.first.id, ...q.docs.first.data()};
      notifyListeners();
    } catch (_) {
      // Leave it unknown so a later attempt can retry rather than caching
      // a failure as "this person does not exist".
      _byEmail.remove(key);
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Fetches several at once, for a list that is about to render.
  Future<void> warm(Iterable<String> emails) async {
    final missing = emails
        .map((e) => e.toLowerCase())
        .where((e) => e.isNotEmpty && !_byEmail.containsKey(e))
        .toSet();
    if (missing.isEmpty) return;
    await Future.wait(missing.map(_fetch));
  }

  /// Drops a cached entry so the next read re-fetches — used after someone
  /// edits their own profile.
  void invalidate(String email) {
    _byEmail.remove(email.toLowerCase());
    notifyListeners();
  }
}

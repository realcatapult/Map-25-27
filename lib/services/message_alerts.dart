import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'profile_cache.dart';

/// Which conversation the user is currently looking at.
///
/// A notification for the chat already on screen is noise, so each chat
/// screen claims the room while it is open and releases it on the way out.
class ActiveChat {
  static String? _id;

  static void enter(String id) => _id = id;

  static void leave(String id) {
    if (_id == id) _id = null;
  }

  static bool isOpen(String id) => _id == id;
}

/// A single incoming message worth announcing.
class MessageAlert {
  const MessageAlert({
    required this.title,
    required this.body,
    required this.senderEmail,
    required this.onOpen,
  });

  final String title;
  final String body;
  final String senderEmail;
  final VoidCallback onOpen;
}

/// Watches the user's conversations and announces messages that arrive while
/// they are somewhere else in the app.
///
/// This is deliberately not push notification: there is no FCM in this
/// project, so nothing can reach the user when the app is closed. What it
/// does cover is the common case — you are on the home screen or in another
/// chat and someone writes to you.
class MessageAlerts extends ChangeNotifier {
  MessageAlerts._();
  static final MessageAlerts instance = MessageAlerts._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final List<StreamSubscription<dynamic>> _subs = [];

  /// Message ids already seen. Firestore replays the latest document when a
  /// listener attaches, so without this every tab change would re-announce
  /// the last message in every conversation.
  final Set<String> _seen = {};

  /// Set once the initial replay for a conversation has been absorbed.
  final Set<String> _primed = {};

  MessageAlert? _current;
  MessageAlert? get current => _current;

  bool _running = false;

  /// Starts watching. Safe to call repeatedly; later calls are ignored while
  /// already running.
  void start() {
    if (_running) return;
    final me = _auth.currentUser?.email;
    if (me == null) return;
    _running = true;

    // Direct messages: every thread the user is part of.
    _subs.add(
      _db
          .collection('directMessages')
          .where('participants', arrayContains: me)
          .snapshots()
          .listen((threads) {
            for (final thread in threads.docs) {
              _watchDmThread(thread.id, me);
            }
          }),
    );

    // Club chats: every group the user belongs to.
    _subs.add(
      _db
          .collection('groups')
          .where('members', arrayContains: me)
          .snapshots()
          .listen((groups) {
            for (final g in groups.docs) {
              _watchGroup(g.id, (g.data()['name'] as String?) ?? 'Club', me);
            }
          }),
    );
  }

  final Set<String> _watching = {};

  void _watchDmThread(String threadId, String me) {
    final key = 'dm:$threadId';
    if (_watching.contains(key)) return;
    _watching.add(key);

    _subs.add(
      _db
          .collection('directMessages')
          .doc(threadId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .listen((snap) {
            if (snap.docs.isEmpty) return;
            final doc = snap.docs.first;
            final d = doc.data();
            final sender = (d['senderEmail'] as String?) ?? '';

            if (!_absorb(key, doc.id)) return;
            if (sender == me) return;
            if (ActiveChat.isOpen(key)) return;

            _raise(
              MessageAlert(
                title: ProfileCache.instance.nameFor(sender),
                body: (d['text'] as String?) ?? '',
                senderEmail: sender,
                onOpen: () {},
              ),
            );
          }),
    );
  }

  void _watchGroup(String groupId, String groupName, String me) {
    final key = 'group:$groupId';
    if (_watching.contains(key)) return;
    _watching.add(key);

    _subs.add(
      _db
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .listen((snap) {
            if (snap.docs.isEmpty) return;
            final doc = snap.docs.first;
            final d = doc.data();
            final sender = (d['senderEmail'] as String?) ?? '';

            if (!_absorb(key, doc.id)) return;
            if (sender == me) return;
            if (ActiveChat.isOpen(key)) return;

            final who = ProfileCache.instance.nameFor(sender);
            _raise(
              MessageAlert(
                title: groupName,
                body: '$who: ${(d['text'] as String?) ?? ''}',
                senderEmail: sender,
                onOpen: () {},
              ),
            );
          }),
    );
  }

  /// Returns true if this is genuinely new. The first document a listener
  /// delivers is history, not news, so it is swallowed.
  bool _absorb(String conversationKey, String messageId) {
    if (_seen.contains(messageId)) return false;
    _seen.add(messageId);

    if (!_primed.contains(conversationKey)) {
      _primed.add(conversationKey);
      return false;
    }
    return true;
  }

  Timer? _clear;

  void _raise(MessageAlert alert) {
    _current = alert;
    notifyListeners();

    // Long enough to read a line, short enough not to sit over the UI.
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 4), dismiss);
  }

  void dismiss() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  /// Tears everything down on sign-out, so the next account does not inherit
  /// another person's listeners or seen-message history.
  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _watching.clear();
    _seen.clear();
    _primed.clear();
    _clear?.cancel();
    _current = null;
    _running = false;
  }
}

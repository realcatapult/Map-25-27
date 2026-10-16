import 'package:flutter/material.dart';

/// A member's self-set availability inside one club.
///
/// Per club rather than per account on purpose: someone can be free for the
/// robotics build night and heads-down for debate the same evening, and a
/// single global status cannot express that.
enum ClubPresence {
  available,
  busy,
  away,
  doNotDisturb;

  /// Stored value. Kept as a short stable string so the field stays readable
  /// in the Firestore console and survives reordering this enum.
  String get id => switch (this) {
    ClubPresence.available => 'available',
    ClubPresence.busy => 'busy',
    ClubPresence.away => 'away',
    ClubPresence.doNotDisturb => 'dnd',
  };

  String get label => switch (this) {
    ClubPresence.available => 'Available',
    ClubPresence.busy => 'Busy',
    ClubPresence.away => 'Away',
    ClubPresence.doNotDisturb => 'Do Not Disturb',
  };

  /// What it tells other members. A status nobody can interpret is noise, so
  /// each one says what it means for being contacted.
  String get hint => switch (this) {
    ClubPresence.available => 'Free for club stuff',
    ClubPresence.busy => 'Around, but tied up',
    ClubPresence.away => 'Not checking this club',
    ClubPresence.doNotDisturb => 'Please do not ping me',
  };

  /// Colours are the conventional ones, so the dot needs no legend.
  Color get color => switch (this) {
    ClubPresence.available => const Color(0xFF23A55A),
    ClubPresence.busy => const Color(0xFFF0B232),
    ClubPresence.away => const Color(0xFF80848E),
    ClubPresence.doNotDisturb => const Color(0xFFF23F43),
  };

  /// The inner glyph, so the status is not conveyed by colour alone — the
  /// four dots have to be distinguishable to a colour-blind reader too.
  IconData? get glyph => switch (this) {
    ClubPresence.available => null,
    ClubPresence.busy => Icons.remove,
    ClubPresence.away => Icons.schedule,
    ClubPresence.doNotDisturb => Icons.do_not_disturb_on,
  };

  static ClubPresence fromId(String? id) => switch (id) {
    'busy' => ClubPresence.busy,
    'away' => ClubPresence.away,
    'dnd' => ClubPresence.doNotDisturb,
    _ => ClubPresence.available,
  };

  /// A member with no stored status reads as Available, so the member list
  /// never shows an empty or unknown state.
  static const ClubPresence fallback = ClubPresence.available;
}

/// The coloured dot, drawn to overlap an avatar's lower-right corner.
class PresenceDot extends StatelessWidget {
  const PresenceDot({
    super.key,
    required this.presence,
    this.size = 13,
    this.ringColor,
  });

  final ClubPresence presence;
  final double size;

  /// Matches the surface behind the avatar, which is what makes the dot read
  /// as punched out of it rather than floating on top.
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final ring = ringColor ?? Theme.of(context).colorScheme.surface;
    final glyph = presence.glyph;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: presence.color,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: size * 0.17),
      ),
      child: glyph == null
          ? null
          : Icon(glyph, size: size * 0.62, color: Colors.white),
    );
  }
}

/// An avatar with the presence dot attached.
class AvatarWithPresence extends StatelessWidget {
  const AvatarWithPresence({
    super.key,
    required this.avatar,
    required this.presence,
    this.dotSize = 13,
    this.ringColor,
  });

  final Widget avatar;
  final ClubPresence presence;
  final double dotSize;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: PresenceDot(
            presence: presence,
            size: dotSize,
            ringColor: ringColor,
          ),
        ),
      ],
    );
  }
}

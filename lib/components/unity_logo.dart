import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:login_ui/theme/app_theme.dart';

/// Displays the GroupApp brand mark.
///
/// This is the same artwork as the home-screen app icon, which carries its
/// own ivory backing, so the mark needs no tile behind it — it is simply
/// clipped to the rounded square the launcher icon already reads as.
class UnityLogo extends StatelessWidget {
  final double size;

  /// Controls how visible the mark is during the login reveal.
  final double assembly;

  /// Scales the complete mark away during the login reveal.
  final double explode;

  const UnityLogo({
    super.key,
    this.size = 120,
    this.assembly = 1,
    this.explode = 0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Opacity(
        opacity: (assembly * (1 - explode)).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 1 - 0.55 * explode,
          // Same corner radius iOS applies to the home-screen icon, so the
          // in-app mark and the installed app read as one thing.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.22),
            child: Image.asset(
              'images/logo.png',
              fit: BoxFit.cover,
              semanticLabel: 'GroupApp logo',
              // Decode at display size; the source is a 1024px icon.
              cacheWidth: (size * 3).round(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plays once after login: an overlay that spins the brand mark, then scales
/// and fades it away to reveal the app underneath.
///
/// This renders ONLY the logo + backdrop — stack it ON TOP of the real app so
/// the app never structurally moves in the tree (which would rebuild it and
/// cause a flicker). The split does NOT start until [ready] is true, with a
/// [maxWait] cap. Calls [onDone] when finished so the parent can remove it.
class UnityRevealOverlay extends StatefulWidget {
  /// Flips to true when the app content behind the overlay is loaded. The split
  /// waits for this (up to [maxWait]) so real content is shown, not a skeleton.
  final ValueListenable<bool>? ready;

  /// Hard cap on how long to hold before splitting even if [ready] never fires.
  final Duration maxWait;

  /// Called once when the reveal animation finishes.
  final VoidCallback? onDone;

  const UnityRevealOverlay({
    super.key,
    this.ready,
    this.maxWait = const Duration(seconds: 6),
    this.onDone,
  });

  @override
  State<UnityRevealOverlay> createState() => _UnityRevealOverlayState();
}

class _UnityRevealOverlayState extends State<UnityRevealOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _minSpin = Duration(milliseconds: 1800);
  // Extra grace period spun AFTER the app reports ready — keeps the opaque
  // backdrop up a bit longer so the content fully settles before it's revealed
  // (covers any brief post-load flicker).
  static const Duration _readyGrace = Duration(milliseconds: 500);

  // Continuous spin controller (loops). We switch it to the one-shot split when
  // the app behind is ready AND the minimum time has elapsed.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000), // one spin loop = 1s
  );

  final Stopwatch _elapsed = Stopwatch()..start();
  bool _splitting = false; // true once the explode has begun
  bool _done = false;
  double _spinAtSplit = 0; // spin angle frozen when the split starts
  Stopwatch? _readySince; // starts when the app first reports ready

  @override
  void initState() {
    super.initState();
    _c.addStatusListener(_onStatus);
    _c.repeat(); // spin forever until we trigger the split
    widget.ready?.addListener(_maybeSplit);
    // Also poll, so "min time reached after ready" is handled.
    _tick();
  }

  void _tick() {
    if (!mounted || _splitting) return;
    _maybeSplit();
    if (!_splitting) {
      Future.delayed(const Duration(milliseconds: 60), _tick);
    }
  }

  void _maybeSplit() {
    if (_splitting || !mounted) return;
    final ready = widget.ready?.value ?? true;

    // Once ready, start (or keep) the grace clock. Only split after the grace
    // period AND the overall minimum spin time have both elapsed.
    if (ready) {
      _readySince ??= Stopwatch()..start();
    } else {
      _readySince = null; // not ready anymore — reset the grace clock
    }

    final graceDone =
        _readySince != null && _readySince!.elapsed >= _readyGrace;
    if (ready && graceDone && _elapsed.elapsed >= _minSpin) {
      _beginSplit();
    }
  }

  void _beginSplit() {
    if (_splitting || !mounted) return;
    _splitting = true;
    _spinAtSplit = _c.value; // freeze rotation here
    _c.stop();
    _c
      ..duration = const Duration(milliseconds: 650)
      ..value = 0
      ..forward(); // now _c.value drives the explode 0->1
    setState(() {});
  }

  void _onStatus(AnimationStatus s) {
    if (_splitting && s == AnimationStatus.completed && mounted) {
      setState(() => _done = true);
      widget.onDone?.call();
    }
  }

  @override
  void dispose() {
    widget.ready?.removeListener(_maybeSplit);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the overlay opaque until its final frame so removing it does not
    // reveal a partially blended frame.
    if (_done) return const SizedBox.shrink();

    return IgnorePointer(
      // Navy backdrop; the mark's tile is one step lighter so it reads as
      // a tile rather than merging into this.
      child: ColoredBox(
        color: AppColors.navy,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final spin = (_splitting ? _spinAtSplit : _c.value) * 2 * math.pi;
              final split = _splitting ? _c.value : 0.0;
              final explode = Curves.easeInCubic.transform(split);
              return Center(
                child: Transform.rotate(
                  angle: spin,
                  child: UnityLogo(size: 160, assembly: 1, explode: explode),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

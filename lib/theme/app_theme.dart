import 'dart:ui';
import 'package:flutter/material.dart';

/// Navy + White + Brass design tokens with glassmorphism and warm glow.
class AppColors {
  // Brass is the primary accent (warm gold).
  static const Color brass = Color(0xFFC9A227);
  static const Color brassLight = Color(0xFFE6C55A);
  static const Color brassDeep = Color(0xFF9A7B1B);

  // Navy is the brand/base color.
  static const Color navy = Color(0xFF0A1836);
  static const Color navyMid = Color(0xFF14294F);
  static const Color navyDeep = Color(0xFF060F24);

  // Primary/secondary map to brass + navy so buttons/highlights read brass.
  static const Color primary = brass;
  static const Color secondary = brassLight;
  static const Color deepBlue = navy;

  // Legacy accent aliases (many widgets reference these) → brass family, so
  // every existing "glow"/highlight becomes brass automatically.
  static const Color cyan = brass;
  static const Color teal = brassLight;
  static const Color green = brassLight;

  // Base surfaces (DARK mode) — deeper blues over soft black.
  static const Color bg = Color(0xFF070C18); // scaffold: soft-black navy
  static const Color surface = Color(0xFF0E1E3D); // card / panel: deep blue
  static const Color surfaceHigh = Color(0xFF152A50); // higher elevation

  // Light-mode base — warm ivory white (navy text, brass accents).
  static const Color bgLight = Color(0xFFF6F3EC); // warm ivory
  static const Color surfaceLight = Color(0xFFFFFFFF);

  static const Color textDark = Color(0xFFF3F6FC); // near-white on navy
  static const Color textMutedDark = Color(0xFFAEBBD4);
  static const Color textLight = navy; // navy text in light mode
  static const Color textMutedLight = Color(0xFF5A6B8A);

  /// Signature diagonal brand gradient — clearly navy blue (light mode).
  static const List<Color> brandGradient = [
    Color(0xFF1E3A6E),
    Color(0xFF27509A),
    Color(0xFF3465C0),
  ];

  /// Deeper navy gradient for dark mode.
  static const List<Color> brandGradientDark = [
    Color(0xFF0E1E3D),
    Color(0xFF163060),
    Color(0xFF1E4285),
  ];

  /// Accent gradient used on buttons / highlights (brass).
  static const List<Color> accentGradient = [brass, brassLight];
}

/// Full-screen gradient wallpaper with two translucent accent circles.
///
/// Dark mode: deeper blues / soft-black base. Light mode: warm ivory with
/// navy + brass accents (strictly the navy/white/brass palette).
class NeonBackground extends StatelessWidget {
  final Widget child;
  const NeonBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Base gradient.
    final baseGradient = isDark
        ? const [Color(0xFF05070E), Color(0xFF0B1A33)] // soft-black → deep blue
        : const [Color(0xFFFBF9F3), Color(0xFFEFE9DC)]; // warm ivory

    // Two translucent accent circles (brass + navy).
    final circleTop = isDark
        ? AppColors.brass.withValues(alpha: 0.14)
        : AppColors.brass.withValues(alpha: 0.16);
    final circleBottom = isDark
        ? const Color(0xFF2A4E86).withValues(alpha: 0.22) // deep blue
        : AppColors.navy.withValues(alpha: 0.08);

    // Full physical screen height, ignoring keyboard insets, so the wallpaper
    // NEVER shifts when the keyboard opens (the body shrinks, the bg stays put).
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Wallpaper layer pinned to the full screen height. OverflowBox lets it
        // keep its full size even when the Scaffold body shrinks for the keyboard.
        Positioned.fill(
          child: OverflowBox(
            minHeight: screenHeight,
            maxHeight: screenHeight,
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: screenHeight,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: baseGradient,
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -90,
                    right: -70,
                    child: _circle(circleTop, 260),
                  ),
                  Positioned(
                    bottom: -110,
                    left: -80,
                    child: _circle(circleBottom, 300),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Page content — tight, bounded constraints (resizes with the keyboard).
        Positioned.fill(child: child),
      ],
    );
  }

  Widget _circle(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

/// A frosted "glassmorphism" card — translucent fill, blur, thin edge.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isDark
                  ? AppColors.cyan.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.06),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? AppColors.cyan.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );

    if (onTap == null) {
      return Padding(padding: margin ?? EdgeInsets.zero, child: card);
    }
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: card,
        ),
      ),
    );
  }
}

/// A pill button with the neon accent gradient and a soft glow.
class NeonButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;

  const NeonButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(colors: AppColors.accentGradient),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
              child: IconTheme.merge(
                data: const IconThemeData(color: Colors.white),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A gradient app bar background (drop into AppBar.flexibleSpace).
///
/// Uses SizedBox.expand so the gradient fills the entire app bar area — a bare
/// DecoratedBox has zero size and would leave the (transparent) app bar black.
class GradientAppBarBackground extends StatelessWidget {
  const GradientAppBarBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? AppColors.brandGradientDark
                : AppColors.brandGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }
}

/// Fades + slides a child up into place on first build. Pass [delay] to
/// stagger a list (e.g. index * 40ms) so items cascade in.
class AnimatedEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;

  const AnimatedEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 380),
    this.offsetY = 18,
  });

  @override
  State<AnimatedEntrance> createState() => _AnimatedEntranceState();
}

class _AnimatedEntranceState extends State<AnimatedEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        return Opacity(
          opacity: _curve.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _curve.value) * widget.offsetY),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Scales its child down briefly while pressed, for tactile feedback.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

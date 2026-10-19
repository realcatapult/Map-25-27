import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'Pages/admin_dashboard_page.dart';
import 'Pages/auth_page.dart';
import 'Pages/home_page.dart';
import 'services/chat_service.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';
import 'components/unity_logo.dart';
import 'components/skeleton_loader.dart';
import 'components/message_alert_overlay.dart';
import 'services/message_alerts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    const primaryColor = AppColors.primary;
    const secondaryColor = AppColors.secondary;

    final baseTextColor = isDark ? AppColors.textDark : AppColors.textLight;
    final mutedTextColor = isDark
        ? AppColors.textMutedDark
        : AppColors.textMutedLight;
    final poppinsTextTheme = GoogleFonts.poppinsTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ).apply(bodyColor: baseTextColor, displayColor: baseTextColor);

    final surface = isDark ? AppColors.surface : AppColors.surfaceLight;
    final surfaceHigh = isDark ? AppColors.surfaceHigh : Colors.white;

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      textTheme: poppinsTextTheme,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: primaryColor,
            brightness: brightness,
          ).copyWith(
            primary: primaryColor,
            secondary: secondaryColor,
            surface: surface,
            surfaceContainerLow: isDark
                ? AppColors.surface
                : const Color(0xFFF0EBDF),
            surfaceContainerHigh: surfaceHigh,
            surfaceContainerHighest: surfaceHigh,
            onSurface: baseTextColor,
            onSurfaceVariant: mutedTextColor,
            onPrimary: AppColors.navy,
          ),
      scaffoldBackgroundColor: isDark ? AppColors.bg : AppColors.bgLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardColor: surface,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: AppColors.navy,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        hintStyle: TextStyle(color: mutedTextColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : primaryColor.withValues(alpha: 0.20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryColor, width: 1.6),
        ),
      ),
    );
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          home: const _AuthGate(),
        );
      },
    );
  }
}

/// Watches auth state, shows the brand-mark loading screen while resolving, and
/// plays the split-apart reveal exactly once when the user logs in.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final ChatService _chatService = ChatService();

  bool _wasLoggedIn = false;

  // False until the login reveal has finished for this session. The overlay is
  // a permanent Stack sibling; once this flips true it renders as a no-op (we
  // never remove it from the tree — that teardown caused a 1-frame flash).
  bool _playedReveal = false;

  // Cached per login so rebuilds reuse the SAME Future/landing widget instead
  // of recreating them every frame — recreating them made the skeleton flicker.
  Future<bool>? _adminCheck;
  Widget? _landing;

  // The reveal holds until this flips true, so the split never exposes a
  // skeleton. It becomes true once the admin check AND the first groups
  // snapshot have arrived.
  final ValueNotifier<bool> _appReady = ValueNotifier<bool>(false);
  StreamSubscription<QuerySnapshot>? _groupsSub;
  bool _adminDone = false;
  bool _groupsDone = false;

  void _armReadyTracking() {
    _adminDone = false;
    _groupsDone = false;
    _appReady.value = false;

    _adminCheck!.whenComplete(() {
      _adminDone = true;
      _updateReady();
    });

    _groupsSub?.cancel();
    _groupsSub = _chatService.getUserGroups().listen(
      (_) {
        _groupsDone = true;
        _updateReady();
      },
      onError: (_) {
        _groupsDone = true;
        _updateReady();
      },
    );
  }

  void _updateReady() {
    if (_adminDone && _groupsDone) _appReady.value = true;
  }

  @override
  void dispose() {
    _groupsSub?.cancel();
    _appReady.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // authStateChanges fires only on actual sign-in/out — NOT on periodic
      // token refreshes. idTokenChanges was rebuilding this whole tree (and the
      // NeonBackground) on every token tick right after login, flashing the bg.
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SkeletonScreen();
        }

        final loggedIn = snapshot.hasData;

        // Detect the logged-out -> logged-in transition.
        if (loggedIn && !_wasLoggedIn) {
          MessageAlerts.instance.start(); // watch conversations
          _playedReveal = false; // arm the reveal for this fresh login
          _adminCheck = _chatService.isCurrentUserSchoolAdmin(); // once
          _landing = null; // rebuild landing with the fresh check
          _armReadyTracking(); // start watching for "app loaded"
        }
        if (!loggedIn) {
          // Drop listeners and seen-history so the next account does not
          // inherit another person's conversations.
          MessageAlerts.instance.stop();
          _playedReveal = false;
          _adminCheck = null;
          _landing = null;
          _groupsSub?.cancel();
          _appReady.value = false;
        }
        _wasLoggedIn = loggedIn;

        if (!loggedIn) {
          return const AuthPage();
        }

        // Build the landing exactly once and reuse it across rebuilds.
        _landing ??= _buildLanding();

        // The landing ALWAYS sits at this fixed position in the tree (never
        // rebuilt/re-subscribed). The reveal overlay is a PERMANENT sibling on
        // top — it renders itself as a zero-size no-op once finished, and we do
        // NOT remove it from the Stack. Removing it (tearing down its Opacity/
        // compositing layer) in the same frame the app becomes visible caused a
        // one-frame flash at the handoff. Keeping it avoids that entirely.
        return Stack(
          fit: StackFit.expand,
          children: [
            _landing!,
            const MessageAlertOverlay(),
            if (_playedReveal)
              const SizedBox.shrink()
            else
              UnityRevealOverlay(
                key: const ValueKey('login-reveal'),
                ready: _appReady,
                onDone: () {
                  // Defer the state flip so the overlay's final fully-transparent
                  // frame has already painted before we swap it for a no-op.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _playedReveal = true);
                  });
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildLanding() {
    return FutureBuilder<bool>(
      future: _adminCheck ??= _chatService.isCurrentUserSchoolAdmin(),
      builder: (context, adminSnapshot) {
        // Show the real landing page immediately after login so the reveal can
        // transition smoothly without a blank flash. Admins still switch to the
        // dashboard once the check resolves.
        if (adminSnapshot.connectionState == ConnectionState.waiting) {
          return const HomePage();
        }
        if (adminSnapshot.hasError || adminSnapshot.data != true) {
          return const HomePage();
        }
        return AdminDashboardPage();
      },
    );
  }
}

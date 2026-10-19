import 'package:flutter/material.dart';
import 'package:login_ui/components/my_textfield.dart';
import 'package:login_ui/components/my_button.dart';
import 'package:login_ui/components/square_tile.dart';
import 'dart:math' as math;
import 'package:login_ui/services/auth_service.dart';
import 'package:login_ui/theme/app_theme.dart';
import 'package:login_ui/components/unity_logo.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback? showRegisterPage;

  const LoginPage({super.key, this.showRegisterPage});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // text editing controllers
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  // sign user in method
  void signUserIn() async {
    try {
      await _authService.signInWithEmailPassword(
        emailController.text.trim(),
        passwordController.text,
      );
      // Accounts created before profiles were written automatically have no
      // users document, which makes them invisible to member lists and
      // friend lookups. Backfill the email once, on the way in.
      await _authService.ensureProfileExists();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NeonBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 40),

                  // GroupApp brand mark
                  const _PulsingUnityLogo(size: 100),
                  const SizedBox(height: 18),

                  // App name
                  const Text(
                    'GroupApp',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: AppColors.brass,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // welcome back
                  Text(
                    'Welcome back!',
                    style: TextStyle(color: Colors.grey[700], fontSize: 16),
                  ),
                  const SizedBox(height: 10),

                  // Email
                  MyTextField(
                    controller: emailController,
                    hintText: 'Email',
                    obscureText: false,
                  ),
                  const SizedBox(height: 16),

                  // Password
                  MyTextField(
                    controller: passwordController,
                    hintText: 'Password',
                    obscureText: true,
                  ),
                  const SizedBox(height: 10),

                  // Forgot password
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Forgot Password?',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),

                  // Sign in button
                  MyButton(onTap: signUserIn),
                  const SizedBox(height: 40),

                  // Divider with text
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Divider(
                            thickness: 0.5,
                            color: Colors.grey[400],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0),
                          child: Text(
                            'Or continue with',
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            thickness: 0.5,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 5),

                  // social buttons placeholder with labels
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Google button + label
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SquareTile(imagePath: 'lib/images/google.png'),
                          const SizedBox(height: 8),
                          const Text(
                            'Google',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),

                      const SizedBox(width: 25),

                      // Apple button + label
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SquareTile(
                            imagePath: 'lib/images/apple.png',
                            logoHeight: 46,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Apple',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 50),

                  //not a member register
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Not a member?',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: widget.showRegisterPage,
                        child: const Text(
                          'Register now',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The GroupApp logo with a gentle breathing pulse + soft rotation drift, for the
/// login screen hero.
class _PulsingUnityLogo extends StatefulWidget {
  final double size;
  const _PulsingUnityLogo({required this.size});

  @override
  State<_PulsingUnityLogo> createState() => _PulsingUnityLogoState();
}

class _PulsingUnityLogoState extends State<_PulsingUnityLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final pulse = 1 + 0.04 * math.sin(t * 2 * math.pi);
        final drift = math.sin(t * 2 * math.pi) * 0.06;
        return Transform.rotate(
          angle: drift,
          child: Transform.scale(
            scale: pulse,
            child: UnityLogo(size: widget.size),
          ),
        );
      },
    );
  }
}

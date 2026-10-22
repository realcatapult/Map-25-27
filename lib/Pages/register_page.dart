import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:login_ui/components/my_textfield.dart';
import 'package:login_ui/services/auth_service.dart';
import 'package:login_ui/services/chat_service.dart';
import 'package:login_ui/theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:login_ui/components/image_source_sheet.dart';
import 'dart:io';

class RegisterPage extends StatefulWidget {
  final VoidCallback showLoginPage;

  const RegisterPage({super.key, required this.showLoginPage});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // text editing controllers
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController adminCodeController = TextEditingController();
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();
  final ImagePicker _imagePicker = ImagePicker();
  File? _profileImage;
  bool _signUpAsAdmin = false;
  bool _isSigningUp = false;

  Future<void> _rollbackFailedAdminSignup() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        await currentUser.delete();
      } catch (_) {
        // If delete fails for any reason, still force sign-out below.
      }
    }
    await _authService.signOut();
  }

  void signUserUp() async {
    if (_isSigningUp) return;
    if (passwordController.text != confirmPasswordController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Passwords don't match!")));
      return;
    }
    if (_signUpAsAdmin && adminCodeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the admin verification code.')),
      );
      return;
    }

    setState(() {
      _isSigningUp = true;
    });

    try {
      await _authService.signUpWithEmailPassword(
        emailController.text.trim(),
        passwordController.text,
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
      );

      // Upload profile picture if selected
      if (_profileImage != null) {
        final imageUrl = await _chatService.uploadProfilePicture(
          _profileImage!,
        );
        await _chatService.updateProfilePicture(imageUrl);
      }

      if (_signUpAsAdmin) {
        final code = adminCodeController.text.trim();
        if (code != '9999') {
          await _rollbackFailedAdminSignup();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid admin code. Account not created.'),
            ),
          );
          return;
        }

        await _chatService.setCurrentUserSchoolAdmin(true);
        await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSigningUp = false;
        });
      }
    }
  }

  void _pickProfilePicture() async {
    final source = await showImageSourceSheet(context);
    if (source == null) return;

    final XFile? image = await _imagePicker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() {
        _profileImage = File(image.path);
      });
    }
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    adminCodeController.dispose();
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
                  const SizedBox(height: 25),

                  // App name
                  Text(
                    'GroupApp',
                    style: TextStyle(
                      fontSize: 45,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Let's create an account
                  Text(
                    "Let's create an account for you!",
                    style: TextStyle(color: Colors.grey[700], fontSize: 16),
                  ),
                  const SizedBox(height: 25),

                  // Profile picture picker
                  GestureDetector(
                    onTap: _pickProfilePicture,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey[400],
                      backgroundImage: _profileImage != null
                          ? FileImage(_profileImage!)
                          : null,
                      child: _profileImage == null
                          ? Icon(
                              Icons.add_a_photo,
                              size: 40,
                              color: Colors.grey[700],
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to add profile picture (optional)',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 25),

                  // Name, so the person shows up as a name rather than an
                  // email everywhere else in the app.
                  MyTextField(
                    controller: firstNameController,
                    hintText: 'First name',
                    obscureText: false,
                  ),
                  const SizedBox(height: 10),

                  MyTextField(
                    controller: lastNameController,
                    hintText: 'Last name',
                    obscureText: false,
                  ),
                  const SizedBox(height: 10),

                  // Email
                  MyTextField(
                    controller: emailController,
                    hintText: 'Email',
                    obscureText: false,
                  ),
                  const SizedBox(height: 10),

                  // Password
                  MyTextField(
                    controller: passwordController,
                    hintText: 'Password',
                    obscureText: true,
                  ),
                  const SizedBox(height: 10),

                  // Confirm password
                  MyTextField(
                    controller: confirmPasswordController,
                    hintText: 'Confirm Password',
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: CheckboxListTile(
                        value: _signUpAsAdmin,
                        onChanged: (value) {
                          setState(() {
                            _signUpAsAdmin = value ?? false;
                          });
                        },
                        title: const Text('Sign up as admin'),
                        subtitle: const Text(
                          'After signup, you must verify with a code to unlock admin access.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                  ),
                  if (_signUpAsAdmin) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 25.0),
                      child: TextField(
                        controller: adminCodeController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Admin verification code',
                          hintText: 'Enter code',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 25),

                  // Sign up button
                  GestureDetector(
                    onTap: _isSigningUp ? null : signUserUp,
                    child: Container(
                      padding: const EdgeInsets.all(25),
                      margin: const EdgeInsets.symmetric(horizontal: 25),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isSigningUp
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Sign Up',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 50),

                  // Already have an account? Login now
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account?',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: widget.showLoginPage,
                        child: const Text(
                          'Login now',
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

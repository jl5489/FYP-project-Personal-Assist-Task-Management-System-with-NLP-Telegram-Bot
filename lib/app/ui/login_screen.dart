import 'package:flutter/material.dart';
import 'package:todark/app/controller/auth_controller.dart';
import 'package:get/get.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailOrUsernameController =
      TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthController _authController = Get.find<AuthController>();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final verificationMessage =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (verificationMessage != null &&
                verificationMessage['verificationMessage'] != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  verificationMessage['verificationMessage'],
                  style: const TextStyle(color: Colors.green),
                  textAlign: TextAlign.center,
                ),
              ),
            const Text(
              'Welcome Back!',
              style: TextStyle(
                fontSize: 32.0,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 20.0),
            _buildTextField(
              _emailOrUsernameController,
              'Email or Username',
              false,
            ),
            const SizedBox(height: 20.0),
            _buildTextField(_passwordController, 'Password', true),
            const SizedBox(height: 20.0),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            _buildLoginButton(),
            const SizedBox(height: 20.0),
            _buildDivider(),
            const SizedBox(height: 20.0),
            _buildGoogleSignInButton(),
            const SizedBox(height: 20.0),
            _buildSignUpLink(),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, bool obscure) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.deepPurple),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.deepPurple),
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildLoginButton() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ElevatedButton(
            onPressed: _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
            child: const Text(
              'Login',
              style: TextStyle(fontSize: 18.0),
            ),
          );
  }

  Widget _buildGoogleSignInButton() {
    return OutlinedButton.icon(
      onPressed: _handleGoogleSignIn,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        minimumSize: const Size(double.infinity, 50),
        side: const BorderSide(color: Colors.deepPurple),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
      ),
      icon: Image.asset('assets/google_logo.png', height: 24.0),
      label: const Text(
        'Continue with Google',
        style: TextStyle(
          fontSize: 18.0,
          color: Colors.deepPurple,
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Row(
      children: [
        Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text('OR'),
        ),
        Expanded(child: Divider()),
      ],
    );
  }

  Widget _buildSignUpLink() {
    return Center(
      child: TextButton(
        onPressed: () {
          Navigator.pushNamed(context, '/signup');
        },
        child: const Text(
          'Don\'t have an account? Sign Up',
          style: TextStyle(
            color: Colors.deepPurple,
            fontSize: 16.0,
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authController.loginWithEmailAndPassword(
        _emailOrUsernameController.text.trim(),
        _passwordController.text.trim(),
      );

      // Navigate to home after successful login
      Get.offAllNamed('/home');
    } catch (error) {
      setState(() => _errorMessage = error.toString());
      Get.snackbar("Login Error", _errorMessage!,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // Trigger Google sign-in
      await _authController.signInWithGoogle();

      if (mounted) {
        // Navigate to home screen only if the widget is still mounted
        Get.offAllNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
        Get.snackbar("Error", "Google Sign-In failed: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailOrUsernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

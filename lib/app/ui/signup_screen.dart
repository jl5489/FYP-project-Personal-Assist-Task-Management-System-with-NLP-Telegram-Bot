import 'package:flutter/material.dart';
import 'package:todark/app/controller/auth_controller.dart';
import 'package:get/get.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  SignupScreenState createState() => SignupScreenState();
}

class SignupScreenState extends State<SignupScreen> {
  bool _isValidEmail(String email) {
    return RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(email);
  }

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final AuthController _authController = AuthController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create Account',
              style: TextStyle(
                  fontSize: 32.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple),
            ),
            const SizedBox(height: 20.0),
            _buildTextField(_nameController, 'Full Name', false),
            const SizedBox(height: 20.0),
            _buildTextField(_emailController, 'Email', false),
            const SizedBox(height: 20.0),
            _buildTextField(_passwordController, 'Password', true),
            const SizedBox(height: 20.0),
            _buildTextField(
                _confirmPasswordController, 'Confirm Password', true),
            const SizedBox(height: 20.0),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            _buildSignUpButton(),
            const SizedBox(height: 20.0),
            _buildDivider(),
            const SizedBox(height: 20.0),
            _buildGoogleSignInButton(),
            const SizedBox(height: 20.0),
            _buildLoginLink(),
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

  Widget _buildSignUpButton() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ElevatedButton(
            onPressed: _handleSignUp,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
            child: const Text(
              'Sign Up',
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
        'Sign up with Google',
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

  Widget _buildLoginLink() {
    return Center(
      child: TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text(
          'Already have an account? Login',
          style: TextStyle(
            color: Colors.deepPurple,
            fontSize: 16.0,
          ),
        ),
      ),
    );
  }

  Future<void> _handleSignUp() async {
    // Add more comprehensive form validation
    if (_nameController.text.length < 2) {
      setState(() => _errorMessage = "Name must be at least 2 characters");
      return;
    }

    if (!_isValidEmail(_emailController.text)) {
      setState(() => _errorMessage = "Invalid email format");
      return;
    }

    if (_passwordController.text.length < 8) {
      setState(() => _errorMessage = "Password must be at least 8 characters");
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = "Passwords don't match");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authController.signUpWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        name: _nameController.text.trim(),
      );

      // Navigate to login screen with a verification message
      Get.offAllNamed('/login', arguments: {
        'verificationMessage':
            'Please verify your email. Check your inbox and click the verification link.'
      });
    } catch (error) {
      setState(() => _errorMessage = error.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // For Google Sign-In, we'll still navigate to home for now
      await _authController.signInWithGoogle();
      Navigator.pushReplacementNamed(context, '/home');
    } catch (error) {
      setState(() => _errorMessage = error.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}

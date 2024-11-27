import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart'; // Add this import for Colors
import 'package:todark/app/controller/isar_contoller.dart';

class AuthController extends GetxController {
  final bool _isDebugMode = true;

  void _logDebug(String message) {
    if (_isDebugMode) {
      print('IsarDebug: $message');
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'The account already exists for that email.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'operation-not-allowed':
        return 'Operation not allowed. Please contact support.';
      case 'user-disabled':
        return 'This user has been disabled.';
      case 'user-not-found':
        return 'No user found for that email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'too-many-requests':
        return 'Too many login attempts. Please try again later.';
      case 'email-not-verified':
        return 'Please verify your email.';
      case 'null-user':
        return 'Login failed - no user returned.';
      case 'invalid-input':
        return 'Email and password cannot be empty.';
      default:
        return e.message ?? 'An unknown error occurred.';
    }
  }

  bool _isStrongPassword(String password) {
    // Add your password strength validation logic here
    // For example, you can use a regular expression to check for the required criteria
    return password.length >= 8 &&
        RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password);
  }

  bool _isValidEmail(String email) {
    return RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(email);
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final Logger _logger = Logger();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final IsarController _isarController = Get.find<IsarController>();

  var user = Rxn<User>();
  var userData = {}.obs;
  int _loginAttempts = 0;
  DateTime? _lastLoginAttempt;
  // Reactive variables

  // Tracks the current user's UID
  String? currentUserId;
  @override
  void onInit() {
    super.onInit();

    // Set up Firebase Auth state listener
    user.value = _auth.currentUser;
    if (_auth.currentUser != null) {
      setCurrentUserId(_auth.currentUser!.uid);
    }

    _auth.authStateChanges().listen((User? firebaseUser) {
      user.value = firebaseUser;
      if (firebaseUser != null) {
        setCurrentUserId(firebaseUser.uid);
        fetchUserData(firebaseUser.uid);
      } else {
        currentUserId = null; // Reset UID if logged out
      }
    });
  }

  /// Sets the current user ID
  void setCurrentUserId(String uid) {
    currentUserId = uid;
    print("Current user ID set: $currentUserId");
  }

  // Fetch user-specific data (profile, tasks, todos, notifications)
  Future<Map<String, dynamic>> fetchUserData(String uid) async {
    try {
      await _isarController.clearDatabase();

      // Fetch related collections in parallel
      final userDocFuture = _firestore.collection('users').doc(uid).get();
      final taskFuture =
          _firestore.collection('tasks').where('uid', isEqualTo: uid).get();
      final todoFuture =
          _firestore.collection('todos').where('uid', isEqualTo: uid).get();
      final notificationFuture = _firestore
          .collection('notifications')
          .where('uid', isEqualTo: uid)
          .get();

      // Wait for all queries to complete
      final results = await Future.wait([
        userDocFuture,
        taskFuture,
        todoFuture,
        notificationFuture,
      ]);
      final userDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final taskSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final todoSnapshot = results[2] as QuerySnapshot<Map<String, dynamic>>;
      final notificationSnapshot =
          results[3] as QuerySnapshot<Map<String, dynamic>>;

      // Check if user document exists
      if (!userDoc.exists) {
        _logger.w("User document not found for UID: $uid");
        throw Exception("User document does not exist.");
      }

      // Clear existing local data
      await _isarController.syncDataWithFirestore(
        currentUserId: uid, // Pass the currentUserId here
        tasks: taskSnapshot.docs,
        todos: todoSnapshot.docs,
        notifications: notificationSnapshot.docs,
      );

      // Verify sync was successful
      await _isarController.verifySync();

      // Update userData (RxMap) value
      final updatedUserData = {
        "user": _parseFirestoreUser(userDoc.data()),
        "tasks": taskSnapshot.docs.map((doc) => doc.data()).toList(),
        "todos": todoSnapshot.docs.map((doc) => doc.data()).toList(),
        "notifications":
            notificationSnapshot.docs.map((doc) => doc.data()).toList(),
      };

      userData.value = updatedUserData;

      return updatedUserData;
    } catch (e) {
      _logger.e("Error fetching user data: $e");
      throw Exception("Failed to fetch user data.");
    }
  }

  void verifyFirestoreData(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      String collectionName) {
    final ids = docs.map((doc) => doc.id).toList();
    final duplicates = ids.toSet().difference(ids.toSet());

    if (duplicates.isNotEmpty) {
      _logDebug(
          'Duplicate Firestore IDs detected in $collectionName: $duplicates');
    }
  }

  Future<void> fetchAndClearUserData(String uid) async {
    try {
      // Clear database first
      await _isarController.clearDatabase();

      // Then fetch new data
      await fetchUserData(uid);
    } catch (e) {
      _logger.e("Error in fetchAndClearUserData: $e");
      throw Exception("Failed to fetch and clear user data: $e");
    }
  }

// Helper function to parse Firestore user data
  Map<String, dynamic> _parseFirestoreUser(Map<String, dynamic>? userData) {
    if (userData == null) {
      return {};
    }

    return {
      "uid": userData['uid'] ?? '',
      "email": userData['email'] ?? '',
      "name": userData['name'] ?? 'Unknown User',
      "createdAt": _parseTimestamp(userData['createdAt']),
      "lastLogin": _parseTimestamp(userData['lastLogin']),
      "profileCompleted": userData['profileCompleted'] ?? false,
      "subscription": userData['subscription'] ?? 'free',
      "roles": userData['roles'] ?? ['user'],
      "authMethod": userData['authMethod'] ?? 'email',
    };
  }

// Helper function to parse timestamps
  DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }

    return DateTime.now();
  }

// Added verification in fetchAndReturnUserData
  Future<Map<String, dynamic>> fetchAndReturnUserData(String uid) async {
    await fetchAndClearUserData(uid);
    return await fetchUserData(uid);
  }

// Added proper checks and synchronization in signInWithGoogle
  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; // User cancelled the Google Sign-In

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      final User? firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        throw Exception("Google Sign-In failed. Please try again.");
      }

      // Fetch user document or create a new one
      final userDoc =
          await _firestore.collection('users').doc(firebaseUser.uid).get();

      if (!userDoc.exists) {
        await _firestore.collection('users').doc(firebaseUser.uid).set({
          'uid': firebaseUser.uid,
          'email': firebaseUser.email,
          'name': firebaseUser.displayName ?? 'Google User',
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'profileCompleted': false,
          'subscription': 'free',
          'roles': ['user'],
          'authMethod': 'google',
        });
      } else {
        // Update last login time
        await _firestore.collection('users').doc(firebaseUser.uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }

      // Fetch and sync user data after login
      setCurrentUserId(firebaseUser.uid);

      await fetchUserData(firebaseUser.uid);

      Get.snackbar(
        "Success",
        "Logged in successfully",
        snackPosition: SnackPosition.BOTTOM,
      );
      Get.offAllNamed('/home');
    } catch (e) {
      Get.snackbar("Error", "Google Sign-In failed: $e");
    }
  }

  // Email and Password Login
  Future<void> loginWithEmailAndPassword(String email, String password) async {
    try {
      // Rate limiting check
      if (_loginAttempts >= 3) {
        final now = DateTime.now();
        if (_lastLoginAttempt != null &&
            now.difference(_lastLoginAttempt!) < const Duration(minutes: 5)) {
          throw FirebaseAuthException(
            code: 'too-many-requests',
            message: 'Too many login attempts. Please try again later.',
          );
        }
        _loginAttempts = 0;
      }

      // Validate input
      if (email.isEmpty || password.isEmpty) {
        throw FirebaseAuthException(
          code: 'invalid-input',
          message: 'Email and password cannot be empty',
        );
      }

      // Trim whitespace from email
      email = email.trim();

      _logger.i('Attempting login for email: $email');

      // Attempt to sign in
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        throw FirebaseAuthException(
          code: 'null-user',
          message: 'Login failed - no user returned',
        );
      }

      // Check if email is verified
      if (!credential.user!.emailVerified) {
        // Send verification email again
        await credential.user!.sendEmailVerification();

        // Sign out user
        await _auth.signOut();

        throw FirebaseAuthException(
          code: 'email-not-verified',
          message:
              'Please verify your email. A new verification link has been sent.',
        );
      }

      // Reset login attempts on successful login
      _loginAttempts = 0;
      _lastLoginAttempt = null;

      // Fetch and synchronize user data
      await _isarController.clearDatabase();

      // Fetch user data after successful login
      setCurrentUserId(credential.user!.uid);

      await fetchUserData(credential.user!.uid);

      // Update user state
      user.value = credential.user;

      Get.snackbar(
        "Success",
        "Logged in successfully",
        snackPosition: SnackPosition.BOTTOM,
      );

      // Navigate to home screen
      Get.offAllNamed('/home');
    } on FirebaseAuthException catch (e) {
      _loginAttempts++;
      _lastLoginAttempt = DateTime.now();

      _logger.e('Firebase Auth Error: ${e.code} - ${e.message}');

      String errorMessage = _mapAuthError(e);

      Get.snackbar(
        "Login Error",
        errorMessage,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
        backgroundColor: const Color.fromRGBO(255, 205, 210, 1),
      );

      rethrow;
    } catch (e) {
      _loginAttempts++;
      _lastLoginAttempt = DateTime.now();

      _logger.e('Unexpected login error: $e');

      Get.snackbar(
        "Login Error",
        "An unexpected error occurred. Please try again.",
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
        backgroundColor: const Color.fromRGBO(255, 205, 210, 1),
      );

      rethrow;
    }
  }

  Future<void> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await userCredential.user!.updateDisplayName(name);

      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'email': email,
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
        'profileCompleted': false,
        'subscription': 'free',
        'roles': ['user'],
        'authMethod': 'email',
        'emailVerified': false,
      });

      await userCredential.user!.sendEmailVerification();
      await _auth.signOut();

      Get.snackbar(
        "Success",
        "Account created! Please verify your email.",
        snackPosition: SnackPosition.BOTTOM,
      );
      Get.offAllNamed('/login');
    } catch (e) {
      _logger.e("Signup error: $e");
      Get.snackbar("Error", "Signup failed. Please try again.");
    }
  }

  // Register a new user
  Future<void> registerUser(String email, String password, String name) async {
    try {
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Add user data to Firestore
      await _firestore.collection('users').doc(credential.user!.uid).set({
        'uid': credential.user!.uid,
        'email': email,
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      user.value = credential.user;
      Get.snackbar("Registration Success", "Account created!");
    } catch (e) {
      _logger.e("Registration Error: $e");
      Get.snackbar("Registration Error", e.toString());
    }
  }

  String _mapFirebaseAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email address';
      case 'wrong-password':
        return 'Incorrect password';
      case 'invalid-email':
        return 'Please enter a valid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'email-not-verified':
        return 'Please verify your email address';
      case 'too-many-requests':
        return 'Too many login attempts. Please try again in a few minutes';
      case 'invalid-input':
        return 'Please fill in all fields';
      case 'network-request-failed':
        return 'Network error. Please check your connection';
      case 'invalid-credential':
        return 'The login credentials are invalid. Please try again';
      case 'operation-not-allowed':
        return 'This login method is not enabled. Please contact support';
      default:
        return 'Login failed. Please try again';
    }
  }

  Future<void> signOut() async {
    try {
      // Clear the Isar database
      await _isarController.clearDatabase();

      // Sign out from Firebase and Google
      await _auth.signOut();
      await _googleSignIn.signOut();
      currentUserId = null; // Reset UID

      // Reset user state
      user.value = null;
      userData.value = {};

      Get.snackbar("Success", "Logged out successfully",
          snackPosition: SnackPosition.BOTTOM);
      Get.offAllNamed('/login');
    } catch (e) {
      _logger.e("Sign-out error: $e");
      Get.snackbar("Error", "Logout failed. Please try again.");
    }
  }

  Future<void> updateUsername(String newUsername) async {
    try {
      if (currentUserId == null || newUsername.trim().isEmpty) {
        throw Exception('Invalid user or username');
      }

      // Update Firebase Auth display name
      await _auth.currentUser?.updateDisplayName(newUsername);

      // Update Firestore
      await _firestore.collection('users').doc(currentUserId).update({
        'name': newUsername,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Update local userData
      final updatedUserData = Map<String, dynamic>.from(userData);
      if (updatedUserData['user'] != null) {
        updatedUserData['user'] =
            Map<String, dynamic>.from(updatedUserData['user']);
        updatedUserData['user']['name'] = newUsername;
      }
      userData.value = updatedUserData;

      Get.snackbar(
        "Success",
        "Username updated successfully",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.withOpacity(0.1),
      );
    } catch (e) {
      _logger.e("Error updating username: $e");
      Get.snackbar(
        "Error",
        "Failed to update username. Please try again.",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withOpacity(0.1),
      );
      rethrow;
    }
  }
}

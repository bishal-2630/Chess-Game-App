// lib/screens/auth/auth_service.dart - UPDATED VERSION
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Update this to match your Django server IP
  final String _baseUrl = 'http://192.168.1.68:8000/api/auth/';

  // Sign In with Email/Password
  Future<User?> signInWithEmailPassword(String email, String password) async {
    print('🔐 Attempting sign in with email: $email');

    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      print('✅ Sign in successful: ${userCredential.user?.email}');
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error: ${e.code} - ${e.message}');

      if (e.code == 'user-not-found') {
        throw Exception(
            'No account found with this email. Please register first.');
      } else if (e.code == 'wrong-password') {
        throw Exception('Incorrect password. Please try again.');
      } else if (e.code == 'invalid-email') {
        throw Exception('Invalid email format.');
      } else if (e.code == 'user-disabled') {
        throw Exception('This account has been disabled.');
      } else if (e.code == 'too-many-requests') {
        throw Exception('Too many attempts. Please try again later.');
      }

      throw Exception('Login failed: ${e.message}');
    } catch (e) {
      print('❌ General Error: $e');
      throw Exception('Login failed. Please try again.');
    }
  }

  // Register with Email/Password
  Future<User?> registerWithEmailPassword(
      String email, String password, String username) async {
    print('📝 Starting registration for: $email');

    try {
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      if (username.isNotEmpty) {
        await userCredential.user!.updateDisplayName(username);
      }

      await userCredential.user!.reload();

      print('✅ Registration successful: ${userCredential.user?.email}');
      return userCredential.user;
    } catch (e) {
      print('❌ Registration error: $e');

      if (e.toString().contains('email-already-in-use')) {
        throw Exception(
            'This email is already registered. Please login instead.');
      } else if (e.toString().contains('weak-password')) {
        throw Exception('Password is too weak. Use at least 6 characters.');
      }

      throw Exception('Registration failed: $e');
    }
  }

  // Sign In with Google
  Future<User?> signInWithGoogle() async {
    print('🔄 Starting Google sign in');

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        print('User cancelled Google sign in');
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      print('✅ Google sign in successful: ${userCredential.user?.email}');
      return userCredential.user;
    } catch (e) {
      print('❌ Google sign in error: $e');
      throw Exception('Google sign in failed: $e');
    }
  }

  // NEW: Send Password Reset OTP via Django
  Future<Map<String, dynamic>> sendPasswordResetOTP(String email) async {
    print("📱 Sending OTP to: $email");

    try {
      final url = '${_baseUrl}send-otp/';
      print("🌐 Calling: $url");

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email}),
          )
          .timeout(const Duration(seconds: 10));

      print("📡 Response status: ${response.statusCode}");

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        if (responseData['success'] == true) {
          print("✅ OTP sent successfully!");
          return {
            'success': true,
            'message': responseData['message'] ?? 'OTP sent successfully!',
            'expires_in': responseData['expires_in'] ?? 600,
          };
        } else {
          return {
            'success': false,
            'message': responseData['message'] ?? 'Failed to send OTP',
          };
        }
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } on TimeoutException {
      print("⏱️ Request timeout - backend might not be running");
      return {
        'success': false,
        'message': 'Cannot connect to backend. Make sure Django is running.',
      };
    } catch (e) {
      print("❌ Network error: $e");
      return {
        'success': false,
        'message': 'Backend connection failed.',
      };
    }
  }

  // NEW: Verify OTP via Django
  Future<Map<String, dynamic>> verifyOTP(String email, String otp) async {
    try {
      final url = '${_baseUrl}verify-otp/';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'otp': otp}),
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': responseData['success'] ?? false,
          'message': responseData['message'] ?? 'OTP verification completed',
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'OTP verification failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // NEW: Reset Password with OTP via Django
  Future<Map<String, dynamic>> resetPasswordWithOTP(
    String email,
    String otp,
    String newPassword,
    String confirmPassword,
  ) async {
    try {
      final url = '${_baseUrl}reset-password/';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'otp': otp,
          'new_password': newPassword,
          'confirm_password': confirmPassword,
        }),
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': responseData['success'] ?? false,
          'message': responseData['message'] ?? 'Password reset completed',
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Password reset failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Send Firebase password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      print('🔄 Sending password reset email to: $email');
      await _auth.sendPasswordResetEmail(email: email.trim());
      print('✅ Password reset email sent');
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase password reset error: ${e.code} - ${e.message}');
      String errorMessage = 'Failed to send reset email';
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email format';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many attempts. Try again later';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Check your internet connection';
          break;
      }
      throw Exception(errorMessage);
    } catch (e) {
      print('❌ Unexpected error: $e');
      throw Exception('Failed to send reset email. Please try again.');
    }
  }

  // Check if user is logged in
  bool get isLoggedIn => _auth.currentUser != null;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Sign out
  Future<void> signOut() async {
    try {
      print('🔄 Signing out');
      await _auth.signOut();
      await _googleSignIn.signOut();
      print('✅ Signed out successfully');
    } catch (e) {
      print('❌ Sign out error: $e');
      throw Exception('Sign out failed: $e');
    }
  }
}

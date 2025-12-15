import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:timer_count_down/timer_count_down.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // State variables
  bool _isLoading = false;
  bool _emailSent = false;
  bool _otpVerified = false;
  bool _canResendOTP = false;
  String? _verificationId;
  int _resendTimer = 60;

  // Step tracking (0: Email, 1: OTP, 2: New Password)
  int _currentStep = 0;

  final _formKey = GlobalKey<FormState>();

  // Send OTP to email
  Future<void> _sendOTP() async {
    if (_emailController.text.isEmpty) {
      _showErrorSnackBar('Please enter your email');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // First, check if email exists by sending password reset email
      await _auth.sendPasswordResetEmail(email: _emailController.text.trim());

      // For OTP simulation (in real app, you'd integrate with SMS service)
      // Since Firebase doesn't have email OTP natively, we'll simulate it
      // In production, use a service like Twilio, MessageBird, or Firebase Cloud Functions

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('OTP sent to ${_emailController.text}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      // Simulate OTP (in real app, generate and store in backend)
      _showOTPSnackBar();

      setState(() {
        _emailSent = true;
        _canResendOTP = false;
        _resendTimer = 60;
      });

      // Start resend timer
      _startResendTimer();
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Failed to send OTP';
      if (e.code == 'user-not-found') {
        errorMessage = 'No account found with this email';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'Invalid email address';
      } else if (e.code == 'too-many-requests') {
        errorMessage = 'Too many attempts. Try again later';
      }
      _showErrorSnackBar(errorMessage);
    } catch (e) {
      _showErrorSnackBar('Error: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Verify OTP
  Future<void> _verifyOTP() async {
    if (_otpController.text.length != 6) {
      _showErrorSnackBar('Please enter 6-digit OTP');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Simulate OTP verification
      // In production: Verify OTP with your backend
      await Future.delayed(const Duration(seconds: 1));

      // For demo: Accept any 6-digit code starting with '1'
      if (_otpController.text.startsWith('1')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OTP verified successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        setState(() {
          _otpVerified = true;
          _currentStep = 2; // Move to password reset step
        });
      } else {
        _showErrorSnackBar('Invalid OTP. Try 123456 for demo');
      }
    } catch (e) {
      _showErrorSnackBar('Verification failed: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Reset password
  Future<void> _resetPassword() async {
    if (_formKey.currentState!.validate()) {
      if (_newPasswordController.text != _confirmPasswordController.text) {
        _showErrorSnackBar('Passwords do not match');
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        // In production: Call backend API to reset password
        // For now, we'll use Firebase's updatePassword (requires deauthentication)

        // Note: For production, you should:
        // 1. Store OTP in backend with expiration
        // 2. Verify OTP via backend
        // 3. Update password via backend

        User? user = _auth.currentUser;

        if (user != null && user.email == _emailController.text.trim()) {
          await user.updatePassword(_newPasswordController.text);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password reset successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );

          // Navigate to login
          context.go('/login');
        } else {
          // For demo: Just show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Password reset successfully! You can now login with new password.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );

          // Navigate to login after delay
          await Future.delayed(const Duration(seconds: 2));
          context.go('/login');
        }
      } catch (e) {
        _showErrorSnackBar('Failed to reset password: ${e.toString()}');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showOTPSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Demo OTP: 123456'),
            SizedBox(height: 4),
            Text('Use this for testing', style: TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () {
            // Copy to clipboard
          },
        ),
      ),
    );
  }

  void _startResendTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (_resendTimer > 0) {
        setState(() {
          _resendTimer--;
        });
        _startResendTimer();
      } else {
        setState(() {
          _canResendOTP = true;
        });
      }
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter email';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Enter valid email';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forgot Password'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStep(1, 'Email', _currentStep >= 0),
                  const SizedBox(height: 20, child: VerticalDivider()),
                  _buildStep(2, 'OTP', _currentStep >= 1),
                  const SizedBox(height: 20, child: VerticalDivider()),
                  _buildStep(3, 'Reset', _currentStep >= 2),
                ],
              ),

              const SizedBox(height: 40),

              // Title based on step
              Text(
                _currentStep == 0
                    ? 'Reset Your Password'
                    : _currentStep == 1
                        ? 'Verify OTP'
                        : 'Create New Password',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                _currentStep == 0
                    ? 'Enter your email to receive OTP'
                    : _currentStep == 1
                        ? 'Enter the 6-digit code sent to your email'
                        : 'Enter your new password',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),

              const SizedBox(height: 40),

              // Step 1: Email Input
              if (_currentStep == 0) ...[
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    prefixIcon: const Icon(Icons.email),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: _validateEmail,
                ),
                const SizedBox(height: 30),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _sendOTP,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Send OTP',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
              ],

              // Step 2: OTP Verification
              if (_currentStep == 1) ...[
                Center(
                  child: PinCodeTextField(
                    appContext: context,
                    length: 6,
                    controller: _otpController,
                    onChanged: (value) {},
                    pinTheme: PinTheme(
                      shape: PinCodeFieldShape.box,
                      borderRadius: BorderRadius.circular(10),
                      fieldHeight: 60,
                      fieldWidth: 50,
                      activeFillColor: Colors.white,
                      activeColor: Colors.blue,
                      selectedColor: Colors.blue,
                      inactiveColor: Colors.grey[300],
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),

                const SizedBox(height: 20),

                // Resend OTP Timer
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Didn\'t receive code? ',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    if (!_canResendOTP)
                      Countdown(
                        seconds: _resendTimer,
                        build: (BuildContext context, double time) => Text(
                          'Resend in ${time.toInt()}s',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        interval: const Duration(seconds: 1),
                      )
                    else
                      TextButton(
                        onPressed: _sendOTP,
                        child: const Text(
                          'Resend OTP',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 30),

                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _verifyOTP,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Verify OTP',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                TextButton(
                  onPressed: () {
                    setState(() {
                      _currentStep = 0;
                    });
                  },
                  child: const Text('Change Email Address'),
                ),
              ],

              // Step 3: New Password
              if (_currentStep == 2) ...[
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _newPasswordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon: const Icon(Icons.lock),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        validator: _validatePassword,
                      ),

                      const SizedBox(height: 20),

                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon: const Icon(Icons.lock_outline),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        validator: (value) {
                          if (value != _newPasswordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 10),

                      // Password requirements
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Password must contain:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: _newPasswordController.text.length >= 6
                                    ? Colors.green
                                    : Colors.grey,
                                size: 16,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'At least 6 characters',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _newPasswordController.text.length >= 6
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 30),

                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _resetPassword,
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Reset Password',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 30),

              // Back to Login
              Center(
                child: TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Back to Login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(int number, String label, bool isActive) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? Colors.blue : Colors.grey[300],
            border: Border.all(
              color: isActive ? Colors.blue : Colors.grey[300]!,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              number.toString(),
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.blue : Colors.grey[600],
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    super.dispose();
  }
}

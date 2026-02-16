import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/config.dart';
import '../main.dart'; // To access scaffoldMessengerKey
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../services/mqtt_service.dart';
import 'web_client_stub.dart'
    if (dart.library.html) 'web_client_web.dart'
    if (dart.library.js_util) 'web_client_web.dart';

class DjangoAuthService extends ChangeNotifier {
  // Singleton pattern
  static final DjangoAuthService _instance = DjangoAuthService._internal();
  factory DjangoAuthService() => _instance;
  DjangoAuthService._internal();

  static const String _tokenKey = 'auth_token';
  static const String _refreshKey = 'refresh_token';
  static const String _userKey = 'user_data';

  // Lazy-loaded components (UI only)
  CookieManager? __cookieManager;
  CookieManager get _cookieManager => __cookieManager ??= CookieManager.instance();

  GoogleSignIn? __googleSignIn;
  GoogleSignIn get _googleSignIn => __googleSignIn ??= GoogleSignIn(
    serverClientId:
        '1059251569808-94aeup33dh3tdrr844dlkqnoppqbv49p.apps.googleusercontent.com',
  );

  // User data storage
  Map<String, dynamic>? _currentUser;
  bool _isGuest = false;
  String? _guestName;
  String? _accessToken;
  String? _refreshToken;
  static String? _nextRoute;

  // Getters
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null || _isGuest;
  bool get isGuest => _isGuest;
  String? get guestName => _guestName;
  String? get accessToken => _accessToken;
  String? get currentRefreshToken => _refreshToken;
  static String? get nextRoute => _nextRoute;

  Future<void> initialize({bool autoConnectMqtt = true}) async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_tokenKey);
    _refreshToken = prefs.getString(_refreshKey);

    final userData = prefs.getString(_userKey);
    if (userData != null) {
      _currentUser = json.decode(userData);
    }

    // URL FRAGMENT BOOTSTRAP: High-reliability bridge via URL hash (#token=...)
    if (kIsWeb) {
      final hasUrlTokens = await _handleUrlTokens();
      if (hasUrlTokens) {
        print('🌐 [Initialize] URL Bridge detected. Prioritizing bootstrap...');
        await _bootstrapWebSession();
        notifyListeners(); // NOTIFY
      } else if (_currentUser == null) {
        // Normal bootstrap if no tokens in URL
        await _bootstrapWebSession();
        if (_currentUser != null) notifyListeners(); // NOTIFY
      }
    }

    if (_currentUser != null && autoConnectMqtt && _currentUser?['username'] != null) {
      MqttService().connect(_currentUser!['username']);
      notifyListeners(); // NOTIFY Just in case
    }

    // Clear fragment AFTER initialization is complete to avoid race conditions
    if (kIsWeb) {
      clearUrlFragment();
    }
  }

  Future<bool> _handleUrlTokens() async {
    try {
      final fragment = Uri.base.fragment;
      if (fragment.isEmpty) {
        // Fallback: check query parameters too just in case
        final access = Uri.base.queryParameters['access'];
        final refresh = Uri.base.queryParameters['refresh'];
        if (access != null && refresh != null) {
          print('✅ [URL-Bridge] Captured tokens from QueryParams');
          _accessToken = access;
          _refreshToken = refresh;
          await _saveAuthData();
          return true;
        }
        return false;
      }

      print('🌐 [URL-Bridge] Parsing hash fragment: $fragment');
      final params = Uri.splitQueryString(fragment);
      
      final access = params['access'];
      final refresh = params['refresh'];
      final next = params['next'];
      
      if (access != null && refresh != null) {
        print('✅ [URL-Bridge] Captured tokens from Fragment');
        _accessToken = access;
        _refreshToken = refresh;
        if (next != null) {
          _nextRoute = next;
          print('✅ [URL-Bridge] Captured redirect path: $_nextRoute');
        }
        await _saveAuthData();
        return true;
      }
    } catch (e) {
      print('❌ [URL-Bridge] Error: $e');
    }
    return false;
  }

  /// Bootstrap authentication on Web using session cookies OR captured JWT
  Future<void> _bootstrapWebSession() async {
    try {
      print('🌐 [Bootstrap] Attempting web session bootstrap...');
      
      if (kIsWeb) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Finalizing secure session...'), duration: Duration(seconds: 2)),
        );
      }

      final url = '${_baseUrl}web-session/';
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      
      if (_accessToken != null) {
        headers['Authorization'] = 'Bearer $_accessToken';
        print('🌐 [Bootstrap] Using JWT in headers: ${_accessToken!.substring(0, 10)}...');
      }

      late http.Response response;
      if (kIsWeb) {
        final client = getBrowserClient();
        response = await client.get(Uri.parse(url), headers: headers);
        client.close();
      } else {
        response = await http.get(Uri.parse(url), headers: headers);
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _accessToken = data['access'] ?? _accessToken;
          _refreshToken = data['refresh'] ?? _refreshToken;
          _currentUser = data['user'];
          await _saveAuthData();
          print('✅ [Bootstrap] SUCCESS for ${_currentUser?['username']}');
          
          if (kIsWeb) {
            scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(
                content: Text('Welcome back, ${_currentUser?['username']}! 👋'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          print('ℹ️ [Bootstrap] 200 OK but success=false: ${response.body}');
        }
      } else {
        print('❌ [Bootstrap] API Error: ${response.statusCode}');
        if (kIsWeb && _accessToken != null) {
          scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Text('Session bridge failed (${response.statusCode}). Please log in.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ [Bootstrap] Network/Exception: $e');
    }
  }

  void updateCurrentUser(Map<String, dynamic> userData) {
    _currentUser = userData;
    _saveAuthData();
  }

  Future<void> _saveAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null) await prefs.setString(_tokenKey, _accessToken!);
    if (_refreshToken != null) {
      await prefs.setString(_refreshKey, _refreshToken!);
    }
    if (_currentUser != null) {
      await prefs.setString(_userKey, json.encode(_currentUser));
    }
    notifyListeners(); // NOTIFY
  }

  Future<void> signOut() async {
    try {
      final String? tokenToBlacklist = _refreshToken;

      // 1. CLEAR LOCAL STATE IMMEDIATELY (Instant UI response)
      _currentUser = null;
      _isGuest = false;
      _guestName = null;
      _accessToken = null;
      _refreshToken = null;

      // Disconnect MQTT (User goes offline)
      MqttService().disconnect();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshKey);
      await prefs.remove(_userKey);

      // Clear cookies
      try {
        await _clearCookies();
      } catch (e) {
        print('🍪 Sign out error clearing cookies: $e');
      }

      // Sign out from Google
      try {
        await _googleSignIn.signOut();
      } catch (e) {
        print('📧 Sign out error clearing google session: $e');
      }

      // Optional: inform backend about token blacklist
      if (tokenToBlacklist != null) {
        // We do this non-blockingly
        unawaited(http.post(
          Uri.parse('${_baseUrl}logout/'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'refresh': tokenToBlacklist}),
        ).timeout(const Duration(seconds: 3)).catchError((_) => http.Response('', 500)));
      }

      print('✅ Signed out successfully');
      notifyListeners();
    } catch (e) {
      print('❌ Sign out error: $e');
      _currentUser = null;
      _isGuest = false;
      _guestName = null;
      notifyListeners();
    }
  }

  /// Helper for authenticated requests that handles token refresh automatically
  Future<http.Response> authenticatedRequest(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final Map<String, String> authHeaders = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      ...?headers,
    };

    final uri = Uri.parse(url);
    late http.Response response;

    if (method == 'POST') {
      response = await http.post(uri, headers: authHeaders, body: body);
    } else {
      response = await http.get(uri, headers: authHeaders);
    }

    // Handle 401: Refresh and retry once
    if (response.statusCode == 401 && _refreshToken != null) {
      print('🔄 [Auth] 401 detected. Attempting token refresh...');
      final success = await refreshToken();
      if (success && _accessToken != null) {
        print('🔄 [Auth] Refresh successful. Retrying request...');
        authHeaders['Authorization'] = 'Bearer $_accessToken';
        if (method == 'POST') {
          response = await http.post(uri, headers: authHeaders, body: body);
        } else {
          response = await http.get(uri, headers: authHeaders);
        }
      }
    }

    return response;
  }

  String get _baseUrl {
    return AppConfig.baseUrl;
  }

  // Refresh Token
  Future<bool> refreshToken() async {
    if (_refreshToken == null) {
      return false;
    }

    try {
      final url = '${_baseUrl}token/refresh/';
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refresh': _refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _accessToken = data['access'];
        // Some backends rotate refresh tokens too
        if (data['refresh'] != null) {
          _refreshToken = data['refresh'];
        }
        await _saveAuthData();
        return true;
      } else {
        print('❌ Token refresh failed: ${response.body}');
        await signOut(); // Force logout if refresh fails
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  // Guest login
  Future<void> loginAsGuest(String name) async {
    _isGuest = true;
    _guestName = name;
    _currentUser = null;
    notifyListeners();
  }

  // Guest logout
  void logoutGuest() {
    _isGuest = false;
    _guestName = null;
    notifyListeners();
  }

  // Email/Password Login
  Future<Map<String, dynamic>> signInWithEmailPassword(
      String email, String password) async {
    logoutGuest(); // Clear guest state

    try {
      // Use standard Django login endpoint
      final url = '${_baseUrl}login/';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'email': email.trim(),
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          _currentUser = responseData['user'];

          // Store tokens if available
          if (responseData['tokens'] != null) {
            _accessToken = responseData['tokens']['access'];
            _refreshToken = responseData['tokens']['refresh'];
          }

          await _saveAuthData();

          return {
            'success': true,
            'user': responseData['user'],
            'tokens': responseData['tokens'] ?? {},
          };
        } else {
          final errorMessage = responseData['message'] ?? 'Login failed';
          return {
            'success': false,
            'error': errorMessage,
          };
        }
      } else {
        // Handle error responses
        String errorMessage = 'Login failed';
        try {
          final errorData = json.decode(response.body);

          // Check for message field first
          if (errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
          // Fallback to other error fields
          else if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          } else if (errorData['email'] != null) {
            errorMessage = errorData['email'][0];
          } else if (errorData['password'] != null) {
            errorMessage = errorData['password'][0];
          } else if (errorData['non_field_errors'] != null) {
            errorMessage = errorData['non_field_errors'][0];
          }
        } catch (e) {
          errorMessage = 'Network error during login: ${response.statusCode}';
        }

        return {
          'success': false,
          'error': errorMessage,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
    // Removed unreachable code for saving tokens and user data.
  }

  // Email/Password Registration
  Future<Map<String, dynamic>> registerWithEmailPassword(
      String email, String password, String username) async {

    try {
      final url = '${_baseUrl}register/';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'email': email.trim(),
          'password': password,
          'username': username.trim(),
        }),
      );

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);

        // Store user data
        _currentUser = responseData['user'];

        await _saveAuthData();

        // Handle cookies for web view
        String? rawCookie = response.headers['set-cookie'];
        if (rawCookie != null) {
          await _injectCookies(rawCookie);
        }


        return {'success': true, 'user': _currentUser, 'tokens': responseData};
      } else {
        final errorData = json.decode(response.body);
        String errorMessage = 'Registration failed';

        if (errorData['detail'] != null) {
          errorMessage = errorData['detail'];
        } else if (errorData['email'] != null) {
          errorMessage = errorData['email'][0];
        } else if (errorData['password'] != null) {
          errorMessage = errorData['password'][0];
        } else if (errorData['username'] != null) {
          errorMessage = errorData['username'][0];
        } else if (errorData['non_field_errors'] != null) {
          errorMessage = errorData['non_field_errors'][0];
        }

        return {'success': false, 'error': errorMessage};
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error. Please check your connection.'
      };
    }
  }

  // Google Sign-In
  Future<Map<String, dynamic>> signInWithGoogle() async {
    logoutGuest(); // Clear guest state

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return {'success': false, 'error': 'Sign in cancelled'};
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Send Google token to Django backend
      final url = '${_baseUrl}google-login/';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'access_token': googleAuth.accessToken,
          'id_token': googleAuth.idToken,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        // Store user data
        _currentUser = responseData['user'];

        // Store tokens (Backend returns them at root level)
        if (responseData['access'] != null) {
          _accessToken = responseData['access'];
          _refreshToken = responseData['refresh'];
        } else if (responseData['tokens'] != null) {
          // Fallback if backend changes
          _accessToken = responseData['tokens']['access'];
          _refreshToken = responseData['tokens']['refresh'];
        }

        await _saveAuthData();

        // Handle cookies for web view
        String? rawCookie = response.headers['set-cookie'];
        if (rawCookie != null) {
          await _injectCookies(rawCookie);
        }


        return {'success': true, 'user': _currentUser, 'tokens': responseData};
      } else {
        final errorData = json.decode(response.body);
        String errorMessage = 'Google sign in failed';

        if (errorData['detail'] != null) {
          errorMessage = errorData['detail'];
        } else if (errorData['error'] != null) {
          errorMessage = errorData['error'];
        }

        return {'success': false, 'error': errorMessage};
      }
    } catch (e) {
      return {
        'success': false,
        'error':
            'Google sign in failed. Please make sure Google Play Services are updated.'
      };
    }
  }

  // Send Password Reset OTP
  Future<Map<String, dynamic>> sendPasswordResetOTP(String email) async {

    try {
      final url = '${_baseUrl}send-otp/';

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email}),
          )
          .timeout(const Duration(seconds: 20));

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        if (responseData['success'] == true) {
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
          'message':
              'Server error: ${response.statusCode}. ${responseData['message'] ?? ""}',
        };
      }
    } on TimeoutException {
      return {
        'success': false,
        'message':
            'Connection timeout. The server is taking too long to respond. Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Backend connection failed: ${e.toString()}',
      };
    }
  }

  // Verify OTP
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

  // Reset Password with OTP
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

  Future<void> _injectCookies(String rawCookie) async {
    try {
      Uri uri = Uri.parse(_baseUrl);
      String domain = uri.host;

      List<String> cookies =
          rawCookie.split(RegExp(r',(?=\s*[a-zA-Z0-9_-]+=)'));

      for (String cookie in cookies) {
        int equalsIndex = cookie.indexOf('=');
        if (equalsIndex == -1) continue;

        String key = cookie.substring(0, equalsIndex).trim();
        String valueAndAttributes = cookie.substring(equalsIndex + 1).trim();

        int semiIndex = valueAndAttributes.indexOf(';');
        String value = semiIndex == -1
            ? valueAndAttributes
            : valueAndAttributes.substring(0, semiIndex);

        await _cookieManager.setCookie(
          url: WebUri(_baseUrl),
          name: key,
          value: value,
          domain: domain,
          path: "/",
          isHttpOnly: false,
          isSecure: uri.scheme == 'https',
        );
      }
    } catch (e) {
    }
  }

  // Clear cookies
  Future<void> _clearCookies() async {
    try {
      await _cookieManager.deleteCookies(url: WebUri(_baseUrl));
    } catch (e) {
    }
  }

  // Get current user display name
  String get displayName {
    if (_isGuest && _guestName != null) {
      return _guestName!;
    }
    if (_currentUser != null) {
      return _currentUser!['username'] ?? _currentUser!['email'] ?? 'User';
    }
    return 'Guest';
  }

  // Get current user email
  String? get email {
    if (_currentUser != null) {
      return _currentUser!['email'];
    }
    return null;
  }

  // Check if user has specific role (for future use)
  bool hasRole(String role) {
    if (_currentUser != null && _currentUser!['roles'] != null) {
      List<String> roles = List<String>.from(_currentUser!['roles']);
      return roles.contains(role);
    }
    return false;
  }
}

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'django_auth_service.dart';
import 'config.dart';

class CookieInjectionService {
  // Singleton pattern
  static final CookieInjectionService _instance = CookieInjectionService._internal();
  factory CookieInjectionService() => _instance;
  CookieInjectionService._internal();

  final DjangoAuthService _authService = DjangoAuthService();
  final CookieManager _cookieManager = CookieManager.instance();

  /// Get web session cookie from backend using JWT token
  Future<Map<String, dynamic>> getWebSessionCookie() async {
    try {
      final token = _authService.accessToken;
      
      if (token == null) {
        return {
          'success': false,
          'error': 'No authentication token available'
        };
      }

      final url = '${AppConfig.baseUrl}web-session/';
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Extract session cookie from response
        String? setCookieHeader = response.headers['set-cookie'];
        
        return {
          'success': true,
          'session_key': data['session_key'],
          'expires_at': data['expires_at'],
          'set_cookie_header': setCookieHeader,
          'user': data['user'],
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to get web session: ${response.statusCode}'
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e'
      };
    }
  }

  /// Inject authentication cookies into WebView
  Future<bool> injectAuthCookies({String? customUrl}) async {
    try {
      // Get session cookie from backend
      final result = await getWebSessionCookie();
      
      if (result['success'] != true) {
        print('❌ Failed to get session cookie: ${result['error']}');
        return false;
      }

      final sessionKey = result['session_key'];
      final expiresAt = result['expires_at'];
      
      // Determine the URL to inject cookies for
      String targetUrl = customUrl ?? AppConfig.baseUrl;
      Uri uri = Uri.parse(targetUrl);
      
      // Create cookie
      await _cookieManager.setCookie(
        url: WebUri(targetUrl),
        name: 'sessionid',
        value: sessionKey,
        domain: uri.host,
        path: '/',
        expiresDate: DateTime.parse(expiresAt).millisecondsSinceEpoch,
        isSecure: uri.scheme == 'https',
        isHttpOnly: false,
        sameSite: HTTPCookieSameSitePolicy.NONE,
      );

      print('✅ Successfully injected session cookie');
      return true;
      
    } catch (e) {
      print('❌ Cookie injection failed: $e');
      return false;
    }
  }

  /// Clear all cookies (for logout)
  Future<void> clearCookies() async {
    try {
      String baseUrl = AppConfig.baseUrl;
      await _cookieManager.deleteCookies(url: WebUri(baseUrl));
      print('✅ Cookies cleared');
    } catch (e) {
      print('❌ Failed to clear cookies: $e');
    }
  }

  /// Get all cookies for debugging
  Future<List<Cookie>> getCookies() async {
    try {
      String baseUrl = AppConfig.baseUrl;
      final cookies = await _cookieManager.getCookies(url: WebUri(baseUrl));
      return cookies;
    } catch (e) {
      print('❌ Failed to get cookies: $e');
      return [];
    }
  }
}

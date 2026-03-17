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

      // Determine the URL to inject cookies for
      String targetUrl = customUrl ?? AppConfig.baseUrl;
      Uri uri = Uri.parse(targetUrl);
      String domain = uri.host;
      
      // 1. Inject from explicit session_key if available
      final sessionKey = result['session_key'];
      final expiresAt = result['expires_at'];
      
      if (sessionKey != null) {
        await _cookieManager.setCookie(
          url: WebUri(targetUrl),
          name: 'sessionid',
          value: sessionKey,
          domain: domain,
          path: '/',
          expiresDate: expiresAt != null ? DateTime.parse(expiresAt).millisecondsSinceEpoch : null,
          isSecure: uri.scheme == 'https',
          isHttpOnly: false,
          sameSite: HTTPCookieSameSitePolicy.NONE,
        );
        print('✅ Injected sessionid from response data');
      }

      // 2. Parse and inject ALL cookies from Set-Cookie header
      String? setCookieHeader = result['set_cookie_header'];
      if (setCookieHeader != null && setCookieHeader.isNotEmpty) {
        print('🍪 Parsing Set-Cookie header: $setCookieHeader');
        
        // Handle common comma-separation issue in Set-Cookie headers
        // Commas in 'expires=Wed, 21 Oct 2015 07:28:00 GMT' should NOT be splitters
        // This regex looks for commas that are followed by a name=value pattern
        final cookieRegex = RegExp(r',(?=\s*[a-zA-Z0-9_\-]+?=)');
        final rawCookies = setCookieHeader.split(cookieRegex);
        
        for (var rawCookie in rawCookies) {
          try {
            // Basic parsing: "name=value; Path=/; ..."
            final parts = rawCookie.split(';');
            final mainPart = parts[0].trim();
            final equalsIndex = mainPart.indexOf('=');
            if (equalsIndex == -1) continue;
            
            final name = mainPart.substring(0, equalsIndex).trim();
            final value = mainPart.substring(equalsIndex + 1).trim();
            
            // Extract attributes
            String path = '/';
            bool isSecure = uri.scheme == 'https';
            bool isHttpOnly = false;
            
            for (int i = 1; i < parts.length; i++) {
              final attr = parts[i].trim().toLowerCase();
              if (attr.startsWith('path=')) {
                path = parts[i].trim().substring(5);
              } else if (attr == 'secure') {
                isSecure = true;
              } else if (attr == 'httponly') {
                isHttpOnly = true;
              }
            }

            await _cookieManager.setCookie(
              url: WebUri(targetUrl),
              name: name,
              value: value,
              domain: domain,
              path: path,
              isSecure: isSecure,
              isHttpOnly: isHttpOnly,
              sameSite: HTTPCookieSameSitePolicy.NONE,
            );
            print('✅ Injected cookie from header: $name');
          } catch (e) {
            print('⚠️ Error parsing individual cookie: $e');
          }
        }
      }

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

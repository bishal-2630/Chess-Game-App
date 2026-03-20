import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'django_auth_service.dart';
import 'config.dart';
import '../main.dart'; // To access scaffoldMessengerKey

class DeepLinkHandler {
  // Singleton pattern
  static final DeepLinkHandler _instance = DeepLinkHandler._internal();
  factory DeepLinkHandler() => _instance;
  DeepLinkHandler._internal();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  Future<void> _launchSystemBrowser(String verifyUrl) async {
    final uri = Uri.parse(verifyUrl);
    print('🌐 [Launcher] Attempting launchUrl: $uri');
    final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    print('🌐 [Launcher] Success: $success');
    if (!success) {
       print('❌ [Launcher] Failed to launch external browser for $uri');
    }
  }

  /// Bridge the app session to the system browser
  Future<void> performSessionTransfer(Uri uri) async {
    final authService = DjangoAuthService();
    if (!authService.isLoggedIn) {
      print('⚠️ [Transfer] Aborting: Not logged in');
      return;
    }

    // Diagnostic UI feedback
    scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 15),
            Text('Bridging session to Chrome...'),
          ],
        ),
        duration: Duration(seconds: 5),
      ),
    );

    try {
      final endpoint = '${AppConfig.baseUrl}magic-token/generate/';
      print('🔗 [Transfer] Calling Generate Token at $endpoint');
      
      final response = await authService.authenticatedRequest(
        endpoint,
        method: 'POST',
      );

      print('🔗 [Transfer] API Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['handshake_token'];
        
        // Prepare verification URL
        // Example: https://.../api/auth/magic-token/verify/?token=...&next=/play
        final verifyUrl = '${AppConfig.baseUrl}magic-token/verify/?token=$token&next=${uri.path}';
        
        print('🌐 [Transfer] Final Verify URL: $verifyUrl');
        
        // STABILITY DELAY: Wait 1 second to ensure the app is fully resumed
        // before launching the external browser intent.
        await Future.delayed(const Duration(seconds: 1));
        
        await _launchSystemBrowser(verifyUrl);
      } else {
        print('❌ [Transfer] Failed: ${response.statusCode} - ${response.body}');
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Bridge failed (API ${response.statusCode}). Please log in again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ [Transfer] EXCEPTION: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Bridge failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Initialize deep link listener

  Future<void> initialize(Function(Uri) onLinkReceived) async {
    // Handle initial link if app was opened via deep link
    try {
      final initialUri = await _appLinks.getInitialAppLink();
      if (initialUri != null) {
        print('📎 Initial deep link: $initialUri');
        onLinkReceived(initialUri);
      }
    } catch (e) {
      print('❌ Failed to get initial link: $e');
    }

    // Listen for deep links while app is running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        print('📎 Deep link received: $uri');
        onLinkReceived(uri);
      },
      onError: (err) {
        print('❌ Deep link error: $err');
      },
    );
  }

  /// Parse deep link and extract parameters
  DeepLinkData parseDeepLink(Uri uri) {
    final path = uri.path;
    final queryParams = uri.queryParameters;

    // Determine the type of deep link
    final String scheme = uri.scheme;
    final String host = uri.host;

    if (path.contains('/play') || host == 'play') {
      return DeepLinkData(
        type: DeepLinkType.play,
        gameId: queryParams['gameId'],
        roomId: queryParams['roomId'],
        sessionSync: queryParams['session_sync'] == '1',
      );
    } else if (path.contains('/game/') || host == 'game') {
      // Extract game ID from path like /game/123 or host if it's chess://game/123
      final gameId = path.split('/').last;
      return DeepLinkData(
        type: DeepLinkType.game,
        gameId: gameId.isEmpty ? host : gameId,
        sessionSync: queryParams['session_sync'] == '1',
      );
    } else if (path.contains('/profile')) {
      return DeepLinkData(
        type: DeepLinkType.profile,
        username: queryParams['username'],
      );
    } else {
      return DeepLinkData(
        type: DeepLinkType.home,
        sessionSync: queryParams['session_sync'] == '1',
      );
    }
  }

  /// Dispose the listener
  void dispose() {
    _linkSubscription?.cancel();
  }
}

/// Deep link types
enum DeepLinkType {
  home,
  play,
  game,
  profile,
}

/// Deep link data model
class DeepLinkData {
  final DeepLinkType type;
  final String? gameId;
  final String? roomId;
  final String? username;
  final bool sessionSync;

  DeepLinkData({
    required this.type,
    this.gameId,
    this.roomId,
    this.username,
    this.sessionSync = false,
  });

  @override
  String toString() {
    return 'DeepLinkData(type: $type, gameId: $gameId, roomId: $roomId, username: $username, sessionSync: $sessionSync)';
  }
}

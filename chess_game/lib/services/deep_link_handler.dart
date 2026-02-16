import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'django_auth_service.dart';
import '../config.dart';

class DeepLinkHandler {
  // Singleton pattern
  static final DeepLinkHandler _instance = DeepLinkHandler._internal();
  factory DeepLinkHandler() => _instance;
  DeepLinkHandler._internal();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  /// Bridge the app session to the system browser
  Future<void> performSessionTransfer(Uri uri) async {
    final authService = DjangoAuthService();
    if (!authService.isLoggedIn) {
      print('⚠️ Cannot transfer session: User not logged in');
      return;
    }

    try {
      print('🔗 Generating magic token for session transfer...');
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}api/auth/magic-token/generate/'),
        headers: {
          'Authorization': 'Bearer ${authService.accessToken}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['handshake_token'];
        
        // Prepare verification URL (which sets cookies and redirects)
        final verifyUrl = Uri.parse(
          '${AppConfig.baseUrl}api/auth/magic-token/verify/?token=$token&next=${uri.path}'
        );
        
        print('🌐 Launching system browser for authenticated session: $verifyUrl');
        
        // Launch in external browser
        if (!await launchUrl(verifyUrl, mode: LaunchMode.externalApplication)) {
          throw 'Could not launch $verifyUrl';
        }
      } else {
        print('❌ Failed to generate magic token: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Session transfer error: $e');
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
    if (path.contains('/play')) {
      return DeepLinkData(
        type: DeepLinkType.play,
        gameId: queryParams['gameId'],
        roomId: queryParams['roomId'],
      );
    } else if (path.contains('/game/')) {
      // Extract game ID from path like /game/123
      final gameId = path.split('/').last;
      return DeepLinkData(
        type: DeepLinkType.game,
        gameId: gameId,
      );
    } else if (path.contains('/profile')) {
      return DeepLinkData(
        type: DeepLinkType.profile,
        username: queryParams['username'],
      );
    } else {
      return DeepLinkData(type: DeepLinkType.home);
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

  DeepLinkData({
    required this.type,
    this.gameId,
    this.roomId,
    this.username,
  });

  @override
  String toString() {
    return 'DeepLinkData(type: $type, gameId: $gameId, roomId: $roomId, username: $username)';
  }
}

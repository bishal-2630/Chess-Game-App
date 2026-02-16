import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Added for kIsWeb
import 'package:go_router/go_router.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/forgot_password.dart';
import 'screens/game/chess_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/call_screen.dart';
import 'screens/users/user_list_screen.dart';
import 'screens/users/invitations_screen.dart';
import 'screens/chess_webview_screen.dart';
import 'services/django_auth_service.dart';
import 'services/mqtt_service.dart';
import 'services/game_service.dart';
import 'services/background_service.dart';
import 'services/deep_link_handler.dart';
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MqttService.isMainIsolate = true;

  await DjangoAuthService().initialize();

  // Initialize MQTT Service (sets up local notifications)
  final mqttService = MqttService();
  await mqttService.initialize();
  // Isolate listener is mobile-only
  if (!kIsWeb) {
    mqttService.initializeIsolateListener(isBackground: false);
  }

  // Initialize Background Service for persistent connection (Mobile only)
  if (!kIsWeb) {
    await BackgroundServiceInstance.initializeService();
  }

  runApp(const MyApp());
}

final authService = DjangoAuthService();

// Global router for deep link navigation
final GoRouter _globalRouter = GoRouter(
  initialLocation: authService.isLoggedIn ? '/chess' : '/login',
  refreshListenable: authService,
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return IncomingCallWrapper(child: child);
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/chess',
          builder: (context, state) {
            final roomId = state.uri.queryParameters['roomId'];
            final color = state.uri.queryParameters['color'];
            final opponentName = state.uri.queryParameters['opponentName'];
            return ChessScreen(roomId: roomId, color: color, opponentName: opponentName);
          },
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/call',
          builder: (context, state) {
            final roomId = state.uri.queryParameters['roomId'] ?? 'testroom';
            final otherUserName = state.uri.queryParameters['otherUserName'] ??
                state.uri.queryParameters['callerName'] ??
                'Unknown';
            final isCaller = state.uri.queryParameters['isCaller'] == 'true';

            return CallScreen(
              roomId: roomId,
              otherUserName: otherUserName,
              isCaller: isCaller,
            );
          },
        ),
        GoRoute(
          path: '/users',
          builder: (context, state) => const UserListScreen(),
        ),
        GoRoute(
          path: '/invitations',
          builder: (context, state) => const InvitationsScreen(),
        ),
        GoRoute(
          path: '/web-chess',
          builder: (context, state) {
            final gameId = state.uri.queryParameters['gameId'];
            return ChessWebViewScreen(gameId: gameId);
          },
        ),
        GoRoute(
          path: '/play',
          redirect: (context, state) {
            if (!kIsWeb && authService.isLoggedIn) {
              print('🚦 [Router] /play Intercepted -> Session Transfer Triggered');
              DeepLinkHandler().performSessionTransfer(state.uri);
              return '/chess';
            }
            if (kIsWeb) return '/users';
            return null;
          },
          builder: (context, state) => const ChessWebViewScreen(),
        ),
        GoRoute(
          path: '/game/:gameId',
          redirect: (context, state) {
            final gameId = state.pathParameters['gameId'];
            if (!kIsWeb && authService.isLoggedIn) {
              print('🚦 [Router] /game Intercepted -> Session Transfer Triggered');
              DeepLinkHandler().performSessionTransfer(state.uri);
              return '/chess';
            }
            if (kIsWeb) return '/chess?roomId=$gameId';
            return null;
          },
          builder: (context, state) {
            final gameId = state.pathParameters['gameId'];
            return ChessWebViewScreen(gameId: gameId);
          },
        ),
        GoRoute(
          path: '/web-bridge',
          redirect: (context, state) {
             // This path is hit (in Chrome) after the magic-token verification.
             // authentication is handled automatically in DjangoAuthService.initialize()
             final nextParam = state.uri.queryParameters['next'];
             final next = nextParam ?? DjangoAuthService.nextRoute ?? '/chess';
             print('🌐 [Router] WebBridge: Finalizing transfer to $next');
             return next;
          }
        ),
      ],
    ),
  ],
  redirect: (context, state) {
    final isLoggedIn = authService.isLoggedIn;
    final currentPath = state.uri.path;
    
    print('🚦 [Router] Redirect Check: path=$currentPath, isLoggedIn=$isLoggedIn');

    final isAuthPage = currentPath == '/login' ||
        currentPath == '/register' ||
        currentPath == '/forgot-password' ||
        currentPath == '/web-bridge';

    if (!isLoggedIn && !isAuthPage) {
      print('🚦 [Router] Not logged in, redirecting to /login');
      return '/login';
    }

    if (isLoggedIn && (currentPath == '/login' || currentPath == '/register' || currentPath == '/forgot-password' || currentPath == '/web-bridge')) {
      final next = DjangoAuthService.nextRoute ?? '/chess';
      print('🚦 [Router] Logged in, redirecting to $next');
      return next;
    }
    return null;
  },
);

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _initializeDeepLinks();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Chess Game',
      scaffoldMessengerKey: scaffoldMessengerKey,
      routerConfig: _globalRouter,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
    );
  }

  void _initializeDeepLinks() {
    final deepLinkHandler = DeepLinkHandler();
    
    deepLinkHandler.initialize((Uri uri) async {
      print('📎 [DeepLink] Incoming: $uri');
      
      // If we are on mobile and logged in, transfer session to system browser
      if (!kIsWeb && authService.isLoggedIn) {
        print('📎 [DeepLink] Mobile + Authenticated. Triggering Session Transfer...');
        await deepLinkHandler.performSessionTransfer(uri);
        return; 
      }

      final linkData = deepLinkHandler.parseDeepLink(uri);
      print('📎 [DeepLink] Parsed Model: $linkData');
      
      switch (linkData.type) {
        case DeepLinkType.play:
          _globalRouter.go('/play'); // Will trigger the redirect logic appropriately
          break;
        case DeepLinkType.game:
          if (linkData.gameId != null) {
            _globalRouter.go('/game/${linkData.gameId}');
          } else {
             _globalRouter.go('/play');
          }
          break;
        case DeepLinkType.profile:
          _globalRouter.go('/profile');
          break;
        case DeepLinkType.home:
        default:
          _globalRouter.go('/chess');
          break;
      }
    });
  }
}

class IncomingCallWrapper extends StatefulWidget {
  final Widget child;
  const IncomingCallWrapper({super.key, required this.child});

  @override
  _IncomingCallWrapperState createState() => _IncomingCallWrapperState();
}

class _IncomingCallWrapperState extends State<IncomingCallWrapper> {
  // Removed _isDialogShowing as dialogs are now disabled per user request

  @override
  void initState() {
    super.initState();
    _handleInitialNotification();
    _listenForNotifications();
    _checkInitialAuth();
    _setupGlobalSignals();
  }

  void _setupGlobalSignals() {
    // Signals (stopAudio, dismiss_call, etc.) are already routed 
    // through mqttService.notifications stream which we listen to in _listenForNotifications()
  }

  Future<void> _handleInitialNotification() async {
    final details = await MqttService().flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (details != null && details.didNotificationLaunchApp && details.notificationResponse != null) {
      // Immediately pass to MqttService to buffer it
      MqttService().onNotificationTapped(details.notificationResponse!);
    }
  }

  void _checkInitialAuth() async {
    final authService = DjangoAuthService();
    print('🔍 Checking initial auth. isLoggedIn: ${authService.isLoggedIn}');
    if (authService.isLoggedIn) {
      final username =
          authService.currentUser?['username'] ?? authService.guestName;
      print('🔍 Username: $username');
      if (username != null) {
        await MqttService().connect(username);
      }
    }
  }

  void _listenForNotifications() {
    final mqtt = MqttService();
    
    mqtt.notifications.listen((data) {
      _processNotificationData(data);
    });

    // Check for buffered event (e.g., from cold launch)
    if (mqtt.lastNotificationEvent != null) {
      final event = mqtt.lastNotificationEvent!;
      mqtt.clearLastNotification();
      
      // Safety delay to ensure GoRouter is fully ready
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _processNotificationData(event);
        }
      });
    }
  }

  void _processNotificationData(Map<String, dynamic> data) async {
    if (!mounted) return;

    final type = data['type'];
    final action = data['action'];
    final payload = data['data'] ?? data['payload'];

    if (type == 'call_ended' || type == 'call_declined' || type == 'call_cancelled' || type == 'dismiss_call') {
      // Stop audio immediately as this is a termination event
      final roomId = payload != null ? payload['room_id'] : null;
      print('🧹 [Main] Termination signal received ($type). Stopping audio and clearing notification...');
      MqttService().stopAudio(broadcast: false, roomId: roomId);
      MqttService().cancelCallNotification(roomId: roomId, broadcast: false);
    } else if (type == 'invitation_response') {
      _handleInvitationResponse(data);
    } else if (type == 'call_invitation') {
      if (action == 'accept') {
        // Cleanup in background without awaiting
        MqttService().stopAudio(broadcast: true);
        MqttService().cancelCallNotification();

        final caller = payload['caller'];
        final roomId = payload['room_id'];
        try {
          context.go('/call?roomId=$roomId&otherUserName=$caller&isCaller=false');
        } catch (e) {
        }
      } else {
        // PER USER REQUEST: Do not show dialog box anymore.
        // User must respond from the system notification.
      }
    } else if (type == 'game_invitation') {
      if (action == 'accept') {
        final roomId = payload['room_id'];
        // Opponent is the sender of the invitation
        final sender = payload['sender']['username'] ?? 'Unknown';
        
        // Navigate immediately
        context.go('/chess?roomId=$roomId&color=b&opponentName=$sender');

        // Cleanup in background
        MqttService().stopAudio(broadcast: true);
        MqttService().cancelCallNotification();
        
        final invitationId = payload['id'];
        if (invitationId != null) {
          GameService.respondToInvitation(
            invitationId: invitationId,
            action: 'accept',
          );
        }
      } else {
        // PER USER REQUEST: Do not show dialog box anymore.
      }
    }
  }

  void _handleInvitationResponse(Map<String, dynamic> data) {
    if (!mounted) return;
    
    final payload = data['data'] ?? data['payload'];
    final action = payload['action'] ?? data['action'];
    final invitation = payload['invitation'] ?? payload;
    final receiver = invitation['receiver']['username'];
    final roomId = invitation['room_id'];

    if (action == 'accept') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$receiver accepted your challenge! Tap the notification to join.'),
          backgroundColor: Colors.green,
        ),
      );
      // Auto-navigation disabled per user request. User joins via notification tap.
    } else if (action == 'join_confirmed') {
      print('🚀 [Main] Join confirmed! Navigating to game room: $roomId');
      // Receiver is the opponent as I am the challenger
      context.go('/chess?roomId=$roomId&color=w&opponentName=$receiver');
    } else if (action == 'decline') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$receiver declined your challenge'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _declineInvitation(int invitationId) async {
    try {
      await GameService.respondToInvitation(
        invitationId: invitationId,
        action: 'decline',
      );
    } catch (e) {
      print('Error declining invitation: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

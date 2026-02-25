import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
// import 'package:mqtt_client/mqtt_server_client.dart'; // REMOVED for Web compatibility
import 'mqtt_client_factory.dart'; // Added factory
import 'isolate_handler.dart'; // Added isolate handler
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:ui';
import 'dart:isolate';
import 'game_service.dart';
import 'django_auth_service.dart';
import 'notification_handler.dart';

// No handler here anymore, moved to notification_handler.dart

class MqttService {
  static bool isMainIsolate = false; // Set this in main.dart
  
  // Static port to prevent GC
  static final ReceivePort _listenerPort = ReceivePort();

  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttClient? client; // Changed type to generic MqttClient
  final String broker = 'broker.emqx.io';
  final int port = 1883;
  bool isConnected = false;
  bool _isListening = false;

  final StreamController<Map<String, dynamic>> _notificationController = 
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get notifications => _notificationController.stream;

  // Buffer for the last notification event to solve race conditions on startup
  Map<String, dynamic>? _lastNotificationEvent;
  Map<String, dynamic>? get lastNotificationEvent => _lastNotificationEvent;

  void clearLastNotification() => _lastNotificationEvent = null;

  void _emitNotification(Map<String, dynamic> data) {
    _lastNotificationEvent = data;
    _notificationController.add(data);
  }

  static AudioPlayer? __audioPlayer;
  static AudioPlayer get _audioPlayer => __audioPlayer ??= AudioPlayer();
  static bool _isAudioLoading = false;
  static bool _isPlaying = false;
  static bool _isMutedWindow = false; // Prevents re-ring within a short window
  bool _isInCall = false; 
  static String? _currentCallRoomId;
  static String? _activeChessRoomId; // TRACK ACTIVE GAME ROOM
  static final Set<String> _declinedRoomIds = {};

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (kIsWeb) return; // Skip notifications on Web for now

    if (!isMainIsolate) {
      return;
    }
    
    
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    
    if (isMainIsolate) {
      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: onNotificationTapped,
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );
    } else {
      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );
    }

    // Create High Priority Channels
    const AndroidNotificationChannel challengeChannel = AndroidNotificationChannel(
      'chess_challenges_v2', // Updated ID
      'Chess Challenges',
      description: 'Notifications for chess game invitations',
      importance: Importance.max,
      playSound: false,
      enableVibration: true,
      showBadge: true,
    );

    const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
      'chess_incoming_calls_v6', // Fresh v6
      'Incoming Calls',
      description: 'Notifications for incoming calls',
      importance: Importance.max,
      playSound: false,
      enableVibration: true,
      showBadge: true,
    );

    const AndroidNotificationChannel ongoingCallChannel = AndroidNotificationChannel(
      'chess_ongoing_calls',
      'Ongoing Calls',
      description: 'Persistent notification for active calls',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );

    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
            
    // Set Audio Context for better control on physical devices (Main Isolate Only)
    // AudioContextAndroid is not available on Web
    if (!kIsWeb && isMainIsolate) {
      try {
        const audioContext = AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
          ),
          android: AudioContextAndroid(
            usageType: AndroidUsageType.notification,
            contentType: AndroidContentType.music,
            audioFocus: AndroidAudioFocus.gain,
          ),
        );
        AudioLogger.logLevel = AudioLogLevel.info;
        await AudioPlayer.global.setAudioContext(audioContext).catchError((e) {
          print('⚠️ MQTT: Global audio context error: $e');
        });
      } catch (e) {
        print('⚠️ MQTT: Global audio context error: $e');
      }
    }

    await androidPlugin?.createNotificationChannel(challengeChannel);
    await androidPlugin?.createNotificationChannel(callChannel);
    await androidPlugin?.createNotificationChannel(ongoingCallChannel);

    // Request notification permissions ONLY in Main Isolate (requires Activity)
    if (isMainIsolate) {
      final bool? permissionGranted = await androidPlugin?.requestNotificationsPermission();
    }
  }
  
  static bool _isPortListening = false;
  
  void initializeIsolateListener({bool isBackground = false}) {
    if (kIsWeb) return; // Skip on Web

    if (_isPortListening) {
      print('⚠️ MQTT: Isolate port already being listened to, skipping');
      return;
    }
    _isPortListening = true;

    // Use platform-agnostic handler
    registerIsolatePort(_listenerPort, isBackground);
    
    _listenerPort.listen((message) async {
      if (message == 'stop_audio') {
        await stopAudio(broadcast: false);
      } else if (message is Map) {
        if (message['action'] == 'stop_audio') {
          final roomId = message['roomId'];
          await stopAudio(broadcast: false, roomId: roomId);
        } else if (message['action'] == 'dismiss_call') {
          // Internal signal to clear UI or stop ringing
          _notificationController.add({'type': 'dismiss_call'});
        } else if (message['action'] == 'decline_call') {
          _notificationController.add({
            'type': 'decline_call', 
            'caller': message['caller'],
            'roomId': message['roomId'],
          });
        } else if (message['action'] == 'respond_invitation') {
          _notificationController.add({
            'type': 'respond_invitation',
            'invitationId': message['invitationId'],
            'action': message['action_type'],
          });
        } else if (message['action'] == 'cancel_notification') {
          final id = message['id'];
          if (id != null) {
            await flutterLocalNotificationsPlugin.cancel(id);
          }
        } else if (message['action'] == 'set_active_room') {
          _activeChessRoomId = message['roomId']?.toString();
        }
      }
    });
  }

  void onNotificationTapped(NotificationResponse response) async {
    if (response.payload != null) {
      try {
        final Map<String, dynamic> data = json.decode(response.payload!);
        final payloadMap = (data['data'] ?? data['payload']) as Map<String, dynamic>?;
        final type = data['type'];

        // Handle Game Invitation Actions
        if (type == 'game_invitation' || type == 'game_challenge') {
          if (response.actionId == 'decline_action' || response.actionId == 'decline') {
            await cancelCallNotification();
            final rawId = payloadMap?['id'];
            final invitationId = int.tryParse(rawId.toString());
            if (invitationId != null) {
              await GameService.respondToInvitation(
                invitationId: invitationId,
                action: 'decline',
              );
            }
            return;
          } else if (response.actionId == 'accept') {
            print('✅ [FG] ACTION: ACCEPT GAME');
            _emitNotification({
              ...data,
              'action': 'accept',
            });
            return;
          }
        }
        
        // Handle Call Invitation Actions
        if (type == 'call_invitation' || type == 'incoming_call') {
          if (response.actionId == 'decline_action' || response.actionId == 'decline') {
            await cancelCallNotification();
            if (payloadMap != null) {
              final caller = payloadMap['caller'] ?? payloadMap['sender'];
              final roomId = payloadMap['room_id']?.toString();
              
              if (caller != null && roomId != null) {
                  await GameService.declineCall(
                    callerUsername: caller,
                    roomId: roomId,
                  );
              }
            }
            return;
          } else if (response.actionId == 'accept' || response.actionId == 'accept_action') {
            print('✅ [FG] ACTION: ACCEPT CALL');
            _isInCall = true; // Mark as in-call to prevent further ringing
            
            // Cleanup in background without awaiting
            stopAudio();
            cancelCallNotification();
            
            // Broadcast to open call screen immediately
            _emitNotification({
              ...data,
              'action': 'accept',
            });
            return;
          }
        }
        
        // Handle Invitation Response Actions (e.g. Join Challenge)
        if (type == 'invitation_response') {
          final action = payloadMap?['action'] ?? data['action'];
          if (action == 'accept' || response.actionId == 'join_action') {
            print('✅ [FG] ACTION: JOIN CHALLENGE (CONFIRMED)');
            _emitNotification({
              ...data,
              'action': 'join_confirmed',
            });
            return;
          }
        }

        // Handle regular notification tap (no action button pressed)
        _emitNotification(data);
      } catch (e) {
        print('❌ [FG] Error: $e');
      }
    } else {
      print('⚠️ [FG] Notification payload is NULL');
    }
  }

  String? _currentUsername;

  Future<void> connect(String username) async {
    if (isConnected) {
      print('⚠️ MQTT: Already connected, skipping');
      return;
    }

    _currentUsername = username;
    _currentUsername = username;
    final clientIdentifier = 'flutter_client_${username}_${DateTime.now().millisecondsSinceEpoch}';
    
    // Use Factory to create client
    client = setupMqttClient(broker, clientIdentifier, port);
    
    client!.keepAlivePeriod = 20;
    client!.onDisconnected = onDisconnected;
    client!.onConnected = onConnected;
    client!.onSubscribed = onSubscribed;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientIdentifier)
        .withWillTopic('willtopic')
        .withWillMessage('My Will message')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client!.connectionMessage = connMess;

    try {
      await client!.connect();
    } on Exception catch (e) {
      print('❌ MQTT: Connection failed - $e');
      disconnect();
      return;
    }

    // Wait a bit for the connection to stabilize
    await Future.delayed(Duration(milliseconds: 500));

    if (client!.connectionStatus!.state == MqttConnectionState.connected) {
      isConnected = true;
      _subscribeToNotifications(username);
      _listen();
    } else {
      print('MQTT: Connection failed - state is ${client!.connectionStatus!.state}');
      disconnect();
    }
  }

  void _subscribeToNotifications(String username) {
    final topic = 'chess/user/$username/notifications';
    client!.subscribe(topic, MqttQos.atLeastOnce);
  }

  void _listen() {
    if (_isListening) {
      print('⚠️ MQTT: Already listening, skipping');
      return;
    }
    
    _isListening = true;
    client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      final MqttPublishMessage recMess = c![0].payload as MqttPublishMessage;
      final String topic = c[0].topic;
      final String pt =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      try {
        final data = json.decode(pt);
        _handleNotification(data);
      } catch (e) {
        print('MQTT: Error parsing message: $e');
      }
    });
  }

  Future<void> _handleNotification(Map<String, dynamic> data) async {
    final type = data['type'];
    final payload = data['payload'];

    if (type == 'game_invitation') {
      _showGameNotification(
        'New Challenge!',
        '${payload['sender']['username']} has challenged you to a game.',
        json.encode(data),
      );
    } else if (type == 'call_invitation') {
      final roomId = payload['room_id'];
      
      // Check if we already suspended/declined this call
      if (_declinedRoomIds.contains(roomId) || _isMutedWindow) {
        return;
      }
      
      // Check if we are already in a call
      if (_isInCall) {
        return;
      }
      
      // Check if we are already ringing for this exact room
      if (_isPlaying && _currentCallRoomId == roomId) {
        return;
      }

      // Suppress system notification if we are already in the Chess Screen for THIS room
      // Use .toString() to be safe with int vs string room IDs
      final String? normalizedIncomingRoomId = roomId?.toString();
      final String? normalizedActiveRoomId = _activeChessRoomId?.toString();
      
      if (normalizedActiveRoomId != null && normalizedActiveRoomId == normalizedIncomingRoomId) {
        print('🚫 MQTT: Suppressing system notification but PLAYING SOUND for active in-game call in room: $roomId');
        
        // playSound immediately (requested by user for audible alert)
        playSound('sounds/ringtone.mp3', roomId: normalizedIncomingRoomId);

        // We still emit the notification so the ChessScreen AppBar can catch it
        _notificationController.add(data);
        return; 
      }

      _currentCallRoomId = roomId;
      
      // RESTORED: Play sound immediately
      playSound('sounds/ringtone.mp3', roomId: roomId);

      _showCallNotification(
        '${payload['caller']}',
        roomId,
        json.encode(data),
      );
    } else if (type == 'call_declined' || type == 'call_ended') {
      final String? roomId = payload != null ? payload['room_id']?.toString() : null;
      
      if (roomId != null) {
        ignoreRoom(roomId);
        stopAudio(broadcast: true, roomId: roomId);
        cancelCallNotification(roomId: roomId); 
      } else {
        cancelCallNotification();
      }
    } else if (type == 'call_cancelled') {
        final String? roomId = payload != null ? payload['room_id']?.toString() : null;
        final String? sender = payload != null ? (payload['sender'] ?? payload['caller']) : null; 

        if (roomId != null) {
          ignoreRoom(roomId);
          stopAudio(broadcast: true, roomId: roomId);
          cancelCallNotification(roomId: roomId); 
          
          // Show Missed Call Notification
          if (sender != null) {
             _showMissedCallNotification(sender);
          }
        } else {
           cancelCallNotification();
        }
    } else if (type == 'invitation_response') {
      final invitation = payload['invitation'];
      final action = payload['action'];
      
      if (action == 'decline') {
        _showLocalNotification(
          'Missed Challenge',
          '${invitation['receiver']['username']} declined your challenge.',
          'invitation_declined',
        );
      } else if (action == 'accept') {
        final roomId = invitation['room_id'];
        _showLocalNotification(
          'Challenge Accepted',
          '${invitation['receiver']['username']} is ready! Tap to join.',
          json.encode({
            'type': 'invitation_response',
            'action': 'accept',
            'payload': invitation, 
          }),
          actions: [
            const AndroidNotificationAction(
              'join_action',
              'Join Now',
              showsUserInterface: true,
            ),
          ],
        );
      }
    }
    
    _notificationController.add(data);
  }

  Future<void> _showGameNotification(String title, String body, String payload) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'chess_challenges_v2', // Match channel creation ID
      'Chess Challenges',
      channelDescription: 'Notifications for chess game invitations',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      fullScreenIntent: true, // Show on lock screen
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      ticker: title, // Ensures notification appears
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
      ),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'decline_action',
          'Decline',
          showsUserInterface: true, // Force foreground for reliability
          cancelNotification: true, 
        ),
        const AndroidNotificationAction(
          'accept',
          'Accept',
          showsUserInterface: true,
          cancelNotification: true, 
        ),
      ],
    );
    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    
    // Use a fixed ID for game notifications so they are manageable
    const int gameNotificationId = 888;

    await flutterLocalNotificationsPlugin.show(
      gameNotificationId,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  Future<void> _showCallNotification(String caller, String roomId, String payload) async {
    // Create notification with action buttons
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chess_incoming_calls_v6', // v6
      'Incoming Calls',
      channelDescription: 'Notifications for incoming calls',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      ongoing: true, // User requirement: unswipeable until response
      autoCancel: false, // Prevent swiping away
      playSound: false,
      enableVibration: true,
      ticker: 'Incoming call from $caller', // Ensures notification appears
      styleInformation: BigTextStyleInformation(
        '$caller is calling you...',
        contentTitle: 'Incoming Call',
      ),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'decline_action',
          'Decline',
          showsUserInterface: true, // Force foreground for reliability
          cancelNotification: true, 
        ),
        const AndroidNotificationAction(
          'accept_action',
          'Accept',
          showsUserInterface: true,
          cancelNotification: true, 
        ),
      ],
    );

    final NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    // Use a fixed ID for call notifications so we can cancel it later
    const int callNotificationId = 999;

    await flutterLocalNotificationsPlugin.show(
      callNotificationId,
      'Incoming Call',
      '$caller is calling you...',
      notificationDetails,
      payload: payload,
    );
  }

  Future<void> _showMissedCallNotification(String caller) async {
    // Create notification channel for missed calls if not exists
    // (Ideally create this in initialize(), but details here work too)
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chess_missed_calls', 
      'Missed Calls',
      channelDescription: 'Notifications for missed calls',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showWhen: true,
      autoCancel: true,
      enableVibration: true,
      category: AndroidNotificationCategory.missedCall,
    );

    final NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    // Use a unique ID (random or based on time)
    final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await flutterLocalNotificationsPlugin.show(
      notificationId,
      'Missed Call',
      'You missed a call from $caller',
      notificationDetails,
      payload: 'missed_call',
    );
  }

  Future<void> _showLocalNotification(String title, String body, String payload, {List<AndroidNotificationAction>? actions}) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chess_general_alerts',
      'General Alerts',
      channelDescription: 'General notifications and alerts',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      autoCancel: true,
      actions: actions,
    );

    final NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);
    final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  void ignoreRoom(String? roomId) {
    if (roomId != null) {
      _declinedRoomIds.add(roomId);
      Future.delayed(const Duration(minutes: 1), () {
        _declinedRoomIds.remove(roomId);
      });
    }
  }

  // Cancels ONLY the system notification without stopping audio or declining
  Future<void> dismissCallNotification() async {
    try {
      await flutterLocalNotificationsPlugin.cancel(999).catchError((_) {});
    } catch (e) {
      print('Error dismissing call notification: $e');
    }
  }

  Future<void> cancelCallNotification({String? roomId, bool broadcast = true}) async {
    // Standardize IDs: game=888, call=999
    try {
      await flutterLocalNotificationsPlugin.cancel(888).catchError((_) {});
      await flutterLocalNotificationsPlugin.cancel(999).catchError((_) {});
      await flutterLocalNotificationsPlugin.cancel(777).catchError((_) {}); // CLEAR ONGOING NOTIFICATION
    } catch (e) {
      print('Notification cancellation error: $e');
    }
    
    if (broadcast) {
      // Broadcast cancellation to other isolates
      for (final portName in ['chess_game_main_port', 'chess_game_bg_port']) {
        final sendPort = IsolateNameServer.lookupPortByName(portName);
        if (sendPort != null) {
          sendPort.send({'action': 'cancel_notification', 'id': 999});
          sendPort.send({'action': 'cancel_notification', 'id': 888});
          sendPort.send({'action': 'cancel_notification', 'id': 777}); // BROADCAST 777 CLEAR
          sendPort.send({'action': 'dismiss_call'});
        }
      }
    }
    
    final String? roomIdToStop = roomId ?? _currentCallRoomId;
    
    if (roomIdToStop != null) {
      _declinedRoomIds.add(roomIdToStop);
      Future.delayed(const Duration(minutes: 1), () {
        _declinedRoomIds.remove(roomIdToStop);
      });

      if (_currentCallRoomId == roomIdToStop) {
        _currentCallRoomId = null;
      }
    } else {
      _currentCallRoomId = null;
    }
    
    stopAudio(broadcast: broadcast, roomId: roomIdToStop);
  }
  
  void setInCall(bool inCall) {
    _isInCall = inCall;
  }

  void setActiveChessRoomId(String? roomId, {bool broadcast = true}) {
    final String? normalizedId = roomId?.toString();
    _activeChessRoomId = normalizedId;

      for (final portName in ['chess_game_main_port', 'chess_game_bg_port']) {
        final sendPort = IsolateNameServer.lookupPortByName(portName);
        if (sendPort != null) {
          sendPort.send({'action': 'set_active_room', 'roomId': normalizedId});
        }
      }
  }

  // Ongoing call notification methods
  Future<void> showOngoingCallNotification({
    required String otherUserName,
    required String roomId,
  }) async {
    const int ongoingCallId = 777; // Unique ID for ongoing call notification
    
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chess_ongoing_calls',
      'Ongoing Calls',
      channelDescription: 'Persistent notification for active calls',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true, // Makes notification persistent
      autoCancel: false,
      showWhen: true,
      usesChronometer: true, // Shows elapsed time
      actions: [
        const AndroidNotificationAction(
          'return_to_call',
          'Return to Call',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'end_call',
          'End Call',
          showsUserInterface: false,
        ),
      ],
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      ongoingCallId,
      'Call in progress',
      'Talking with $otherUserName',
      notificationDetails,
      payload: json.encode({
        'type': 'ongoing_call',
        'room_id': roomId,
        'other_user': otherUserName,
      }),
    );
  }

  Future<void> cancelOngoingCallNotification() async {
    const int ongoingCallId = 777;
    try {
      await flutterLocalNotificationsPlugin.cancel(ongoingCallId);
    } catch (e) {
      print('Error cancelling ongoing call notification: $e');
    }
  }

  void onConnected() {
    isConnected = true;
    if (_currentUsername != null && _isListening == false) {
      _subscribeToNotifications(_currentUsername!);
      _listen();
    }
  }

  void onDisconnected() {
    isConnected = false;
  }

  void onSubscribed(String topic) {
    // Subscribed
  }

  Future<void> playSound(String fileName, {String? roomId}) async {
    final isolateName = Isolate.current.debugName ?? 'unknown';
    
    // Safety check 0: Mute window active?
    if (_isMutedWindow) {
      print('MQTT [$isolateName]: Aborting playSound - Muted window');
      return;
    }

    // Safety check 1: already declined?
    if (roomId != null && _declinedRoomIds.contains(roomId)) {
      print('MQTT [$isolateName]: Blocking playSound - room $roomId already declined');
      return;
    }

    // Safety check 2: already in call?
    if (_isInCall) {
      print('MQTT [$isolateName]: Blocking playSound - user is in active call');
      return;
    }

    _isPlaying = true;
    _isAudioLoading = true;
    
    try {
      // Final Check before starting
      if (_isMutedWindow || _isInCall || (roomId != null && _declinedRoomIds.contains(roomId))) {
        print('MQTT [$isolateName]: Play blocked. Muted: $_isMutedWindow, InCall: $_isInCall, Declined: ${roomId != null && _declinedRoomIds.contains(roomId)}');
        _isPlaying = false;
        _isAudioLoading = false;
        return;
      }

      // Reset player mode
      await _audioPlayer.setReleaseMode(ReleaseMode.loop).catchError((e) {
        print('MQTT [$isolateName]: Error setting release mode: $e');
      });
      await _audioPlayer.setVolume(1.0).catchError((e) {
        print('MQTT [$isolateName]: Error setting volume: $e');
      });

      // Reinforce Audio Context (in case WebRTC or other service changed it)
      const audioContext = AudioContext(
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
        android: AudioContextAndroid(
          usageType: AndroidUsageType.notification,
          contentType: AndroidContentType.music,
          audioFocus: AndroidAudioFocus.gain,
        ),
      );
      await AudioPlayer.global.setAudioContext(audioContext).catchError((e) {
        print('MQTT [$isolateName]: Context reinforcement error: $e');
      });

      if (!_isPlaying) {
        _isAudioLoading = false;
        print('MQTT [$isolateName]: Aborting play - _isPlaying became false during context setup');
        return;
      }

      // Clean path (remove 'assets/' prefix if if play() handles it automatically via AssetSource)
      // audioplayers 5.x AssetSource expectation: 'sounds/ringtone.mp3' (relative to assets/ folder usually)
      String cleanFileName = fileName;
      if (cleanFileName.startsWith('assets/')) {
        cleanFileName = cleanFileName.replaceFirst('assets/', '');
      }

      print('MQTT [$isolateName]: Final Path to Play: $cleanFileName');

      // Play the asset
      await _audioPlayer.play(AssetSource(cleanFileName)).catchError((e) {
        print('MQTT [$isolateName]: CRITICAL Play error: $e');
        _isPlaying = false;
      });
      
      // Explicit resume just in case play() only sets the source
      await _audioPlayer.resume().catchError((_) {});
      
      _isAudioLoading = false;

      // Final Check in case stop was called while loading
      if (!_isPlaying) {
        await _audioPlayer.stop().catchError((_) {});
        await _audioPlayer.setVolume(0).catchError((_) {});
        await _audioPlayer.release().catchError((_) {});
      }
    } catch (e) {
      print('MQTT [$isolateName]: EXCEPTION in playSound: $e');
      _isPlaying = false;
      _isAudioLoading = false;
    }
  }

  Future<void> stopAudio({bool broadcast = false, String? roomId}) async {
    _isPlaying = false; 
    _isMutedWindow = true; // Start mute window

    if (roomId != null) {
      _declinedRoomIds.add(roomId);
    }
    _currentCallRoomId = null; 

    try {
      // Immediate silence
      await _audioPlayer.setVolume(0).catchError((_) {});
      await _audioPlayer.stop().catchError((_) {});
      await _audioPlayer.release().catchError((e) {
      });
      
    } catch (e) {
      print('Stop error: $e');
    }
    
    // Safety: ensure muted window expires but prevents immediate re-trigger during cancellation flows
    Future.delayed(const Duration(seconds: 3), () {
      _isMutedWindow = false;
    });

    if (broadcast) {
      // Signal all Isolates via Port Registry (Fastest)
      // This reaches the Main Isolate and the Background Isolate if they are listening
      for (final portName in ['chess_game_main_port', 'chess_game_bg_port']) {
        final sendPort = IsolateNameServer.lookupPortByName(portName);
        if (sendPort != null) {
          sendPort.send({'action': 'stop_audio', 'roomId': roomId});
        }
      }

      // Signals already sent via Port Registry above
    }
  }

  void disconnect() {
    if (client != null) {
      client!.disconnect();
    }
    isConnected = false;
    _isListening = false;
    stopAudio();
  }
}

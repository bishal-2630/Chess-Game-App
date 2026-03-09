import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import './mqtt_service.dart';
import './django_auth_service.dart';
import './game_service.dart';

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Removed manual DartPluginRegistrant.ensureInitialized() as it triggers problematic UI plugin loads in BG

  // Check if user is logged in before connecting
  final authService = DjangoAuthService();
  await authService.initialize(); // Load from prefs

  // Always register port immediately on start so it can receive stop signals
  final mqttService = MqttService();
  mqttService.initializeIsolateListener(isBackground: true);

  if (authService.isLoggedIn) {
    final username = authService.currentUser?['username'];
    if (username != null) {
      await mqttService.initialize();
      await mqttService.connect(username);
    }
  }

  // Standardized signaling via MqttService stream
  mqttService.notifications.listen((data) async {
    final type = data['type'];
    final payload = data['data'] ?? data['payload'];

    if (type == 'stop_audio') {
      final roomId = payload != null ? payload['room_id'] : null;
      if (roomId != null) {
        MqttService().ignoreRoom(roomId);
      }
      MqttService().stopAudio(broadcast: false, roomId: roomId);
    } else if (type == 'decline_call') {
       final caller = data['caller'];
       final roomId = data['roomId'];
       if (caller != null && roomId != null) {
         await GameService.declineCall(callerUsername: caller, roomId: roomId);
       }
    } else if (type == 'respond_invitation') {
       final id = data['invitationId'];
       final action = data['action'];
       if (id != null && action != null) {
         await GameService.respondToInvitation(invitationId: id, action: action);
       }
    } else if (type == 'cancel_notification') {
       final id = payload?['id'];
       if (id != null) {
         final fln = FlutterLocalNotificationsPlugin();
         await fln.cancel(id);
       }
    }
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Keep service alive
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // You can update the tray notification here if needed
      }
    }

    // Check connection occasionally
    final authService = DjangoAuthService();
    if (authService.isLoggedIn) {
      final mqtt = MqttService();
      if (!mqtt.isConnected) {
        final username = authService.currentUser?['username'];
        if (username != null) {
          // Ensure port is registered even if service restarted/woke up
          mqtt.initializeIsolateListener(isBackground: true);
          await mqtt.connect(username);
        }
      }
    }
  });
}

class BackgroundServiceInstance {
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // Configure local notifications for the foreground service tray
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'my_foreground', // id
      'MY FOREGROUND SERVICE', // title
      description:
          'This channel is used for important notifications.', // description
      importance: Importance.low, // low importance so it doesn't pop up
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'my_foreground',
        initialNotificationTitle: 'Chess Service',
        initialNotificationContent: 'Running in background to receive calls',
        foregroundServiceNotificationId: 800,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: (ServiceInstance service) {}, // Do nothing in FG isolate
        onBackground: onIosBackground,
      ),
    );

    service.startService();
  }
}

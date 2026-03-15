import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';

class MqttService {
  static bool isMainIsolate = false;
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttClient? client;
  bool isConnected = false;
  
  // Dummy field to satisfy compiler - accessible as dynamic
  dynamic flutterLocalNotificationsPlugin; 
  
  Stream<Map<String, dynamic>> get notifications => Stream.empty();

  Future<void> initialize() async {
    print('ℹ️ MqttService: Web initialization (Stub)');
  }
  
  Future<void> connect(String username) async {
    print('ℹ️ MqttService: Web connect called for $username (Stub)');
    isConnected = true;
  }
  
  Future<void> disconnect() async {
     isConnected = false;
  }
  
  void initializeIsolateListener({bool isBackground = false}) {}
  
  Future<void> stopAudio({bool broadcast = false, String? roomId}) async {}
  
  void ignoreRoom(String? roomId) {}
  
  Future<void> playSound(String fileName, {String? roomId}) async {}
  
  void clearLastNotification() {}
  
  Map<String, dynamic>? get lastNotificationEvent => null;

  // Stub methods for missing symbols
  void onNotificationTapped(dynamic response) {}
  
  Future<void> cancelCallNotification({String? roomId, bool broadcast = true}) async {}
  
  Future<void> dismissCallNotification() async {}
  
  void setInCall(bool inCall) {
    print('ℹ️ MqttService: Setting inCall to $inCall (Stub)');
  }

  Future<void> speakRecordingAnnouncement() async {
    print('ℹ️ MqttService: Web announcement (Stub)');
  }
}

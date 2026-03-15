import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

MqttClient setupMqttClient(String broker, String clientIdentifier, int port) {
  // Use WebSocket port for Web (usually 8083 or 8084 for SSL)
  // emqx.io uses 8083 for WS, 8084 for WSS
  final client = MqttBrowserClient('wss://$broker/mqtt', clientIdentifier);
  client.port = 8083; 
  return client;
}

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient setupMqttClient(String broker, String clientIdentifier, int port) {
  final client = MqttServerClient(broker, clientIdentifier);
  client.port = port;
  client.useWebSocket = false;
  return client;
}

import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWithHeaders(String url, Map<String, String> headers) {
  return WebSocketChannel.connect(Uri.parse(url));
}

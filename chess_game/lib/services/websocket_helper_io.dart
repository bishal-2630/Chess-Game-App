import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

WebSocketChannel connectWithHeaders(String url, Map<String, String> headers) {
  return IOWebSocketChannel.connect(Uri.parse(url), headers: headers);
}

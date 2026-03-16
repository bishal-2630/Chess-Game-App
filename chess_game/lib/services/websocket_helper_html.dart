import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/html.dart';

WebSocketChannel connectWithHeaders(String url, Map<String, String> headers) {
  return HtmlWebSocketChannel.connect(Uri.parse(url));
}

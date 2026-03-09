import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart' as http_browser;
import 'dart:html' as html;

http.Client getBrowserClient() {
  return http_browser.BrowserClient()..withCredentials = true;
}

void clearUrlFragment() {
  html.window.history.replaceState(null, 'Chess Game', html.window.location.pathname);
}

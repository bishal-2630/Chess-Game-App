import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart' as http_browser;

http.Client getBrowserClient() {
  return http_browser.BrowserClient()..withCredentials = true;
}

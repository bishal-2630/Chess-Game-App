import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'django_auth_service.dart';
import 'config.dart';

class PaymentService {
  static String get _baseUrl => AppConfig.baseUrl;

  static Future<Map<String, dynamic>> createCheckoutSession() async {
    final authService = DjangoAuthService();
    // baseUrl usually ends with /api/auth/, we need /api/payments/
    final url = _baseUrl.replaceAll('/api/auth/', '/api/payments/create-checkout-session/');
    
    try {
      final response = await authService.authenticatedRequest(
        url,
        method: 'POST',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'success': true, 'url': data['url']};
      } else {
        final data = json.decode(response.body);
        return {'success': false, 'error': data['error'] ?? 'Failed to create session'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<void> launchCheckout(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }
}

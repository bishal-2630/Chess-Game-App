import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../services/config.dart';
import 'django_auth_service.dart';

class GameService {
  static String get _baseUrl => AppConfig.baseUrl;

  // Helper to get headers with JWT token
  static Future<Map<String, String>> _getAuthHeaders() async {
    final authService = DjangoAuthService();
    final token = authService.accessToken;

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Helper for authenticated requests with auto-refresh
  static Future<http.Response> _authenticatedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
    int retryCount = 0,
  }) async {
    headers ??= await _getAuthHeaders();

    http.Response response;
    try {
      if (method == 'POST') {
        response = await http
            .post(Uri.parse(url), headers: headers, body: body)
            .timeout(const Duration(seconds: 30));
      } else {
        response = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 30));
      }

      // Check for token expiration (401)
      if (response.statusCode == 401 && retryCount < 1) {
        final refreshed = await DjangoAuthService().refreshToken();
        if (refreshed) {
          // Retry with new token
          final newHeaders = await _getAuthHeaders();
          return _authenticatedRequest(method, url, headers: newHeaders, body: body, retryCount: retryCount + 1);
        }
      }
      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Get online users
  static Future<Map<String, dynamic>> getOnlineUsers() async {
    try {
      final response = await _authenticatedRequest(
        'GET',
        '${_baseUrl}users/online/',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'users': data['online_users'],
          'count': data['count']
        };
      } else {
        return {'success': false, 'error': 'Failed to load online users'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  // Get all users
  static Future<Map<String, dynamic>> getAllUsers() async {
    try {
      final response = await _authenticatedRequest(
        'GET',
        '${_baseUrl}users/all/',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'users': data['users'],
          'count': data['count']
        };
      } else {
        return {'success': false, 'error': 'Failed to load users'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  // Update online status
  static Future<Map<String, dynamic>> updateOnlineStatus({
    required bool isOnline,
    String? roomId,
  }) async {
    try {
      final response = await _authenticatedRequest(
        'POST',
        '${_baseUrl}users/status/',
        body: json.encode({
          'is_online': isOnline,
          'room_id': roomId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'status': data['status'],
          'is_online': data['is_online'],
          'current_room': data['current_room']
        };
      } else {
        return {'success': false, 'error': 'Failed to update status'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  // Send game invitation
  static Future<Map<String, dynamic>> sendInvitation({
    required String receiverUsername,
    required String roomId,
  }) async {
    try {
      final response = await _authenticatedRequest(
        'POST',
        '${_baseUrl}invitations/send/',
        body: json.encode({
          'receiver_username': receiverUsername,
          'room_id': roomId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': data['success'],
          'invitation': data['invitation'],
          'message': data['message']
        };
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'Failed to send invitation'
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  // Get my invitations
  static Future<Map<String, dynamic>> getMyInvitations() async {
    try {
      final response = await _authenticatedRequest(
        'GET',
        '${_baseUrl}invitations/my/',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'invitations': data['invitations'],
          'count': data['count']
        };
      } else {
        return {'success': false, 'error': 'Failed to load invitations'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  // Respond to invitation
  static Future<Map<String, dynamic>> respondToInvitation({
    required int invitationId,
    required String action, // 'accept' or 'decline'
  }) async {
    try {
      final response = await _authenticatedRequest(
        'POST',
        '${_baseUrl}invitations/$invitationId/respond/',
        body: json.encode({
          'action': action,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': data['success'],
          'invitation': data['invitation'],
          'message': data['message']
        };
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'Failed to respond to invitation'
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  // Cancel invitation
  static Future<Map<String, dynamic>> cancelInvitation({
    required int invitationId,
  }) async {
    try {
      final response = await _authenticatedRequest(
        'POST',
        '${_baseUrl}invitations/$invitationId/cancel/',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'success': data['success'], 'message': data['message']};
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'Failed to cancel invitation'
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  // Send call signal
  static Future<Map<String, dynamic>> sendCallSignal({
    required String receiverUsername,
    required String roomId,
    bool initialVideo = false,
  }) async {
    try {
      final response = await _authenticatedRequest(
        'POST',
        '${_baseUrl}call/send/',
        body: json.encode({
          'receiver_username': receiverUsername,
          'room_id': roomId,
          'initial_video': initialVideo,
        }),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        return {'success': false, 'error': 'Failed to send call signal'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  // Decline call
  static Future<Map<String, dynamic>> declineCall({
    required String callerUsername,
    required String roomId,
  }) async {
    try {
      final response = await _authenticatedRequest(
        'POST',
        '${_baseUrl}call/decline/',
        body: json.encode({
          'caller_username': callerUsername,
          'room_id': roomId,
        }),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        return {'success': false, 'error': 'Failed to decline call'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  // Cancel call (called by caller)
  static Future<Map<String, dynamic>> cancelCall({
    required String receiverUsername,
    required String roomId,
    bool initialVideo = false,
  }) async {
    try {
      final response = await _authenticatedRequest(
        'POST',
        '${_baseUrl}call/cancel/',
        body: json.encode({
          'receiver_username': receiverUsername,
          'room_id': roomId,
          'initial_video': initialVideo,
        }),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        return {'success': false, 'error': 'Failed to cancel call signal'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  // Record game result (win, draw, loss)
  static Future<Map<String, dynamic>> recordGameResult(String result) async {
    try {
      final response = await _authenticatedRequest(
        'POST',
        '${_baseUrl}game/result/',
        body: json.encode({
          'result': result,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Update local user data in DjangoAuthService if needed
        final authService = DjangoAuthService();
        if (authService.currentUser != null) {
          final updatedUser = Map<String, dynamic>.from(authService.currentUser!);
          updatedUser['wins'] = data['wins'];
          updatedUser['draws'] = data['draws'];
          updatedUser['losses'] = data['losses'];
          authService.updateCurrentUser(updatedUser);
        }
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': 'Failed to record result'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }
}

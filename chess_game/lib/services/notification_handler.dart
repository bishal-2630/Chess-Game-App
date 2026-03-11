import 'dart:ui';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// IMPORTANT: Do NOT import MqttService, DjangoAuthService, or GameService here!
// This file must remain lean and pure to avoid background crashes.

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  print('🔔🔔🔔 [BG-FATAL] NOTIFICATION HANDLER WOKE UP!');
  
  try {
    final String? actionId = response.actionId;
    final String? rawPayload = response.payload;
    final int? notificationId = response.id;

    print('🔔 [BG-FATAL] Action: "$actionId", ID: $notificationId');
    print('🔔 [BG-FATAL] Raw Payload: $rawPayload');

    if (rawPayload == null) return;
    final Map<String, dynamic> rawData = json.decode(rawPayload);
    final type = rawData['type'];
    final payload = rawData['data'] ?? rawData['payload'];
    final String? roomId = (payload != null && payload['room_id'] != null) 
        ? payload['room_id'].toString() 
        : null;

    print('🔔 [BG-FATAL] Decoded Data: type=$type, roomId=$roomId');

    // 1. BROADCAST SIGNAL
    // We send to both ports to ensure whoever is alive catches it.
    for (final portName in ['chess_game_main_port', 'chess_game_bg_port']) {
      final SendPort? sendPort = IsolateNameServer.lookupPortByName(portName);
      if (sendPort != null) {
        print('📡 [BG-FATAL] Dispatching to Port: $portName');
        
        // Stop Audio immediately
        sendPort.send({'action': 'stop_audio', 'roomId': roomId});
        sendPort.send({'action': 'dismiss_call'});

        // Handle ongoing call actions
        if (actionId == 'return_to_call' && type == 'ongoing_call') {
          print('📞 [BG-FATAL] Return to Call action');
          // Navigation will be handled by main app
          sendPort.send({
            'action': 'navigate_to_call',
            'roomId': roomId,
            'otherUser': payload?['other_user'],
          });
        } else if (actionId == 'end_call' && type == 'ongoing_call') {
          print('❌ [BG-FATAL] End Call action');
          sendPort.send({
            'action': 'end_active_call',
            'roomId': roomId,
          });
        }

        // If Decline, delegate the network request
        if (actionId == 'decline_action' || actionId == 'decline') {
          if ((type == 'call_invitation' || type == 'incoming_call') && payload != null) {
            final caller = payload['caller'] ?? payload['sender'];
            print('❌ [BG-FATAL] Signaling DECLINE for Call: $caller');
            sendPort.send({
              'action': 'decline_call',
              'caller': caller,
              'roomId': roomId,
            });
          } else if ((type == 'game_invitation' || type == 'game_challenge') && payload != null) {
             final invitationId = int.tryParse(payload['id'].toString());
             print('❌ [BG-FATAL] Signaling DECLINE for Game: $invitationId');
             if (invitationId != null) {
               sendPort.send({
                 'action': 'respond_invitation',
                 'invitationId': invitationId,
                 'action_type': 'decline',
               });
             }
          }
        }
        
        // Signal notification cleanup
        if (notificationId != null) {
           sendPort.send({'action': 'cancel_notification', 'id': notificationId});
        }
        // Force cleanup of common notification IDs
        sendPort.send({'action': 'cancel_notification', 'id': 999});
        sendPort.send({'action': 'cancel_notification', 'id': 888});
        
        print('✅ [BG-FATAL] Port Signal SENT: $portName');
      } else {
        print('⚠️ [BG-FATAL] Port Status: NOT FOUND ($portName)');
      }
    }

  } catch (e, stack) {
    print('❌ [BG-FATAL] HANDLER CRASH: $e');
    print('❌ [BG-FATAL] STACKTRACE: $stack');
  }
}

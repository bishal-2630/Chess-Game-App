import 'dart:convert';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class SignalingService {
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal();

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  // Callbacks
  void Function(TrackPublication publication, Participant participant)? onAddRemoteStream;
  void Function(TrackPublication publication, Participant participant)? onRemoveRemoteStream;
  Function(Map<String, dynamic>)? onGameMove;
  void Function()? onEndCall;
  void Function()? onIncomingCall;
  void Function()? onCallAccepted;
  void Function(bool videoOn)? onRemoteVideoToggle;

  // Connection state
  void Function(bool isConnected)? onConnectionState;

  Future<void> connectToLiveKit(String url, String token) async {
    print("📞 Connecting to LiveKit: $url");
    
    // Check permissions
    if (!kIsWeb) {
      await [Permission.microphone, Permission.camera].request();
    }

    // Disconnect if already connected
    await disconnect();

    _room = Room();
    _listener = _room!.createEventsListener();

    _listener!
      ..on<TrackSubscribedEvent>((event) {
        print("📞 Remote track subscribed: ${event.track.sid}");
        onAddRemoteStream?.call(event.publication, event.participant);
      })
      ..on<TrackUnsubscribedEvent>((event) {
        onRemoveRemoteStream?.call(event.publication, event.participant);
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        // If it's a 1-on-1 call, if the other person leaves, end the call
        if (_room?.remoteParticipants.isEmpty ?? true) {
          onEndCall?.call();
        }
      })
      ..on<DataReceivedEvent>((event) {
         final String data = utf8.decode(event.data);
         try {
           final decoded = jsonDecode(data);
           if (decoded['type'] == 'move') {
             onGameMove?.call(decoded['payload']);
           }
         } catch (e) {
           print("Error decoding data message: $e");
         }
      });

    try {
      await _room!.connect(url, token);
      
      // Auto-publish local tracks
      await _room!.localParticipant?.setCameraEnabled(true);
      await _room!.localParticipant?.setMicrophoneEnabled(true);
      
      onConnectionState?.call(true);
      print("✅ Connected to LiveKit room");
    } catch (e) {
      print("❌ Failed to connect to LiveKit: $e");
      onConnectionState?.call(false);
      rethrow;
    }
  }

  Future<void> setVideoEnabled(bool enabled) async {
    await _room?.localParticipant?.setCameraEnabled(enabled);
  }

  Future<void> muteAudio(bool mute) async {
    await _room?.localParticipant?.setMicrophoneEnabled(!mute);
  }

  void sendMove(Map<String, dynamic> moveData) {
    if (_room != null) {
      final jsonStr = jsonEncode({'type': 'move', 'payload': moveData});
      _room!.localParticipant?.publishData(utf8.encode(jsonStr));
    }
  }

  Future<void> disconnect() async {
    try {
      await _room?.disconnect();
      await _listener?.dispose();
    } catch (e) {
      print("Error during disconnect: $e");
    }
    _room = null;
    _listener = null;
    onConnectionState?.call(false);
  }

  // Compatibility aliases
  Future<void> hangUp() => disconnect();
  void sendEndCall() => disconnect();
}

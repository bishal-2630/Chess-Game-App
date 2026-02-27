import 'dart:convert';
import 'dart:async';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class SignalingService {
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal();

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  // New LiveKit Callbacks
  void Function(TrackPublication publication, Participant participant)? onAddRemoteStream;
  void Function(TrackPublication publication, Participant participant)? onRemoveRemoteStream;
  Function(Map<String, dynamic>)? onGameMove;
  void Function()? onEndCall;
  void Function()? onIncomingCall;
  void Function()? onCallAccepted;
  void Function(bool videoOn)? onRemoteVideoToggle;
  void Function(bool isConnected)? onConnectionState;

  // LEGACY Callbacks (to maintain compatibility with ChessScreen)
  set onLocalStream(Function(dynamic)? callback) {}
  set onPlayerLeft(Function()? callback) {}
  set onCallRejected(Function()? callback) {}
  set onNewGame(Function()? callback) {}
  set onPlayerJoined(Function()? callback) {}

  Future<void> connectToLiveKit(String url, String token) async {
    print("📞 Connecting to LiveKit: $url");
    
    if (!kIsWeb) {
      await [Permission.microphone, Permission.camera].request();
    }

    await disconnect();

    _room = Room();
    
    // In LiveKit 2.x, use createListener()
    _listener = _room!.createListener();
    _listener!
      ..on<TrackSubscribedEvent>((event) {
        onAddRemoteStream?.call(event.publication, event.participant);
      })
      ..on<TrackUnsubscribedEvent>((event) {
        onRemoveRemoteStream?.call(event.publication, event.participant);
      })
      ..on<ParticipantDisconnectedEvent>((event) {
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
      await _room!.localParticipant?.setCameraEnabled(true);
      await _room!.localParticipant?.setMicrophoneEnabled(true);
      onConnectionState?.call(true);
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
    if (_room?.localParticipant != null) {
      final jsonStr = jsonEncode({'type': 'move', 'payload': moveData});
      _room!.localParticipant!.publishData(utf8.encode(jsonStr));
    }
  }

  Future<void> disconnect() async {
    if (_room != null) {
      await _listener?.dispose();
      _listener = null;
      await _room!.disconnect();
      _room = null;
    }
    onConnectionState?.call(false);
  }

  // LEGACY Methods (Stubs to prevent build errors)
  Future<void> stopAudio() async {}
  void sendBye() {}
  void connect(String url, {String? token}) {}
  Future<void> acceptCall(dynamic local, dynamic remote, {bool videoEnabled = false}) async {
    // This is called from ChessScreen. 
    // It already has the roomId in its state, but we need the token.
    // However, the roomId isn't passed here. 
    // WE SHOULD FETCH THE TOKEN IN THE SCREEN AND CALL connectToLiveKit directly.
    // For legacy support, we can't do much without a roomId.
  }
  
  Future<void> startCall(dynamic local, dynamic remote, {bool videoEnabled = false}) async {
    // Same as acceptCall.
  }
  void sendNewGame() {}
  Future<void> hangUp() => disconnect();
  void sendEndCall() => disconnect();
}

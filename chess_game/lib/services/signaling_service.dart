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
  StreamSubscription? _eventSubscription;

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
    
    // In LiveKit 2.x, we listen to the events stream
    _eventSubscription = _room!.events.listen(_onRoomEvent);

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

  void _onRoomEvent(RoomEvent event) {
    if (event is TrackSubscribedEvent) {
      onAddRemoteStream?.call(event.publication, event.participant);
    } else if (event is TrackUnsubscribedEvent) {
      onRemoveRemoteStream?.call(event.publication, event.participant);
    } else if (event is ParticipantDisconnectedEvent) {
       if (_room?.remoteParticipants.isEmpty ?? true) {
          onEndCall?.call();
        }
    } else if (event is DataReceivedEvent) {
      final String data = utf8.decode(event.data);
      try {
        final decoded = jsonDecode(data);
        if (decoded['type'] == 'move') {
          onGameMove?.call(decoded['payload']);
        }
      } catch (e) {
        print("Error decoding data message: $e");
      }
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
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      await _room!.disconnect();
      _room = null;
    }
    onConnectionState?.call(false);
  }

  // LEGACY Methods (Stubs to prevent build errors)
  Future<void> stopAudio() async {}
  void sendBye() {}
  void connect(String url, {String? token}) {}
  Future<void> acceptCall(dynamic local, dynamic remote, {bool videoEnabled = false}) async {}
  Future<void> startCall(dynamic local, dynamic remote, {bool videoEnabled = false}) async {}
  void sendNewGame() {}
  Future<void> hangUp() => disconnect();
  void sendEndCall() => disconnect();
}

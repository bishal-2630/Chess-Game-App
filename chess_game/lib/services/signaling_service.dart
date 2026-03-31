import 'dart:convert';
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'config.dart';

class SignalingService {
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal();

  WebSocketChannel? _channel;
  String? _currentRoomId; // Track current intended room
  String? get currentRoomId => _currentRoomId;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  
  // Callbacks for UI
  void Function(MediaStream stream)? onLocalStream;
  void Function(MediaStream stream)? onAddRemoteStream;
  void Function(MediaStream stream)? onRemoveRemoteStream;
  void Function()? onEndCall;
  void Function(bool isConnected)? onConnectionState;
  
  // Game Signaling Callbacks
  void Function(Map<String, dynamic> data)? onGameMove;
  void Function(Map<String, dynamic> opponent)? onRoomStatus;
  void Function(Map<String, dynamic> opponent)? onPlayerJoined;
  void Function()? onPlayerLeft;
  void Function()? onIncomingCall;
  void Function(bool enabled)? onRemoteVideoToggle;
  void Function()? onCallAccepted;
  void Function()? onCallRejected;
  void Function()? onNewGame;

  // WebRTC Configuration
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': ['stun:stun1.l.google.com:19302', 'stun:stun2.l.google.com:19302']}
    ]
  };

  Future<void> connectToWebSocket(String roomId) async {
    // 1. If already connecting/connected to this room, skip
    if (_channel != null && _currentRoomId == roomId) {
      print("🔔 Already connecting to room $roomId. Skipping redundant request.");
      onConnectionState?.call(true); // Ensure UI stays in sync
      return;
    }

    _currentRoomId = roomId;

    // 2. Cleanly close any existing channel
    if (_channel != null) {
      print("🚿 Closing stale connection before room change.");
      // We don't await sink.close() here as it might hang; just clear reference
      final oldChannel = _channel;
      _channel = null;
      oldChannel!.sink.close();
    }

    final host = AppConfig.baseUrl.replaceAll('http://', '').replaceAll('https://', '').replaceAll('/api/auth/', '');
    final scheme = AppConfig.baseUrl.startsWith('https') ? 'wss' : 'ws';
    final url = '$scheme://$host/ws/call/$roomId/';
    
    print("📞 Connecting to Signaling Server: $url");
    
    try {
      final newChannel = WebSocketChannel.connect(Uri.parse(url));
      _channel = newChannel;

      _channel!.stream.listen(
        (msg) {
          // Only process message if this is the CURRENT active channel
          if (_channel == newChannel) {
            _onMessage(msg);
          }
        }, 
        onDone: () {
          // ONLY trigger disconnect logic if this was the intended channel
          if (_channel == newChannel) {
            print("⚠️ Current Signaling Socket Closed.");
            _currentRoomId = null;
            onConnectionState?.call(false);
          } else {
            print("💡 Stale Signaling Socket Closed (Ignored).");
          }
        }, 
        onError: (e) {
          if (_channel == newChannel) {
            print("❌ Current Signaling Error: $e");
            _currentRoomId = null;
            onConnectionState?.call(false);
          }
        }
      );
      
      // Delay slightly to ensure UI has finished building the "Connecting..." state
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_channel == newChannel) {
          onConnectionState?.call(true);
        }
      });
    } catch (e) {
      print("❌ Failed to connect to signaling server: $e");
      _currentRoomId = null;
      onConnectionState?.call(false);
    }
  }

  void _onMessage(dynamic message) async {
    final data = jsonDecode(message);
    final type = data['type'];
    final payload = data['payload'] ?? data;

    print("📬 Received Signaling Message: $type");

    switch (data['type']) {
      case 'connected':
        onConnectionState?.call(true); // Ensure UI knows we are connected
        if (data['opponent'] != null) {
          onRoomStatus?.call(data['opponent']);
        }
        break;
      case 'offer':
        await _handleOffer(payload);
        break;
      case 'answer':
        await _handleAnswer(payload);
        break;
      case 'candidate':
        await _handleCandidate(payload);
        break;
      case 'end_call':
        onEndCall?.call();
        break;
      case 'move':
        onGameMove?.call(payload);
        break;
      case 'leave':
      case 'player_left':
        onPlayerLeft?.call();
        break;
      case 'incoming_call':
        onIncomingCall?.call();
        break;
      case 'call_accepted':
        onCallAccepted?.call();
        break;
      case 'call_rejected':
        onCallRejected?.call();
        break;
      case 'remote_video_toggle':
        onRemoteVideoToggle?.call(payload['enabled'] ?? false);
        break;
      case 'new_game':
        onNewGame?.call();
        break;
      case 'player_joined':
        if (data['opponent'] != null) {
          onPlayerJoined?.call(data['opponent']);
        }
        break;
    }
  }

  Future<void> _createPeerConnection() async {
    if (_peerConnection != null) return;
    _peerConnection = await createPeerConnection(_iceServers);

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _send('candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      print("🎵 Received Remote Track: ${event.track.kind}");
      if (event.streams.isNotEmpty) {
        onAddRemoteStream?.call(event.streams[0]);
      }
    };

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
    }
  }

  /// Opens user media. Returns null on success, or an error string on failure.
  Future<String?> openUserMedia({bool videoEnabled = false}) async {
    // Try with requested constraints first
    try {
      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': videoEnabled ? {
          'facingMode': 'user',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        } : false,
      };
      
      print("🎤 Requesting Media: $mediaConstraints");
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      
      if (_localStream != null) {
        print("✅ Media Access Granted: Audio=${_localStream!.getAudioTracks().length}, Video=${_localStream!.getVideoTracks().length}");
        onLocalStream?.call(_localStream!);
        return null;
      }
      return "Failed to get local stream";
    } catch (e) {
      print("⚠️ Media access failed: $e");
      return "Failed to get media: $e";
    }
  }

  Future<void> startCall() async {
    await _createPeerConnection();
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _send('offer', {'sdp': offer.sdp, 'type': offer.type});
  }

  Future<void> _handleOffer(Map<String, dynamic> data) async {
    await _createPeerConnection();
    await _peerConnection!.setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']));
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    _send('answer', {'sdp': answer.sdp, 'type': answer.type});
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    if (_peerConnection != null) {
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']));
    }
  }

  Future<void> _handleCandidate(Map<String, dynamic> data) async {
    if (_peerConnection != null) {
      await _peerConnection!.addCandidate(RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
    }
  }

  void _send(String type, dynamic payload) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({'type': type, 'payload': payload}));
    }
  }

  Future<void> disconnect() async {
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
    
    _peerConnection?.close();
    _peerConnection = null;
    
    _channel?.sink.close();
    _channel = null;
    
    clearCallbacks();
    onConnectionState?.call(false);
  }

  void clearCallbacks() {
    onLocalStream = null;
    onAddRemoteStream = null;
    onConnectionState = null;
    onRoomStatus = null;
    onEndCall = null;
    onGameMove = null;
    onNewGame = null;
    onPlayerJoined = null;
    onRemoteVideoToggle = null;
  }

  // Support methods for CallScreen
  Future<void> muteAudio(bool mute) async {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !mute);
  }

  Future<void> setVideoEnabled(bool enabled) async {
    if (enabled && (_localStream == null || _localStream!.getVideoTracks().isEmpty)) {
      try {
        print("📸 Acquiring video track mid-call...");
        final MediaStream videoStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {
            'facingMode': 'user',
            'width': {'ideal': 640},
            'height': {'ideal': 480},
          }
        });

        if (videoStream.getVideoTracks().isNotEmpty) {
          final videoTrack = videoStream.getVideoTracks().first;
          _localStream?.addTrack(videoTrack);
          
          if (_peerConnection != null) {
            _peerConnection!.addTrack(videoTrack, _localStream!);
            
            // Trigger re-negotiation
            final offer = await _peerConnection!.createOffer();
            await _peerConnection!.setLocalDescription(offer);
            _send('offer', {'sdp': offer.sdp, 'type': offer.type});
          }
          
          onLocalStream?.call(_localStream!);
        }
      } catch (e) {
        print("❌ Failed to add video track mid-call: $e");
      }
    }

    _localStream?.getVideoTracks().forEach((t) => t.enabled = enabled);
    _send('remote_video_toggle', {'enabled': enabled});
  }

  // Game Signaling Methods
  void sendMove(Map<String, dynamic> moveData) => _send('move', moveData);
  void sendNewGame() => _send('new_game', {});
  void sendBye() => _send('leave', {});
  
  void sendEndCall() {
    print("📞 Sending end_call signal");
    _send('end_call', {});
  }

  /// Called by the callee after accepting a call.
  /// Signals the caller to begin the WebRTC offer negotiation.
  void signalCallAccepted() {
    print("📞 Sending call_accepted signal");
    _send('call_accepted', {});
  }

  Future<void> stopAudio() async {
    _localStream?.getAudioTracks().forEach((t) => t.stop());
  }

  Future<void> hangUp() async => disconnect();

}

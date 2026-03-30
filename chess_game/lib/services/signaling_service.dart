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
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  
  // Callbacks for UI
  void Function(MediaStream stream)? onLocalStream;
  void Function(MediaStream stream)? onAddRemoteStream;
  void Function(MediaStream stream)? onRemoveRemoteStream;
  void Function()? onEndCall;
  void Function(bool isConnected)? onConnectionState;

  // WebRTC Configuration
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': ['stun:stun1.l.google.com:19302', 'stun:stun2.l.google.com:19302']}
    ]
  };

  Future<void> connectToWebSocket(String roomId) async {
    final host = AppConfig.baseUrl.replaceAll('http://', '').replaceAll('https://', '').replaceAll('/', '');
    final scheme = AppConfig.baseUrl.startsWith('https') ? 'wss' : 'ws';
    final url = '$scheme://$host/ws/call/$roomId/';
    
    print("📞 Connecting to Signaling Server: $url");
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen(_onMessage, onDone: disconnect, onError: (e) => print("❌ Signaling Error: $e"));
      onConnectionState?.call(true);
    } catch (e) {
      print("❌ Failed to connect to signaling server: $e");
      onConnectionState?.call(false);
    }
  }

  void _onMessage(dynamic message) async {
    final data = jsonDecode(message);
    final type = data['type'];
    final payload = data['payload'] ?? data;

    switch (type) {
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
    }
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _send('candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) {
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

  Future<bool> openUserMedia({bool videoEnabled = false}) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': videoEnabled ? {'facingMode': 'user'} : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      onLocalStream?.call(_localStream!);
      return true;
    } catch (e) {
      print("❌ Error accessing media: $e");
      return false;
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

  void _send(String type, Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode({'type': type, 'payload': data}));
  }

  Future<void> disconnect() async {
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
    
    _peerConnection?.close();
    _peerConnection = null;
    
    _channel?.sink.close();
    _channel = null;
    
    onConnectionState?.call(false);
  }

  // Support methods for CallScreen
  Future<void> muteAudio(bool mute) async {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !mute);
  }

  Future<void> setVideoEnabled(bool enabled) async {
    _localStream?.getVideoTracks().forEach((t) => t.enabled = enabled);
  }

  // Compatibility stubs
  Future<void> connectToLiveKit(String url, String token, {bool videoEnabled = false}) async => connectToWebSocket(url);
  void sendEndCall() => _send('end_call', {});
}

import 'dart:convert';
import 'dart:math';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart'; // Added for kIsWeb
import './websocket_helper.dart';

typedef StreamStateCallback = void Function(MediaStream stream);

class SignalingService {
  WebSocketChannel? _channel;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final List<RTCIceCandidate> _remoteCandidates = [];

  // Call handling
  Map<String, dynamic>? _pendingOffer;

  StreamStateCallback? onLocalStream;
  StreamStateCallback? onAddRemoteStream;
  StreamStateCallback? onRemoveRemoteStream;
  Function(Map<String, dynamic>)? onGameMove;
  void Function()? onPlayerLeft;
  void Function()? onPlayerJoined;
  void Function()? onEndCall;
  void Function()? onCallRejected;
  void Function()? onIncomingCall;
  void Function()? onCallAccepted;
  void Function()? onNewGame;
  void Function(bool videoOn)? onRemoteVideoToggle;

  // Connection state callbacks
  void Function(bool isConnected)? onConnectionState;

  // Stun servers
  Map<String, dynamic> configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302'
        ]
      }
    ],
    'sdpSemantics': 'unified-plan',
  };

  // Connect using a full URL (e.g., ws://... or wss://...)
  void connect(String socketUrl, {String? token}) async {
    // Clean up any existing connection first
    await disconnect();

    try {
      String urlWithToken = socketUrl;
      final headers = {'ngrok-skip-browser-warning': 'true'};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
        // Also add as query param for robustness (some proxies strip headers)
        urlWithToken += '?token=$token';
      }

      _channel = connectWithHeaders(
        urlWithToken,
        headers,
      );

      _channel!.stream.listen((message) {
        try {
          _onMessage(jsonDecode(message));
        } catch (e) {
        }
      }, onDone: () {
        if (onConnectionState != null) onConnectionState!(false);
      }, onError: (error) {
        print('WebSocket Error: $error');
        if (onConnectionState != null) onConnectionState!(false);
      });

      // ADD THIS LINE HERE (if you haven't already correctly)
      if (onConnectionState != null) onConnectionState!(true);
    } catch (e) {
      print('Connection failed: $e');
      if (onConnectionState != null) onConnectionState!(false);
    }
  }

  Future<void> _onMessage(Map<String, dynamic> data) async {
    String type = data['type'];
    Map<String, dynamic> payload = data['payload'] ?? data;
    print('📞 Signaling MSG: $type');

    switch (type) {
      case 'offer':
        print("📞 Received Offer");
        _pendingOffer = payload;
        if (onIncomingCall != null) {
          onIncomingCall!();
        }
        break;
      case 'answer':
        print("📞 Received Answer");
        await _handleAnswer(payload);
        break;
      case 'candidate':
        print("📞 Received Candidate");
        await _handleCandidate(payload);
        break;
      case 'move':
        if (onGameMove != null) {
          onGameMove!(payload);
        }
        break;
      case 'bye':
        if (onPlayerLeft != null) {
          onPlayerLeft!();
        }
        break;
      case 'end_call':
        if (onEndCall != null) {
          onEndCall!();
        }
        break;
      case 'call_accepted':
        print("📞 Call Accepted by remote");
        if (onCallAccepted != null) {
          onCallAccepted!();
        }
        break;
      case 'connected':
        if (onConnectionState != null) {
          onConnectionState!(true);
        }
        break;
      case 'new_game':
        if (onNewGame != null) {
          onNewGame!();
        }
        break;
      case 'join':
        print("📞 Peer Joined room");
        if (onPlayerJoined != null) {
          onPlayerJoined!();
        }
        break;
      case 'call_rejected':
        if (onCallRejected != null) {
          onCallRejected!();
        }
        break;
      case 'video_toggle':
        if (onRemoteVideoToggle != null) {
          onRemoteVideoToggle!(payload['videoOn']);
        }
        break;
      default:
        print('📞 Unknown signaling type: $type');
    }
  }

  // --- Call Control ---

  // Initiator: Start a call
  Future<void> startCall(
      RTCVideoRenderer localVideo, RTCVideoRenderer remoteVideo, {bool videoEnabled = true}) async {
    print("📞 startCall() initiated (video: $videoEnabled)");
    try {
      await _openUserMedia(localVideo, remoteVideo, videoEnabled: videoEnabled);
      if (_localStream == null) {
        throw Exception("Failed to get local media stream");
      }

      await _createPeerConnection();
      if (_peerConnection == null) {
        throw Exception("Failed to create PeerConnection");
      }

      print("📞 Creating Offer...");
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      _send('offer', {
        'sdp': offer.sdp,
        'type': offer.type,
      });
      print("📞 Offer sent");
    } catch (e) {
      print("❌ SignalingService.startCall failed: $e");
      rethrow;
    }
  }

  // Receiver: Accept an incoming call
  Future<void> acceptCall(
      RTCVideoRenderer localVideo, RTCVideoRenderer remoteVideo, {bool videoEnabled = true}) async {
    print("📞 acceptCall() initiated (video: $videoEnabled)");
    if (_pendingOffer == null) {
      print("❌ No pending offer to accept");
      return;
    }

    try {
      await _openUserMedia(localVideo, remoteVideo, videoEnabled: videoEnabled);
      await _createPeerConnection(); 

      print("📞 Setting Remote Description (Offer)...");
      var description =
          RTCSessionDescription(_pendingOffer!['sdp'], _pendingOffer!['type']);
      await _peerConnection!.setRemoteDescription(description);

      print("📞 Creating Answer...");
      RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      _send('answer', {
        'sdp': answer.sdp,
        'type': answer.type,
      });
      print("📞 Answer sent");

      _pendingOffer = null;
      _send('call_accepted', {});

      // Add queued candidates now that remote description is set
      print("📞 Processing ${_remoteCandidates.length} queued candidates");
      for (var candidate in _remoteCandidates) {
        await _peerConnection!.addCandidate(candidate);
      }
      _remoteCandidates.clear();
    } catch (e) {
      print("❌ SignalingService.acceptCall failed: $e");
      rethrow;
    }
  }

  void sendEndCall() {
    _send('end_call', {});
  }

  Future<void> _createPeerConnection() async {
    print("📞 Creating PeerConnection...");
    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate == null) {
        print("📞 ICE Gathering complete");
        return;
      }
      print("📞 ICE Candidate generated: ${candidate.candidate?.substring(0, 20)}...");
      _send('candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      print("📞 ICE Connection State: $state");
    };

    _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
      print("📞 ICE Gathering State: $state");
    };

    _peerConnection!.onSignalingState = (RTCSignalingState state) {
      print("📞 Signaling State: $state");
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      print("📞 Remote track received: ${event.track.kind}");
      if (event.streams.isNotEmpty && onAddRemoteStream != null) {
        onAddRemoteStream!(event.streams[0]);
      }
    };

    // Add local stream
    if (_localStream != null && _peerConnection != null) {
      print("📞 Adding local tracks to PeerConnection");
      _localStream!.getTracks().forEach((track) {
        if (_peerConnection != null) {
          _peerConnection!.addTrack(track, _localStream!);
        }
      });
    }
  }

  Future<void> _openUserMedia(
      RTCVideoRenderer localVideo, RTCVideoRenderer remoteVideo, {bool videoEnabled = true}) async {
    print("📞 _openUserMedia() initiated (video: $videoEnabled)");
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': true, // ALWAYS request video so we can toggle it later
    };

    try {
      // 1. Check & Request Permissions on Mobile
      if (!kIsWeb) {
        print("📞 Checking Permissions...");
        final micStatus = await Permission.microphone.request();
        if (micStatus.isDenied) {
          throw Exception("Microphone permission denied");
        }
        
        // Request camera permission but don't strictly require it if call starts as audio-only
        final cameraStatus = await Permission.camera.request();
        if (videoEnabled && cameraStatus.isDenied) {
          throw Exception("Camera permission denied (required for Video Call)");
        }
      }

      print("📞 Requesting getUserMedia...");
      MediaStream stream;
      try {
        stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      } catch (e) {
        print("⚠️ getUserMedia failed with video, trying audio-only fallback: $e");
        if (videoEnabled) rethrow; // If they wanted video and it failed, stop.
        
        // Fallback for audio-only calls
        stream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
      }
      
      _localStream = stream;

      // Disable video track initially if call started as audio-only
      if (!videoEnabled && stream.getVideoTracks().isNotEmpty) {
        stream.getVideoTracks()[0].enabled = false;
        print("📞 Video track disabled initially (Audio Call)");
      }

      await Helper.setSpeakerphoneOn(true);

      if (onLocalStream != null) {
        onLocalStream!(stream);
      }
      print("📞 getUserMedia Success");
    } catch (e) {
      print("❌ SignalingService._openUserMedia failed: $e");
      _localStream = null;
      rethrow;
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    try {
      if (_peerConnection == null) {
        print("❌ Cannot handle answer - PeerConnection is null");
        return;
      }
      print("📞 Setting Remote Description (Answer)...");
      var description = RTCSessionDescription(data['sdp'], data['type']);
      await _peerConnection!.setRemoteDescription(description);

      // Processing queued candidates for Caller
      print("📞 Processing ${_remoteCandidates.length} queued candidates");
      for (var candidate in _remoteCandidates) {
        await _peerConnection!.addCandidate(candidate);
      }
      _remoteCandidates.clear();
    } catch (e) {
      print("❌ Error handling answer: $e");
    }
  }

  Future<void> _handleCandidate(Map<String, dynamic> data) async {
    try {
      if (data['candidate'] == null) return;

      var candidate = RTCIceCandidate(
          data['candidate'], data['sdpMid'], data['sdpMLineIndex']);

      // Only add candidate if Remote Description is set
      // Otherwise queue it
      if (_peerConnection != null) {
        final remoteDesc = await _peerConnection!.getRemoteDescription();
        if (remoteDesc != null) {
          print("📞 Adding ICE candidate immediately");
          await _peerConnection!.addCandidate(candidate);
        } else {
          print("📞 Remote description not set, queuing ICE candidate");
          _remoteCandidates.add(candidate);
        }
      } else {
        print("📞 PeerConnection not ready, queuing ICE candidate");
        _remoteCandidates.add(candidate);
      }
    } catch (e) {
      print("❌ Error adding candidate: $e");
    }
  }

  void _send(String type, Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({'type': type, ...data}));
    }
  }

  void sendMove(Map<String, dynamic> moveData) {
    _send('move', moveData);
  }

  void sendBye() {
    _send('bye', {});
  }

  void sendNewGame() {
    _send('new_game', {});
  }

  void sendJoin() {
    _send('join', {});
  }

  void sendCallRejected() {
    _send('call_rejected', {});
  }

  void muteAudio(bool mute) {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      _localStream!.getAudioTracks()[0].enabled = !mute;
    }
  }

  void setVideoEnabled(bool enabled) {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      _localStream!.getVideoTracks()[0].enabled = enabled;
      _send('video_toggle', {'videoOn': enabled});
    }
  }

  // Close only audio/video, keep WebSocket (Game) alive
  Future<void> stopAudio() async {
    try {
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) => track.stop());
        _localStream!.dispose();
        _localStream = null;
      }
      if (_peerConnection != null) {
        _peerConnection!.close();
        _peerConnection = null;
      }
    } catch (e) {
      print(e.toString());
    }
  }

  // Close everything including WebSocket
  Future<void> disconnect() async {
    await stopAudio();
    try {
      if (_channel != null) {
        _channel!.sink.close();
        _channel = null;
      }
    } catch (e) {
      print(e.toString());
    }
  }

  // Deprecated alias
  Future<void> hangUp() => disconnect();
}

import 'dart:convert';
import 'dart:math';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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

    switch (type) {
      case 'offer':
        // received an offer, notify UI but DO NOT answer yet
        _pendingOffer = payload;
        if (onIncomingCall != null) {
          onIncomingCall!();
        }
        break;
      case 'answer':
        await _handleAnswer(payload);
        break;
      case 'candidate':
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
        if (onPlayerJoined != null) {
          onPlayerJoined!();
        }
        break;
      case 'call_rejected':
        if (onCallRejected != null) {
          onCallRejected!();
        }
        break;
      default:
        // Unknown message type
    }
  }

  // --- Call Control ---

  // Initiator: Start a call
  Future<void> startCall(
      RTCVideoRenderer localVideo, RTCVideoRenderer remoteVideo) async {
    try {
      await _openUserMedia(localVideo, remoteVideo);
      if (_localStream == null) {
        throw Exception("Failed to get local media stream");
      }

      await _createPeerConnection();
      if (_peerConnection == null) {
        throw Exception("Failed to create PeerConnection");
      }

      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      _send('offer', {
        'sdp': offer.sdp,
        'type': offer.type,
      });
    } catch (e) {
      print("❌ SignalingService.startCall failed: $e");
      rethrow;
    }
  }

  // Receiver: Accept an incoming call
  Future<void> acceptCall(
      RTCVideoRenderer localVideo, RTCVideoRenderer remoteVideo) async {
    if (_pendingOffer == null) {
      print("No pending offer to accept");
      return;
    }

    await _openUserMedia(localVideo, remoteVideo);
    await _createPeerConnection(); // Create PC before setting remote desc

    // Set Remote Description (the pending offer)
    var description =
        RTCSessionDescription(_pendingOffer!['sdp'], _pendingOffer!['type']);
    await _peerConnection!.setRemoteDescription(description);

    // Create Answer
    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _send('answer', {
      'sdp': answer.sdp,
      'type': answer.type,
    });

    // Clear pending
    _pendingOffer = null;

    // Notify initiator that we accepted
    _send('call_accepted', {});

    // Add any queued candidates
    for (var candidate in _remoteCandidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    _remoteCandidates.clear();
  }

  void sendEndCall() {
    _send('end_call', {});
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate == null) {
        return;
      }
      _send('candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
    };

    _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
    };

    _peerConnection!.onSignalingState = (RTCSignalingState state) {
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && onAddRemoteStream != null) {
        onAddRemoteStream!(event.streams[0]);
      }
    };

    // Add local stream
    if (_localStream != null && _peerConnection != null) {
      _localStream!.getTracks().forEach((track) {
        if (_peerConnection != null) {
          _peerConnection!.addTrack(track, _localStream!);
        }
      });
    }
  }

  Future<void> _openUserMedia(
      RTCVideoRenderer localVideo, RTCVideoRenderer remoteVideo) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': true,
    };

    try {
      var stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localStream = stream;

      // Ensure audio is routed to speaker
      await Helper.setSpeakerphoneOn(true);

      if (onLocalStream != null) {
        onLocalStream!(stream);
      }
    } catch (e) {
      print("❌ SignalingService._openUserMedia failed: $e");
      _localStream = null;
      rethrow;
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    try {
      if (_peerConnection == null) {
        return;
      }
      print("📞 Setting remote description (answer)");
      var description = RTCSessionDescription(data['sdp'], data['type']);

      // Secondary check before await
      if (_peerConnection == null) return;

      await _peerConnection!.setRemoteDescription(description);
    } catch (e) {
      print("❌ Error handling answer: $e");
    }
  }

  Future<void> _handleCandidate(Map<String, dynamic> data) async {
    try {
      if (data['candidate'] == null) {
        return;
      }

      var candidate = RTCIceCandidate(
          data['candidate'], data['sdpMid'], data['sdpMLineIndex']);

      if (_peerConnection != null) {
        await _peerConnection!.addCandidate(candidate);
      } else {
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

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling_service.dart';
import '../services/config.dart';
import '../services/django_auth_service.dart';
import '../services/game_service.dart';
import '../services/mqtt_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:go_router/go_router.dart';
import 'dart:async'; // Add this import for Timer

class CallScreen extends StatefulWidget {
  final String roomId;
  final String otherUserName;
  final bool isCaller;
  final bool initialVideo;

  const CallScreen({
    super.key,
    required this.roomId,
    required this.otherUserName,
    this.isCaller = false,
    this.initialVideo = false,
  });

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final DjangoAuthService _authService = DjangoAuthService();
  final SignalingService _signalingService = SignalingService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inCall = false;
  String _status = "Connecting...";
  bool _isMuted = false;
  late bool _isVideoOn;
  bool _isExiting = false;
  Timer? _callTimeoutTimer; // Add timer variable

  @override
  void initState() {
    super.initState();
    print("📞 CallScreen: initState called (initialVideo: ${widget.initialVideo})");
    _isVideoOn = widget.initialVideo;
    MqttService().setInCall(true); // Mark as in-call
    
    // For Callee, stop the incoming ringtone and cancel notification
    if (!widget.isCaller) {
      MqttService().stopAudio().then((_) {
        MqttService().cancelCallNotification();
      });
    }
    _initRenderers();
    _connect();
    _listenForDecline();

    // Start 30s timeout if I am the caller
    if (widget.isCaller) {
      _startCallTimeout();
    }
  }

  void _startCallTimeout() {
    _callTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted || _inCall || _isExiting) return;
      
      _isExiting = true; // Prevent multiple exists

      // Cancel call via backend
      GameService.cancelCall(
        receiverUsername: widget.otherUserName,
        roomId: widget.roomId,
      );

      // Stop audio
      MqttService().stopAudio();
      _signalingService.hangUp();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.otherUserName} did not answer')),
        );
        context.go('/users');
      }
    });
  }

  void _listenForDecline() {
    MqttService().notifications.listen((data) {
      if (!mounted || _isExiting) return;
      
      final type = data['type'];
      if (type == 'call_declined') {
        final decliner = data['data'] != null ? data['data']['decliner'] : data['payload']['decliner'];
        print("❌ Call declined by $decliner");
        
        // Stop audio (ringback tone)
        MqttService().stopAudio(broadcast: true);
        
        _handleCallEnd("Call Declined");
      }
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _signalingService.onLocalStream = ((stream) {
      _localRenderer.srcObject = stream;
      setState(() {});
    });

    _signalingService.onAddRemoteStream = ((stream) {
      print("📞 Remote stream added to renderer");
      _remoteRenderer.srcObject = stream;
      setState(() {});
    });

    _signalingService.onPlayerJoined = () async {
      print("👋 Peer joined the room callback");
      _callTimeoutTimer?.cancel(); // Cancel timeout when answered
      
      // Stop ringback tone as soon as someone joins
      await MqttService().stopAudio();
      
      if (widget.isCaller) {
        print("📞 I am the caller, starting handshake...");
        setState(() => _status = "Peer joined. Calling...");
        _startCall(); // Auto-start call when peer joins
      }
    };

    _signalingService.onIncomingCall = () async {
      print("📞 Incoming call offer received callback");
      if (!widget.isCaller) {
        print("📞 Accepting incoming call (video: $_isVideoOn)...");
        setState(() => _status = "Accepting call...");
        await _signalingService.acceptCall(_localRenderer, _remoteRenderer, videoEnabled: _isVideoOn);
        setState(() {
          _inCall = true;
          _status = "Connected";
        });
        print("📞 Handshake complete (Callee side)");
        
        // Show ongoing call notification
        await MqttService().showOngoingCallNotification(
          otherUserName: widget.otherUserName,
          roomId: widget.roomId,
        );
      }
    };

    _signalingService.onCallAccepted = () async {
      print("📞 Call accepted by remote callback");
      await MqttService().stopAudio(broadcast: true);
      setState(() {
        _inCall = true;
        _status = "Connected";
      });
      print("📞 Handshake complete (Caller side)");
      
      // Show ongoing call notification
      await MqttService().showOngoingCallNotification(
        otherUserName: widget.otherUserName,
        roomId: widget.roomId,
      );
    };

    _signalingService.onEndCall = () async {
      print("❌ Call ended by peer");
      if (mounted && !_isExiting) {
        // Stop audio if any (should already be stopped)
        await MqttService().stopAudio();
        _handleCallEnd("Call Ended");
      }
    };
  }

  void _connect() async {
    // 1. Connect to WebSocket Room
    String baseUrl = AppConfig.socketUrl;
    if (!baseUrl.endsWith("/")) baseUrl += "/";
    String fullUrl = "$baseUrl${widget.roomId}/";

    print("📞 Connecting to call room: $fullUrl");
    final token = _authService.accessToken;
    _signalingService.connect(fullUrl, token: token);

    // 2. If Caller, send notification to invitee and play calling tone
    if (widget.isCaller) {
      setState(() => _status = "Calling ${widget.otherUserName}...");
      // Sound already started in UserListScreen

      // Delay slightly to ensure WS is connecting? sending via HTTP is independent.
      final result = await GameService.sendCallSignal(
        receiverUsername: widget.otherUserName,
        roomId: widget.roomId,
      );

      if (!result['success']) {
        await MqttService().stopAudio();
        setState(() => _status = "Failed to call: ${result['error']}");
      }
    } else {
      setState(() => _status = "Joining call with ${widget.otherUserName}...");
    }
  }

  Future<void> _startCall() async {
    try {
      await _signalingService.startCall(_localRenderer, _remoteRenderer, videoEnabled: _isVideoOn);
    } catch (e) {
      print("Start call failed: $e");
    }
  }

  void _handleCallEnd(String status) {
    if (_isExiting) return;
    _isExiting = true;
    
    // Ensure audio is stopped and in-call state cleared
    MqttService().stopAudio(broadcast: true);
    MqttService().setInCall(false);
    MqttService().cancelOngoingCallNotification();
    
    if (mounted) {
      setState(() {
        _status = status;
        _inCall = false;
      });
      
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          // Use context.go instead of pop because call screen replaces home
          // Redirecting to /users which is the player list
          context.go('/users');
        }
      });
    }
  }

  @override
  void dispose() {
    print("📞 CallScreen: dispose called");
    _callTimeoutTimer?.cancel();
    MqttService().setInCall(false);
    MqttService().cancelOngoingCallNotification();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signalingService.hangUp();
    MqttService().stopAudio(broadcast: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Call with ${widget.otherUserName}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _inCall
                ? Stack(
                    children: [
                      RTCVideoView(
                        _remoteRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                      Positioned(
                        right: 20,
                        top: 20,
                        width: 120,
                        height: 180,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: RTCVideoView(
                              _localRenderer,
                              mirror: true,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Text(
                            "In call with ${widget.otherUserName}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  blurRadius: 10.0,
                                  color: Colors.black,
                                  offset: Offset(2.0, 2.0),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          child: Text(
                            widget.otherUserName.isNotEmpty
                                ? widget.otherUserName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(fontSize: 40),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _status,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
          ),
          if (!_isExiting)
            Padding(
              padding: const EdgeInsets.only(bottom: 50.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton(
                    backgroundColor: _isMuted ? Colors.blueGrey : Colors.blue,
                    onPressed: () {
                      setState(() {
                        _isMuted = !_isMuted;
                        _signalingService.muteAudio(_isMuted);
                      });
                    },
                    heroTag: 'mute_btn',
                    child: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton(
                    backgroundColor: _isVideoOn ? Colors.blue : Colors.blueGrey,
                    onPressed: () {
                      setState(() {
                        _isVideoOn = !_isVideoOn;
                        _signalingService.setVideoEnabled(_isVideoOn);
                      });
                    },
                    heroTag: 'video_btn',
                    child: Icon(_isVideoOn ? Icons.videocam : Icons.videocam_off),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton(
                    backgroundColor: Colors.red,
                    onPressed: () {
                      if (widget.isCaller && !_inCall) {
                        print("📞 Caller hanging up early. Signaling cancellation...");
                        GameService.cancelCall(
                          receiverUsername: widget.otherUserName,
                          roomId: widget.roomId,
                        );
                      }
                      
                      _signalingService.sendEndCall();
                      _signalingService.hangUp();
                      
                      // Use context.go to return to users list
                      context.go('/users');
                    },
                    heroTag: 'hangup_btn',
                    child: const Icon(Icons.call_end),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

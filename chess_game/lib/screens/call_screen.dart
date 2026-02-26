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
  bool _isRemoteVideoOn = false;
  bool _isExiting = false;
  bool _isSpeakerOn = false; // Add speaker state
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
    _initRenderers().then((_) {
      if (mounted) {
        _connect();
        _listenForDecline();
      }
    });

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
      if (mounted) {
        _localRenderer.srcObject = stream;
        setState(() {});
      }
    });

    _signalingService.onAddRemoteStream = ((stream) {
      print("📞 Remote stream added to renderer");
      if (mounted) {
        _remoteRenderer.srcObject = stream;
        setState(() {});
      }
    });

    _signalingService.onPlayerJoined = () async {
      print("👋 Peer joined the room callback");
      _callTimeoutTimer?.cancel(); // Cancel timeout when answered
      
      // Stop ringback tone as soon as someone joins
      await MqttService().stopAudio();
      
      if (widget.isCaller) {
        print("📞 I am the caller, starting handshake...");
        if (mounted) {
          setState(() => _status = "Peer joined. Calling...");
        }
        _startCall(); // Auto-start call when peer joins
      }
    };

    _signalingService.onIncomingCall = () async {
      print("📞 Incoming call offer received callback");
      if (!widget.isCaller) {
        print("📞 Accepting incoming call (video: $_isVideoOn)...");
        if (mounted) {
          setState(() => _status = "Accepting call...");
        }
        await _signalingService.acceptCall(_localRenderer, _remoteRenderer, videoEnabled: _isVideoOn);
        if (mounted) {
          setState(() {
            _inCall = true;
            _status = "Connected";
          });
        }
        print("📞 Handshake complete (Callee side)");
        
        // Ongoing notification removed per user request
      }
    };

    _signalingService.onCallAccepted = () async {
      print("📞 Call accepted by remote callback");
      await MqttService().stopAudio(broadcast: true);
      if (mounted) {
        setState(() {
          _inCall = true;
          _status = "Connected";
        });
      }
      print("📞 Handshake complete (Caller side)");
      
      // Ongoing notification removed per user request
    };

    _signalingService.onEndCall = () async {
      print("❌ Call ended by peer");
      if (mounted && !_isExiting) {
        // Stop audio if any (should already be stopped)
        await MqttService().stopAudio();
        _handleCallEnd("Call Ended");
      }
    };

    _signalingService.onRemoteVideoToggle = (enabled) {
      if (mounted) {
        setState(() {
          _isRemoteVideoOn = enabled;
        });
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
      final callType = widget.initialVideo ? "Video" : "Audio";
      if (mounted) {
        setState(() => _status = "$callType Calling ${widget.otherUserName}...");
      }
      // Sound already started in UserListScreen

      // Delay slightly to ensure WS is connecting? sending via HTTP is independent.
      final result = await GameService.sendCallSignal(
        receiverUsername: widget.otherUserName,
        roomId: widget.roomId,
        initialVideo: widget.initialVideo,
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
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signalingService.hangUp();
    MqttService().stopAudio(broadcast: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Background (Video or Avatar)
          Positioned.fill(
            child: _inCall
                ? _buildVideoStack()
                : _buildPlaceholderView(),
          ),

          // 2. Status Label (Top Center)
          if (!_inCall)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  _status,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),

          // 3. Back Button
          Positioned(
            top: 40,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black45,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  if (widget.isCaller && !_inCall) {
                    GameService.cancelCall(
                      receiverUsername: widget.otherUserName,
                      roomId: widget.roomId,
                    );
                  }
                  _signalingService.sendEndCall();
                  context.go('/users');
                },
              ),
            ),
          ),

          // 4. Control Bar (Bottom Overlay)
          if ((_inCall || widget.isCaller) && !_isExiting)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: _buildCallControls(),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoStack() {
    return Stack(
      children: [
        if (_isVideoOn || _isRemoteVideoOn) ...[
          // Remote Video (Background)
          if (_isRemoteVideoOn)
            RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            _buildRemoteAvatarView(),

          // Local Video (Overlay)
          if (_isVideoOn)
            Positioned(
              right: 20,
              top: 100,
              width: 100, // Shrunk from 120
              height: 150, // Shrunk from 180
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 5))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),
        ] else ...[
          // Audio Call View
          _buildRemoteAvatarView(isAudioOnly: true),
        ],
      ],
    );
  }

  Widget _buildPlaceholderView() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.blue[900],
              child: Text(
                widget.otherUserName.isNotEmpty ? widget.otherUserName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 40, color: Colors.white),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              "Call with ${widget.otherUserName}",
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteAvatarView({bool isAudioOnly = false}) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.blue[100],
              child: Icon(Icons.person, size: 60, color: Colors.blue[900]),
            ),
            const SizedBox(height: 24),
            Text(
              widget.otherUserName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isAudioOnly ? "Voice Connected" : "${widget.otherUserName}'s camera is off",
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_inCall) ...[
          _buildControlCircle(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            color: _isMuted ? Colors.red : Colors.white24,
            onPressed: () {
              setState(() {
                _isMuted = !_isMuted;
                _signalingService.muteAudio(_isMuted);
              });
            },
          ),
          const SizedBox(width: 20),
          _buildControlCircle(
            icon: _isVideoOn ? Icons.videocam : Icons.videocam_off,
            color: _isVideoOn ? Colors.blue : Colors.white24,
            onPressed: () {
              setState(() {
                _isVideoOn = !_isVideoOn;
                _signalingService.setVideoEnabled(_isVideoOn);
              });
            },
          ),
          const SizedBox(width: 20),
        ],
        // Speaker Toggle (Always visible during call/ringing)
        _buildControlCircle(
          icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
          color: _isSpeakerOn ? Colors.blue : Colors.white24,
          onPressed: _toggleSpeaker,
        ),
        const SizedBox(width: 20),
        _buildControlCircle(
          icon: Icons.call_end,
          color: Colors.red,
          onPressed: () {
            if (widget.isCaller && !_inCall) {
              GameService.cancelCall(
                receiverUsername: widget.otherUserName,
                roomId: widget.roomId,
                initialVideo: widget.initialVideo,
              );
            }
            _signalingService.sendEndCall();
            _handleCallEnd("Call Cancelled");
          },
        ),
      ],
    );
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    });
  }

  Widget _buildControlCircle({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 50, // Shriveled slightly more
          height: 50,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12, width: 1),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

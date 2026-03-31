import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import '../services/signaling_service.dart';
import '../services/game_service.dart';
import '../services/mqtt_service.dart';

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
  final SignalingService _signalingService = SignalingService();
  
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  
  bool _inCall = false;
  String _status = "Initializing...";
  bool _isMuted = false;
  late bool _isVideoOn;
  bool _isExiting = false;
  Timer? _callTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _isVideoOn = widget.initialVideo;
    MqttService().setInCall(true);
    _init();
  }

  Future<void> _init() async {
    // CRITICAL: Init renderers BEFORE starting the call flow
    // to prevent EglRenderer crashes
    await _initRenderers();
    if (mounted) _startFlow();

    if (widget.isCaller) {
      _startCallTimeout();
    }
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _startFlow() async {
    try {
      // 1. Check & Request Permissions
      setState(() => _status = "Checking permissions...");

      // Microphone
      PermissionStatus micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        if (micStatus.isPermanentlyDenied) {
          _handleCallEnd("Microphone permission permanently denied.\nPlease enable it in app settings.");
          return;
        }
        micStatus = await Permission.microphone.request();
      }

      if (widget.initialVideo) {
        PermissionStatus camStatus = await Permission.camera.status;
        if (!camStatus.isGranted) {
          if (camStatus.isPermanentlyDenied) {
            _handleCallEnd("Camera permission permanently denied.\nPlease enable it in app settings.");
            return;
          }
          camStatus = await Permission.camera.request();
          if (!camStatus.isGranted) {
            _handleCallEnd("Camera permission denied.");
            return;
          }
        }
      }

      if (!micStatus.isGranted) {
        _handleCallEnd("Microphone permission denied.");
        return;
      }

      // 2. Setup UI Callbacks BEFORE opening media
      _signalingService.onLocalStream = (stream) {
        if (mounted) {
          _localRenderer.srcObject = stream;
          setState(() {});
        }
      };

      _signalingService.onAddRemoteStream = (stream) {
        if (mounted) {
          _remoteRenderer.srcObject = stream;
          setState(() {
            _inCall = true;
          });
          // Check if remote stream has video tracks
          bool hasVideo = stream.getVideoTracks().isNotEmpty;
          print("📺 Remote Stream Added: Video=${hasVideo}");
        }
        _callTimeoutTimer?.cancel();
        MqttService().stopAudio();
      };

      _signalingService.onRemoteVideoToggle = (enabled) {
        if (mounted) {
          setState(() {
            // We can show a notification or update UI if needed
            print("📺 Remote Video Toggle: $enabled");
          });
        }
      };

      _signalingService.onEndCall = () => _handleCallEnd("Call Ended");

      // 3. Open media so _localStream is ready before any offer arrives
      setState(() => _status = "Opening microphone...");
      final mediaError = await _signalingService.openUserMedia(videoEnabled: widget.initialVideo);
      if (mediaError != null) {
        _handleCallEnd(mediaError);
        return;
      }

      // 4. If caller, also send call notification to the other player
      if (widget.isCaller) {
        setState(() => _status = "Calling ${widget.otherUserName}...");
        await GameService.sendCallSignal(
          receiverUsername: widget.otherUserName,
          roomId: widget.roomId,
          initialVideo: widget.initialVideo,
        );
      }

      // 5. Connect to signaling server
      setState(() => _status = "Connecting...");
      await _signalingService.connectToWebSocket(widget.roomId);

      // 6. Caller: wait for callee to join before sending offer
      //    Callee: just wait — offer will arrive via _onMessage → _handleOffer
      if (widget.isCaller) {
        setState(() => _status = "Waiting for ${widget.otherUserName}...");
        // Set up a completer that resolves when the callee joins the room
        final peerJoined = Completer<void>();
        _signalingService.onPlayerJoined = () {
          if (!peerJoined.isCompleted) peerJoined.complete();
        };
        // Also resolve immediately if we get call_accepted (callee already there)
        _signalingService.onCallAccepted = () {
          if (!peerJoined.isCompleted) peerJoined.complete();
        };
        // Timeout after 30s if callee never joins
        await peerJoined.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Callee did not join'),
        );
        setState(() => _status = "Starting call...");
        await _signalingService.startCall();
      }

    } catch (e) {
      print("❌ Call Flow Error: $e");
      _handleCallEnd("Connection Failed: $e");
    }
  }

  void _handleCallEnd(String status) {
    if (_isExiting) return;
    _isExiting = true;
    _callTimeoutTimer?.cancel();
    _signalingService.disconnect();
    MqttService().setInCall(false);
    
    if (mounted) {
      setState(() {
        _status = status;
        _inCall = false;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        context.go('/users');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _inCall ? _buildInCallView() : _buildPlaceholderView(),
          ),
          if (!_inCall && !_isExiting)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(_status, 
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w300),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 40,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black45,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  if (widget.isCaller && !_inCall) {
                    GameService.cancelCall(receiverUsername: widget.otherUserName, roomId: widget.roomId);
                  }
                  _handleCallEnd("Exiting...");
                },
              ),
            ),
          ),
          if (!_isExiting)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: _buildControls(),
            ),
        ],
      ),
    );
  }

  Widget _buildInCallView() {
    return Stack(
      children: [
        // Placeholder (avatar and name) acts as background for audio-only calls
        Positioned.fill(
          child: _buildPlaceholderView(),
        ),
        // Remote Video
        Positioned.fill(
          child: RTCVideoView(_remoteRenderer, 
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
        // Name Overlay
        Positioned(
          top: 50,
          left: 0,
          right: 0,
          child: Column(
            children: [
              Text(
                widget.otherUserName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "Connected",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        // Local Video (PiP)
        if (_isVideoOn)
          Positioned(
            right: 20,
            top: 100,
            width: 120,
            height: 160,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: RTCVideoView(_localRenderer, mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
          ),
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
              backgroundColor: Colors.blueGrey,
              child: Text(widget.otherUserName[0].toUpperCase(), 
                style: const TextStyle(fontSize: 40, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Text(widget.otherUserName, 
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildCircleBtn(
          icon: _isMuted ? Icons.mic_off : Icons.mic,
          color: _isMuted ? Colors.red : Colors.white24,
          onPressed: () {
            setState(() => _isMuted = !_isMuted);
            _signalingService.muteAudio(_isMuted);
          },
        ),
        const SizedBox(width: 20),
        _buildCircleBtn(
          icon: _isVideoOn ? Icons.videocam : Icons.videocam_off,
          color: _isVideoOn ? Colors.blue : Colors.white24,
          onPressed: () {
            setState(() => _isVideoOn = !_isVideoOn);
            _signalingService.setVideoEnabled(_isVideoOn);
          },
        ),
        const SizedBox(width: 20),
        _buildCircleBtn(
          icon: Icons.call_end,
          color: Colors.red,
          onPressed: () async {
            if (widget.isCaller && !_inCall) {
               GameService.cancelCall(receiverUsername: widget.otherUserName, roomId: widget.roomId);
            } else if (_inCall) {
               _signalingService.sendEndCall(); // Notify the other peer
               // Small delay to ensure the message is sent before we disconnect
               await Future.delayed(const Duration(milliseconds: 200));
            }
             _handleCallEnd("Call Ended");
          },
        ),
      ],
    );
  }

  Widget _buildCircleBtn({required IconData icon, required Color color, required VoidCallback onPressed}) {
    return IconButton(
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white),
      ),
      onPressed: onPressed,
    );
  }

  void _startCallTimeout() {
    _callTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (!mounted || _inCall || _isExiting) return;
      GameService.cancelCall(receiverUsername: widget.otherUserName, roomId: widget.roomId);
      _handleCallEnd("No Answer");
    });
  }

  @override
  void dispose() {
    _callTimeoutTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signalingService.disconnect();
    super.dispose();
  }
}

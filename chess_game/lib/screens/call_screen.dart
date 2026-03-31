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
    
    _initRenderers();
    _startFlow();

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
      // 1. Request Permissions FIRST to avoid crashes
      setState(() => _status = "Requesting permissions...");
      
      final micStatus = await Permission.microphone.status;
      if (micStatus.isDenied || micStatus.isRestricted) {
        await Permission.microphone.request();
      }
      
      if (widget.initialVideo) {
        final camStatus = await Permission.camera.status;
        if (camStatus.isDenied || camStatus.isRestricted) {
          await Permission.camera.request();
        }
      }

      // Re-check essential permissions
      if (await Permission.microphone.isDenied || (widget.initialVideo && await Permission.camera.isDenied)) {
        _handleCallEnd("Permissions Denied\nPlease enable camera/mic in settings.");
        return;
      }

      // 2. Start Signaling IMMEDIATELY (Don't wait for media)
      if (widget.isCaller) {
        setState(() => _status = "Calling ${widget.otherUserName}...");
        await GameService.sendCallSignal(
          receiverUsername: widget.otherUserName,
          roomId: widget.roomId,
          initialVideo: widget.initialVideo,
        );
      }

      // 3. Setup Callbacks
      _signalingService.onLocalStream = (stream) {
        setState(() => _localRenderer.srcObject = stream);
      };

      _signalingService.onAddRemoteStream = (stream) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _inCall = true;
          _status = "Connected";
        });
        _callTimeoutTimer?.cancel();
        MqttService().stopAudio();
      };

      _signalingService.onEndCall = () => _handleCallEnd("Call Ended");

      // 4. Connect to Signaling Server
      await _signalingService.connectToWebSocket(widget.roomId);

      // 5. Open Media and Start Handshake
      final mediaSuccess = await _signalingService.openUserMedia(videoEnabled: widget.initialVideo);
      if (!mediaSuccess) {
        _handleCallEnd("Failed to access camera/mic");
        return;
      }

      if (widget.isCaller) {
        await _signalingService.startCall();
      }

    } catch (e) {
      print("❌ Call Flow Error: $e");
      _handleCallEnd("Connection Failed\n$e");
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
          if (!_inCall)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(_status, 
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
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
        // Remote Video
        RTCVideoView(_remoteRenderer, 
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
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
          onPressed: () {
            if (widget.isCaller && !_inCall) {
               GameService.cancelCall(receiverUsername: widget.otherUserName, roomId: widget.roomId);
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

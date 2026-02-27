import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../services/signaling_service.dart';
import '../services/config.dart';
import '../services/django_auth_service.dart';
import '../services/game_service.dart';
import '../services/mqtt_service.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

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
  
  VideoTrack? _remoteVideoTrack;
  
  bool _inCall = false;
  String _status = "Connecting...";
  bool _isMuted = false;
  late bool _isVideoOn;
  bool _isExiting = false;
  Timer? _callTimeoutTimer;

  @override
  void initState() {
    super.initState();
    print("📞 CallScreen (LiveKit): Initializing");
    _isVideoOn = widget.initialVideo;
    MqttService().setInCall(true);
    
    if (!widget.isCaller) {
      MqttService().stopAudio().then((_) {
        MqttService().cancelCallNotification();
      });
    }

    _setupCallbacks();
    _connect();

    if (widget.isCaller) {
      _startCallTimeout();
    }
  }

  void _setupCallbacks() {
    _signalingService.onAddRemoteStream = (publication, participant) {
      if (publication is RemoteVideoTrackPublication) {
        setState(() {
          _remoteVideoTrack = publication.track as VideoTrack?;
          _inCall = true;
          _status = "Connected";
        });
        _callTimeoutTimer?.cancel();
        MqttService().stopAudio();
      }
    };

    _signalingService.onEndCall = () {
      _handleCallEnd("Call Ended");
    };
  }

  Future<void> _connect() async {
    try {
      final token = _authService.accessToken;
      
      // 1. Get Token from Django
      final url = "${AppConfig.baseUrl}call/token/?room_id=${widget.roomId}";
      print("📞 Requesting token from: $url");
      
      final response = await http.get(
        Uri.parse(url),
        headers: {"Authorization": "Bearer $token"}
      );
      
      if (response.statusCode != 200) {
        throw Exception("Server returned ${response.statusCode}");
      }
      
      final data = jsonDecode(response.body);
      final livekitToken = data['token'];
      final livekitUrl = data['url'];

      // 2. Connect to LiveKit Room
      await _signalingService.connectToLiveKit(livekitUrl, livekitToken);
      
      if (mounted) {
        setState(() {
          _status = widget.isCaller ? "Calling ${widget.otherUserName}..." : "Connected";
        });
      }

      // If caller, send notification
      if (widget.isCaller) {
        await GameService.sendCallSignal(
          receiverUsername: widget.otherUserName,
          roomId: widget.roomId,
          initialVideo: widget.initialVideo,
        );
      }
    } catch (e) {
      print("❌ Connection Error: $e");
      if (mounted) _handleCallEnd("Connection Failed");
    }
  }

  void _startCallTimeout() {
    _callTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted || _inCall || _isExiting) return;
      _handleCallEnd("No Answer");
    });
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
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) context.go('/users');
      });
    }
  }

  @override
  void dispose() {
    _callTimeoutTimer?.cancel();
    _signalingService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _inCall ? _buildVideoView() : _buildPlaceholderView(),
          ),

          if (!_inCall)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Text(_status, style: const TextStyle(color: Colors.white, fontSize: 20)),
              ),
            ),

          Positioned(
            top: 40,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black45,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => _handleCallEnd("Exiting..."),
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

  Widget _buildVideoView() {
    return Stack(
      children: [
        if (_remoteVideoTrack != null)
          VideoTrackRenderer(_remoteVideoTrack!, fit: VideoFit.cover)
        else
          _buildRemoteAvatarView(),
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
              child: Text(widget.otherUserName[0].toUpperCase(), style: const TextStyle(fontSize: 40)),
            ),
            const SizedBox(height: 20),
            Text("Calling ${widget.otherUserName}", style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteAvatarView() {
    return Center(child: Icon(Icons.person, size: 100, color: Colors.white24));
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
          onPressed: () => _handleCallEnd("Call Ended"),
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
}

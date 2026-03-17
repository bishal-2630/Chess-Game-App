import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
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
<<<<<<< HEAD
  bool _announcementSpoken = false; // New flag
=======
>>>>>>> 4a571096459dce595587a0248b4b8498b376faa8
  bool _isMuted = false;
  late bool _isVideoOn;
  bool _isExiting = false;
  Timer? _callTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _isVideoOn = widget.initialVideo;
    MqttService().setInCall(true);
    
    if (!widget.isCaller) {
      MqttService().stopAudio().then((_) {
        MqttService().cancelCallNotification();
      });
    }

    _signalingService.onConnectionState = null;
    _signalingService.onGameMove = null;
    _setupCallbacks();
    _connect();

    if (widget.isCaller) {
      _startCallTimeout();
    }
  }

  void _setupCallbacks() {
    _signalingService.onAddRemoteStream = (publication, participant) {
      // publication is a TrackPublication. 
      // In 2.x, we check if it's a video track (TrackType.VIDEO).
<<<<<<< HEAD
      // Mark as connected on first track (audio or video)
      if (mounted) {
        setState(() {
          if (publication.kind == TrackType.VIDEO) {
             _remoteVideoTrack = publication.track as VideoTrack?;
          }
          _inCall = true;
          _status = "Connected";
        });
        
        // Trigger announcement once after connection
        if (!_announcementSpoken) {
          _announcementSpoken = true;
          MqttService().speakRecordingAnnouncement();
        }
      }
      _callTimeoutTimer?.cancel();
      MqttService().stopAudio();
=======
      if (publication.kind == TrackType.VIDEO) {
        if (mounted) {
          setState(() {
            _remoteVideoTrack = publication.track as VideoTrack?;
            _inCall = true;
            _status = "Connected";
          });
        }
        _callTimeoutTimer?.cancel();
        MqttService().stopAudio();
      }
>>>>>>> 4a571096459dce595587a0248b4b8498b376faa8
    };

    _signalingService.onEndCall = () {
      if (mounted) _handleCallEnd("Call Ended");
    };
  }

  Future<void> _connect() async {
    try {
      final token = _authService.accessToken;
<<<<<<< HEAD
      // Request recording for standalone calls (archival for future use)
      final url = "${AppConfig.baseUrl}call/token/?room_id=${widget.roomId}&record=true";
=======
      final url = "${AppConfig.baseUrl}call/token/?room_id=${widget.roomId}";
>>>>>>> 4a571096459dce595587a0248b4b8498b376faa8
      
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

      print("🌐 LiveKit URL: $livekitUrl");
      print("🔑 LiveKit Token Snippet: ${livekitToken.toString().substring(0, 15)}...");

<<<<<<< HEAD
      await _signalingService.connectToLiveKit(livekitUrl, livekitToken, videoEnabled: widget.initialVideo);
=======
      await _signalingService.connectToLiveKit(livekitUrl, livekitToken);
>>>>>>> 4a571096459dce595587a0248b4b8498b376faa8
      
      if (mounted) {
        setState(() {
          _status = widget.isCaller ? "Calling ${widget.otherUserName}..." : "Connected";
        });
      }

      if (widget.isCaller) {
        await GameService.sendCallSignal(
          receiverUsername: widget.otherUserName,
          roomId: widget.roomId,
          initialVideo: widget.initialVideo,
        );
      }
    } catch (e) {
      print("❌ Connection Error Detail: $e");
      if (mounted) _handleCallEnd("Connection Failed\n$e");
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
<<<<<<< HEAD
=======
        _remoteRenderer.srcObject = null;
        _localRenderer.srcObject = null;
>>>>>>> 4a571096459dce595587a0248b4b8498b376faa8
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        try {
          context.go('/users');
        } catch (e) {
          print("Error navigating back: $e");
        }
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
          VideoTrackRenderer(_remoteVideoTrack!, fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
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

  void _startCallTimeout() {
    _callTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted || _inCall || _isExiting) return;
      _handleCallEnd("No Answer");
    });
  }

  @override
  void dispose() {
    _callTimeoutTimer?.cancel();
    _signalingService.disconnect();
    super.dispose();
  }
}

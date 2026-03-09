import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:go_router/go_router.dart';
import '../../services/signaling_service.dart';
import '../../services/django_auth_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:flutter/foundation.dart';
import '../../services/config.dart';
import '../../services/game_service.dart';
import 'dart:math';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import '../../services/mqtt_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChessScreen extends StatefulWidget {
  final String? roomId;
  final String? color;
  final String? opponentName;
  const ChessScreen({super.key, this.roomId, this.color, this.opponentName});

  @override
  State<ChessScreen> createState() => _ChessGameScreenState();
}

class _ChessGameScreenState extends State<ChessScreen> {
  final DjangoAuthService _authService = DjangoAuthService();

  // Chess board state
  List<List<String>> board = [];
  String selectedPiece = '';
  int selectedRow = -1;
  int selectedCol = -1;
  bool isWhiteTurn = true;
  String status = "White's turn";
  List<List<bool>> validMoves = [];
  List<Map<String, dynamic>> moveHistory = [];
  List<String> whiteCapturedPieces = [];
  List<String> blackCapturedPieces = [];

  // Advanced chess state
  bool whiteKingMoved = false;
  bool blackKingMoved = false;
  bool whiteKingsideRookMoved = false;
  bool whiteQueensideRookMoved = false;
  bool blackKingsideRookMoved = false;
  bool blackQueensideRookMoved = false;
  String? enPassantTarget; // Square where en passant is possible (e.g., "e3")
  int halfMoveClock = 0; // For 50-move rule (moves without capture/pawn move)
  int fullMoveNumber = 1;
  List<String> positionHistory = []; // For threefold repetition
  bool whiteInCheck = false;
  bool blackInCheck = false;
  bool gameOver = false;
  String winner = '';
  String? pendingPromotion; // Stores the pawn that needs promotion

  // Audio Call State
  final SignalingService _signalingService = SignalingService();
  final rtc.RTCVideoRenderer _localRenderer = rtc.RTCVideoRenderer();
  final rtc.RTCVideoRenderer _remoteRenderer = rtc.RTCVideoRenderer();
  lk.VideoTrack? _remoteVideoTrack;

  bool _isConnectedToRoom = false;
  bool _isAudioOn = false;
  bool _isMuted = false;
  bool _isVideoOn = false;
  bool _isRemoteVideoOn = false;
  bool _isIncomingCall = false;
  String _callStatus = "";
  String? _playerColor; // 'w' or 'b' in multiplayer mode
  Timer? _statusTimer;

  final Map<String, String> pieceIcons = {
    'wp': '♙',
    'wr': '♖',
    'wn': '♘',
    'wb': '♗',
    'wq': '♕',
    'wk': '♔',
    'bp': '♟',
    'br': '♜',
    'bn': '♞',
    'bb': '♝',
    'bq': '♛',
    'bk': '♚',
  };

  int _inviteCount = 0;
  Timer? _inviteTimer;

  // In-game call notification state
  bool _showIncomingCallBanner = false;
  bool _isCalling = false; // New state for outgoing call
  String _incomingCallFrom = '';
  String _incomingCallRoomId = '';
  int _callDuration = 0;
  Timer? _callTimer;
  StreamSubscription? _callNotificationSubscription;

  @override
  void initState() {
    super.initState();
    _initializeBoard();
    // NEW: Notify MqttService that we are in a game room to suppress duplicate system notifications
    if (widget.roomId != null) {
      final mqtt = MqttService();
      mqtt.setActiveChessRoomId(widget.roomId);
      // Forced clear in case a notification was already popping up as we entered
      mqtt.cancelCallNotification(broadcast: true); 
    }
    _initRenderers();
    _loadInviteCount();
    // Refresh invite count every 30 seconds
    _inviteTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _loadInviteCount());
    // MqttService handles notifications globally

    // Listen for incoming calls during gameplay
    _callNotificationSubscription = MqttService().notifications.listen((data) {
      if (!mounted) return;

      final type = data['type'];
      if (type == 'call_invitation' || type == 'incoming_call') {
        final payload = data['data'] ?? data['payload'];
        final caller = payload['caller'] ?? payload['sender'];
        final roomId = payload['room_id'];

        // If user is in a chess room, show banner and cancel system notification
        if (_isConnectedToRoom) {
          // Cancel system notification in favor of in-app banner
          MqttService().dismissCallNotification();

          setState(() {
            _showIncomingCallBanner = true;
            _incomingCallFrom = caller ?? 'Unknown';
            _incomingCallRoomId = roomId ?? '';
            _isVideoOn = payload['initial_video'] == true; // Capture the caller's video preference
          });
        }
        // If user is not in a room, system notification will handle it
        // (MqttService already shows notification and plays ringtone)
      } else if ((type == 'call_ended' ||
          type == 'call_declined' ||
          type == 'call_cancelled') && mounted) {
        // Hide banner and stop ringtone
        setState(() {
          _showIncomingCallBanner = false;
          _isCalling = false; // Stop outgoing call banner too
        });
        MqttService().stopAudio(broadcast: true);
      }
    });

    // Auto-connect if parameters provided via route
    if (widget.roomId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playerColor = widget.color ?? 'w';
        _connectRoom(_defaultServerUrl, widget.roomId!);
      });
    }
  }

  Future<void> _loadInviteCount() async {
    try {
      final result = await GameService.getMyInvitations();
      if (result['success'] && mounted) {
        setState(() {
          _inviteCount = result['count'];
        });
      }
    } catch (e) {
      // Error loading invite count
    }
  }

  @override
  void didUpdateWidget(ChessScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If room info changes while already on the board, reconnect
    if (widget.roomId != oldWidget.roomId && widget.roomId != null) {
      _playerColor = widget.color ?? 'w';
      _connectRoom(_defaultServerUrl, widget.roomId!);
    }
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _signalingService.onLocalStream = ((stream) {
      // For now, keep as is or stub out.
      // _localRenderer.srcObject = stream;
      if (mounted) setState(() {});
    });

    _signalingService.onAddRemoteStream = (publication, participant) {
      if (publication.kind == lk.TrackType.VIDEO) {
        if (mounted) {
          setState(() {
            _remoteVideoTrack = publication.track as lk.VideoTrack?;
          });
        }
      }
    };

    _signalingService.onGameMove = (data) {
      // Handle remote move
      if (mounted) {
        setState(() {
          _handleRemoteMove(data);
        });
      }
    };

    _signalingService.onPlayerLeft = () {

      // If game was active, record as a win for this player
      if (!gameOver && moveHistory.isNotEmpty) {
        GameService.recordGameResult('win');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Opponent left the room. Resetting game."),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 5),
        ));
      }
      _initializeBoard(); // Reset board state
      _hangUp(); // Disconnect self
    };

    _signalingService.onConnectionState = (isConnected) {
      if (mounted) {
        setState(() {
          _isConnectedToRoom = isConnected;
        });
      }
      if (isConnected && mounted) {
        _setEphemeralStatus("Connected to Server");
      } else if (mounted) {
        _setEphemeralStatus("Disconnected");
      }
      if (!isConnected && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Warning: Disconnected from signaling server.")));
      }
    };

    _signalingService.onIncomingCall = () {
      if (mounted) {
        setState(() {
          _isIncomingCall = true;
        });
      }
      // Banner handles UI
    };

    _signalingService.onRemoteVideoToggle = (enabled) {
      if (mounted) {
        setState(() {
          _isRemoteVideoOn = enabled;
        });
      }
    };

    _signalingService.onCallAccepted = () {
      if (mounted) {
        setState(() {
          _isAudioOn = true;
          _isCalling = false; // Stop calling banner
        });
      }
      // Banner handles "Voice Connected" UI
      // Stop calling ringtone
      MqttService().stopAudio(broadcast: true);
      _startCallTimer();
    };

    _signalingService.onCallRejected = () {
      if (mounted) {
        setState(() {
          _callStatus = "";
          _isCalling = false; // Stop calling banner
        });
      }
      _setEphemeralStatus("Call Declined");
      // Stop calling ringtone
      MqttService().stopAudio(broadcast: true);
      _stopCallTimer();
    };

    _signalingService.onEndCall = () async {
      await MqttService().stopAudio(broadcast: true); // Stop any ringing
      _stopCallTimer();
      if (_isAudioOn || _callStatus == "Calling..." || _isCalling) {
        await _signalingService.stopAudio();
        if (mounted) {
          setState(() {
            _isAudioOn = false;
            _isIncomingCall = false;
            _isCalling = false;
            _callStatus = ""; // NEW: Clear status on remote end
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Call ended."), duration: Duration(seconds: 2)));
        }
        // Even if not active, ensure status is clear
        if (mounted) {
          setState(() => _callStatus = "");
        }
      }
    };

    _signalingService.onNewGame = () {
      _initializeBoard();
      _setEphemeralStatus("Opponent started a new game");
    };

    _signalingService.onPlayerJoined = () {
      _setEphemeralStatus("Opponent joined the room");
    };
  }

  void _setEphemeralStatus(String message) {
    _statusTimer?.cancel();
    if (mounted) {
      setState(() {
        _callStatus = message;
      });
    }
    _statusTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _callStatus = "";
        });
      }
    });
  }


  void _showOpponentLeftDialog() {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text("Disconnected"),
              content: const Text("Opponent has left the room."),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                )
              ],
            ));
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _signalingService.muteAudio(_isMuted);
  }


  void _toggleVideo() async {
    // Request camera permission if enabling video for the first time
    if (!_isVideoOn && !kIsWeb) {
      var status = await Permission.camera.request();
      if (status != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Camera permission is required for video calls."),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
    }

    setState(() {
      _isVideoOn = !_isVideoOn;
    });
    _signalingService.setVideoEnabled(_isVideoOn);
  }

  void _onLogout() async {
    if (_isConnectedToRoom) {
      if (!gameOver && moveHistory.isNotEmpty) {
        // Game is active, ask for confirmation
        final bool confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Leave Game?'),
                content: const Text(
                  'If you leave now, you will lose the game. Are you sure?',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('CANCEL'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('LEAVE GAME',
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ) ??
            false;

        if (!confirm) return;

        // Record loss if confirmed
        await GameService.recordGameResult('loss');
      }

      _signalingService.sendBye();
      _hangUp();
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    setState(() => _callDuration = 0);
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _callDuration++);
      }
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
    if (mounted) {
      setState(() => _callDuration = 0);
    }
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    // NEW: Clear active room ID so notifications are restored for future sessions
    MqttService().setActiveChessRoomId(null);
    _statusTimer?.cancel();
    _inviteTimer?.cancel();
    _callNotificationSubscription?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    if (_isConnectedToRoom) {
      _signalingService.sendBye();
    }
    _signalingService.hangUp();
    // Notification service lifecycle is now managed by DjangoAuthService
    super.dispose();
  }

  void _handleRemoteMove(Map<String, dynamic> data) {
    if (data['type'] == 'move') {
      int fromRow = data['fromRow'];
      int fromCol = data['fromCol'];
      int toRow = data['toRow'];
      int toCol = data['toCol'];
      String piece = data['movedPiece'];
      String? promotion = data['promotion'];

      _executeMove(fromRow, fromCol, toRow, toCol, piece, promotion: promotion);
    }
  }

  // default server url suggestion
  String get _defaultServerUrl {
    return AppConfig.socketUrl;
  }

  void _connectRoom(String serverUrl, String roomId) async {
    setState(() {
      _callStatus = "Connecting...";
    });

    try {
      final token = _authService.accessToken;
      final url = "${AppConfig.baseUrl}call/token/?room_id=$roomId";
      
      final response = await http.get(
        Uri.parse(url),
        headers: {"Authorization": "Bearer $token"}
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _signalingService.connectToLiveKit(data['url'], data['token']);
      } else {
        _setEphemeralStatus("Connection failed: ${response.statusCode}");
      }
    } catch (e) {
      _setEphemeralStatus("Connection error: $e");
    }
  }

  Future<void> _toggleAudio() async {
    // Request microphone permission before starting/accepting call
    if (!kIsWeb) {
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Microphone permission is required for audio calls."),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }

    if (_isAudioOn || (_isCalling && !_isAudioOn)) {
      // End Call or Cancel Outgoing Call
      if (_isCalling && !_isAudioOn && widget.opponentName != null && widget.roomId != null) {
        await GameService.cancelCall(
          receiverUsername: widget.opponentName!,
          roomId: widget.roomId!,
        );
      }

      _signalingService.sendEndCall();
      await _signalingService.stopAudio();
      await MqttService().cancelCallNotification(broadcast: true); // Stop ringtone AND clear system banners
      _stopCallTimer();
      setState(() {
        _isAudioOn = false;
        _isIncomingCall = false;
        _isCalling = false;
        _isMuted = false;
        _isVideoOn = false;
        _isRemoteVideoOn = false;
        _callStatus = ""; // NEW: Clear status when ending via toggle
      });
    } else {
      // Start or Accept Call
      try {
        final token = _authService.accessToken;
        final tokenUrl = "${AppConfig.baseUrl}call/token/?room_id=${widget.roomId}";
        
        final response = await http.get(
          Uri.parse(tokenUrl),
          headers: {"Authorization": "Bearer $token"}
        );

        if (response.statusCode != 200) throw Exception("Failed to get call token");
        
        final tokenData = jsonDecode(response.body);
        final livekitToken = tokenData['token'];
        final livekitUrl = tokenData['url'];

        if (_isIncomingCall) {
          // Accept
          await _signalingService.connectToLiveKit(livekitUrl, livekitToken);
          _startCallTimer();
          setState(() {
            _isAudioOn = true;
            _isIncomingCall = false;
            _isCalling = false;
          });
          // Force clear system notifications on accept
          await MqttService().cancelCallNotification(broadcast: true);
        } else {
          // Start Call (Initiator part)
          if (widget.opponentName == null) {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
               content: Text("Cannot start call: Opponent unknown"),
               backgroundColor: Colors.red,
             ));
             return;
          }

          setState(() {
             _isCalling = true;
          });
          
          // Play calling ringtone IMMEDIATELY before signaling setup
          MqttService().playSound('sounds/call_ringtone.mp3');

          // Send notification to opponent
          await GameService.sendCallSignal(
            receiverUsername: widget.opponentName!, 
            roomId: widget.roomId!,
            initialVideo: _isVideoOn
          );

          await _signalingService.connectToLiveKit(livekitUrl, livekitToken);
        }
      } catch (e) {
        MqttService().stopAudio(broadcast: true); // Stop ringtone on error
        _stopCallTimer();
        setState(() {
           _isCalling = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Could not start call: $e"),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _showRoomDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Play Online'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  "Connect to the multiplayer server to play with others."),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _playerColor = 'w';
                  _createRoom(_defaultServerUrl);
                },
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40)),
                child: Text('Create Room (Generate ID)'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _playerColor = 'b';
                  _showJoinDialog(_defaultServerUrl);
                },
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40)),
                child: Text('Join Room (Enter ID)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _createRoom(String serverUrl) {
    // Generate random 4-digit ID
    final String roomId = (1000 + Random().nextInt(9000)).toString();

    // Use the unified route-based connection
    context.go('/chess?roomId=$roomId&color=w');

    // Show ID to user - we use roomID from above
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Room Created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Room ID (Share this):'),
            const SizedBox(height: 4),
            Text(
              roomId,
              style: const TextStyle(
                  fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            const SizedBox(height: 20),
            const Text('Opponent can join using this ID.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showJoinDialog(String serverUrl) async {
    final TextEditingController roomIdController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Join Room'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: roomIdController,
                decoration: const InputDecoration(
                    hintText: "Enter Room ID (e.g. 1234)"),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final roomId = roomIdController.text.trim();
                if (roomId.isNotEmpty) {
                  Navigator.pop(context);
                  // Use the unified route-based connection
                  context.go('/chess?roomId=$roomId&color=b');
                }
              },
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
  }

  // Deprecated direct join (keeping helper but unused in main UI flow if prefered)
  Future<void> _showJoinCallDialog() async {
    // _showJoinDialog(_defaulturl);
  }

  void _hangUp() async {
    await _signalingService.hangUp();
    setState(() {
      _isConnectedToRoom = false;
      _isAudioOn = false;
      _isIncomingCall = false;
      _isMuted = false;
      _isVideoOn = false;
      _isRemoteVideoOn = false;
      _callStatus = ""; // NEW: Clear status on hangup (was "Room Disconnected")
      _playerColor = null; // Back to local mode
    });

    // Reset board for a fresh local start
    _initializeBoard();
  }

  // Convert row/col to algebraic notation
  String _toAlgebraic(int row, int col) {
    final file = String.fromCharCode('a'.codeUnitAt(0) + col);
    final rank = (8 - row).toString();
    return '$file$rank';
  }

  // Convert algebraic notation to row/col
  List<int> _fromAlgebraic(String square) {
    final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = 8 - int.parse(square.substring(1));
    return [rank, file];
  }

  // Get FEN representation of current position (simplified)
  String _getBoardFEN() {
    String fen = '';
    for (int row = 0; row < 8; row++) {
      int emptyCount = 0;
      for (int col = 0; col < 8; col++) {
        final piece = board[row][col];
        if (piece.isEmpty) {
          emptyCount++;
        } else {
          if (emptyCount > 0) {
            fen += emptyCount.toString();
            emptyCount = 0;
          }
          final pieceChar = _getPieceType(piece);
          final isWhite = _isWhitePiece(piece);
          String char;
          switch (pieceChar) {
            case 'k':
              char = 'k';
              break;
            case 'q':
              char = 'q';
              break;
            case 'r':
              char = 'r';
              break;
            case 'b':
              char = 'b';
              break;
            case 'n':
              char = 'n';
              break;
            case 'p':
              char = 'p';
              break;
            default:
              char = '';
          }
          fen += isWhite ? char.toUpperCase() : char;
        }
      }
      if (emptyCount > 0) fen += emptyCount.toString();
      if (row < 7) fen += '/';
    }

    // Add active color
    fen += isWhiteTurn ? ' w ' : ' b ';

    // Add castling availability
    String castling = '';
    if (!whiteKingMoved) {
      if (!whiteKingsideRookMoved) castling += 'K';
      if (!whiteQueensideRookMoved) castling += 'Q';
    }
    if (!blackKingMoved) {
      if (!blackKingsideRookMoved) castling += 'k';
      if (!blackQueensideRookMoved) castling += 'q';
    }
    fen += castling.isNotEmpty ? castling : '-';

    // Add en passant target
    fen += ' ${enPassantTarget ?? "-"} ';

    // Add halfmove clock and fullmove number
    fen += '$halfMoveClock $fullMoveNumber';

    return fen;
  }

  // Check for insufficient material draw
  bool _isInsufficientMaterial() {
    int whitePieces = 0;
    int blackPieces = 0;
    bool whiteHasBishopOrKnight = false;
    bool blackHasBishopOrKnight = false;
    int whiteBishops = 0;
    int blackBishops = 0;
    bool whiteHasBishopOnLight = false;
    bool whiteHasBishopOnDark = false;
    bool blackHasBishopOnLight = false;
    bool blackHasBishopOnDark = false;

    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final piece = board[row][col];
        if (piece.isNotEmpty) {
          final pieceType = _getPieceType(piece);
          final isWhite = _isWhitePiece(piece);

          if (isWhite) {
            whitePieces++;
            if (pieceType == 'q' || pieceType == 'r' || pieceType == 'p') {
              return false; // Queen, rook, or pawn means sufficient material
            }
            if (pieceType == 'b') {
              whiteBishops++;
              whiteHasBishopOrKnight = true;
              // Check bishop color (light or dark square)
              if ((row + col) % 2 == 0) {
                whiteHasBishopOnDark = true;
              } else {
                whiteHasBishopOnLight = true;
              }
            }
            if (pieceType == 'n') {
              whiteHasBishopOrKnight = true;
            }
          } else {
            blackPieces++;
            if (pieceType == 'q' || pieceType == 'r' || pieceType == 'p') {
              return false; // Queen, rook, or pawn means sufficient material
            }
            if (pieceType == 'b') {
              blackBishops++;
              blackHasBishopOrKnight = true;
              // Check bishop color (light or dark square)
              if ((row + col) % 2 == 0) {
                blackHasBishopOnDark = true;
              } else {
                blackHasBishopOnLight = true;
              }
            }
            if (pieceType == 'n') {
              blackHasBishopOrKnight = true;
            }
          }
        }
      }
    }

    // King vs King
    if (whitePieces == 1 && blackPieces == 1) return true;

    // King and bishop vs King
    if (whitePieces == 2 && whiteBishops == 1 && blackPieces == 1) return true;
    if (blackPieces == 2 && blackBishops == 1 && whitePieces == 1) return true;

    // King and knight vs King
    if (whitePieces == 2 &&
        whiteHasBishopOrKnight &&
        whiteBishops == 0 &&
        blackPieces == 1) {
      return true;
    }
    if (blackPieces == 2 &&
        blackHasBishopOrKnight &&
        blackBishops == 0 &&
        whitePieces == 1) {
      return true;
    }

    // King and bishop vs King and bishop with bishops on same color
    if (whitePieces == 2 &&
        whiteBishops == 1 &&
        blackPieces == 2 &&
        blackBishops == 1) {
      if ((whiteHasBishopOnLight && blackHasBishopOnLight) ||
          (whiteHasBishopOnDark && blackHasBishopOnDark)) {
        return true;
      }
    }

    return false;
  }

  // Check for 50-move rule draw
  bool _isFiftyMoveDraw() {
    return halfMoveClock >= 100; // 100 half-moves = 50 full moves
  }

  // Check for threefold repetition draw
  bool _isThreefoldRepetition() {
    final currentPosition = _getBoardFEN().split(' ')[0]; // Only board position
    final repetitions =
        positionHistory.where((pos) => pos == currentPosition).length;
    return repetitions >= 3;
  }

  void _executeMove(
      int fromRow, int fromCol, int toRow, int toCol, String piece,
      {String? promotion}) {
    if (gameOver) return;

    final pieceType = _getPieceType(piece);
    final isWhite = _isWhitePiece(piece);
    String capturedPiece = board[toRow][toCol];
    bool isEnPassantCapture = false;
    bool isCastling = false;

    // Check for en passant capture
    if (pieceType == 'p' &&
        fromCol != toCol &&
        capturedPiece.isEmpty &&
        enPassantTarget != null) {
      final targetPos = _fromAlgebraic(enPassantTarget!);
      if (toRow == targetPos[0] && toCol == targetPos[1]) {
        // Capture the pawn behind
        final capturedRow = fromRow;
        final capturedCol = toCol;
        capturedPiece = board[capturedRow][capturedCol];
        board[capturedRow][capturedCol] = '';
        isEnPassantCapture = true;
      }
    }

    // Check for castling
    if (pieceType == 'k' && (fromCol - toCol).abs() == 2) {
      isCastling = true;
      // Move the rook
      if (toCol > fromCol) {
        // Kingside castling
        board[toRow][toCol - 1] = board[toRow][7];
        board[toRow][7] = '';
      } else {
        // Queenside castling
        board[toRow][toCol + 1] = board[toRow][0];
        board[toRow][0] = '';
      }
    }

    // Handle regular capture
    if (capturedPiece.isNotEmpty && !isEnPassantCapture) {
      if (isWhiteTurn) {
        blackCapturedPieces.add(capturedPiece);
      } else {
        whiteCapturedPieces.add(capturedPiece);
      }
    }

    // Record move
    moveHistory.add({
      'fromRow': fromRow,
      'fromCol': fromCol,
      'toRow': toRow,
      'toCol': toCol,
      'movedPiece': piece,
      'capturedPiece': capturedPiece,
      'wasWhiteTurn': isWhiteTurn,
      'isEnPassant': isEnPassantCapture,
      'isCastling': isCastling,
      'promotion': promotion,
    });

    if (moveHistory.length > 50) moveHistory.removeAt(0);

    // Execute move
    String movedPiece = piece;

    // Handle pawn promotion
    if (pieceType == 'p' && (toRow == 0 || toRow == 7)) {
      if (promotion != null) {
        // Use specified promotion
        movedPiece = (isWhite ? 'w' : 'b') + promotion;
      } else {
        // Queue promotion dialog
        pendingPromotion = _toAlgebraic(toRow, toCol);
        board[toRow][toCol] = piece; // Temporarily place pawn
        board[fromRow][fromCol] = '';

        // Show promotion dialog
        _showPromotionDialog(toRow, toCol, isWhite);
        return; // Don't continue with turn logic yet
      }
    }

    board[toRow][toCol] = movedPiece;
    board[fromRow][fromCol] = '';

    // Update castling rights
    if (piece == 'wk') whiteKingMoved = true;
    if (piece == 'bk') blackKingMoved = true;
    if (piece == 'wr' && fromCol == 0 && fromRow == 7) {
      whiteQueensideRookMoved = true;
    }
    if (piece == 'wr' && fromCol == 7 && fromRow == 7) {
      whiteKingsideRookMoved = true;
    }
    if (piece == 'br' && fromCol == 0 && fromRow == 0) {
      blackQueensideRookMoved = true;
    }
    if (piece == 'br' && fromCol == 7 && fromRow == 0) {
      blackKingsideRookMoved = true;
    }

    // Set en passant target for next move
    if (pieceType == 'p' && (fromRow - toRow).abs() == 2) {
      // Pawn moved two squares
      final enPassantRow = (fromRow + toRow) ~/ 2;
      enPassantTarget = _toAlgebraic(enPassantRow, fromCol);
    } else {
      enPassantTarget = null;
    }

    // Update half-move clock
    if (capturedPiece.isNotEmpty || pieceType == 'p') {
      halfMoveClock = 0;
    } else {
      halfMoveClock++;
    }

    // Update full move number after black's move
    if (!isWhiteTurn) {
      fullMoveNumber++;
    }

    // Add position to history for threefold repetition
    positionHistory.add(_getBoardFEN().split(' ')[0]);

    // Switch turns
    isWhiteTurn = !isWhiteTurn;

    // Clear selection
    selectedPiece = '';
    selectedRow = -1;
    selectedCol = -1;

    // Clear valid moves
    for (int i = 0; i < 8; i++) {
      for (int j = 0; j < 8; j++) {
        validMoves[i][j] = false;
      }
    }

    // Update check status
    _updateCheckStatus();

    // Check for draws
    _checkForDraws();

    // Check for checkmate or stalemate
    if (!gameOver) {
      final currentPlayerInCheck = isWhiteTurn ? whiteInCheck : blackInCheck;
      final hasLegalMoves = _hasAnyLegalMove(isWhiteTurn);

      if (currentPlayerInCheck && !hasLegalMoves) {
        // Checkmate!
        gameOver = true;
        winner = isWhiteTurn ? 'Black' : 'White';
        status = 'Checkmate! $winner wins!';
        _showGameOverDialog('Checkmate! $winner wins!');
      } else if (!currentPlayerInCheck && !hasLegalMoves) {
        // Stalemate
        gameOver = true;
        status = 'Stalemate! Game drawn.';
        _showGameOverDialog('Stalemate! Game drawn.');
      }
    }
  }

  void _checkForDraws() {
    // 50-move rule
    if (_isFiftyMoveDraw()) {
      gameOver = true;
      status = 'Draw by 50-move rule';
      _showGameOverDialog('Draw by 50-move rule');
      return;
    }

    // Threefold repetition
    if (_isThreefoldRepetition()) {
      gameOver = true;
      status = 'Draw by threefold repetition';
      _showGameOverDialog('Draw by threefold repetition');
      return;
    }

    // Insufficient material
    if (_isInsufficientMaterial()) {
      gameOver = true;
      status = 'Draw by insufficient material';
      _showGameOverDialog('Draw by insufficient material');
      return;
    }
  }

  void _showPromotionDialog(int row, int col, bool isWhite) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Pawn Promotion'),
        content: const Text('Choose a piece to promote to:'),
        actions: [
          _buildPromotionButton('Queen', 'q', row, col, isWhite),
          _buildPromotionButton('Rook', 'r', row, col, isWhite),
          _buildPromotionButton('Bishop', 'b', row, col, isWhite),
          _buildPromotionButton('Knight', 'n', row, col, isWhite),
        ],
      ),
    );
  }

  Widget _buildPromotionButton(
      String label, String pieceType, int row, int col, bool isWhite) {
    final pieceCode = (isWhite ? 'w' : 'b') + pieceType;
    return TextButton(
      onPressed: () {
        Navigator.pop(context);
        // Complete the promotion
        board[row][col] = pieceCode;
        pendingPromotion = null;

        // Send promotion move to opponent if connected
        if (_isConnectedToRoom) {
          _signalingService.sendMove({
            'fromRow': selectedRow,
            'fromCol': selectedCol,
            'toRow': row,
            'toCol': col,
            'movedPiece': '${isWhite ? 'w' : 'b'}p',
            'promotion': pieceType,
          });
        }

        // Continue with turn logic
        setState(() {
          _updateCheckStatus();
          _checkForDraws();
        });
      },
      child: Text('$label ${pieceIcons[pieceCode]}'),
    );
  }

  void _movePiece(int toRow, int toCol) {
    // Local move
    // Send move to opponent
    if (_isConnectedToRoom) {
      _signalingService.sendMove({
        'fromRow': selectedRow,
        'fromCol': selectedCol,
        'toRow': toRow,
        'toCol': toCol,
        'movedPiece': selectedPiece,
        'promotion': null, // Will be set if it's a promotion
      });
    }

    setState(() {
      _executeMove(selectedRow, selectedCol, toRow, toCol, selectedPiece);
    });
  }

  void _initializeBoard() {
    board = List.generate(8, (_) => List.filled(8, ''));
    validMoves = List.generate(8, (_) => List.filled(8, false));
    moveHistory.clear();
    whiteInCheck = false;
    blackInCheck = false;
    gameOver = false;
    winner = '';

    // Reset advanced state
    whiteKingMoved = false;
    blackKingMoved = false;
    whiteKingsideRookMoved = false;
    whiteQueensideRookMoved = false;
    blackKingsideRookMoved = false;
    blackQueensideRookMoved = false;
    enPassantTarget = null;
    halfMoveClock = 0;
    fullMoveNumber = 1;
    positionHistory.clear();
    pendingPromotion = null;

    // Set up initial pieces
    board[0] = ['br', 'bn', 'bb', 'bq', 'bk', 'bb', 'bn', 'br'];
    board[1] = List.filled(8, 'bp');
    board[6] = List.filled(8, 'wp');
    board[7] = ['wr', 'wn', 'wb', 'wq', 'wk', 'wb', 'wn', 'wr'];

    whiteCapturedPieces.clear();
    blackCapturedPieces.clear();

    setState(() {
      status = "White's turn";
      isWhiteTurn = true;
      selectedPiece = '';
      selectedRow = -1;
      selectedCol = -1;
    });
  }

  // Helper functions
  bool _isWhitePiece(String piece) => piece.startsWith('w');
  String _getPieceType(String piece) =>
      piece.length > 1 ? piece.substring(1) : '';

  /// Find the position of a king
  List<int> _findKingPosition(bool findWhiteKing) {
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final piece = board[row][col];
        if (piece.isNotEmpty &&
            _getPieceType(piece) == 'k' &&
            _isWhitePiece(piece) == findWhiteKing) {
          return [row, col];
        }
      }
    }
    return [-1, -1]; // Should never happen
  }

  /// Check if a square is under attack by opponent's pieces
  bool _isSquareUnderAttack(int row, int col, bool isWhiteKing) {
    // Check all opponent's pieces and see if they can attack this square
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece.isNotEmpty && _isWhitePiece(piece) != isWhiteKing) {
          if (_canPieceAttack(r, c, row, col, piece)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Check if a piece can attack a specific square
  bool _canPieceAttack(
      int fromRow, int fromCol, int toRow, int toCol, String piece) {
    final pieceType = _getPieceType(piece);
    final isWhite = _isWhitePiece(piece);

    // Simulate the attack using existing movement logic
    if (pieceType == 'p') {
      // Pawn attack pattern (diagonal only)
      final direction = isWhite ? -1 : 1;
      final attackRow = fromRow + direction;
      return (attackRow == toRow &&
          (fromCol - 1 == toCol || fromCol + 1 == toCol));
    } else if (pieceType == 'r') {
      return _canRookAttack(fromRow, fromCol, toRow, toCol, isWhite);
    } else if (pieceType == 'n') {
      final moves = [
        [-2, -1],
        [-2, 1],
        [-1, -2],
        [-1, 2],
        [1, -2],
        [1, 2],
        [2, -1],
        [2, 1],
      ];
      for (final move in moves) {
        if (fromRow + move[0] == toRow && fromCol + move[1] == toCol) {
          return true;
        }
      }
      return false;
    } else if (pieceType == 'b') {
      return _canBishopAttack(fromRow, fromCol, toRow, toCol, isWhite);
    } else if (pieceType == 'q') {
      return _canRookAttack(fromRow, fromCol, toRow, toCol, isWhite) ||
          _canBishopAttack(fromRow, fromCol, toRow, toCol, isWhite);
    } else if (pieceType == 'k') {
      // King can attack adjacent squares
      final rowDiff = (fromRow - toRow).abs();
      final colDiff = (fromCol - toCol).abs();
      return rowDiff <= 1 && colDiff <= 1 && !(rowDiff == 0 && colDiff == 0);
    }

    return false;
  }

  bool _canRookAttack(
      int fromRow, int fromCol, int toRow, int toCol, bool isWhite) {
    // Must be same row or same column
    if (fromRow != toRow && fromCol != toCol) return false;

    // Check if path is clear
    if (fromRow == toRow) {
      // Horizontal movement
      final step = fromCol < toCol ? 1 : -1;
      for (int c = fromCol + step; c != toCol; c += step) {
        if (board[fromRow][c].isNotEmpty) return false;
      }
    } else {
      // Vertical movement
      final step = fromRow < toRow ? 1 : -1;
      for (int r = fromRow + step; r != toRow; r += step) {
        if (board[r][fromCol].isNotEmpty) return false;
      }
    }

    // Check if destination has opponent's piece or is empty
    final targetPiece = board[toRow][toCol];
    return targetPiece.isEmpty || _isWhitePiece(targetPiece) != isWhite;
  }

  bool _canBishopAttack(
      int fromRow, int fromCol, int toRow, int toCol, bool isWhite) {
    // Must be diagonal
    final rowDiff = (fromRow - toRow).abs();
    final colDiff = (fromCol - toCol).abs();
    if (rowDiff != colDiff) return false;

    // Check if diagonal path is clear
    final rowStep = fromRow < toRow ? 1 : -1;
    final colStep = fromCol < toCol ? 1 : -1;

    int r = fromRow + rowStep;
    int c = fromCol + colStep;
    while (r != toRow && c != toCol) {
      if (board[r][c].isNotEmpty) return false;
      r += rowStep;
      c += colStep;
    }

    // Check if destination has opponent's piece or is empty
    final targetPiece = board[toRow][toCol];
    return targetPiece.isEmpty || _isWhitePiece(targetPiece) != isWhite;
  }

  /// Check if the current player's king is in check
  void _updateCheckStatus() {
    // Find both kings
    final whiteKingPos = _findKingPosition(true);
    final blackKingPos = _findKingPosition(false);

    // Check if kings are under attack
    whiteInCheck = _isSquareUnderAttack(whiteKingPos[0], whiteKingPos[1], true);
    blackInCheck =
        _isSquareUnderAttack(blackKingPos[0], blackKingPos[1], false);

    // Update status message
    if (whiteInCheck) {
      status = "White is in check!";
    } else if (blackInCheck) {
      status = "Black is in check!";
    } else if (!gameOver) {
      status = isWhiteTurn ? "White's turn" : "Black's turn";
    }
  }

  /// Check if the current player has any legal moves
  bool _hasAnyLegalMove(bool isWhite) {
    // Check all pieces of the current player
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final piece = board[row][col];
        if (piece.isNotEmpty && _isWhitePiece(piece) == isWhite) {
          // Get all possible moves for this piece (including special moves)
          final moves =
              _getAllPossibleMovesWithSpecials(row, col, piece, isWhite);

          // Try each move to see if it's legal (doesn't leave king in check)
          for (final move in moves) {
            // Simulate the move
            final originalPiece = board[move[0]][move[1]];
            final isSpecial = move.length > 2;
            final specialType = isSpecial ? move[2] : null;

            board[move[0]][move[1]] = piece;
            board[row][col] = '';

            // Handle special moves in simulation
            if (specialType == 'enpassant') {
              // Remove the captured pawn in en passant
              final capturedRow = row;
              final capturedCol = move[1];
              board[capturedRow][capturedCol] = '';
            } else if (specialType == 'castling_kingside') {
              // Move rook for kingside castling
              board[move[0]][move[1] - 1] = isWhite ? 'wr' : 'br';
              board[move[0]][7] = '';
            } else if (specialType == 'castling_queenside') {
              // Move rook for queenside castling
              board[move[0]][move[1] + 1] = isWhite ? 'wr' : 'br';
              board[move[0]][0] = '';
            }

            // Check if king is still in check after move
            final kingPos = _findKingPosition(isWhite);
            final stillInCheck =
                _isSquareUnderAttack(kingPos[0], kingPos[1], isWhite);

            // Undo the simulation
            board[row][col] = piece;
            board[move[0]][move[1]] = originalPiece;

            if (specialType == 'enpassant') {
              // Restore the captured pawn
              final capturedRow = row;
              final capturedCol = move[1];
              board[capturedRow][capturedCol] = isWhite ? 'bp' : 'wp';
            } else if (specialType == 'castling_kingside') {
              // Restore rook
              board[move[0]][7] = isWhite ? 'wr' : 'br';
              board[move[0]][move[1] - 1] = '';
            } else if (specialType == 'castling_queenside') {
              // Restore rook
              board[move[0]][0] = isWhite ? 'wr' : 'br';
              board[move[0]][move[1] + 1] = '';
            }

            if (!stillInCheck) {
              return true; // Found at least one legal move
            }
          }
        }
      }
    }
    return false; // No legal moves found
  }

  /// Get all possible moves for a piece (including special moves)
  List<List<dynamic>> _getAllPossibleMovesWithSpecials(
      int row, int col, String piece, bool isWhite) {
    final pieceType = _getPieceType(piece);
    List<List<dynamic>> moves = [];

    // Add regular moves
    final regularMoves =
        _getAllPossibleMoves(row, col, piece, pieceType, isWhite);
    moves.addAll(regularMoves.map((move) => [move[0], move[1]]));

    // Add special moves
    if (pieceType == 'p') {
      // En passant
      if (enPassantTarget != null) {
        final targetPos = _fromAlgebraic(enPassantTarget!);
        final targetRow = targetPos[0];
        final targetCol = targetPos[1];

        // Check if pawn can capture en passant
        final direction = isWhite ? -1 : 1;
        final pawnRow = row + direction;

        if (pawnRow == targetRow &&
            (col - 1 == targetCol || col + 1 == targetCol)) {
          moves.add([targetRow, targetCol, 'enpassant']);
        }
      }
    } else if (pieceType == 'k') {
      // Castling
      if (!isWhite) {
        // Black king castling
        if (!blackKingMoved && row == 0 && col == 4) {
          // Kingside castling
          if (!blackKingsideRookMoved &&
              board[0][5].isEmpty &&
              board[0][6].isEmpty &&
              !_isSquareUnderAttack(0, 5, false) &&
              !_isSquareUnderAttack(0, 6, false)) {
            moves.add([0, 6, 'castling_kingside']);
          }
          // Queenside castling
          if (!blackQueensideRookMoved &&
              board[0][3].isEmpty &&
              board[0][2].isEmpty &&
              board[0][1].isEmpty &&
              !_isSquareUnderAttack(0, 3, false) &&
              !_isSquareUnderAttack(0, 2, false)) {
            moves.add([0, 2, 'castling_queenside']);
          }
        }
      } else {
        // White king castling
        if (!whiteKingMoved && row == 7 && col == 4) {
          // Kingside castling
          if (!whiteKingsideRookMoved &&
              board[7][5].isEmpty &&
              board[7][6].isEmpty &&
              !_isSquareUnderAttack(7, 5, true) &&
              !_isSquareUnderAttack(7, 6, true)) {
            moves.add([7, 6, 'castling_kingside']);
          }
          // Queenside castling
          if (!whiteQueensideRookMoved &&
              board[7][3].isEmpty &&
              board[7][2].isEmpty &&
              board[7][1].isEmpty &&
              !_isSquareUnderAttack(7, 3, true) &&
              !_isSquareUnderAttack(7, 2, true)) {
            moves.add([7, 2, 'castling_queenside']);
          }
        }
      }
    }

    return moves;
  }

  /// Get all possible moves for a piece (without considering check)
  List<List<int>> _getAllPossibleMoves(
      int row, int col, String piece, String pieceType, bool isWhite) {
    List<List<int>> moves = [];

    if (pieceType == 'p') {
      final direction = isWhite ? -1 : 1;
      final newRow = row + direction;

      // Forward move
      if (newRow >= 0 && newRow < 8 && board[newRow][col].isEmpty) {
        moves.add([newRow, col]);

        // Double move from starting position
        final startRow = isWhite ? 6 : 1;
        if (row == startRow) {
          final doubleRow = row + 2 * direction;
          if (board[doubleRow][col].isEmpty && board[newRow][col].isEmpty) {
            moves.add([doubleRow, col]);
          }
        }
      }

      // Diagonal captures
      for (final dc in [-1, 1]) {
        final newCol = col + dc;
        if (newRow >= 0 && newRow < 8 && newCol >= 0 && newCol < 8) {
          final targetPiece = board[newRow][newCol];
          if (targetPiece.isNotEmpty && _isWhitePiece(targetPiece) != isWhite) {
            moves.add([newRow, newCol]);
          }
        }
      }
    } else if (pieceType == 'r') {
      moves.addAll(_getRookMoves(row, col, isWhite));
    } else if (pieceType == 'n') {
      moves.addAll(_getKnightMoves(row, col, isWhite));
    } else if (pieceType == 'b') {
      moves.addAll(_getBishopMoves(row, col, isWhite));
    } else if (pieceType == 'q') {
      moves.addAll(_getRookMoves(row, col, isWhite));
      moves.addAll(_getBishopMoves(row, col, isWhite));
    } else if (pieceType == 'k') {
      moves.addAll(_getKingMoves(row, col, isWhite));
    }

    return moves;
  }

  // Individual piece move generators
  List<List<int>> _getRookMoves(int row, int col, bool isWhite) {
    List<List<int>> moves = [];
    for (int dr in [-1, 0, 1]) {
      for (int dc in [-1, 0, 1]) {
        if ((dr == 0 && dc == 0) || (dr != 0 && dc != 0)) continue;

        for (int step = 1; step < 8; step++) {
          final newRow = row + dr * step;
          final newCol = col + dc * step;

          if (newRow < 0 || newRow >= 8 || newCol < 0 || newCol >= 8) break;

          final targetPiece = board[newRow][newCol];
          if (targetPiece.isEmpty) {
            moves.add([newRow, newCol]);
          } else {
            if (_isWhitePiece(targetPiece) != isWhite) {
              moves.add([newRow, newCol]);
            }
            break;
          }
        }
      }
    }
    return moves;
  }

  List<List<int>> _getKnightMoves(int row, int col, bool isWhite) {
    List<List<int>> moves = [];
    final knightMoves = [
      [-2, -1],
      [-2, 1],
      [-1, -2],
      [-1, 2],
      [1, -2],
      [1, 2],
      [2, -1],
      [2, 1],
    ];

    for (final move in knightMoves) {
      final newRow = row + move[0];
      final newCol = col + move[1];

      if (newRow >= 0 && newRow < 8 && newCol >= 0 && newCol < 8) {
        final targetPiece = board[newRow][newCol];
        if (targetPiece.isEmpty || _isWhitePiece(targetPiece) != isWhite) {
          moves.add([newRow, newCol]);
        }
      }
    }
    return moves;
  }

  List<List<int>> _getBishopMoves(int row, int col, bool isWhite) {
    List<List<int>> moves = [];
    for (int dr in [-1, 1]) {
      for (int dc in [-1, 1]) {
        for (int step = 1; step < 8; step++) {
          final newRow = row + dr * step;
          final newCol = col + dc * step;

          if (newRow < 0 || newRow >= 8 || newCol < 0 || newCol >= 8) break;

          final targetPiece = board[newRow][newCol];
          if (targetPiece.isEmpty) {
            moves.add([newRow, newCol]);
          } else {
            if (_isWhitePiece(targetPiece) != isWhite) {
              moves.add([newRow, newCol]);
            }
            break;
          }
        }
      }
    }
    return moves;
  }

  List<List<int>> _getKingMoves(int row, int col, bool isWhite) {
    List<List<int>> moves = [];
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;

        final newRow = row + dr;
        final newCol = col + dc;

        if (newRow >= 0 && newRow < 8 && newCol >= 0 && newCol < 8) {
          final targetPiece = board[newRow][newCol];
          if (targetPiece.isEmpty || _isWhitePiece(targetPiece) != isWhite) {
            moves.add([newRow, newCol]);
          }
        }
      }
    }
    return moves;
  }

  void _calculateValidMoves(int row, int col, String piece) {
    // Reset all valid moves
    for (int i = 0; i < 8; i++) {
      for (int j = 0; j < 8; j++) {
        validMoves[i][j] = false;
      }
    }

    final pieceType = _getPieceType(piece);
    final isWhite = _isWhitePiece(piece);

    // Get all possible moves for this piece (including special moves)
    final moves = _getAllPossibleMovesWithSpecials(row, col, piece, isWhite);

    // Filter moves that would leave king in check
    for (final move in moves) {
      final toRow = move[0];
      final toCol = move[1];
      final isSpecial = move.length > 2;
      final specialType = isSpecial ? move[2] : null;

      // Simulate the move
      final originalPiece = board[toRow][toCol];
      board[toRow][toCol] = piece;
      board[row][col] = '';

      // Handle special moves in simulation
      if (specialType == 'enpassant') {
        // Remove the captured pawn in en passant
        final capturedRow = row;
        final capturedCol = toCol;
        board[capturedRow][capturedCol] = '';
      } else if (specialType == 'castling_kingside') {
        // Move rook for kingside castling
        board[toRow][toCol - 1] = isWhite ? 'wr' : 'br';
        board[toRow][7] = '';
      } else if (specialType == 'castling_queenside') {
        // Move rook for queenside castling
        board[toRow][toCol + 1] = isWhite ? 'wr' : 'br';
        board[toRow][0] = '';
      }

      // Check if king is still in check after this move
      final kingPos = _findKingPosition(isWhite);
      final stillInCheck =
          _isSquareUnderAttack(kingPos[0], kingPos[1], isWhite);

      // Undo the simulation
      board[row][col] = piece;
      board[toRow][toCol] = originalPiece;

      if (specialType == 'enpassant') {
        // Restore the captured pawn
        final capturedRow = row;
        final capturedCol = toCol;
        board[capturedRow][capturedCol] = isWhite ? 'bp' : 'wp';
      } else if (specialType == 'castling_kingside') {
        // Restore rook
        board[toRow][7] = isWhite ? 'wr' : 'br';
        board[toRow][toCol - 1] = '';
      } else if (specialType == 'castling_queenside') {
        // Restore rook
        board[toRow][0] = isWhite ? 'wr' : 'br';
        board[toRow][toCol + 1] = '';
      }

      // Only allow move if it doesn't leave king in check
      if (!stillInCheck) {
        validMoves[toRow][toCol] = true;
      }
    }
  }

  void _onSquareTap(int row, int col) {
    if (gameOver || pendingPromotion != null) return;

    final piece = board[row][col];

    if (selectedPiece.isEmpty) {
      // Selecting a piece
      if (piece.isNotEmpty) {
        final isPieceWhite = _isWhitePiece(piece);

        // Multiplayer movement restriction
        if (_isConnectedToRoom && _playerColor != null) {
          final isMyPiece = (isPieceWhite && _playerColor == 'w') ||
              (!isPieceWhite && _playerColor == 'b');
          if (!isMyPiece) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("That is your opponent's piece!"),
                duration: Duration(milliseconds: 500)));
            return;
          }
        }

        if ((isPieceWhite && isWhiteTurn) || (!isPieceWhite && !isWhiteTurn)) {
          _calculateValidMoves(row, col, piece);
          setState(() {
            selectedPiece = piece;
            selectedRow = row;
            selectedCol = col;
          });
        }
      }
    } else if (validMoves[row][col]) {
      // Moving to a valid square
      _movePiece(row, col);
    } else if (piece.isNotEmpty &&
        _isWhitePiece(piece) == _isWhitePiece(selectedPiece)) {
      // Selecting a different piece of the same color
      _calculateValidMoves(row, col, piece);
      setState(() {
        selectedPiece = piece;
        selectedRow = row;
        selectedCol = col;
      });
    } else {
      // Clicking elsewhere - clear selection
      setState(() {
        selectedPiece = '';
        selectedRow = -1;
        selectedCol = -1;
        for (int i = 0; i < 8; i++) {
          for (int j = 0; j < 8; j++) {
            validMoves[i][j] = false;
          }
        }
      });
    }
  }

  void _undoMove() {
    if (moveHistory.isEmpty || gameOver || pendingPromotion != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No moves to undo')),
      );
      return;
    }

    final lastMove = moveHistory.removeLast();
    if (lastMove['capturedPiece'].isNotEmpty && !lastMove['isEnPassant']) {
      if (lastMove['wasWhiteTurn']) {
        if (blackCapturedPieces.isNotEmpty) {
          blackCapturedPieces.removeLast();
        }
      } else {
        if (whiteCapturedPieces.isNotEmpty) {
          whiteCapturedPieces.removeLast();
        }
      }
    }

    setState(() {
      // Restore captured piece
      if (lastMove['isEnPassant']) {
        // For en passant, restore pawn in different square
        final capturedRow = lastMove['wasWhiteTurn']
            ? lastMove['toRow'] + 1
            : lastMove['toRow'] - 1;
        board[capturedRow][lastMove['toCol']] = lastMove['capturedPiece'];
        board[lastMove['toRow']][lastMove['toCol']] = '';
      } else {
        board[lastMove['toRow']][lastMove['toCol']] = lastMove['capturedPiece'];
      }

      // Move piece back
      board[lastMove['fromRow']][lastMove['fromCol']] = lastMove['movedPiece'];

      // Handle castling undo
      if (lastMove['isCastling']) {
        if (lastMove['toCol'] > lastMove['fromCol']) {
          // Undo kingside castling
          board[lastMove['toRow']][7] =
              board[lastMove['toRow']][lastMove['toCol'] - 1];
          board[lastMove['toRow']][lastMove['toCol'] - 1] = '';
        } else {
          // Undo queenside castling
          board[lastMove['toRow']][0] =
              board[lastMove['toRow']][lastMove['toCol'] + 1];
          board[lastMove['toRow']][lastMove['toCol'] + 1] = '';
        }
      }

      // Restore castling rights if needed
      if (lastMove['movedPiece'] == 'wk') {
        whiteKingMoved = moveHistory.any((move) => move['movedPiece'] == 'wk');
      }
      if (lastMove['movedPiece'] == 'bk') {
        blackKingMoved = moveHistory.any((move) => move['movedPiece'] == 'bk');
      }
      // Similar for rooks...

      // Restore turn
      isWhiteTurn = lastMove['wasWhiteTurn'];

      // Update position history
      if (positionHistory.isNotEmpty) {
        positionHistory.removeLast();
      }

      // Update check status
      _updateCheckStatus();

      // Clear selection
      selectedPiece = '';
      selectedRow = -1;
      selectedCol = -1;

      // Clear valid moves
      for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++) {
          validMoves[i][j] = false;
        }
      }

      gameOver = false;
      status = isWhiteTurn ? "White's turn" : "Black's turn";
    });
  }

  void _showGameOverDialog(String message) {
    // Record game statistics if in an online game
    if (_isConnectedToRoom && _playerColor != null) {
      if (message.toLowerCase().contains('draw') ||
          message.toLowerCase().contains('stalemate')) {
        GameService.recordGameResult('draw');
      } else if (winner != null) {
        final String myColorName = _playerColor == 'w' ? 'White' : 'Black';
        if (winner == myColorName) {
          GameService.recordGameResult('win');
        } else {
          GameService.recordGameResult('loss');
        }
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Game Over'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _initializeBoard();
            },
            child: const Text('New Game'),
          ),
        ],
      ),
    );
  }

  Widget _buildChessSquare(int row, int col) {
    final piece = board[row][col];
    final isWhiteSquare = (row + col) % 2 == 0;
    final isSelected = row == selectedRow && col == selectedCol;
    final isValidMove = validMoves[row][col];

    // Check if this square contains a king in check
    bool isKingInCheck = false;
    if (piece.isNotEmpty && _getPieceType(piece) == 'k') {
      isKingInCheck = _isWhitePiece(piece) ? whiteInCheck : blackInCheck;
    }

    // Check if this is en passant target square
    bool isEnPassantTarget = false;
    if (enPassantTarget != null) {
      final targetPos = _fromAlgebraic(enPassantTarget!);
      isEnPassantTarget = (row == targetPos[0] && col == targetPos[1]);
    }

    Color squareColor;
    if (isSelected) {
      squareColor = Colors.yellow.withOpacity(0.5);
    } else if (isValidMove) {
      squareColor = Colors.green.withOpacity(0.3);
    } else if (isKingInCheck) {
      squareColor = Colors.red.withOpacity(0.5); // Red for king in check
    } else if (isEnPassantTarget) {
      squareColor = Colors.blue.withOpacity(0.2); // Blue for en passant target
    } else {
      squareColor =
          isWhiteSquare ? const Color(0xFFF0D9B5) : const Color(0xFFB58863);
    }

    return GestureDetector(
      onTap: () => _onSquareTap(row, col),
      child: Container(
        decoration: BoxDecoration(
          color: squareColor,
          border: Border.all(color: Colors.black12, width: 0.5),
        ),
        child: Center(
          child: piece.isEmpty
              ? const SizedBox()
              : FittedBox(
                  fit: BoxFit.contain,
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Text(
                      pieceIcons[piece] ?? '',
                      style: TextStyle(
                        fontSize: 28,
                        color: _isWhitePiece(piece) ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Chess Game', style: TextStyle(color: Colors.white)),
            if (_isAudioOn)
              Text(
                _formatDuration(_callDuration),
                style: const TextStyle(
                  fontSize: 12, 
                  color: Colors.white70, 
                  fontWeight: FontWeight.normal,
                  fontFamily: 'monospace',
                ),
              ),
            if (_isCalling && !_isAudioOn)
              const Text(
                'Calling...',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            if (_showIncomingCallBanner)
              Text(
                'Incoming: $_incomingCallFrom',
                style: const TextStyle(fontSize: 12, color: Colors.greenAccent),
              ),
          ],
        ),
        backgroundColor: Colors.blue[800],
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isConnectedToRoom) ...[
            IconButton(
              icon: Icon(_isAudioOn ? Icons.call_end : Icons.call, 
                         color: _isAudioOn ? Colors.red : Colors.white),
              onPressed: () {
                if (_isAudioOn) {
                  _toggleAudio(); // Ends call
                } else {
                  // Direct audio call (user requested no dialog)
                  if (!_isAudioOn) {
                    setState(() => _isVideoOn = false);
                    _toggleAudio();
                  }
                }
              },
              tooltip: _isAudioOn ? "End Call" : "Call Opponent",
            ),
          ],
          
          if (_isConnectedToRoom)
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: _onLogout,
              tooltip: 'Leave Room',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Main Game Content
          Column(
            children: [
              // User Profile Header
              if (_isAudioOn || _isCalling || _showIncomingCallBanner)
                _buildCallInterface()
              else
                GestureDetector(
                  onTap: () => context.go('/profile'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8), // Reduced padding
                    color: Colors.blue[50],
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16, // Reduced radius
                          backgroundColor: Colors.blue[100],
                          backgroundImage: _authService
                                      .currentUser?['profile_picture'] !=
                                  null
                              ? NetworkImage(
                                  _authService.currentUser!['profile_picture']!)
                              : null,
                          child: _authService.currentUser?['profile_picture'] ==
                                  null
                              ? Icon(
                                  Icons.person,
                                  size: 16, // Reduced size
                                  color: Colors.blue[800],
                                )
                              : null,
                        ),
                      const SizedBox(width: 8), // Reduced spacing
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _authService.displayName,
                              style: const TextStyle(
                                fontSize: 13, // Reduced font size
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _authService.email ?? 'No email',
                              style: TextStyle(
                                fontSize: 10, // Reduced font size
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16, // Smaller icon
                        color: Colors.grey[500],
                      ),
                    ],
                  ),
                ),
              ),

              // Game Status with check indicator
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 16), // Reduced vertical padding
                color: isWhiteTurn ? Colors.white : Colors.black,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isWhiteTurn ? Colors.black : Colors.white,
                      ),
                    ),
                    if (whiteInCheck || blackInCheck)
                      const Icon(
                        Icons.warning,
                        color: Colors.red,
                        size: 20,
                      ),
                    Text(
                      'Moves: ${moveHistory.length}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isWhiteTurn ? Colors.black54 : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),

              // Top captured pieces (Opponent's captures)
              _buildCapturedDisplay(_playerColor == 'b'
                  ? blackCapturedPieces
                  : whiteCapturedPieces),

              // Chess Board
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Calculate the best fit square size based on available space
                      // Use full available space
                      final availableWidth = constraints.maxWidth;
                      final availableHeight = constraints.maxHeight;
                      final size = availableWidth < availableHeight
                          ? availableWidth
                          : availableHeight;
                      return Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.brown, width: 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: GridView.builder(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 8,
                          ),
                          itemCount: 64,
                          itemBuilder: (context, index) {
                            // Flip board for black player
                            final row = _playerColor == 'b'
                                ? 7 - (index ~/ 8)
                                : index ~/ 8;
                            final col = _playerColor == 'b'
                                ? 7 - (index % 8)
                                : index % 8;
                            return _buildChessSquare(row, col);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Bottom captured pieces (Current player's captures)
              _buildCapturedDisplay(_playerColor == 'b'
                  ? whiteCapturedPieces
                  : blackCapturedPieces),

              // Call Status Footer (Only show when message is active)
              if (_callStatus.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  width: double.infinity,
                  color: Colors.green[100],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Colors.green[800]),
                      const SizedBox(width: 8),
                      Text(
                        _callStatus,
                        style: TextStyle(
                            color: Colors.green[800],
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

              // Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Reduced vertical padding
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _isConnectedToRoom || pendingPromotion != null
                                    ? null
                                    : _undoMove,
                            icon: const Icon(Icons.undo),
                            label: const Text('Undo'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (_isConnectedToRoom ||
                                      pendingPromotion != null)
                                  ? Colors.grey
                                  : Colors.orange,
                              padding: const EdgeInsets.symmetric(vertical: 8), // Reduced padding
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              if (_isConnectedToRoom) {
                                _signalingService.sendNewGame();
                              }
                              _initializeBoard();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('New'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 8), // Reduced padding
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6), // Reduced height
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => context.go('/users'),
                            icon: const Icon(Icons.people),
                            label: const Text('Players'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              padding: const EdgeInsets.symmetric(vertical: 8), // Reduced padding
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    await context.push('/invitations');
                                    _loadInviteCount(); // Refresh when coming back
                                  },
                                  icon: const Icon(Icons.mail),
                                  label: const Text('Invites'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8), // Reduced padding
                                  ),
                                ),
                              ),
                              if (_inviteCount > 0)
                                Positioned(
                                  right: -5,
                                  top: -5,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 20,
                                      minHeight: 20,
                                    ),
                                    child: Text(
                                      '$_inviteCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCapturedDisplay(List<String> capturedPieces) {
    // Sort pieces by value (queen > rook > bishop/knight > pawn)
    final sortedPieces = List.from(capturedPieces)
      ..sort((a, b) {
        final values = {'q': 9, 'r': 5, 'b': 3, 'n': 3, 'p': 1};
        final aValue = values[_getPieceType(a)] ?? 0;
        final bValue = values[_getPieceType(b)] ?? 0;
        return bValue.compareTo(aValue); // Descending order
      });

    return Container(
      height: 30, // Reduced height
      margin: const EdgeInsets.symmetric(vertical: 4), // Reduced margin
      child: sortedPieces.isEmpty
          ? const SizedBox()
          : Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: sortedPieces.map((piece) {
                return Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _isWhitePiece(piece) ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: Center(
                    child: Text(
                      pieceIcons[piece] ?? '',
                      style: TextStyle(
                        fontSize: 20,
                        color:
                            _isWhitePiece(piece) ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildCallInterface() {
    Widget? activeControls;
    
    if (_showIncomingCallBanner) {
      activeControls = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCallControlButton(
              icon: Icons.call,
              color: Colors.green,
              onPressed: () async {
                await MqttService().cancelCallNotification(broadcast: true);
                setState(() {
                  _showIncomingCallBanner = false;
                  _isIncomingCall = true;
                });
                if (mounted) await _toggleAudio();
              },
            ),
            const SizedBox(width: 12),
            _buildCallControlButton(
              icon: Icons.call_end,
              color: Colors.red,
              onPressed: () async {
                await MqttService().cancelCallNotification(broadcast: true);
                setState(() => _showIncomingCallBanner = false);
                await GameService.declineCall(
                  callerUsername: _incomingCallFrom,
                  roomId: _incomingCallRoomId,
                );
              },
            ),
          ],
        ),
      );
    } else if (_isCalling && !_isAudioOn) {
      activeControls = _buildCallControlButton(
        icon: Icons.call_end,
        color: Colors.red,
        onPressed: _toggleAudio,
      );
    } else if (_isAudioOn) {
      activeControls = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCallControlButton(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              color: _isMuted ? Colors.red : Colors.white24,
              onPressed: _toggleMute,
            ),
            const SizedBox(width: 8),
            _buildCallControlButton(
              icon: _isVideoOn ? Icons.videocam : Icons.videocam_off,
              color: _isVideoOn ? Colors.blue : Colors.white24,
              onPressed: _toggleVideo,
            ),
            const SizedBox(width: 8),
            _buildCallControlButton(
              icon: Icons.call_end,
              color: Colors.red,
              onPressed: _toggleAudio,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: const Border(bottom: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      child: Row(
        children: [
          // Local Player Box
          Expanded(
            child: _buildCallProfileBox(
              name: "You",
              renderer: _localRenderer,
              isCameraOn: _isVideoOn,
              isMuted: _isMuted,
              profilePic: _authService.currentUser?['profile_picture'],
              controls: activeControls, // Local user gets the controls
            ),
          ),
          const SizedBox(width: 8),
          // Remote Player Box
          Expanded(
            child: _buildCallProfileBox(
              name: widget.opponentName ?? "Opponent",
              renderer: _remoteRenderer,
              isCameraOn: _isRemoteVideoOn,
              isMuted: false,
              profilePic: null,
              // Opponent doesn't get controls for now, or could show call status
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallProfileBox({
    required String name,
    required rtc.RTCVideoRenderer renderer,
    required bool isCameraOn,
    required bool isMuted,
    String? profilePic,
    Widget? controls,
  }) {
    return Container(
      height: 120, // Increased slightly as requested
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Background / Avatar
            Center(
              child: profilePic != null
                  ? CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(profilePic),
                    )
                  : Icon(Icons.person, size: 30, color: Colors.blue[100]),
            ),
            // Video Stream
            if (isCameraOn)
              name == "Opponent" && _remoteVideoTrack != null
                  ? lk.VideoTrackRenderer(
                      _remoteVideoTrack!,
                      fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : rtc.RTCVideoView(
                      renderer,
                      objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      mirror: name == "You",
                    ),
            // Name Overlay
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
            // Mute Icon
            if (isMuted)
              const Positioned(
                top: 8,
                right: 8,
                child: Icon(Icons.mic_off, color: Colors.red, size: 16),
              ),
            // Controls Overlay
            if (controls != null)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(child: controls),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.all(4), // Further reduced padding
        decoration: BoxDecoration(
          color: color.withOpacity(0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 12, // Further reduced size
        ),
      ),
    );
  }
}

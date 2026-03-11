import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../services/game_service.dart';
import '../../services/mqtt_service.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  List<dynamic> _invitations = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  StreamSubscription? _mqttSubscription;

  @override
  void initState() {
    super.initState();
    _loadInvitations();
    
    // Auto-refresh every 30 seconds to handle expiry
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {}); // Trigger rebuild to re-filter expired ones
      }
    });

    // Listen for real-time invitation updates
    _mqttSubscription = MqttService().notifications.listen((data) {
      if (mounted && (data['type'] == 'game_invitation' || data['type'] == 'invitation_response' || data['type'] == 'invitation_cancelled')) {
        _loadInvitations();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mqttSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadInvitations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await GameService.getMyInvitations();
      if (result['success']) {
        setState(() {
          _invitations = result['invitations'];
        });
      }
    } catch (e) {
      print('Error loading invitations: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _respondToInvitation(int invitationId, String action) async {
    try {
      final result = await GameService.respondToInvitation(
        invitationId: invitationId,
        action: action,
      );

      if (mounted) {
        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: action == 'accept' ? Colors.green : Colors.orange,
            ),
          );
          
          if (action == 'accept') {
            final invitation = result['invitation'];
            final roomId = invitation['room_id'];
            final senderName = invitation['sender']['username'];
            
            // Navigate to the game room
            context.go('/chess?roomId=$roomId&color=b&opponentName=$senderName');
          } else {
            // Refresh invitations after declining
            _loadInvitations();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Failed to respond'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Invitations'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/chess'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInvitations,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _invitations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mail_outline,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No pending invitations',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadInvitations,
                  child: ListView.builder(
                    itemCount: _getValidInvitations().length,
                    itemBuilder: (context, index) {
                      final invitation = _getValidInvitations()[index];
                      return InvitationCard(
                        invitation: invitation,
                        onAccept: () => _respondToInvitation(
                          invitation['id'],
                          'accept',
                        ),
                        onDecline: () => _respondToInvitation(
                          invitation['id'],
                          'decline',
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  List<dynamic> _getValidInvitations() {
    final now = DateTime.now();
    return _invitations.where((inv) {
      final createdAt = DateTime.parse(inv['created_at']);
      // 5-minute expiry
      return now.difference(createdAt).inMinutes < 5;
    }).toList();
  }
}

class InvitationCard extends StatelessWidget {
  final dynamic invitation;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const InvitationCard({
    super.key,
    required this.invitation,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final sender = invitation['sender'];
    final createdAt = DateTime.parse(invitation['created_at']);
    final timeAgo = _getTimeAgo(createdAt);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            spreadRadius: 2,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // Top Accent Bar
            Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[400]!, Colors.blue[800]!],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Sender profile picture with modern border
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.blue[100]!, width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.blue[50],
                          backgroundImage: sender['profile_picture'] != null
                              ? NetworkImage(sender['profile_picture'])
                              : null,
                          child: sender['profile_picture'] == null
                              ? Icon(
                                  Icons.person_rounded,
                                  size: 32,
                                  color: Colors.blue[400],
                                )
                              : null,
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Invitation info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sender['username'],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'CHALLENGED YOU',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  color: Colors.blue[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Time badge
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Icon(Icons.access_time_rounded, size: 14, color: Colors.grey),
                          const SizedBox(height: 4),
                          Text(
                            timeAgo,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Room details
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F9F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.meeting_room_rounded, size: 18, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'Room: ${invitation['room_id']}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Invite Expires in 5m',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Action buttons with modern style
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: onDecline,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey[600],
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'DECLINE',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: onAccept,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[600],
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.play_arrow_rounded),
                                SizedBox(width: 8),
                                Text(
                                  'ACCEPT',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    }
  }
}

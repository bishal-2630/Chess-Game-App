import 'package:flutter/material.dart';

class CallNotificationBanner extends StatefulWidget {
  final String callerName;
  final bool initialVideo;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  const CallNotificationBanner({
    super.key,
    required this.callerName,
    this.initialVideo = false,
    required this.onAnswer,
    required this.onDecline,
  });

  @override
  State<CallNotificationBanner> createState() => _CallNotificationBannerState();
}

class _CallNotificationBannerState extends State<CallNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Colors.green[700],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Animated phone icon
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (_pulseController.value * 0.2),
                  child: Icon(
                    widget.initialVideo ? Icons.videocam : Icons.phone_in_talk,
                    color: Colors.white,
                    size: 28,
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            // Caller info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.initialVideo ? 'Incoming Video Call' : 'Incoming Audio Call',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.callerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Action buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Decline button
                IconButton(
                  onPressed: widget.onDecline,
                  icon: const Icon(Icons.call_end),
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    padding: const EdgeInsets.all(12),
                  ),
                  tooltip: 'Decline',
                ),
                const SizedBox(width: 8),
                // Answer button
                IconButton(
                  onPressed: widget.onAnswer,
                  icon: const Icon(Icons.call),
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.green[900],
                    padding: const EdgeInsets.all(12),
                  ),
                  tooltip: 'Answer',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

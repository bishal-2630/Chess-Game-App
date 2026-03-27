import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/django_auth_service.dart';
import '../../services/ad_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final DjangoAuthService _authService = DjangoAuthService();

  @override
  void initState() {
    super.initState();
    _authService.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? user = _authService.currentUser;
    final bool isGuest = _authService.isGuest;
    final String displayName = _authService.displayName;
    final String displayEmail = isGuest ? "Guest Account" : (user?['email'] ?? 'No email provided');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/chess'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // Profile Picture
              CircleAvatar(
                radius: 60,
                backgroundColor: Colors.blue[100],
                backgroundImage: (!isGuest && user?['profile_picture'] != null)
                    ? NetworkImage(user!['profile_picture']!)
                    : null,
                child: (isGuest || user?['profile_picture'] == null)
                    ? Icon(
                        isGuest ? Icons.person_outline : Icons.person,
                        size: 60,
                        color: Colors.blue[800],
                      )
                    : null,
              ),

              const SizedBox(height: 20),

              // Display Name
              Text(
                displayName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isGuest)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Text(
                    'Guest Session',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),

              const SizedBox(height: 10),

              // Email
              Text(
                displayEmail,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),

              const SizedBox(height: 30),

              // Account Info Card
              Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.email),
                        title: const Text('Account Type'),
                        subtitle: Text(
                          isGuest ? 'Guest Account' : 'Registered User',
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.calendar_today),
                        title: const Text('Username'),
                        subtitle: Text(
                          user?['username'] ?? 'Unknown',
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.login),
                        title: const Text('Authentication'),
                        subtitle: Text(
                          user?['google_id'] != null ? 'Google Sign-In' : 'Email/Password',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Game Stats Card
              Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Game Statistics',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem('Wins', (user?['wins'] ?? 0).toString(), Icons.emoji_events, color: Colors.green),
                          _buildStatItem('Coins', (user?['coins'] ?? 0).toString(), Icons.monetization_on, color: Colors.amber, onAdd: () {
                            final adService = AdService();
                            if (adService.isLoading) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Row(
                                    children: [
                                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                      SizedBox(width: 15),
                                      Text("Loading ad... Please wait."),
                                    ],
                                  ),
                                  backgroundColor: Colors.blueAccent,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              return;
                            }

                            adService.showRewardedAd(
                              onUserEarnedReward: (reward) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("You earned ${reward.amount > 0 ? reward.amount : 10} coins!"), backgroundColor: Colors.green),
                                );
                              },
                              onError: (errorMsg) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(errorMsg), 
                                    backgroundColor: Colors.orange[800],
                                    action: SnackBarAction(
                                      label: 'Retry',
                                      textColor: Colors.white,
                                      onPressed: () => AdService().loadRewardedAd(),
                                    ),
                                  ),
                                );
                              },
                            );
                          }),
                          _buildStatItem('Losses', (user?['losses'] ?? 0).toString(), Icons.sentiment_dissatisfied, color: Colors.red),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Center(
                        child: Text(
                          'Total Games: ${(user?['wins'] ?? 0) + (user?['draws'] ?? 0) + (user?['losses'] ?? 0)}',
                          style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Action Buttons
              SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          await _authService.signOut();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Logged out successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            context.go('/login');
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Logout failed: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () => context.go('/chess'),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Game'),
                    ),
                  ],
                ),
              ),
            ],
            ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {Color? color, VoidCallback? onAdd}) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: color ?? Colors.blue[700], size: 30),
            if (onAdd != null)
              Positioned(
                right: -10,
                top: -10,
                child: IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green, size: 20),
                  onPressed: onAdd,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

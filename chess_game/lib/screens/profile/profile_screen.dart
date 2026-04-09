import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/django_auth_service.dart';
import '../../services/payment_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = DjangoAuthService();
    final Map<String, dynamic>? user = authService.currentUser;
    final bool isGuest = authService.isGuest;
    final String displayName = authService.displayName;
    final String displayEmail = isGuest ? "Guest Account" : (user?['email'] ?? 'No email provided');
    final bool isPro = authService.isPro;

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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isPro) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'PRO',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
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

              // Pro Upgrade Card
              if (!isPro && !isGuest)
                Card(
                  color: Colors.blue[50],
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: const BorderSide(color: Colors.blue, width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 40),
                        const SizedBox(height: 10),
                        const Text(
                          'Upgrade to Pro',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Unlock premium features and support the development!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () async {
                            final result = await PaymentService.createCheckoutSession();
                            if (result['success']) {
                              await PaymentService.launchCheckout(result['url']);
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: ${result['error']}'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text(
                            'UPGRADE FOR $9.99',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                          _buildStatItem('Draws', (user?['draws'] ?? 0).toString(), Icons.handshake, color: Colors.orange),
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
                          await authService.signOut();
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
                    OutlinedButton.icon(
                      onPressed: () async {
                        await authService.refreshUserData();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Profile refreshed'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Profile'),
                      style: OutlinedButton.styleFrom(
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

  Widget _buildStatItem(String label, String value, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, color: color ?? Colors.blue[700], size: 30),
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

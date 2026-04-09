import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/local_network_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HotspotSetupScreen
// ─────────────────────────────────────────────────────────────────────────────

class HotspotSetupScreen extends StatefulWidget {
  const HotspotSetupScreen({super.key});

  @override
  State<HotspotSetupScreen> createState() => _HotspotSetupScreenState();
}

class _HotspotSetupScreenState extends State<HotspotSetupScreen>
    with SingleTickerProviderStateMixin {
  final LocalNetworkService _lns = LocalNetworkService();

  // UI state
  _Mode _mode = _Mode.idle;
  bool _isLoading = false;
  String _statusMessage = '';
  String _localIp = '';
  List<DiscoveredHost> _hosts = [];
  StreamSubscription<List<DiscoveredHost>>? _discoverySub;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _discoverySub?.cancel();
    // Only dispose the LNS if we are not connected (we don't want to kill
    // a session that was handed off to ChessScreen)
    if (!_lns.isConnected) {
      _lns.dispose();
    }
    super.dispose();
  }

  // ── permissions ────────────────────────────────────────────────────────────

  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.locationWhenInUse,
      Permission.nearbyWifiDevices,
    ].request();

    final denied = statuses.values.any(
      (s) => s == PermissionStatus.denied || s == PermissionStatus.permanentlyDenied,
    );

    if (denied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Location / Nearby Wi-Fi permission is required for local play.'),
        backgroundColor: Colors.red,
      ));
    }
    return !denied;
  }

  // ── HOST actions ───────────────────────────────────────────────────────────

  Future<void> _startHost() async {
    if (!await _requestPermissions()) return;

    setState(() {
      _isLoading = true;
      _mode = _Mode.hosting;
      _statusMessage = 'Starting server…';
    });

    final username = 'Player'; // placeholder – could pull from DjangoAuthService
    await _lns.startHost(username);

    final ip = await _lns.getLocalIp();
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _localIp = ip ?? 'Unknown';
      _statusMessage = 'Waiting for opponent…';
    });

    // Generate a random room ID so the ChessScreen game logic still works
    final roomId = 'hotspot_${Random().nextInt(9000) + 1000}';

    _lns.onOpponentConnected = () {
      if (!mounted) return;
      // Navigate immediately – the game channel is the local server
      context.go('/chess?roomId=$roomId&color=w&mode=hotspot');
    };
  }

  // ── CLIENT actions ─────────────────────────────────────────────────────────

  Future<void> _startDiscovery() async {
    if (!await _requestPermissions()) return;

    setState(() {
      _mode = _Mode.scanning;
      _hosts = [];
      _statusMessage = 'Scanning for games…';
    });

    await _lns.startDiscovery();

    _discoverySub = _lns.discoveredHosts.listen((hosts) {
      if (mounted) {
        setState(() => _hosts = hosts);
      }
    });
  }

  Future<void> _joinHost(DiscoveredHost host) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Connecting to ${host.name}…';
    });

    final error = await _lns.connectToHost(host);
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _isLoading = false;
        _statusMessage = error;
      });
      return;
    }

    // Generate a matching room ID (doesn't matter – the local channel is used)
    const roomId = 'hotspot_guest';
    context.go('/chess?roomId=$roomId&color=b&mode=hotspot');
  }

  // ── reset ──────────────────────────────────────────────────────────────────

  Future<void> _reset() async {
    _discoverySub?.cancel();
    _discoverySub = null;
    await _lns.dispose();
    if (mounted) {
      setState(() {
        _mode = _Mode.idle;
        _isLoading = false;
        _statusMessage = '';
        _hosts = [];
      });
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(context),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1117), Color(0xFF161B22), Color(0xFF0D1117)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.go('/chess'),
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
          ),
          const SizedBox(width: 8),
          const Text(
            'Wifi Hotspot Mode',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (_mode != _Mode.idle)
            TextButton.icon(
              onPressed: _isLoading ? null : _reset,
              icon: const Icon(Icons.refresh, color: Colors.orangeAccent, size: 18),
              label: const Text('Reset', style: TextStyle(color: Colors.orangeAccent)),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case _Mode.idle:
        return _buildIdleScreen();
      case _Mode.hosting:
        return _buildHostingScreen();
      case _Mode.scanning:
        return _buildScanningScreen();
    }
  }

  // ── IDLE ───────────────────────────────────────────────────────────────────

  Widget _buildIdleScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Animated chess / wifi icon
        ScaleTransition(
          scale: _pulseAnim,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF3A7BD5), Color(0xFF1A3A6A)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3A7BD5).withOpacity(0.4),
                  blurRadius: 30,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: const Icon(Icons.wifi, size: 64, color: Colors.white),
          ),
        ),
        const SizedBox(height: 40),
        const Text(
          'Play Locally',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'No internet required. Host a game or join a nearby game on the same Wi-Fi / Hotspot network.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 48),
        _buildActionButton(
          icon: Icons.router,
          label: 'Host a Game',
          subtitle: 'Turn on hotspot, then start',
          gradient: const LinearGradient(
            colors: [Color(0xFF3A7BD5), Color(0xFF00D2FF)],
          ),
          onTap: _startHost,
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: Icons.search,
          label: 'Join a Game',
          subtitle: 'Connect to host\'s hotspot first',
          gradient: const LinearGradient(
            colors: [Color(0xFF4CAF50), Color(0xFF8BC34A)],
          ),
          onTap: _startDiscovery,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8), fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── HOSTING ────────────────────────────────────────────────────────────────

  Widget _buildHostingScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPulsingDot(const Color(0xFF3A7BD5)),
        const SizedBox(height: 32),
        Text(
          _statusMessage,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        if (_localIp.isNotEmpty) ...[
          Text(
            'Your IP Address',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              _localIp,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Enable your device\'s Wi-Fi Hotspot, then ask your opponent to connect to it and select "Join a Game" in the app.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ),
        ],
        if (_isLoading) ...[
          const SizedBox(height: 32),
          const CircularProgressIndicator(color: Color(0xFF3A7BD5)),
        ],
      ],
    );
  }

  // ── SCANNING ───────────────────────────────────────────────────────────────

  Widget _buildScanningScreen() {
    return Column(
      children: [
        const SizedBox(height: 24),
        _buildPulsingDot(const Color(0xFF4CAF50)),
        const SizedBox(height: 20),
        Text(
          _statusMessage,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_hosts.length} game(s) found',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
        ),
        const SizedBox(height: 24),
        if (_hosts.isEmpty)
          Expanded(child: _buildEmptyHosts())
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _hosts.length,
              itemBuilder: (_, i) => _buildHostTile(_hosts[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyHosts() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_find, size: 72, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'No games found yet',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure both devices are on\nthe same Wi-Fi or Hotspot network.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildHostTile(DiscoveredHost host) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: _isLoading ? null : () => _joinHost(host),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Color(0xFF4CAF50), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${host.host}:${host.port}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.45), fontSize: 12),
                    ),
                  ],
                ),
              ),
              _isLoading && _statusMessage.contains(host.name)
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF4CAF50)),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4CAF50), Color(0xFF8BC34A)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Join',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  Widget _buildPulsingDot(Color color) {
    return ScaleTransition(
      scale: _pulseAnim,
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.15),
          border: Border.all(color: color.withOpacity(0.6), width: 2.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 24,
              spreadRadius: 6,
            ),
          ],
        ),
        child: Icon(Icons.wifi_tethering, color: color, size: 44),
      ),
    );
  }
}

enum _Mode { idle, hosting, scanning }

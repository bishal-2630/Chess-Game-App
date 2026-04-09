import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nsd/nsd.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../utils/logger.dart';

/// A service discovery type used for NSD.
const _kServiceType = '_chess._tcp';

/// The local port used by the host's WebSocket server.
const int kHotspotPort = 47654;

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class DiscoveredHost {
  final String name;
  final String host;
  final int port;

  const DiscoveredHost({
    required this.name,
    required this.host,
    required this.port,
  });

  @override
  String toString() => '$name ($host:$port)';
}

// ─────────────────────────────────────────────────────────────────────────────
// LocalNetworkService  (singleton)
// ─────────────────────────────────────────────────────────────────────────────

class LocalNetworkService {
  static final LocalNetworkService _instance = LocalNetworkService._internal();
  factory LocalNetworkService() => _instance;
  LocalNetworkService._internal();

  // ── host state ──────────────────────────────────────────────────────────────
  HttpServer? _httpServer;
  Registration? _nsdRegistration;
  final List<WebSocketSink> _clientSinks = [];

  // ── client state ────────────────────────────────────────────────────────────
  Discovery? _discovery;
  WebSocketChannel? _channel;

  // ── shared state ────────────────────────────────────────────────────────────
  bool _isHost = false;
  bool get isHost => _isHost;
  bool get isConnected => _channel != null || _clientSinks.isNotEmpty;

  // ── event streams ────────────────────────────────────────────────────────────
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  final StreamController<List<DiscoveredHost>> _hostsController =
      StreamController<List<DiscoveredHost>>.broadcast();
  Stream<List<DiscoveredHost>> get discoveredHosts => _hostsController.stream;

  /// Callback fired when the opponent joins (host) or we connect (client).
  void Function()? onOpponentConnected;

  /// Callback fired when the opponent leaves.
  void Function()? onOpponentLeft;

  final List<DiscoveredHost> _foundHosts = [];

  // ─────────────────────────────────────────────────────────────────────────
  //  HOST  side
  // ─────────────────────────────────────────────────────────────────────────

  /// Start the local WS server and register an NSD service.
  Future<void> startHost(String playerName) async {
    _isHost = true;
    _clientSinks.clear();

    final handler = webSocketHandler((webSocket) {
      AppLogger.i('🌐 [Hotspot] Client connected');
      final sink = webSocket.sink;
      _clientSinks.add(sink);

      // Notify UI
      onOpponentConnected?.call();

      // Send initial handshake
      sink.add(jsonEncode({'type': 'connected', 'opponent': null}));

      webSocket.stream.listen(
        (msg) {
          try {
            final data = jsonDecode(msg as String) as Map<String, dynamic>;
            // Broadcast to self (UI) and relay to all OTHER clients
            _messageController.add(data);
            _broadcastToClients(msg, except: sink);
          } catch (e) {
            AppLogger.e('❌ [Hotspot Host] Parse error: $e');
          }
        },
        onDone: () {
          AppLogger.w('⚠️ [Hotspot] Client disconnected');
          _clientSinks.remove(sink);
          onOpponentLeft?.call();
        },
        onError: (e) {
          AppLogger.e('❌ [Hotspot] Client error: $e');
          _clientSinks.remove(sink);
          onOpponentLeft?.call();
        },
      );
    });

    _httpServer = await shelf_io.serve(handler, InternetAddress.anyIPv4, kHotspotPort);
    AppLogger.i('🖥️  [Hotspot] Server started at port $kHotspotPort');

    // Register NSD so client can find us
    final service = Service(
      name: 'Chess-$playerName',
      type: _kServiceType,
      port: kHotspotPort,
    );
    _nsdRegistration = await register(service);
    AppLogger.i('📡 [Hotspot] NSD registered: ${service.name}');
  }

  void _broadcastToClients(String msg, {WebSocketSink? except}) {
    for (final sink in List.from(_clientSinks)) {
      if (sink != except) {
        sink.add(msg);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  CLIENT  side
  // ─────────────────────────────────────────────────────────────────────────

  /// Start NSD discovery and stream results via [discoveredHosts].
  Future<void> startDiscovery() async {
    _foundHosts.clear();
    _hostsController.add([]);
    _discovery = await startDiscovery_(_kServiceType);

    _discovery!.addServiceListener((service, status) async {
      if (status == ServiceStatus.found) {
        // Resolve host & port
        final resolved = await resolveService(service);
        final host = resolved.host?.address;
        final port = resolved.port;
        final name = resolved.name ?? 'Unknown';

        if (host != null && port != null) {
          final discovered = DiscoveredHost(name: name, host: host, port: port);
          if (!_foundHosts.any((h) => h.host == host && h.port == port)) {
            _foundHosts.add(discovered);
            _hostsController.add(List.from(_foundHosts));
            AppLogger.i('🔍 [Hotspot] Found: $discovered');
          }
        }
      } else if (status == ServiceStatus.lost) {
        final name = service.name ?? '';
        _foundHosts.removeWhere((h) => h.name == name);
        _hostsController.add(List.from(_foundHosts));
      }
    });
  }

  /// Connect to a chosen host. Returns null on success or an error message.
  Future<String?> connectToHost(DiscoveredHost host) async {
    _isHost = false;
    try {
      final url = 'ws://${host.host}:${host.port}';
      AppLogger.i('📡 [Hotspot Client] Connecting to $url');
      _channel = IOWebSocketChannel.connect(Uri.parse(url));

      _channel!.stream.listen(
        (msg) {
          try {
            final data = jsonDecode(msg as String) as Map<String, dynamic>;
            _messageController.add(data);
            if (data['type'] == 'connected') {
              onOpponentConnected?.call();
            }
          } catch (e) {
            AppLogger.e('❌ [Hotspot Client] Parse error: $e');
          }
        },
        onDone: () {
          AppLogger.w('⚠️ [Hotspot Client] Disconnected');
          _channel = null;
          onOpponentLeft?.call();
        },
        onError: (e) {
          AppLogger.e('❌ [Hotspot Client] Error: $e');
          _channel = null;
          onOpponentLeft?.call();
        },
      );
      return null;
    } catch (e) {
      return 'Failed to connect: $e';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Send (works for both host and client)
  // ─────────────────────────────────────────────────────────────────────────

  void send(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    if (_isHost) {
      _broadcastToClients(encoded);
      // Also notify the host's own UI (so move is reflected locally)
      // NB: the caller/ChessScreen handles own moves directly,
      //     so we only send to remote peers here.
    } else {
      _channel?.sink.add(encoded);
    }
    AppLogger.d('📤 [Hotspot] Sent: $message');
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Cleanup
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    // Stop NSD discovery
    if (_discovery != null) {
      await stopDiscovery_(_discovery!);
      _discovery = null;
    }

    // Unregister NSD service
    if (_nsdRegistration != null) {
      await unregister(_nsdRegistration!);
      _nsdRegistration = null;
    }

    // Notify all clients of shutdown
    _broadcastToClients(jsonEncode({'type': 'leave'}));
    for (final sink in _clientSinks) {
      await sink.close();
    }
    _clientSinks.clear();

    // Close HTTP server
    await _httpServer?.close(force: true);
    _httpServer = null;

    // Close client channel
    await _channel?.sink.close();
    _channel = null;

    _isHost = false;
    _foundHosts.clear();
    AppLogger.i('🧹 [Hotspot] Disposed');
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> getLocalIp() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (e) {
      AppLogger.e('❌ [Hotspot] Could not get local IP: $e');
      return null;
    }
  }
}

// Alias NSD functions to avoid naming conflicts with dart:io
Future<Discovery> startDiscovery_(String serviceType) =>
    startDiscovery(serviceType);

Future<void> stopDiscovery_(Discovery discovery) =>
    stopDiscovery(discovery);

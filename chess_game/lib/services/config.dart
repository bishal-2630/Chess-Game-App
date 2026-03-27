import 'dart:io';
import 'package:flutter/foundation.dart';

class AppConfig {
  // ============================================================================
  // ENVIRONMENT CONFIGURATION
  // ============================================================================

  // Set to true for local development, false for production
  static const bool _isDevelopment = false;

  // Production backend URL (Hugging Face Spaces)
  static const String _productionHost =
      'bishal26-chess-game-bishal.hf.space';

  // Local development configuration
  static const String _physicalDeviceHost = '192.168.1.76:8000';
  static const String _emulatorHost = '10.0.2.2:8000';

  // ============================================================================
  // HOST SELECTION LOGIC
  // ============================================================================

  static String get _host {
    // Production mode: use Railway backend
    if (!_isDevelopment) {
      return _productionHost;
    }

    // Development mode: detect emulator vs physical device
    // Check for environment variable override first
    const String envHost =
        String.fromEnvironment('WEBSOCKET_HOST', defaultValue: '');
    if (envHost.isNotEmpty) return envHost;

    // For Android: detect emulator vs physical device
    if (!kIsWeb && Platform.isAndroid) {
      final isEmulator = Platform.environment['ANDROID_EMULATOR'] == 'true' ||
          Platform.version.contains('emulator');

      return isEmulator ? _emulatorHost : _physicalDeviceHost;
    }

    // Default to emulator host for other platforms
    return _emulatorHost;
  }

  // ============================================================================
  // API ENDPOINTS
  // ============================================================================

  static String get baseUrl {
    // Always use the explicit production host so Vercel-hosted web builds
    // call HuggingFace (not their own origin, which has no Django backend).
    const protocol = _isDevelopment ? 'http' : 'https';
    return '$protocol://$_host/api/auth/';
  }

  static String get socketUrl {
    // Always use explicit production host for WebSockets.
    // Vercel is serverless and cannot handle WS — HuggingFace does.
    const protocol = _isDevelopment ? 'ws' : 'wss';
    return "$protocol://$_host/ws/call/";
  }
}

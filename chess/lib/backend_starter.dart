// lib/backend_starter.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class BackendStarter {
  static Process? _djangoProcess;

  static Future<bool> startBackend() async {
    print('🚀 Attempting to start Django backend...');

    // Get Flutter project directory
    final flutterProjectDir = Directory.current.path;
    print('📁 Flutter project: $flutterProjectDir');

    // start_backend.py should be in Flutter project root
    final scriptPath = '$flutterProjectDir/start_backend.py';
    print('📄 Looking for script: $scriptPath');

    final scriptFile = File(scriptPath);
    if (!scriptFile.existsSync()) {
      print('❌ start_backend.py not found in Flutter project!');
      print('   Please place it in: $flutterProjectDir');
      return false;
    }

    // Find Django path (sibling directory)
    final djangoPath = '$flutterProjectDir/../chess_backend';
    print('🔗 Django expected at: $djangoPath');

    final djangoDir = Directory(djangoPath);
    if (!djangoDir.existsSync()) {
      print('❌ Django project not found!');
      print('   Expected at: $djangoPath');
      return false;
    }

    try {
      print('⚙️  Starting Django backend process...');

      if (Platform.isWindows) {
        _djangoProcess = await Process.start(
          'python',
          [scriptPath],
          runInShell: true,
        );
      } else {
        _djangoProcess = await Process.start(
          'python3',
          [scriptPath],
          runInShell: true,
        );
      }

      // Read output
      _djangoProcess!.stdout.transform(utf8.decoder).listen((data) {
        print('📡 Django: $data');
      });

      _djangoProcess!.stderr.transform(utf8.decoder).listen((data) {
        print('❌ Django Error: $data');
      });

      // Wait for startup
      await Future.delayed(Duration(seconds: 10));

      print('✅ Backend startup initiated');
      return true;
    } catch (e) {
      print('❌ Failed to start backend: $e');
      return false;
    }
  }

  static void stopBackend() {
    if (_djangoProcess != null) {
      print('🛑 Stopping Django backend...');
      _djangoProcess!.kill();
      _djangoProcess = null;
    }
  }
}

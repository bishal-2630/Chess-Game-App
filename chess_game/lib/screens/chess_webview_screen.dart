import 'dart:convert';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/cookie_injection_service.dart';
import '../services/config.dart';
import '../services/django_auth_service.dart';

class ChessWebViewScreen extends StatefulWidget {
  final String? gameId;
  final String? customUrl;

  const ChessWebViewScreen({
    super.key,
    this.gameId,
    this.customUrl,
  });

  @override
  State<ChessWebViewScreen> createState() => _ChessWebViewScreenState();
}

class _ChessWebViewScreenState extends State<ChessWebViewScreen> {
  final CookieInjectionService _cookieService = CookieInjectionService();
  final DjangoAuthService _authService = DjangoAuthService();
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool _cookiesInjected = false;
  String? _magicUrl;
  String? _errorMessage;
  double _progress = 0;

  String _getAuthUserScript() {
    final accessToken = _authService.accessToken;
    final refreshToken = _authService.currentRefreshToken;
    final userData = _authService.currentUser;

    if (accessToken == null) return '';

    // shared_preferences web uses 'flutter.' prefix and encodes values as JSON strings
    final script = StringBuffer();
    // Use double quotes for the JSON value as expected by shared_preferences web
    script.write("localStorage.setItem('flutter.auth_token', '\"$accessToken\"');");
    if (refreshToken != null) {
      script.write("localStorage.setItem('flutter.refresh_token', '\"$refreshToken\"');");
    }
    if (userData != null) {
      final userDataJson = json.encode(userData).replaceAll("'", "\\'");
      script.write("localStorage.setItem('flutter.user_data', '$userDataJson');");
    }
    
    // Safety check for CSRF token in localStorage as well if needed by the frontend
    script.write("console.log('🚀 [ChessWebView] Auth script executed');");
    
    return script.toString();
  }

  @override
  void initState() {
    super.initState();
    _prepareMagicLink();
  }

  Future<void> _prepareMagicLink() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _cookieService.generateMagicToken();

    if (result['success'] == true) {
      final token = result['handshake_token'];
      final nextPath = _webUrlPath;
      final magicUrl = '${AppConfig.baseUrl}magic-token/verify/?token=$token&next=$nextPath';
      
      setState(() {
        _magicUrl = magicUrl;
        _cookiesInjected = true;
      });
    } else {
      setState(() {
        _errorMessage = 'Failed to generate secure access token. Please try logging in again.';
        _isLoading = false;
      });
    }
  }

  String get _webUrlPath {
    if (widget.customUrl != null) {
      return widget.customUrl!;
    }
    if (widget.gameId != null) {
      return '/game/${widget.gameId}';
    }
    return '/play';
  }

  String get _webUrl {
    if (widget.customUrl != null) {
      return widget.customUrl!;
    }

    // Build URL based on game ID
    final baseUrl = AppConfig.baseUrl.replaceAll('/api/auth/', '');
    if (widget.gameId != null) {
      return '$baseUrl/game/${widget.gameId}';
    }
    return '$baseUrl/play';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess Game'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _webViewController?.reload();
            },
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _showDebugInfo,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
            onPressed: _prepareMagicLink,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!_cookiesInjected) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Authenticating...'),
          ],
        ),
      );
    }

    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(_magicUrl ?? _webUrl),
          ),
          initialUserScripts: UnmodifiableListView<UserScript>([
            UserScript(
              source: _getAuthUserScript(),
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ]),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            thirdPartyCookiesEnabled: true,
            supportZoom: true,
            useOnLoadResource: true,
            useShouldOverrideUrlLoading: true,
            mediaPlaybackRequiresUserGesture: false,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
          ),
          onWebViewCreated: (controller) {
            _webViewController = controller;
          },
          onLoadStart: (controller, url) {
            setState(() {
              _isLoading = true;
            });
          },
          onLoadStop: (controller, url) async {
            setState(() {
              _isLoading = false;
            });
          },
          onProgressChanged: (controller, progress) {
            setState(() {
              _progress = progress / 100;
            });
          },
          onLoadError: (controller, url, code, message) {
            setState(() {
              _errorMessage = 'Failed to load page: $message';
              _isLoading = false;
            });
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            // Allow all navigation
            return NavigationActionPolicy.ALLOW;
          },
        ),
        if (_isLoading)
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
      ],
    );
  }

  Future<void> _showDebugInfo() async {
    final cookies = await _cookieService.getCookies();
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Debug Info'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('URL: $_webUrl'),
              const SizedBox(height: 8),
              Text('Cookies Injected: $_cookiesInjected'),
              const SizedBox(height: 8),
              Text('Cookies Count: ${cookies.length}'),
              const SizedBox(height: 8),
              const Text('Cookies:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...cookies.map((cookie) => Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text('${cookie.name}: ${cookie.value.length > 15 ? "${cookie.value.substring(0, 12)}..." : cookie.value}'),
              )),
              if (cookies.isEmpty) const Text('No cookies found'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

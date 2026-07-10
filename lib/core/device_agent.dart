// Real-device User-Agent builder plus a thin http.Client wrapper.
//
// Every outbound request from the gray flow uses this UA so it looks like a
// stock Chrome install rather than a Dart HTTP client. The suffix
// `appid/<bundleId> appname/<AppName>` is required for the volcanic theme
// (see `gray_user_agent.mdc`) — omitting it changes how the backend routes
// the campaign.

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../env/facade.dart';
import '../env/ua_secrets.dart';

class DeviceAgent extends http.BaseClient {
  DeviceAgent({http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;
  String? _userAgent;

  /// Populates [userAgent]. Safe to call multiple times (no-op after first).
  Future<void> ignite() async {
    if (_userAgent != null) return;
    _userAgent = await _buildUserAgent();
  }

  String get userAgent => _userAgent ?? _fallbackUa();

  Future<String> _buildUserAgent() async {
    final chromeVersion = unmaskChromeVersion().isNotEmpty
        ? unmaskChromeVersion()
        : '149.0.0.0';
    final webkitVersion = unmaskWebkitVersion().isNotEmpty
        ? unmaskWebkitVersion()
        : '537.36';

    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        final sdk = android.version.sdkInt;
        final brand = _clean(android.brand);
        final model = _clean(android.model);
        final build = _clean(
          android.display.isNotEmpty ? android.display : android.id,
        );
        return _compose(
          'Mozilla/5.0 (Linux; Android $sdk; $brand $model Build/$build) '
          'AppleWebKit/$webkitVersion (KHTML, like Gecko) '
          'Chrome/$chromeVersion Mobile Safari/$webkitVersion',
        );
      }
      final ios = await info.iosInfo;
      final ver = ios.systemVersion.replaceAll('.', '_');
      return _compose(
        'Mozilla/5.0 (iPhone; CPU iPhone OS $ver like Mac OS X) '
        'AppleWebKit/$webkitVersion (KHTML, like Gecko) '
        'Version/${ios.systemVersion} Mobile/15E148 Safari/$webkitVersion',
      );
    } catch (_) {
      return _fallbackUa();
    }
  }

  /// Ensures neither the brand nor the model injects spaces / newlines that
  /// would break header parsing on the backend.
  String _clean(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _fallbackUa() {
    final chromeVersion = unmaskChromeVersion().isNotEmpty
        ? unmaskChromeVersion()
        : '149.0.0.0';
    final webkitVersion = unmaskWebkitVersion().isNotEmpty
        ? unmaskWebkitVersion()
        : '537.36';
    if (Platform.isAndroid) {
      return _compose(
        'Mozilla/5.0 (Linux; Android 15; SM-S931U Build/AP3A.240905.015.A2) '
        'AppleWebKit/$webkitVersion (KHTML, like Gecko) '
        'Chrome/$chromeVersion Mobile Safari/$webkitVersion',
      );
    }
    return _compose(
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/$webkitVersion (KHTML, like Gecko) '
      'Version/17.0 Mobile/15E148 Safari/$webkitVersion',
    );
  }

  String _compose(String base) {
    // The `appid` / `appname` suffix must land AFTER `Mobile Safari/...` and
    // must remain space-free in the appname token.
    return '$base appid/${Facade.bundleId} appname/${Facade.appName}';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => userAgent);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Shared instance – kept as a top-level singleton so both the config beacon
/// and the WebView shell talk to the same UA string.
final DeviceAgent deviceAgent = DeviceAgent();

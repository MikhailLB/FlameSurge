// AppsFlyer wrapper + two-phase attribution acquisition.
//
// The template's canonical flow "await one callback, POST body, done" was
// battle-tested to time out for 1–4 minutes on some Android device / network
// combos. The pitfalls doc §11 describes the fix that is implemented here:
//
//   Phase 1 – race the SDK's install callback (25s cap) against the deep-link
//             callback (5s cap). If the install body arrives, we're done.
//   Phase 2 – if phase 1 ends without an install body BUT the deep-link
//             callback delivered a real click, poll the GCD REST endpoint
//             every 4s (up to 90s) in parallel with another waitForAttribution.
//
// Pure organic installs skip phase 2 and drop straight into the arena so the
// puzzle path stays fast.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../env/attribution_secrets.dart';
import '../env/facade.dart';
import 'device_agent.dart';

class AttributionPipeline {
  AppsflyerSdk? _sdk;
  Map<String, dynamic>? _installBody;
  Map<String, dynamic>? _deepLink;
  Map<String, dynamic>? _appOpen;

  final Completer<Map<String, dynamic>> _installGate =
      Completer<Map<String, dynamic>>();
  final Completer<void> _deepLinkGate = Completer<void>();

  bool _sdkReady = false;

  bool get hasInstallBody =>
      _installBody != null && _installBody!.isNotEmpty;

  /// True when the deep-link callback delivered a click that looks non-organic
  /// (any of `deep_link_value`, `deep_link_sub1`, `shortlink` non-empty).
  bool get deepLinkLooksNonOrganic {
    final d = _deepLink;
    if (d == null || d.isEmpty) return false;
    bool nonEmpty(String key) {
      final v = d[key];
      return v is String && v.trim().isNotEmpty;
    }

    return nonEmpty('deep_link_value') ||
        nonEmpty('deep_link_sub1') ||
        nonEmpty('shortlink');
  }

  Future<void> ignite() async {
    if (_sdkReady) return;
    _sdkReady = true;

    if (Facade.attributionKey.isEmpty) {
      // No dev key yet – finish both gates so callers stop waiting.
      _completeInstallGate(<String, dynamic>{});
      _completeDeepLinkGate();
      return;
    }

    final options = AppsFlyerOptions(
      afDevKey: Facade.attributionKey,
      appId: Platform.isIOS ? Facade.iosAppStoreId : '',
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );

    _sdk = AppsflyerSdk(options);

    _sdk!.onInstallConversionData((data) async {
      final payload = _extractPayload(data);
      if (payload.isEmpty) return;
      if ((payload['af_status'] as String?) == 'Organic') {
        // Known SDK false-positive — the real click may arrive shortly.
        await Future<void>.delayed(
          Duration(seconds: Facade.organicRetryDelaySeconds),
        );
        final refreshed = await _refreshFromGcd();
        _installBody =
            refreshed != null && refreshed.isNotEmpty ? refreshed : payload;
      } else {
        _installBody = payload;
      }
      _completeInstallGate(_installBody ?? payload);
    });

    _sdk!.onAppOpenAttribution((data) {
      _appOpen = _extractPayload(data);
    });

    _sdk!.onDeepLinking((result) {
      final deep = result.deepLink;
      if (deep != null) {
        _deepLink = Map<String, dynamic>.from(deep.clickEvent);
      }
      _completeDeepLinkGate();
    });

    _sdk!.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
  }

  Map<String, dynamic> _extractPayload(dynamic raw) {
    if (raw is Map) {
      final payload = raw['payload'];
      if (payload is Map) return Map<String, dynamic>.from(payload);
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }

  void _completeInstallGate(Map<String, dynamic> data) {
    if (!_installGate.isCompleted) _installGate.complete(data);
  }

  void _completeDeepLinkGate() {
    if (!_deepLinkGate.isCompleted) _deepLinkGate.complete();
  }

  /// Waits for the install callback with the caller-supplied timeout.
  Future<Map<String, dynamic>> awaitVerdict({
    Duration timeout = const Duration(seconds: 25),
  }) {
    return _installGate.future.timeout(
      timeout,
      onTimeout: () => <String, dynamic>{},
    );
  }

  Future<void> awaitDeepLink({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _deepLinkGate.future.timeout(timeout, onTimeout: () {});
  }

  Future<String?> analyticsUid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Polls the GCD REST endpoint every [Facade.gcdPollIntervalSeconds] until
  /// either the install gate completes, the deadline is hit, or a payload
  /// with a real `af_status` arrives.
  Future<void> pollGcd({
    int maxSeconds = 90,
    int intervalSeconds = 4,
  }) async {
    if (_installGate.isCompleted) return;
    if (Facade.attributionKey.isEmpty) return;

    final deadline = DateTime.now().add(Duration(seconds: maxSeconds));
    while (!_installGate.isCompleted && DateTime.now().isBefore(deadline)) {
      final refreshed = await _refreshFromGcd();
      if (_installGate.isCompleted) return;
      if (refreshed != null) {
        final status = refreshed['af_status'];
        if (status is String && status.isNotEmpty && status != 'error') {
          _installBody = refreshed;
          _completeInstallGate(refreshed);
          return;
        }
      }
      await Future<void>.delayed(Duration(seconds: intervalSeconds));
    }
  }

  Future<Map<String, dynamic>?> _refreshFromGcd() async {
    final uid = await analyticsUid();
    if (uid == null || uid.isEmpty) return null;
    final url = buildGcdUri(
      appId: Platform.isIOS ? Facade.iosAppStoreId : Facade.bundleId,
      deviceId: uid,
    );
    if (url.isEmpty) return null;

    try {
      final response = await deviceAgent
          .get(
            Uri.parse(url),
            headers: <String, String>{
              'authorization': 'Bearer ${Facade.attributionKey}',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Assembles the full POST body for the config endpoint. Order of merging
  /// mirrors the backend contract – install attribution fields win first,
  /// deep-link and app-open fields fill the gaps, device-side fields always
  /// overwrite duplicates.
  Future<Map<String, dynamic>> assemblePayload({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};
    if (_installBody != null) body.addAll(_installBody!);
    _deepLink?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _appOpen?.forEach((k, v) => body.putIfAbsent(k, () => v));

    body['af_id'] = await analyticsUid() ?? '';
    body['bundle_id'] = Facade.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = Facade.storeId;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    if (Facade.pushProjectNumber.isNotEmpty) {
      body['firebase_project_id'] = Facade.pushProjectNumber;
    }

    if (kDebugMode) {
      debugPrint('[AttributionPipeline] payload=${jsonEncode(body)}');
    }
    return body;
  }
}

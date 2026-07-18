// Firebase Messaging + local notifications wrapper.
//
// PUSH URL LIFECYCLE (per TZ):
//   * COLD (app killed → tap notification): FCM delivers via getInitialMessage
//     during the next boot. We save the URL to secure storage; the splash
//     router plucks it via [Vault.pluckFreshTapLink] before the state switch.
//   * WARM BACKGROUND (app suspended → tap): onMessageOpenedApp fires — pass
//     the URL to the [onFreshLink] callback so PortalShell can loadRequest it.
//     Do NOT save; the spec is explicit that push URLs are one-shot.
//   * FOREGROUND (in-app when push arrives): show a local notification with
//     the flame icon, tapping it fires onDidReceiveNotificationResponse and
//     dispatches through [onFreshLink] the same way.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/url_guard.dart';
import 'device_agent.dart';
import 'vault.dart';

/// Notification channel id used both here and in AndroidManifest.xml.
const String kFlameChannelId = 'flamesurge_alerts';
const String kFlameChannelName = 'Flame Surge Alerts';
const String kFlameChannelDesc = 'Push notifications from Flame Surge.';

const String kFlameNotificationIcon = '@drawable/ic_flame_notification';

@pragma('vm:entry-point')
Future<void> _isolateBgHandler(RemoteMessage message) async {
  // No user-visible work — Android already shows the tray notification for
  // `notification` payloads. The tap opens the app and either
  // onMessageOpenedApp or getInitialMessage will surface the URL.
}

typedef PushLinkSink = void Function(String url);

class PushHub {
  PushHub(this._vault);

  final Vault _vault;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _fcm;
  String? _token;
  bool _ready = false;
  StreamSubscription<List<ConnectivityResult>>? _netWatcher;

  PushLinkSink? onFreshLink;
  void Function(String newToken)? onTokenRotated;

  String? get token => _token;

  Future<void> awaken() async {
    if (_ready) return;

    // Local-notifications side is initialised unconditionally — it does not
    // touch the network so it must succeed even on a cold-launch with no
    // connectivity. This also means POST_NOTIFICATIONS can be requested via
    // the Android plugin below without waiting for Firebase.
    try {
      await _prepareLocalNotifications();
    } catch (e) {
      if (kDebugMode) debugPrint('[PushHub] local-notif init failed: $e');
    }

    try {
      await Firebase.initializeApp();
      _fcm = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(_isolateBgHandler);

      _fcm!.onTokenRefresh.listen((next) {
        _token = next;
        onTokenRotated?.call(next);
      });

      FirebaseMessaging.onMessage.listen(_handleForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleWarmTap);

      // `getInitialMessage()` MUST run so a cold-tap URL is persisted before
      // the splash router reads the vault. Do this BEFORE fetching the FCM
      // token (which is what tends to hang without internet).
      final initial = await _fcm!.getInitialMessage();
      if (initial != null) {
        await _handleColdTap(initial);
      }

      // Token fetch is fire-and-forget with a hard 8s cap. On the first
      // offline launch the plugin's own retry loop can block for tens of
      // seconds, which delays the splash router. `_scheduleTokenRefresh()`
      // will retry as soon as connectivity comes back.
      unawaited(_fetchTokenGuarded());
      _scheduleTokenRefresh();

      _ready = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[PushHub] disabled: $e');
      // Firebase not configured — the app continues without push, per TZ.
    }
  }

  Future<void> _fetchTokenGuarded() async {
    final fcm = _fcm;
    if (fcm == null) return;
    try {
      final next = await fcm.getToken().timeout(const Duration(seconds: 8));
      if (next != null && next.isNotEmpty && next != _token) {
        _token = next;
        onTokenRotated?.call(next);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PushHub] getToken failed: $e');
    }
  }

  /// Retries token acquisition every time connectivity flips from none →
  /// any interface. Without this the backend never learns about a device
  /// whose first launch happened offline (typical for QA scripts that
  /// disable Wi-Fi right after tapping OneLink).
  void _scheduleTokenRefresh() {
    _netWatcher ??= Connectivity().onConnectivityChanged.listen((results) {
      final live = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn ||
          r == ConnectivityResult.bluetooth ||
          r == ConnectivityResult.other);
      if (!live) return;
      if (_token != null && _token!.isNotEmpty) return;
      unawaited(_fetchTokenGuarded());
    });
  }

  Future<void> disposePushHub() async {
    await _netWatcher?.cancel();
    _netWatcher = null;
  }

  Future<void> _prepareLocalNotifications() async {
    const androidInit = AndroidInitializationSettings(
      kFlameNotificationIcon,
    );
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final url = extractPushLink(Map<String, dynamic>.from(decoded));
            if (url != null) onFreshLink?.call(url);
          }
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          kFlameChannelId,
          kFlameChannelName,
          description: kFlameChannelDesc,
          importance: Importance.high,
        ),
      );
    }
  }

  /// Called by PushPromptScreen when the user opts in.
  ///
  /// If the user declined the OS dialog we flip the `os denied` flag so the
  /// prompt is never surfaced again — otherwise the 3-day skip window would
  /// eventually re-open the screen even though Accept can no longer trigger
  /// the system prompt (Android permission model).
  ///
  /// Prefers `flutter_local_notifications`' Android plugin over FCM's
  /// `requestPermission()`: on offline cold-launches Firebase might not have
  /// initialised yet (`_fcm == null`), but POST_NOTIFICATIONS is a purely
  /// local OS grant — pressing "Accept" must still show the system dialog.
  /// On iOS the local plugin also handles APNS registration through Darwin
  /// options set in `_prepareLocalNotifications()`.
  Future<bool> requestOsPermission() async {
    if (Platform.isAndroid) {
      try {
        final plugin = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted =
            (await plugin?.requestNotificationsPermission()) ?? false;
        await _vault.markPushGranted(granted);
        if (!granted) {
          // Android returns `false` for both "just now denied" and "OS-level
          // permanently denied". Either way we should stop re-asking — the
          // system dialog will never appear on subsequent calls without a
          // Settings visit. `PushPromptScreen` still writes a skip cooldown
          // on top, but that's belt-and-braces.
          await _vault.markPushOsDenied();
        }
        return granted;
      } catch (e) {
        if (kDebugMode) debugPrint('[PushHub] local-req failed: $e');
      }
    }

    // iOS + Android fallback (should rarely fire on Android).
    if (_fcm == null) return false;
    try {
      final settings = await _fcm!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      await _vault.markPushGranted(granted);
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        await _vault.markPushOsDenied();
      }
      return granted;
    } catch (_) {
      return false;
    }
  }

  void _handleForeground(RemoteMessage message) async {
    if (!Platform.isAndroid) return;
    final notification = message.notification;
    if (notification == null) return;

    Uint8List? bigPictureBytes;
    final imageUrl = notification.android?.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      bigPictureBytes = await _fetchBytes(imageUrl);
    }

    AndroidNotificationDetails details;
    if (bigPictureBytes != null) {
      details = AndroidNotificationDetails(
        kFlameChannelId,
        kFlameChannelName,
        channelDescription: kFlameChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: kFlameNotificationIcon,
        styleInformation: BigPictureStyleInformation(
          ByteArrayAndroidBitmap(bigPictureBytes),
          largeIcon:
              const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        ),
      );
    } else {
      details = const AndroidNotificationDetails(
        kFlameChannelId,
        kFlameChannelName,
        channelDescription: kFlameChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: kFlameNotificationIcon,
      );
    }

    final payload = message.data.isNotEmpty ? jsonEncode(message.data) : null;

    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  void _handleWarmTap(RemoteMessage message) {
    final url = extractPushLink(Map<String, dynamic>.from(message.data));
    if (url != null) onFreshLink?.call(url);
  }

  Future<void> _handleColdTap(RemoteMessage message) async {
    final url = extractPushLink(Map<String, dynamic>.from(message.data));
    if (url != null) await _vault.writePushLanding(url);
  }

  Future<Uint8List?> _fetchBytes(String url) async {
    try {
      final res = await deviceAgent
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {}
    return null;
  }
}

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

import 'dart:convert';
import 'dart:io';

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

  PushLinkSink? onFreshLink;
  void Function(String newToken)? onTokenRotated;

  String? get token => _token;

  Future<void> awaken() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      _fcm = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(_isolateBgHandler);

      await _prepareLocalNotifications();

      _token = await _fcm!.getToken();
      _fcm!.onTokenRefresh.listen((next) {
        _token = next;
        onTokenRotated?.call(next);
      });

      FirebaseMessaging.onMessage.listen(_handleForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleWarmTap);

      final initial = await _fcm!.getInitialMessage();
      if (initial != null) {
        await _handleColdTap(initial);
      }

      _ready = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[PushHub] disabled: $e');
      // Firebase not configured — the app continues without push, per TZ.
    }
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
  Future<bool> requestOsPermission() async {
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

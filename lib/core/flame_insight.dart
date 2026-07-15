// Crash-safe facade over Microsoft Clarity for Flame Surge.
//
// Clarity captures the native Flutter surface (loading screen, push invite,
// game menu, puzzle screen, portal WebView container). The DOM inside the
// portal WebView is invisible to replay — the funnel signals below are the
// only way to answer "where did this user drop off?" for a paid install.
//
// Every call is wrapped in `_shielded` so a Clarity SDK failure can never
// bubble up into the gray flow. Naming intentionally diverges from the
// reference implementation (FlameInsight vs Insight, FlameInsightPipe JS
// channel vs AegisInsight, etc.) to keep the Play-side fingerprint of this
// app distinct from the shared template.

import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:flutter/foundation.dart';

import '../env/insight_env.dart';

class FlameInsight {
  const FlameInsight._();

  static ClarityConfig get config => ClarityConfig(
        projectId: kFlameInsightProjectId,
        logLevel: kDebugMode ? LogLevel.Verbose : LogLevel.None,
      );

  /// Groups the current replay session by the AppsFlyer id and attaches
  /// attribution tags. No-op on empty [afId] so an unknown installer
  /// never wipes a previously-set custom user id.
  static void identify(
    String? afId, {
    Map<String, String> tags = const <String, String>{},
  }) {
    if (afId != null && afId.isNotEmpty) {
      _shielded(() => Clarity.setCustomUserId(_trim(afId, 255)));
      writeTag('aid', afId);
    }
    tags.forEach(writeTag);
  }

  /// Sets the current screen label AND emits a stable `screen_<name>`
  /// event so both label-based and event-based filters resolve the same
  /// drop-off surface.
  static void enterScreen(String name) {
    labelScreen(name);
    emit('screen_$name');
  }

  /// Sets the current screen label + mirrors it into the persistent
  /// `last_screen` tag. Clarity keeps only the LAST tag value per
  /// session, so filtering by last_screen instantly reveals where the
  /// session ended.
  static void labelScreen(String name) => _shielded(() {
        Clarity.setCurrentScreenName(_trim(name, 255));
        Clarity.setCustomTag('last_screen', _trim(name, 255));
      });

  static void emit(String name) =>
      _shielded(() => Clarity.sendCustomEvent(_trim(name, 254)));

  static void writeTag(String key, String value) {
    if (value.isEmpty) return;
    _shielded(() => Clarity.setCustomTag(key, _trim(value, 255)));
  }

  static String _trim(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  static void _shielded(void Function() body) {
    try {
      body();
    } catch (_) {
      // Silently swallow – Clarity errors must never take down the gray flow.
    }
  }
}

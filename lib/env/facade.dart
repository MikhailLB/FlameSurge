// Single lookup point for every screen/service that needs configuration.
// Values that live behind XOR are resolved lazily so the encoded byte arrays
// only decode once on first access.

import 'attribution_secrets.dart';
import 'beacon_secrets.dart';
import 'legal_endpoints.dart';

class Facade {
  Facade._();

  /// Android application id — must match android/app/build.gradle.kts.
  static const String bundleId = 'com.volcano.flamesurge';

  /// Google Play store package name (same as bundleId on Android).
  static const String storeId = 'com.volcano.flamesurge';

  /// Display name used in notifications and the User-Agent suffix.
  static const String appName = 'FlameSurge';

  /// Empty on Android; reserved for the numeric App Store id on iOS.
  static const String iosAppStoreId = '';

  /// Delay before re-showing the push permission promo after "Skip" (3 days).
  static const int notificationSkipCooldownSeconds = 3 * 24 * 60 * 60;

  /// After the first onInstallConversionData callback returns "Organic",
  /// wait this long before retrying via GCD (SDK false-positive workaround).
  static const int organicRetryDelaySeconds = 5;

  /// Cap for the parallel GCD poll when the deep link callback delivered
  /// a real click but the install callback never fired.
  static const int gcdPollMaxSeconds = 90;
  static const int gcdPollIntervalSeconds = 4;

  static String get beaconEndpoint => unmaskBeaconUri();

  static String get attributionKey => unmaskAttributionKey();

  static String get pushProjectNumber => unmaskPushProjectNumber();

  static const String homeUrl = kFlameSurgeHome;
  static const String privacyPolicyUrl = kFlameSurgePrivacyPolicy;
  static const String supportUrl = kFlameSurgeSupport;
}

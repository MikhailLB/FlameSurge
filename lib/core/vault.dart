// Persistent state store. Non-sensitive flags live in SharedPreferences;
// URLs sit inside flutter_secure_storage (Keystore-backed) so they never end
// up in an unencrypted xml file.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/runtime_stage.dart';

class Vault {
  static const String _kStage = 'runtime_stage_v1';
  static const String _kExpires = 'portal_url_expires_v1';
  static const String _kSkipUntil = 'push_prompt_skip_until_v1';
  static const String _kPushGranted = 'push_prompt_granted_v1';
  static const String _kPushOsDenied = 'push_prompt_os_denied_v1';
  static const String _kBestScore = 'best_score';

  // Kept out of shared_preferences so an APK dump does not reveal the URL.
  static const String _kPortalUrl = 'portal_url_v1';
  static const String _kPushUrl = 'push_landing_v1';

  // flutter_secure_storage 10.x deprecated the Jetpack Security-backed
  // `encryptedSharedPreferences` flag; the plugin now migrates values into a
  // custom cipher store on first access, so the default AndroidOptions are
  // enough. Kept as a field so tests can swap in a mock without touching
  // every call-site.
  final FlutterSecureStorage _safe = const FlutterSecureStorage();

  late SharedPreferences _prefs;

  Future<void> awaken() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ------------------------------------------------------------------------ //
  // Runtime stage                                                            //
  // ------------------------------------------------------------------------ //
  RuntimeStage readStage() => RuntimeStage.decode(_prefs.getString(_kStage));

  Future<void> writeStage(RuntimeStage stage) =>
      _prefs.setString(_kStage, stage.encode());

  // ------------------------------------------------------------------------ //
  // Portal URL (secure)                                                      //
  // ------------------------------------------------------------------------ //
  Future<String?> readPortalUrl() => _safe.read(key: _kPortalUrl);

  Future<void> writePortalUrl(String url) =>
      _safe.write(key: _kPortalUrl, value: url);

  Future<void> forgetPortalUrl() => _safe.delete(key: _kPortalUrl);

  int? readPortalExpires() => _prefs.getInt(_kExpires);

  Future<void> writePortalExpires(int epoch) =>
      _prefs.setInt(_kExpires, epoch);

  bool isPortalUrlExpired() {
    final expires = readPortalExpires();
    if (expires == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= expires;
  }

  // ------------------------------------------------------------------------ //
  // Cold-tap push landing                                                    //
  // ------------------------------------------------------------------------ //
  Future<String?> readPushLanding() => _safe.read(key: _kPushUrl);

  Future<void> writePushLanding(String url) =>
      _safe.write(key: _kPushUrl, value: url);

  Future<String?> pluckFreshTapLink() async {
    final url = await _safe.read(key: _kPushUrl);
    if (url != null) await _safe.delete(key: _kPushUrl);
    return url;
  }

  // ------------------------------------------------------------------------ //
  // Push permission bookkeeping                                              //
  // ------------------------------------------------------------------------ //
  bool isPushGranted() => _prefs.getBool(_kPushGranted) ?? false;

  Future<void> markPushGranted(bool granted) =>
      _prefs.setBool(_kPushGranted, granted);

  bool isPushOsDenied() => _prefs.getBool(_kPushOsDenied) ?? false;

  Future<void> markPushOsDenied() => _prefs.setBool(_kPushOsDenied, true);

  int? readPushSkipUntil() => _prefs.getInt(_kSkipUntil);

  Future<void> writePushSkipUntil(int epoch) =>
      _prefs.setInt(_kSkipUntil, epoch);

  bool shouldOfferPushPrompt() {
    if (isPushGranted()) return false;
    if (isPushOsDenied()) return false;
    final skip = readPushSkipUntil();
    if (skip == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= skip;
  }

  // ------------------------------------------------------------------------ //
  // Best score used by the white puzzle                                      //
  // ------------------------------------------------------------------------ //
  int readBestScore() => _prefs.getInt(_kBestScore) ?? 0;

  Future<void> writeBestScore(int value) => _prefs.setInt(_kBestScore, value);
}

// Posts the attribution payload to the backend and caches the verdict.
//
// The class deliberately keeps a very small surface: the splash router
// receives the raw [BeaconResponse] and decides where to navigate. All URL
// persistence goes through the Vault (secure storage).

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/beacon_response.dart';
import '../env/facade.dart';
import 'device_agent.dart';
import 'vault.dart';

class ConfigBeacon {
  ConfigBeacon(this._vault);

  final Vault _vault;

  Future<BeaconResponse> queryBeacon(Map<String, dynamic> body) async {
    if (Facade.beaconEndpoint.isEmpty) {
      return BeaconResponse.error('endpoint missing');
    }

    try {
      final response = await deviceAgent
          .post(
            Uri.parse(Facade.beaconEndpoint),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[ConfigBeacon] non-200 ${response.statusCode}');
        }
        return BeaconResponse.error(
          'http ${response.statusCode}',
          status: response.statusCode,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return BeaconResponse.error('malformed payload');
      }
      final beacon =
          BeaconResponse.fromJson(Map<String, dynamic>.from(decoded));

      if (beacon.hasUsableUrl) {
        await _vault.writePortalUrl(beacon.url!);
        if (beacon.expires != null) {
          await _vault.writePortalExpires(beacon.expires!);
        }
      }
      return beacon;
    } catch (e) {
      if (kDebugMode) debugPrint('[ConfigBeacon] error $e');
      return BeaconResponse.error(e.toString());
    }
  }

  /// Convenience accessor used by the splash router after a failed refresh:
  /// falls back to the last known URL even when it is expired.
  Future<String?> lastKnownUrl() => _vault.readPortalUrl();
}

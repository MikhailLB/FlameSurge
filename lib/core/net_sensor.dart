// Connectivity heuristic used by the splash router and PortalShell.
//
// The gray-part-pitfalls doc calls out three real-world failure modes:
//   1) VPN interfaces briefly report `none` while coming up.
//   2) DNS through a VPN tunnel can push past the 3-second probe.
//   3) The downstream WebView must not flip to No-Internet on transient blips.
//
// This class keeps the whitelist wide (VPN / bluetooth / other are treated
// as real connectivity) and the probe timeout at 7 seconds. Downstream code
// is expected to debounce the stream before navigating.

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

class NetSensor {
  NetSensor({Connectivity? connectivity})
      : _plugin = connectivity ?? Connectivity();

  final Connectivity _plugin;

  static const Set<ConnectivityResult> _liveInterfaces =
      <ConnectivityResult>{
    ConnectivityResult.wifi,
    ConnectivityResult.mobile,
    ConnectivityResult.ethernet,
    ConnectivityResult.vpn,
    ConnectivityResult.bluetooth,
    ConnectivityResult.other,
  };

  Stream<List<ConnectivityResult>> get statusStream =>
      _plugin.onConnectivityChanged;

  /// Fast probe: any real interface + DNS resolution finishes within 7s.
  Future<bool> probe() async {
    final results = await _plugin.checkConnectivity();
    if (!results.any(_liveInterfaces.contains)) return false;

    // Two independent DNS targets so a single blocked resolver
    // does not falsely report "no internet".
    const hosts = <String>['cloudflare.com', 'apple.com'];
    for (final host in hosts) {
      try {
        final answer = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 7));
        if (answer.isNotEmpty && answer.first.rawAddress.isNotEmpty) {
          return true;
        }
      } on SocketException {
        continue;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  bool isAnyLive(List<ConnectivityResult> results) =>
      results.any(_liveInterfaces.contains);
}

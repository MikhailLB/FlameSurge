// Top-level MaterialApp. Owns the singleton service references so every
// screen down the tree pulls from the same instance.
//
// It also owns the *fallback* warm-tap handler for push notifications. If a
// user taps a push while the app is in arena mode (i.e. PortalShell has not
// been mounted yet), the WebView is loaded on-the-fly and the tapped URL is
// opened. Without this, warm taps outside the portal silently no-oped and
// the user perceived it as an error.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/attribution_pipeline.dart';
import '../core/config_beacon.dart';
import '../core/net_sensor.dart';
import '../core/push_hub.dart';
import '../core/vault.dart';
import '../features/ignition/ignition_stage.dart';
import '../features/portal/portal_shell.dart' deferred as portal;
import '../utils/url_guard.dart';

class FlameSurgeRoot extends StatefulWidget {
  const FlameSurgeRoot({
    super.key,
    required this.vault,
    required this.netSensor,
    required this.attribution,
    required this.configBeacon,
    required this.pushHub,
  });

  final Vault vault;
  final NetSensor netSensor;
  final AttributionPipeline attribution;
  final ConfigBeacon configBeacon;
  final PushHub pushHub;

  @override
  State<FlameSurgeRoot> createState() => _FlameSurgeRootState();
}

class _FlameSurgeRootState extends State<FlameSurgeRoot> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  bool _handlingFallback = false;

  @override
  void initState() {
    super.initState();
    // Root-level fallback for warm taps that arrive when PortalShell isn't
    // mounted (e.g. user is in the game menu). PortalShell overrides this
    // during its lifetime and restores it back on dispose() — see its
    // `_previousHandler` snapshot.
    widget.pushHub.onFreshLink = _handleWarmTapFromRoot;
  }

  @override
  void dispose() {
    if (widget.pushHub.onFreshLink == _handleWarmTapFromRoot) {
      widget.pushHub.onFreshLink = null;
    }
    super.dispose();
  }

  Future<void> _handleWarmTapFromRoot(String rawUrl) async {
    if (_handlingFallback) return;
    final safe = sanitiseUrl(rawUrl);
    if (safe == null) return;

    _handlingFallback = true;
    try {
      final navigator = _navKey.currentState;
      if (navigator == null) return;

      await portal.loadLibrary();
      await portal.primePortal();
      if (!mounted || _navKey.currentState == null) return;

      // Relax the orientation lock so the WebView can rotate on tablets even
      // if the previous surface was arena-locked.
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => portal.PortalShell(
            entryUrl: safe.toString(),
            vault: widget.vault,
            pushHub: widget.pushHub,
            netSensor: widget.netSensor,
          ),
        ),
      );
    } catch (_) {
      // Swallow — the notification failing to open should not crash the app.
    } finally {
      _handlingFallback = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flame Surge',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF120704),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF7A1F),
          secondary: Color(0xFFFFB020),
          surface: Color(0xFF120704),
        ),
        fontFamily: 'Roboto',
      ),
      home: IgnitionStage(
        vault: widget.vault,
        netSensor: widget.netSensor,
        attribution: widget.attribution,
        configBeacon: widget.configBeacon,
        pushHub: widget.pushHub,
      ),
    );
  }
}

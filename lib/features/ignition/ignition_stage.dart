// Splash + state-machine router for the whole gray flow.
//
// State chart:
//
//   RuntimeStage.fresh   → check net → run pending flow
//                        → success  ⇒ portal (PushPrompt→PortalShell)
//                        → refusal  ⇒ arena  (game menu)
//                        → offline  ⇒ tempest screen
//
//   RuntimeStage.portal  → check net → cold-tap URL wins → try refresh
//                        → falls back to lastKnownUrl on failure
//
//   RuntimeStage.arena   → skip network entirely, go straight to game menu.
//
// Visuals: the vertical/horizontal loading webp assets already carry the
// "Flame Surge" logo, so we overlay only the animated `Loading...` label and
// a horizontal progress bar. The bar reaches 100% precisely one frame before
// the navigation call fires.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/attribution_pipeline.dart';
import '../../core/config_beacon.dart';
import '../../core/flame_insight.dart';
import '../../core/net_sensor.dart';
import '../../core/push_hub.dart';
import '../../core/vault.dart';
import '../../data/beacon_response.dart';
import '../../data/runtime_stage.dart';
import '../../utils/url_guard.dart';
import '../portal/portal_shell.dart' deferred as portal;
import '../push_prompt/push_prompt_screen.dart';
import '../tempest/tempest_screen.dart';
import '../../game/screens/game_menu_screen.dart';

class IgnitionStage extends StatefulWidget {
  const IgnitionStage({
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
  State<IgnitionStage> createState() => _IgnitionStageState();
}

class _IgnitionStageState extends State<IgnitionStage>
    with TickerProviderStateMixin {
  late final AnimationController _barCtrl;
  int _dotCount = 1;
  Timer? _dotTimer;
  bool _forceFullBar = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    FlameInsight.enterScreen('loading');

    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
    _barCtrl.animateTo(0.88, curve: Curves.easeOut);

    _dotTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() => _dotCount = (_dotCount % 3) + 1);
    });

    widget.pushHub.onTokenRotated = _handleTokenRotation;

    unawaited(_runFlow());
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    _barCtrl.dispose();
    widget.pushHub.onTokenRotated = null;
    super.dispose();
  }

  void _handleTokenRotation(String next) async {
    // Re-notify the backend so the fresh FCM token replaces the previous one.
    final locale = Platform.localeName.replaceAll('-', '_');
    final payload = await widget.attribution.assemblePayload(
      locale: locale,
      pushToken: next,
    );
    unawaited(widget.configBeacon.queryBeacon(payload));
  }

  Future<void> _runFlow() async {
    // Cold-tap URL takes precedence over the runtime stage. If the user
    // launches the app by tapping a push while it was killed, jump straight
    // to that landing page (still gated by internet). This works even from
    // AppMode.fresh (pitfalls §12).
    final coldTap = sanitiseUrl(await widget.vault.pluckFreshTapLink());
    if (coldTap != null) {
      FlameInsight.emit('route_push_link');
      final online = await widget.netSensor.probe();
      if (!online) {
        await _openTempest();
        return;
      }
      // `promptForPush: true` even on cold-tap: normally the user already
      // granted POST_NOTIFICATIONS (otherwise the FCM message wouldn't have
      // been displayed), and `shouldOfferPushPrompt()` will short-circuit for
      // them. But if the OS-level grant was revoked or the vault flag was
      // cleared, this is the last chance to re-ask — offline branches never
      // get here, so this path must be self-contained.
      await _openPortal(coldTap.toString(), promptForPush: true);
      return;
    }

    final stage = widget.vault.readStage();
    FlameInsight.writeTag('runtime_stage', stage.name);
    switch (stage) {
      case RuntimeStage.arena:
        FlameInsight.writeTag('run_mode', 'native');
        FlameInsight.emit('route_native');
        await _openArena();
        break;
      case RuntimeStage.portal:
        await _returningPortalFlow();
        break;
      case RuntimeStage.fresh:
        await _firstLaunchFlow();
        break;
    }
  }

  Future<void> _firstLaunchFlow() async {
    final online = await widget.netSensor.probe();
    if (!online) {
      FlameInsight.emit('route_offline');
      await _openTempest();
      return;
    }

    await widget.attribution.ignite();

    // 30s here (was 25s) leaves room for the three-round GCD retry that
    // kicks in inside `onInstallConversionData` when the first callback
    // returns "Organic" — pitfalls §19 documents the false-positive that
    // still surfaces even on SDK 6.18 when the referrer service is
    // unavailable or the fingerprint match lags behind the app-open.
    await Future.wait<void>(<Future<void>>[
      widget.attribution
          .awaitVerdict(timeout: const Duration(seconds: 30))
          .then((_) {}),
      widget.attribution.awaitDeepLink(timeout: const Duration(seconds: 5)),
    ]);

    // Phase 2 – GCD long-poll. Fires whenever we still lack a *definitive*
    // non-organic verdict: either the SDK never called us back, the deep
    // link clearly implies non-organic but the install body is still
    // missing, or the callback returned "Organic" (pitfalls §19). In the
    // last case the retries inside `onInstallConversionData` might have
    // beaten the AppsFlyer backend by a few seconds, so we give it a bit
    // more time before sealing the arena.
    if (widget.attribution.needsExtendedPolling) {
      await Future.any<void>(<Future<void>>[
        widget.attribution.pollGcd(
          maxSeconds: 60,
          intervalSeconds: 4,
        ),
        widget.attribution
            .awaitVerdict(timeout: const Duration(seconds: 60))
            .then((_) {}),
      ]);
    }

    final locale = Platform.localeName.replaceAll('-', '_');
    final payload = await widget.attribution.assemblePayload(
      locale: locale,
      pushToken: widget.pushHub.token,
    );
    _identifyFromPayload(payload);
    final BeaconResponse verdict =
        await widget.configBeacon.queryBeacon(payload);

    if (verdict.hasUsableUrl) {
      await widget.vault.writeStage(RuntimeStage.portal);
      FlameInsight.writeTag('run_mode', 'web');
      FlameInsight.emit('route_web');
      await _openPortal(verdict.url!, promptForPush: true);
    } else {
      await widget.vault.writeStage(RuntimeStage.arena);
      FlameInsight.writeTag('run_mode', 'native');
      FlameInsight.emit('route_native');
      await _openArena();
    }
  }

  void _identifyFromPayload(Map<String, dynamic> body) {
    FlameInsight.identify(
      body['af_id']?.toString(),
      tags: <String, String>{
        'af_status': body['af_status']?.toString() ?? '',
        'media_source': body['media_source']?.toString() ?? '',
        'campaign': body['campaign']?.toString() ?? '',
        'os': body['os']?.toString() ?? '',
        'locale': body['locale']?.toString() ?? '',
      },
    );
  }

  Future<void> _returningPortalFlow() async {
    final online = await widget.netSensor.probe();
    if (!online) {
      final savedUrl = await widget.vault.readPortalUrl();
      if (savedUrl != null && !widget.vault.isPortalUrlExpired()) {
        FlameInsight.writeTag('run_mode', 'web');
        FlameInsight.emit('route_cached_link');
        // `promptForPush: true` — POST_NOTIFICATIONS is a *local* Android
        // grant, so it works even offline. If the previous session ended
        // before the user answered the invite (cold-killed on the WebView),
        // this is the only chance to ask again on an offline relaunch.
        // `shouldOfferPushPrompt()` still gates it, so users who already
        // answered are never re-prompted here.
        await _openPortal(savedUrl, promptForPush: true);
        return;
      }
      FlameInsight.emit('route_offline');
      await _openTempest();
      return;
    }

    final savedUrl = await widget.vault.readPortalUrl();

    await widget.attribution.ignite();
    await Future.wait<void>(<Future<void>>[
      widget.attribution
          .awaitVerdict(timeout: const Duration(seconds: 10))
          .then((_) {}),
      widget.attribution.awaitDeepLink(timeout: const Duration(seconds: 4)),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final payload = await widget.attribution.assemblePayload(
      locale: locale,
      pushToken: widget.pushHub.token,
    );
    _identifyFromPayload(payload);
    final BeaconResponse verdict =
        await widget.configBeacon.queryBeacon(payload);

    // `promptForPush: true` is intentional here — the previous session's
    // portal launch may have been interrupted before the notification
    // permission screen appeared (e.g. dev restart, app killed mid-splash),
    // so we always defer the actual decision to `shouldOfferPushPrompt()`
    // below in `_openPortal`. That helper is the single source of truth
    // (granted / OS-denied / cooldown active → skip; otherwise → show).
    if (verdict.hasUsableUrl) {
      FlameInsight.writeTag('run_mode', 'web');
      FlameInsight.emit('route_web');
      await _openPortal(verdict.url!, promptForPush: true);
      return;
    }
    if (savedUrl != null) {
      FlameInsight.writeTag('run_mode', 'web');
      FlameInsight.emit('route_cached_link');
      await _openPortal(savedUrl, promptForPush: true);
      return;
    }
    FlameInsight.emit('route_offline');
    await _openTempest();
  }

  // ------------------------------------------------------------------------ //
  // Navigation helpers                                                       //
  // ------------------------------------------------------------------------ //

  Future<void> _fillBarAndYield() async {
    if (_forceFullBar) return;
    setState(() => _forceFullBar = true);
    _barCtrl.stop();
    _barCtrl.animateTo(1.0, duration: const Duration(milliseconds: 320));
    await Future<void>.delayed(const Duration(milliseconds: 380));
  }

  Future<void> _openArena() async {
    if (_navigated) return;
    _navigated = true;
    await _fillBarAndYield();
    if (!mounted) return;
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GameMenuScreen(vault: widget.vault),
      ),
    );
  }

  Future<void> _openPortal(String url, {required bool promptForPush}) async {
    if (_navigated) return;
    _navigated = true;
    await _fillBarAndYield();
    await portal.loadLibrary();
    await portal.primePortal();
    if (!mounted) return;

    final shouldAsk =
        promptForPush && widget.vault.shouldOfferPushPrompt();

    // Classify this session's push-permission stance even when we're NOT
    // showing the invite (returning-portal users, cooldown-suppressed, etc.),
    // so the `notif_permission` tag is never blank on the Clarity dashboard.
    if (!shouldAsk) {
      final String stance;
      if (widget.vault.isPushGranted()) {
        stance = 'granted';
      } else if (widget.vault.isPushOsDenied()) {
        stance = 'os_denied';
      } else {
        stance = 'snoozed';
      }
      FlameInsight.writeTag('notif_permission', stance);
    }

    if (shouldAsk) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PushPromptScreen(
            vault: widget.vault,
            pushHub: widget.pushHub,
            netSensor: widget.netSensor,
            destinationUrl: url,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => portal.PortalShell(
            entryUrl: url,
            vault: widget.vault,
            pushHub: widget.pushHub,
            netSensor: widget.netSensor,
          ),
        ),
      );
    }
  }

  Future<void> _openTempest() async {
    if (_navigated) return;
    _navigated = true;
    await _fillBarAndYield();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TempestScreen(
          retryBuilder: (_) => IgnitionStage(
            vault: widget.vault,
            netSensor: widget.netSensor,
            attribution: widget.attribution,
            configBeacon: widget.configBeacon,
            pushHub: widget.pushHub,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isPortrait = orientation == Orientation.portrait;
    final asset = isPortrait
        ? 'assets/Vertical_Loading_Screen.webp'
        : 'assets/Horizontal_Loading_Screen.webp';

    return Scaffold(
      backgroundColor: const Color(0xFF0B0503),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(asset, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.transparent,
                  Colors.transparent,
                  Color(0x66000000),
                  Color(0xC0000000),
                ],
                stops: <double>[0.0, 0.55, 0.82, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: isPortrait ? 56 : 26,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isPortrait ? 32 : 96,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _LoadingLabel(dots: _dotCount, portrait: isPortrait),
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _barCtrl,
                    builder: (_, _) => _ProgressStrip(value: _barCtrl.value),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingLabel extends StatelessWidget {
  const _LoadingLabel({required this.dots, required this.portrait});

  final int dots;
  final bool portrait;

  @override
  Widget build(BuildContext context) {
    final trail = '.' * dots + ' ' * (3 - dots);
    return Text(
      'Loading$trail',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: portrait ? 24 : 22,
        fontWeight: FontWeight.w900,
        letterSpacing: 3,
        shadows: const <Shadow>[
          Shadow(color: Color(0xFFFF7A1F), blurRadius: 14),
          Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB067), width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFF7A1F).withValues(alpha: 0.45),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    Color(0xFFFFE082),
                    Color(0xFFFFB020),
                    Color(0xFFFF6A00),
                    Color(0xFFE53935),
                  ],
                ),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0.35),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

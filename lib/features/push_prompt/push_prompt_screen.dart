// Push permission promo. The volcanic Notifications artwork already contains
// the "Allow notifications about bonuses and promos" message + the bell icon,
// so we only lay out the two action buttons over it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/flame_insight.dart';
import '../../core/net_sensor.dart';
import '../../core/push_hub.dart';
import '../../core/vault.dart';
import '../../env/facade.dart';
import '../portal/portal_shell.dart' deferred as portal;

class PushPromptScreen extends StatefulWidget {
  const PushPromptScreen({
    super.key,
    required this.vault,
    required this.pushHub,
    required this.netSensor,
    required this.destinationUrl,
  });

  final Vault vault;
  final PushHub pushHub;
  final NetSensor netSensor;
  final String destinationUrl;

  @override
  State<PushPromptScreen> createState() => _PushPromptScreenState();
}

class _PushPromptScreenState extends State<PushPromptScreen> {
  bool _acceptPressed = false;
  bool _skipPressed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    FlameInsight.enterScreen('push_invite');
    // Prompt supports both orientations — matches the two artwork variants.
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _writeSkipCooldown() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await widget.vault.writePushSkipUntil(
      now + Facade.notificationSkipCooldownSeconds,
    );
  }

  Future<void> _onAccept() async {
    if (_busy) return;
    setState(() => _busy = true);
    FlameInsight.emit('push_invite_accept');
    final granted = await widget.pushHub.requestOsPermission();
    FlameInsight.writeTag(
      'notif_permission',
      granted ? 'granted' : 'denied',
    );
    FlameInsight.emit(granted ? 'push_granted' : 'push_denied');
    if (!granted) {
      await _writeSkipCooldown();
    }
    if (!mounted) return;
    await _navigateToPortal();
  }

  Future<void> _onSkip() async {
    if (_busy) return;
    setState(() => _busy = true);
    FlameInsight.emit('push_invite_skip');
    FlameInsight.writeTag('notif_permission', 'skipped');
    await _writeSkipCooldown();
    if (!mounted) return;
    await _navigateToPortal();
  }

  Future<void> _navigateToPortal() async {
    await portal.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => portal.PortalShell(
          entryUrl: widget.destinationUrl,
          vault: widget.vault,
          pushHub: widget.pushHub,
          netSensor: widget.netSensor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isPortrait = orientation == Orientation.portrait;
    final bg = isPortrait
        ? 'assets/Vertical_Notifications_Screen.webp'
        : 'assets/Horizontal_Notifications_Screen.webp';
    final size = MediaQuery.of(context).size;

    final acceptButton = SizedBox(
      width: double.infinity,
      child: _MoltenAcceptButton(
        pressed: _acceptPressed,
        compact: !isPortrait,
        busy: _busy,
        onDown: () => setState(() => _acceptPressed = true),
        onCancel: () => setState(() => _acceptPressed = false),
        onUp: () {
          setState(() => _acceptPressed = false);
          _onAccept();
        },
      ),
    );
    final skipButton = SizedBox(
      width: double.infinity,
      child: _StoneSkipButton(
        pressed: _skipPressed,
        compact: !isPortrait,
        busy: _busy,
        onDown: () => setState(() => _skipPressed = true),
        onCancel: () => setState(() => _skipPressed = false),
        onUp: () {
          setState(() => _skipPressed = false);
          _onSkip();
        },
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0B0503),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(bg, fit: BoxFit.cover),
          if (isPortrait)
            // Portrait: buttons stacked vertically, both full-width so they
            // render at identical dimensions.
            Positioned(
              left: size.width * 0.10,
              right: size.width * 0.10,
              bottom: size.height * 0.09,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  acceptButton,
                  const SizedBox(height: 14),
                  skipButton,
                ],
              ),
            )
          else
            // Landscape: buttons side-by-side, still equal width via Expanded.
            Positioned(
              left: size.width * 0.22,
              right: size.width * 0.22,
              bottom: size.height * 0.06,
              child: Row(
                children: <Widget>[
                  Expanded(child: acceptButton),
                  const SizedBox(width: 14),
                  Expanded(child: skipButton),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Same height constant for both buttons — the "same size" requirement above.
const double _kPromptButtonHeightCompact = 52.0;
const double _kPromptButtonHeightRegular = 60.0;

class _MoltenAcceptButton extends StatelessWidget {
  const _MoltenAcceptButton({
    required this.pressed,
    required this.compact,
    required this.busy,
    required this.onDown,
    required this.onCancel,
    required this.onUp,
  });

  final bool pressed;
  final bool compact;
  final bool busy;
  final VoidCallback onDown;
  final VoidCallback onCancel;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final height =
        compact ? _kPromptButtonHeightCompact : _kPromptButtonHeightRegular;
    return GestureDetector(
      onTapDown: busy ? null : (_) => onDown(),
      onTapCancel: busy ? null : onCancel,
      onTapUp: busy ? null : (_) => onUp(),
      child: AnimatedScale(
        scale: pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0xFFFFC466),
                Color(0xFFFF7A1F),
                Color(0xFFC62828),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.85),
              width: 1.4,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFFFF7A1F).withValues(alpha: 0.55),
                blurRadius: 22,
                spreadRadius: 1.4,
              ),
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'Accept',
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 16 : 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                shadows: const <Shadow>[
                  Shadow(color: Colors.black87, blurRadius: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoneSkipButton extends StatelessWidget {
  const _StoneSkipButton({
    required this.pressed,
    required this.compact,
    required this.busy,
    required this.onDown,
    required this.onCancel,
    required this.onUp,
  });

  final bool pressed;
  final bool compact;
  final bool busy;
  final VoidCallback onDown;
  final VoidCallback onCancel;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final height =
        compact ? _kPromptButtonHeightCompact : _kPromptButtonHeightRegular;
    return GestureDetector(
      onTapDown: busy ? null : (_) => onDown(),
      onTapCancel: busy ? null : onCancel,
      onTapUp: busy ? null : (_) => onUp(),
      child: AnimatedScale(
        scale: pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF29140A), Color(0xFF0F0705)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFFFB067),
              width: 1.4,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Colors.black54,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'Skip',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: compact ? 15 : 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                shadows: const <Shadow>[
                  Shadow(color: Colors.black87, blurRadius: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

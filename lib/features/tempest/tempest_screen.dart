// Full-screen "no internet" surface using the volcanic Nowifi artwork.
//
// Uses orientation-specific webp images that already contain the copy overlay
// ("No Internet Connection" / "Check your connection and try again"). Only
// the Retry button is drawn on top of the image, positioned to match the
// composition of the artwork.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TempestScreen extends StatefulWidget {
  const TempestScreen({super.key, required this.retryBuilder});

  final WidgetBuilder retryBuilder;

  @override
  State<TempestScreen> createState() => _TempestScreenState();
}

class _TempestScreenState extends State<TempestScreen>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  bool _busy = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // Both the vertical and horizontal artwork exist — allow the device to
    // rotate freely on this surface even if we were locked to portrait by
    // the arena or the previous screen's dispose().
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: widget.retryBuilder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isPortrait = orientation == Orientation.portrait;
    final bg = isPortrait
        ? 'assets/Vertical_Nowifi_Screen.webp'
        : 'assets/no_wifi_screen_hor.png';
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0503),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(bg, fit: BoxFit.cover),
          Positioned(
            left: isPortrait ? size.width * 0.10 : size.width * 0.28,
            right: isPortrait ? size.width * 0.10 : size.width * 0.28,
            bottom:
                isPortrait ? size.height * 0.09 : size.height * 0.07,
            child: _TempestRetryButton(
              busy: _busy,
              pressed: _pressed,
              pulse: _pulse,
              onDown: () => setState(() => _pressed = true),
              onCancel: () => setState(() => _pressed = false),
              onTap: () {
                setState(() => _pressed = false);
                _retry();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TempestRetryButton extends StatelessWidget {
  const _TempestRetryButton({
    required this.busy,
    required this.pressed,
    required this.pulse,
    required this.onDown,
    required this.onCancel,
    required this.onTap,
  });

  final bool busy;
  final bool pressed;
  final AnimationController pulse;
  final VoidCallback onDown;
  final VoidCallback onCancel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onDown(),
      onTapCancel: onCancel,
      onTapUp: (_) => onTap(),
      child: AnimatedScale(
        scale: pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: AnimatedBuilder(
          animation: pulse,
          builder: (context, child) {
            final glow = 0.35 + 0.35 * pulse.value;
            return Container(
              height: 62,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFFFFC466),
                    Color(0xFFFF6A00),
                    Color(0xFFC62828),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 1.4,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFFF7A1F).withValues(alpha: glow),
                    blurRadius: 24 + 6 * pulse.value,
                    spreadRadius: 1.5,
                  ),
                  const BoxShadow(
                    color: Colors.black45,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Center(
            child: busy
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 14),
                      Text(
                        'Reconnecting…',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'Try Again',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      shadows: <Shadow>[
                        Shadow(color: Colors.black, blurRadius: 6),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

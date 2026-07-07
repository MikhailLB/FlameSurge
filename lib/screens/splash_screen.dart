import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  int _dotCount = 1;
  Timer? _dotTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );

    _progress = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.0, end: 0.30)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.30, end: 0.55)
            .chain(CurveTween(curve: Curves.linear)),
        weight: 25,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.55, end: 0.85)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 35,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.85, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 15,
      ),
    ]).animate(_controller);

    _dotTimer = Timer.periodic(const Duration(milliseconds: 380), (_) {
      if (!mounted) return;
      setState(() => _dotCount = (_dotCount % 3) + 1);
    });

    _controller.forward().whenComplete(_goHome);
  }

  Future<void> _goHome() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, Animation<double> anim, _, Widget child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Orientation orientation = MediaQuery.of(context).orientation;
    final bool isPortrait = orientation == Orientation.portrait;
    final String asset = isPortrait
        ? 'assets/Vertical_Loading_Screen.webp'
        : 'assets/Horizontal_Loading_Screen.webp';

    return Scaffold(
      backgroundColor: const Color(0xFF120704),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            asset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.transparent,
                  Colors.transparent,
                  Color(0x66000000),
                  Color(0xB3000000),
                ],
                stops: <double>[0.0, 0.55, 0.8, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: isPortrait ? 56 : 28,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isPortrait ? 32 : 80,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _LoadingText(dotCount: _dotCount, isPortrait: isPortrait),
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _progress,
                    builder: (BuildContext context, _) =>
                        _LoadingBar(value: _progress.value),
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

class _LoadingText extends StatelessWidget {
  const _LoadingText({required this.dotCount, required this.isPortrait});

  final int dotCount;
  final bool isPortrait;

  @override
  Widget build(BuildContext context) {
    final String dots = '.' * dotCount + ' ' * (3 - dotCount);
    return Text(
      'Loading$dots',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: isPortrait ? 24 : 20,
        fontWeight: FontWeight.w800,
        letterSpacing: 3,
        shadows: const <Shadow>[
          Shadow(
            color: Color(0xFFFF7A1F),
            blurRadius: 12,
          ),
          Shadow(
            color: Colors.black,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class _LoadingBar extends StatelessWidget {
  const _LoadingBar({required this.value});

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
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color(0x66FFFFFF),
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

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_screen.dart';
import 'web_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _bestScore = 0;

  @override
  void initState() {
    super.initState();
    _loadBest();
  }

  Future<void> _loadBest() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _bestScore = prefs.getInt('best_score') ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF120704),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset('assets/bg3_asset.webp', fit: BoxFit.cover),
          Container(color: const Color(0x66000000)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 24),
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: Hero(
                        tag: 'game_logo',
                        child: Image.asset(
                          'assets/Game_Name.webp',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  _BestScoreCard(best: _bestScore),
                  const SizedBox(height: 16),
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: <Widget>[
                        _MenuButton(
                          label: 'PLAY',
                          icon: Icons.play_arrow_rounded,
                          primary: true,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const GameScreen(),
                              ),
                            );
                            _loadBest();
                          },
                        ),
                        const SizedBox(height: 14),
                        _MenuButton(
                          label: 'PRIVACY POLICY',
                          icon: Icons.privacy_tip_outlined,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const WebPageScreen(
                                title: 'Privacy Policy',
                                url:
                                    'https://flamesuurge.com/privacy-policy.html',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _MenuButton(
                          label: 'SUPPORT',
                          icon: Icons.support_agent_rounded,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const WebPageScreen(
                                title: 'Support',
                                url: 'https://flamesuurge.com/support.html',
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'v1.0',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _BestScoreCard extends StatelessWidget {
  const _BestScoreCard({required this.best});

  final int best;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB067), width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFF7A1F).withValues(alpha: 0.35),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.emoji_events_rounded,
              color: Color(0xFFFFC466), size: 26),
          const SizedBox(width: 10),
          const Text(
            'BEST',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '$best',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: 1,
              shadows: <Shadow>[
                Shadow(color: Color(0xFFFF7A1F), blurRadius: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatefulWidget {
  const _MenuButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final List<Color> colors = widget.primary
        ? const <Color>[Color(0xFFFFB020), Color(0xFFFF5A00), Color(0xFFB71C1C)]
        : const <Color>[Color(0xFF3A1A0F), Color(0xFF241009)];

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: widget.primary ? 68 : 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFFFB067),
              width: widget.primary ? 2.4 : 1.6,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFFFF7A1F).withValues(
                  alpha: widget.primary ? 0.55 : 0.25,
                ),
                blurRadius: widget.primary ? 20 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(widget.icon,
                  color: Colors.white, size: widget.primary ? 32 : 24),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  fontSize: widget.primary ? 22 : 16,
                  shadows: const <Shadow>[
                    Shadow(color: Colors.black54, blurRadius: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

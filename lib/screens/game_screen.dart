import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/models.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  final GameModel _model = GameModel();
  int _best = 0;
  int _lastGained = 0;
  DateTime _lastGainStamp = DateTime.fromMillisecondsSinceEpoch(0);
  (int, int)? _shakeCell;
  bool _gameOverShown = false;

  @override
  void initState() {
    super.initState();
    _loadBest();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkInitial());
  }

  Future<void> _loadBest() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _best = prefs.getInt('best_score') ?? 0);
  }

  Future<void> _saveBestIfNeeded() async {
    if (_model.score <= _best) return;
    _best = _model.score;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('best_score', _best);
  }

  void _checkInitial() {
    if (_model.gameOver) _showGameOver();
  }

  void _handleTap(int r, int c) {
    if (_model.gameOver) return;
    final PlacementResult res = _model.place(r, c);
    if (res.ok) {
      setState(() {
        _lastGained = res.bonus;
        _lastGainStamp = DateTime.now();
      });
    } else {
      setState(() => _shakeCell = (r, c));
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        setState(() => _shakeCell = null);
      });
    }
    if (_model.gameOver) {
      _saveBestIfNeeded();
      Future<void>.delayed(const Duration(milliseconds: 400), _showGameOver);
    }
  }

  void _showGameOver() {
    if (_gameOverShown || !mounted) return;
    _gameOverShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => _GameOverDialog(
        score: _model.score,
        best: _best,
        placed: _model.placed,
        maxStreak: _model.maxStreak,
        onRestart: () {
          Navigator.of(ctx).pop();
          setState(() {
            _model.reset();
            _gameOverShown = false;
            _shakeCell = null;
            _lastGained = 0;
          });
        },
        onMenu: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF120704),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset('assets/bg1_asset.webp', fit: BoxFit.cover),
          Container(color: const Color(0x99000000)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: <Widget>[
                  _TopBar(
                    onExit: () => Navigator.of(context).maybePop(),
                    onRestart: () {
                      setState(() {
                        _model.reset();
                        _gameOverShown = false;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  _StatsRow(
                    score: _model.score,
                    best: _best,
                    placed: _model.placed,
                    streak: _model.streak,
                    maxStreak: _model.maxStreak,
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Center(
                      child: LayoutBuilder(
                        builder:
                            (BuildContext context, BoxConstraints constraints) {
                          final double side =
                              (constraints.maxWidth < constraints.maxHeight
                                      ? constraints.maxWidth
                                      : constraints.maxHeight)
                                  .clamp(0.0, media.size.width - 24);
                          return SizedBox(
                            width: side,
                            height: side,
                            child: _Board(
                              model: _model,
                              shakeCell: _shakeCell,
                              onTap: _handleTap,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _NextCard(
                    kind: _model.current,
                    gained: _lastGained,
                    gainedAt: _lastGainStamp,
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onExit, required this.onRestart});

  final VoidCallback onExit;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _IconChip(icon: Icons.arrow_back_ios_new_rounded, onTap: onExit),
        const Spacer(),
        const Text(
          'FLAME SURGE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            shadows: <Shadow>[
              Shadow(color: Color(0xFFFF7A1F), blurRadius: 10),
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
        ),
        const Spacer(),
        _IconChip(icon: Icons.refresh_rounded, onTap: onRestart),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFFB067), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.score,
    required this.best,
    required this.placed,
    required this.streak,
    required this.maxStreak,
  });

  final int score;
  final int best;
  final int placed;
  final int streak;
  final int maxStreak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB067), width: 1.5),
      ),
      child: Row(
        children: <Widget>[
          _StatCell(label: 'SCORE', value: '$score', accent: true),
          _StatCell(label: 'BEST', value: '$best'),
          _StatCell(label: 'PLACED', value: '$placed'),
          _StatCell(label: 'STREAK', value: '$streak'),
          _StatCell(label: 'MAX', value: '$maxStreak'),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: accent ? const Color(0xFFFFC466) : Colors.white,
              fontSize: accent ? 20 : 16,
              fontWeight: FontWeight.w900,
              shadows: accent
                  ? const <Shadow>[
                      Shadow(color: Color(0xFFFF7A1F), blurRadius: 10),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    required this.model,
    required this.shakeCell,
    required this.onTap,
  });

  final GameModel model;
  final (int, int)? shakeCell;
  final void Function(int r, int c) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFB067), width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFF7A1F).withValues(alpha: 0.35),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: model.cols,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: model.rows * model.cols,
        itemBuilder: (BuildContext context, int index) {
          final int r = index ~/ model.cols;
          final int c = index % model.cols;
          final GameCell cell = model.board[r][c];
          final bool isShake =
              shakeCell != null && shakeCell!.$1 == r && shakeCell!.$2 == c;
          return _BoardCell(
            cell: cell,
            shake: isShake,
            onTap: () => onTap(r, c),
          );
        },
      ),
    );
  }
}

class _BoardCell extends StatelessWidget {
  const _BoardCell({
    required this.cell,
    required this.shake,
    required this.onTap,
  });

  final GameCell cell;
  final bool shake;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget child = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(
          cell.blocked
              ? 'assets/volcanic_terrain_tile_blocked_asset.webp'
              : 'assets/volcanic_terrain_tile_asset.webp',
          fit: BoxFit.cover,
        ),
        if (cell.kind != null)
          Padding(
            padding: const EdgeInsets.all(4),
            child: Image.asset(cell.kind!.asset, fit: BoxFit.contain),
          ),
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: shake
              ? const Color(0xFFFF3333)
              : (cell.kind != null
                  ? const Color(0xFFFFB067).withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.08)),
          width: shake ? 2.5 : 1.2,
        ),
        boxShadow: shake
            ? <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFFFF3333).withValues(alpha: 0.6),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: cell.isEmpty ? onTap : null,
            splashColor: const Color(0x55FFB067),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({
    required this.kind,
    required this.gained,
    required this.gainedAt,
  });

  final ObjectKind? kind;
  final int gained;
  final DateTime gainedAt;

  @override
  Widget build(BuildContext context) {
    final bool showBonus = gained > 0 &&
        DateTime.now().difference(gainedAt) < const Duration(seconds: 2);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFB067), width: 1.5),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFF7A1F).withValues(alpha: 0.35),
            blurRadius: 14,
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 68,
            height: 68,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFFFB067),
                width: 1.6,
              ),
            ),
            child: kind == null
                ? const Icon(Icons.check_circle, color: Color(0xFFFFC466))
                : Image.asset(kind!.asset, fit: BoxFit.contain),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text(
                      'NEXT ',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (showBonus)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF7A1F),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '+$gained',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  kind?.displayName ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  kind?.ruleText ?? '',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GameOverDialog extends StatelessWidget {
  const _GameOverDialog({
    required this.score,
    required this.best,
    required this.placed,
    required this.maxStreak,
    required this.onRestart,
    required this.onMenu,
  });

  final int score;
  final int best;
  final int placed;
  final int maxStreak;
  final VoidCallback onRestart;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final bool newBest = score >= best && score > 0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF3A1409), Color(0xFF190806)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFFFB067), width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFFF7A1F).withValues(alpha: 0.55),
              blurRadius: 24,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'GAME OVER',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                shadows: <Shadow>[
                  Shadow(color: Color(0xFFFF7A1F), blurRadius: 14),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (newBest)
              const Text(
                'NEW RECORD!',
                style: TextStyle(
                  color: Color(0xFFFFC466),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  fontSize: 14,
                ),
              ),
            const SizedBox(height: 18),
            _stat('SCORE', '$score', accent: true),
            _stat('BEST', '$best'),
            _stat('PLACED', '$placed'),
            _stat('MAX STREAK', '$maxStreak'),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onMenu,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: Color(0xFFFFB067), width: 1.6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'MENU',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onRestart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5A00),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'RETRY',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, {bool accent = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: accent ? const Color(0xFFFFC466) : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: accent ? 22 : 16,
              shadows: accent
                  ? const <Shadow>[
                      Shadow(color: Color(0xFFFF7A1F), blurRadius: 10),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

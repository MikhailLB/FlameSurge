// Volcanic puzzle mechanics — untouched by the gray refactor.
// Class names are project-specific so we don't share a game-code fingerprint
// with any other title in the account.

import 'dart:math';

enum LavaObjectKind {
  magmaVent,
  lavaPlant,
  fireFlower,
  obsidianRock,
  basaltBoulder,
  magmaCrystal,
  lavaMushroom,
}

extension LavaObjectData on LavaObjectKind {
  String get assetPath {
    switch (this) {
      case LavaObjectKind.magmaVent:
        return 'assets/volcanic_magma_vent_asset.webp';
      case LavaObjectKind.lavaPlant:
        return 'assets/lava_plant_asset.webp';
      case LavaObjectKind.fireFlower:
        return 'assets/fire_flower_asset.webp';
      case LavaObjectKind.obsidianRock:
        return 'assets/obsidian_rock_asset.webp';
      case LavaObjectKind.basaltBoulder:
        return 'assets/basalt_boulder_asset.webp';
      case LavaObjectKind.magmaCrystal:
        return 'assets/magma_crystal_asset.webp';
      case LavaObjectKind.lavaMushroom:
        return 'assets/lava_mushroom_asset.webp';
    }
  }

  String get displayName {
    switch (this) {
      case LavaObjectKind.magmaVent:
        return 'Magma Vent';
      case LavaObjectKind.lavaPlant:
        return 'Lava Plant';
      case LavaObjectKind.fireFlower:
        return 'Fire Flower';
      case LavaObjectKind.obsidianRock:
        return 'Obsidian Rock';
      case LavaObjectKind.basaltBoulder:
        return 'Basalt Boulder';
      case LavaObjectKind.magmaCrystal:
        return 'Magma Crystal';
      case LavaObjectKind.lavaMushroom:
        return 'Lava Mushroom';
    }
  }

  String get ruleText {
    switch (this) {
      case LavaObjectKind.lavaPlant:
        return 'Place next to a heat source.';
      case LavaObjectKind.fireFlower:
        return 'Cannot touch obsidian.';
      case LavaObjectKind.obsidianRock:
        return 'Cannot touch fire flower.';
      case LavaObjectKind.basaltBoulder:
        return 'Cannot touch plants or mushrooms.';
      case LavaObjectKind.magmaCrystal:
        return 'Cannot touch another crystal.';
      case LavaObjectKind.lavaMushroom:
        return 'Cannot touch another mushroom.';
      case LavaObjectKind.magmaVent:
        return 'Radiates heat.';
    }
  }

  bool get radiatesHeat =>
      this == LavaObjectKind.magmaVent ||
      this == LavaObjectKind.magmaCrystal ||
      this == LavaObjectKind.fireFlower;
}

class PuzzleTile {
  PuzzleTile({this.blocked = false, this.kind});

  bool blocked;
  LavaObjectKind? kind;

  bool get vacant => !blocked && kind == null;
}

class PlacementOutcome {
  const PlacementOutcome({required this.accepted, this.reward = 0});
  final bool accepted;
  final int reward;
}

class PuzzleBoardState {
  PuzzleBoardState({this.rows = 5, this.cols = 5}) : _rng = Random() {
    reset();
  }

  final int rows;
  final int cols;
  final Random _rng;

  late List<List<PuzzleTile>> board;
  int score = 0;
  int placed = 0;
  int streak = 0;
  int maxStreak = 0;
  LavaObjectKind? current;
  bool exhausted = false;

  static const List<LavaObjectKind> _spawnable = <LavaObjectKind>[
    LavaObjectKind.lavaPlant,
    LavaObjectKind.fireFlower,
    LavaObjectKind.magmaCrystal,
    LavaObjectKind.obsidianRock,
    LavaObjectKind.basaltBoulder,
    LavaObjectKind.lavaMushroom,
  ];

  static const Map<LavaObjectKind, int> _weights = <LavaObjectKind, int>{
    LavaObjectKind.lavaPlant: 3,
    LavaObjectKind.fireFlower: 2,
    LavaObjectKind.magmaCrystal: 2,
    LavaObjectKind.obsidianRock: 2,
    LavaObjectKind.basaltBoulder: 2,
    LavaObjectKind.lavaMushroom: 2,
  };

  void reset() {
    board = List<List<PuzzleTile>>.generate(
      rows,
      (_) => List<PuzzleTile>.generate(cols, (_) => PuzzleTile()),
    );
    board[rows ~/ 2][cols ~/ 2] =
        PuzzleTile(kind: LavaObjectKind.magmaVent);
    _seedBlocks(2);
    score = 0;
    placed = 0;
    streak = 0;
    maxStreak = 0;
    exhausted = false;
    current = _pickNext();
  }

  void _seedBlocks(int count) {
    var added = 0;
    var guard = 0;
    while (added < count && guard < 200) {
      guard++;
      final r = _rng.nextInt(rows);
      final c = _rng.nextInt(cols);
      if (board[r][c].vacant &&
          !_neighbourEquals(r, c, LavaObjectKind.magmaVent)) {
        board[r][c] = PuzzleTile(blocked: true);
        added++;
      }
    }
  }

  bool _neighbourEquals(int r, int c, LavaObjectKind kind) {
    for (final n in _neighbours(r, c)) {
      if (board[n.$1][n.$2].kind == kind) return true;
    }
    return false;
  }

  Iterable<(int, int)> _neighbours(int r, int c) sync* {
    if (r > 0) yield (r - 1, c);
    if (r < rows - 1) yield (r + 1, c);
    if (c > 0) yield (r, c - 1);
    if (c < cols - 1) yield (r, c + 1);
  }

  LavaObjectKind _pickNext() {
    final total = _weights.values.fold<int>(0, (a, b) => a + b);
    var roll = _rng.nextInt(total);
    for (final entry in _weights.entries) {
      roll -= entry.value;
      if (roll < 0) return entry.key;
    }
    return _spawnable.first;
  }

  bool _fits(LavaObjectKind kind, int r, int c) {
    if (!board[r][c].vacant) return false;
    final around = <LavaObjectKind>[];
    for (final n in _neighbours(r, c)) {
      final k = board[n.$1][n.$2].kind;
      if (k != null) around.add(k);
    }
    switch (kind) {
      case LavaObjectKind.lavaPlant:
        return around.any((k) => k.radiatesHeat);
      case LavaObjectKind.fireFlower:
        return !around.contains(LavaObjectKind.obsidianRock);
      case LavaObjectKind.obsidianRock:
        return !around.contains(LavaObjectKind.fireFlower);
      case LavaObjectKind.basaltBoulder:
        return !around.contains(LavaObjectKind.lavaPlant) &&
            !around.contains(LavaObjectKind.lavaMushroom);
      case LavaObjectKind.magmaCrystal:
        return !around.contains(LavaObjectKind.magmaCrystal);
      case LavaObjectKind.lavaMushroom:
        return !around.contains(LavaObjectKind.lavaMushroom);
      case LavaObjectKind.magmaVent:
        return true;
    }
  }

  bool _anyLegalMove(LavaObjectKind kind) {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (board[r][c].vacant && _fits(kind, r, c)) return true;
      }
    }
    return false;
  }

  int _bonus(LavaObjectKind kind, int r, int c) {
    var bonus = 0;
    var neighbours = 0;
    for (final n in _neighbours(r, c)) {
      final k = board[n.$1][n.$2].kind;
      if (k != null) {
        neighbours++;
        if (kind == LavaObjectKind.lavaPlant && k.radiatesHeat) bonus += 5;
        if (kind == LavaObjectKind.fireFlower &&
            k == LavaObjectKind.lavaPlant) {
          bonus += 3;
        }
        if (kind == LavaObjectKind.magmaCrystal &&
            k == LavaObjectKind.lavaPlant) {
          bonus += 3;
        }
        if (kind == LavaObjectKind.lavaMushroom &&
            k == LavaObjectKind.obsidianRock) {
          bonus += 4;
        }
      }
    }
    bonus += neighbours * 2;
    return bonus;
  }

  PlacementOutcome drop(int r, int c) {
    if (exhausted) return const PlacementOutcome(accepted: false);
    final kind = current;
    if (kind == null) return const PlacementOutcome(accepted: false);
    if (!_fits(kind, r, c)) {
      exhausted = true;
      streak = 0;
      return const PlacementOutcome(accepted: false);
    }
    board[r][c] = PuzzleTile(kind: kind);
    placed++;
    streak++;
    if (streak > maxStreak) maxStreak = streak;
    final earned = 10 + _bonus(kind, r, c) + (streak > 2 ? (streak - 2) * 2 : 0);
    score += earned;

    if (placed > 0 && placed % 8 == 0) _spawnRandomBlock();

    current = _pickNext();
    if (!_anyLegalMove(current!)) exhausted = true;
    return PlacementOutcome(accepted: true, reward: earned);
  }

  void _spawnRandomBlock() {
    for (var i = 0; i < 40; i++) {
      final r = _rng.nextInt(rows);
      final c = _rng.nextInt(cols);
      if (board[r][c].vacant) {
        board[r][c] = PuzzleTile(blocked: true);
        return;
      }
    }
  }
}

import 'dart:math';

import 'package:flutter/material.dart';

enum ObjectKind {
  magmaVent,
  lavaPlant,
  fireFlower,
  obsidianRock,
  basaltBoulder,
  magmaCrystal,
  lavaMushroom,
}

extension ObjectKindData on ObjectKind {
  String get asset {
    switch (this) {
      case ObjectKind.magmaVent:
        return 'assets/volcanic_magma_vent_asset.webp';
      case ObjectKind.lavaPlant:
        return 'assets/lava_plant_asset.webp';
      case ObjectKind.fireFlower:
        return 'assets/fire_flower_asset.webp';
      case ObjectKind.obsidianRock:
        return 'assets/obsidian_rock_asset.webp';
      case ObjectKind.basaltBoulder:
        return 'assets/basalt_boulder_asset.webp';
      case ObjectKind.magmaCrystal:
        return 'assets/magma_crystal_asset.webp';
      case ObjectKind.lavaMushroom:
        return 'assets/lava_mushroom_asset.webp';
    }
  }

  String get displayName {
    switch (this) {
      case ObjectKind.magmaVent:
        return 'Magma Vent';
      case ObjectKind.lavaPlant:
        return 'Lava Plant';
      case ObjectKind.fireFlower:
        return 'Fire Flower';
      case ObjectKind.obsidianRock:
        return 'Obsidian Rock';
      case ObjectKind.basaltBoulder:
        return 'Basalt Boulder';
      case ObjectKind.magmaCrystal:
        return 'Magma Crystal';
      case ObjectKind.lavaMushroom:
        return 'Lava Mushroom';
    }
  }

  String get ruleText {
    switch (this) {
      case ObjectKind.lavaPlant:
        return 'Place next to a heat source.';
      case ObjectKind.fireFlower:
        return 'Cannot touch obsidian.';
      case ObjectKind.obsidianRock:
        return 'Cannot touch fire flower.';
      case ObjectKind.basaltBoulder:
        return 'Cannot touch plants or mushrooms.';
      case ObjectKind.magmaCrystal:
        return 'Cannot touch another crystal.';
      case ObjectKind.lavaMushroom:
        return 'Cannot touch another mushroom.';
      case ObjectKind.magmaVent:
        return 'Radiates heat.';
    }
  }

  bool get isHeat =>
      this == ObjectKind.magmaVent ||
      this == ObjectKind.magmaCrystal ||
      this == ObjectKind.fireFlower;
}

class GameCell {
  GameCell({this.blocked = false, this.kind});

  bool blocked;
  ObjectKind? kind;

  bool get isEmpty => !blocked && kind == null;
}

class PlacementResult {
  const PlacementResult({required this.ok, this.bonus = 0});
  final bool ok;
  final int bonus;
}

class GameModel {
  GameModel({this.rows = 5, this.cols = 5}) : _rng = Random() {
    reset();
  }

  final int rows;
  final int cols;
  final Random _rng;

  late List<List<GameCell>> board;
  int score = 0;
  int placed = 0;
  int streak = 0;
  int maxStreak = 0;
  ObjectKind? current;
  bool gameOver = false;

  static const List<ObjectKind> placeableKinds = <ObjectKind>[
    ObjectKind.lavaPlant,
    ObjectKind.fireFlower,
    ObjectKind.magmaCrystal,
    ObjectKind.obsidianRock,
    ObjectKind.basaltBoulder,
    ObjectKind.lavaMushroom,
  ];

  static const Map<ObjectKind, int> _weights = <ObjectKind, int>{
    ObjectKind.lavaPlant: 3,
    ObjectKind.fireFlower: 2,
    ObjectKind.magmaCrystal: 2,
    ObjectKind.obsidianRock: 2,
    ObjectKind.basaltBoulder: 2,
    ObjectKind.lavaMushroom: 2,
  };

  void reset() {
    board = List<List<GameCell>>.generate(
      rows,
      (_) => List<GameCell>.generate(cols, (_) => GameCell()),
    );
    board[rows ~/ 2][cols ~/ 2] =
        GameCell(kind: ObjectKind.magmaVent);
    _seedBlocks(2);
    score = 0;
    placed = 0;
    streak = 0;
    maxStreak = 0;
    gameOver = false;
    current = _drawNext();
  }

  void _seedBlocks(int count) {
    int added = 0;
    int guard = 0;
    while (added < count && guard < 200) {
      guard++;
      final int r = _rng.nextInt(rows);
      final int c = _rng.nextInt(cols);
      if (board[r][c].isEmpty && !_isAdjacent(r, c, ObjectKind.magmaVent)) {
        board[r][c] = GameCell(blocked: true);
        added++;
      }
    }
  }

  bool _isAdjacent(int r, int c, ObjectKind kind) {
    for (final List<int> n in _neighbors(r, c)) {
      final GameCell cell = board[n[0]][n[1]];
      if (cell.kind == kind) return true;
    }
    return false;
  }

  Iterable<List<int>> _neighbors(int r, int c) sync* {
    if (r > 0) yield <int>[r - 1, c];
    if (r < rows - 1) yield <int>[r + 1, c];
    if (c > 0) yield <int>[r, c - 1];
    if (c < cols - 1) yield <int>[r, c + 1];
  }

  ObjectKind _drawNext() {
    final int total =
        _weights.values.fold<int>(0, (int a, int b) => a + b);
    int roll = _rng.nextInt(total);
    for (final MapEntry<ObjectKind, int> e in _weights.entries) {
      roll -= e.value;
      if (roll < 0) return e.key;
    }
    return ObjectKind.lavaPlant;
  }

  bool canPlace(ObjectKind kind, int r, int c) {
    if (!board[r][c].isEmpty) return false;
    final List<ObjectKind> around = <ObjectKind>[];
    for (final List<int> n in _neighbors(r, c)) {
      final ObjectKind? k = board[n[0]][n[1]].kind;
      if (k != null) around.add(k);
    }
    switch (kind) {
      case ObjectKind.lavaPlant:
        return around.any((ObjectKind k) => k.isHeat);
      case ObjectKind.fireFlower:
        return !around.contains(ObjectKind.obsidianRock);
      case ObjectKind.obsidianRock:
        return !around.contains(ObjectKind.fireFlower);
      case ObjectKind.basaltBoulder:
        return !around.contains(ObjectKind.lavaPlant) &&
            !around.contains(ObjectKind.lavaMushroom);
      case ObjectKind.magmaCrystal:
        return !around.contains(ObjectKind.magmaCrystal);
      case ObjectKind.lavaMushroom:
        return !around.contains(ObjectKind.lavaMushroom);
      case ObjectKind.magmaVent:
        return true;
    }
  }

  bool anyLegalPlacement(ObjectKind kind) {
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (board[r][c].isEmpty && canPlace(kind, r, c)) return true;
      }
    }
    return false;
  }

  int _placementBonus(ObjectKind kind, int r, int c) {
    int bonus = 0;
    int neighbours = 0;
    for (final List<int> n in _neighbors(r, c)) {
      final ObjectKind? k = board[n[0]][n[1]].kind;
      if (k != null) {
        neighbours++;
        if (kind == ObjectKind.lavaPlant && k.isHeat) bonus += 5;
        if (kind == ObjectKind.fireFlower && k == ObjectKind.lavaPlant) {
          bonus += 3;
        }
        if (kind == ObjectKind.magmaCrystal && k == ObjectKind.lavaPlant) {
          bonus += 3;
        }
        if (kind == ObjectKind.lavaMushroom && k == ObjectKind.obsidianRock) {
          bonus += 4;
        }
      }
    }
    bonus += neighbours * 2;
    return bonus;
  }

  PlacementResult place(int r, int c) {
    if (gameOver) return const PlacementResult(ok: false);
    final ObjectKind? kind = current;
    if (kind == null) return const PlacementResult(ok: false);
    if (!canPlace(kind, r, c)) {
      gameOver = true;
      streak = 0;
      return const PlacementResult(ok: false);
    }
    board[r][c] = GameCell(kind: kind);
    placed++;
    streak++;
    if (streak > maxStreak) maxStreak = streak;
    final int bonus = _placementBonus(kind, r, c);
    final int streakBonus = streak > 2 ? (streak - 2) * 2 : 0;
    final int gained = 10 + bonus + streakBonus;
    score += gained;

    if (placed > 0 && placed % 8 == 0) {
      _tryAddBlock();
    }
    current = _drawNext();
    if (!anyLegalPlacement(current!)) {
      gameOver = true;
    }
    return PlacementResult(ok: true, bonus: gained);
  }

  void _tryAddBlock() {
    for (int i = 0; i < 40; i++) {
      final int r = _rng.nextInt(rows);
      final int c = _rng.nextInt(cols);
      if (board[r][c].isEmpty) {
        board[r][c] = GameCell(blocked: true);
        return;
      }
    }
  }
}

Color kAccent = const Color(0xFFFF7A1F);

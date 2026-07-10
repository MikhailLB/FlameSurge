// -----------------------------------------------------------------------------
// mask.dart — obfuscation shell for Flame Surge
// -----------------------------------------------------------------------------
// The gray flow keeps a small number of high-signal strings (backend host,
// attribution key, Firebase project number, browser UA fragments) as byte
// arrays that never appear in plain text inside the APK. The array is XOR-ed
// against a 16-byte stream that is derived from a per-project seed.
//
// To rotate the whole binary fingerprint pick a new `_seedPhrase` value and
// re-run `dart run tool/encode_secrets.dart` so every downstream byte array
// is regenerated with the new key. Do NOT copy seeds between projects.
// -----------------------------------------------------------------------------

import 'dart:typed_data';

// Seed unique to this project. 9 ASCII characters – any change here MUST be
// followed by re-encoding every downstream byte array (tool/encode_secrets.dart).
const String _seedPhrase = 'pyroclast';

Uint8List _forgeStream() {
  final seedBytes = _seedPhrase.codeUnits;
  int rolling = 0x811C9DC5; // FNV-1a offset basis
  for (final b in seedBytes) {
    rolling = (rolling ^ b) & 0xFFFFFFFF;
    rolling = (rolling * 0x01000193) & 0xFFFFFFFF;
  }

  final stream = Uint8List(16);
  int state = rolling;
  for (var i = 0; i < stream.length; i++) {
    // xorshift32 → keeps the pattern away from LCG residues that show up in
    // other gray-flow projects (which use `v = v*1103515245 + 12345`).
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= (state >> 17) & 0xFFFFFFFF;
    state ^= (state << 5) & 0xFFFFFFFF;
    state &= 0xFFFFFFFF;
    stream[i] = state & 0xFF;
  }
  return stream;
}

final Uint8List _stream = _forgeStream();

/// XOR-decodes a byte array back to its plain-text string.
/// Feed only arrays produced by tool/encode_secrets.dart with the matching seed.
String unmask(List<int> payload) {
  if (payload.isEmpty) return '';
  final out = Uint8List(payload.length);
  final len = _stream.length;
  for (var i = 0; i < payload.length; i++) {
    out[i] = payload[i] ^ _stream[i % len];
  }
  return String.fromCharCodes(out);
}

/// Exposed for tool/encode_secrets.dart only. Returns the raw stream bytes so
/// the CLI can XOR fresh plaintexts against the same key.
Uint8List debugStream() => Uint8List.fromList(_stream);

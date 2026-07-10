// Command-line helper: generates XOR-encoded byte arrays for the gray flow.
// Run with `dart run tool/encode_secrets.dart` — never through PowerShell loops
// because 32-bit integer overflow on Windows silently corrupts the output.
//
// Fill in the placeholders below with your real values, run the script, then
// paste the printed arrays into the corresponding `env/*_secrets.dart` file.

import 'dart:typed_data';
import 'package:flame_surge/utils/mask.dart';

void main() {
  const inputs = <String, String>{
    // net info
    'beacon_host': 'https://flamesuurge.com',
    'beacon_path': '/config.php',

    // attribution info — DO NOT commit plaintext values.
    // Fill locally, run the tool, paste the printed bytes into env/*_secrets.dart,
    // then reset this file back to the empty placeholders before committing.
    'attribution_key': '',
    'push_project_number': '',
    'gcd_host': 'https://gcdsdk.appsflyer.com',
    'gcd_path': '/install_data/v4.0/',

    // device UA fragments
    'chrome_version': '149.0.7827.163',
    'webkit_version': '537.36',
  };

  final stream = debugStream();

  final out = StringBuffer();
  inputs.forEach((label, plaintext) {
    if (plaintext.isEmpty) {
      out.writeln('// $label → <empty> (fill later)');
      out.writeln('const List<int> $label = <int>[];');
      out.writeln();
      return;
    }
    final bytes = Uint8List.fromList(plaintext.codeUnits);
    final encoded = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      encoded[i] = bytes[i] ^ stream[i % stream.length];
    }
    out.writeln('// $label → "$plaintext" (${encoded.length} bytes)');
    out.write('const List<int> $label = <int>[');
    for (var i = 0; i < encoded.length; i++) {
      if (i > 0) out.write(', ');
      out.write('0x${encoded[i].toRadixString(16).padLeft(2, '0')}');
    }
    out.writeln('];');
    out.writeln();
  });

  // sanity check — decode every non-empty entry
  out.writeln('// --- sanity check ---');
  inputs.forEach((label, plaintext) {
    if (plaintext.isEmpty) return;
    final bytes = Uint8List.fromList(plaintext.codeUnits);
    final encoded = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      encoded[i] = bytes[i] ^ stream[i % stream.length];
    }
    final decoded = unmask(encoded);
    out.writeln('// $label round-trip: '
        '${decoded == plaintext ? 'OK' : 'FAIL — decoded="$decoded"'}');
  });

  // ignore: avoid_print
  print(out.toString());
}

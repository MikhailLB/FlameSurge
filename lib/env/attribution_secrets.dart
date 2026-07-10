// Attribution / push project credentials.
// Byte arrays are populated by `dart run tool/encode_secrets.dart` once real
// values arrive from the manager. Empty arrays make the flow gracefully
// degrade: AppsFlyer never inits, GCD polling is skipped, Firebase project id
// is omitted from the config request body.

import '../utils/mask.dart';

const List<int> _attributionKey = <int>[
  0x90, 0xad, 0x9b, 0xa8, 0x3c, 0xf7, 0x41, 0x8f,
  0xf8, 0xa4, 0xfa, 0x11, 0x3a, 0xec, 0x20, 0x30,
  0xae, 0xb6, 0x97, 0x85, 0x46, 0xf6,
];

const List<int> _pushProjectNumber = <int>[
  0xe9, 0xce, 0x9a, 0xf0, 0x3e, 0x80, 0x00, 0xf9,
  0x9d, 0xd3, 0x8d, 0x66,
];

const List<int> _gcdHost = <int>[
  0xb3, 0x8f, 0xd7, 0xb9, 0x7d, 0x88, 0x1e, 0xee,
  0xca, 0x85, 0xdd, 0x24, 0x66, 0xfd, 0x3d, 0x67,
  0xab, 0x8b, 0xd0, 0xaf, 0x62, 0xcb, 0x54, 0xb3,
  0x83, 0x85, 0xd6, 0x3a,
];

const List<int> _gcdPath = <int>[
  0xf4, 0x92, 0xcd, 0xba, 0x7a, 0xd3, 0x5d, 0xad,
  0xf2, 0x82, 0xd8, 0x23, 0x63, 0xb9, 0x65, 0x32,
  0xf5, 0xcb, 0x8c,
];

String unmaskAttributionKey() =>
    _attributionKey.isEmpty ? '' : unmask(_attributionKey);

String unmaskPushProjectNumber() =>
    _pushProjectNumber.isEmpty ? '' : unmask(_pushProjectNumber);

/// Builds the URL used to hit the AppsFlyer GCD (Get Conversion Data) API.
/// Returns empty string when the host bytes are absent (skips retry entirely).
String buildGcdUri({required String appId, required String deviceId}) {
  if (_gcdHost.isEmpty || _gcdPath.isEmpty) return '';
  final host = unmask(_gcdHost);
  final path = unmask(_gcdPath);
  return '$host$path$appId?device_id=$deviceId';
}

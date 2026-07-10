// Attribution / push project credentials.
// Byte arrays are populated by `dart run tool/encode_secrets.dart` once real
// values arrive from the manager. Empty arrays make the flow gracefully
// degrade: AppsFlyer never inits, GCD polling is skipped, Firebase project id
// is omitted from the config request body.

import '../utils/mask.dart';

const List<int> _attributionKey = <int>[
  // TODO: paste bytes from encode_secrets.dart once the AppsFlyer key lands.
];

const List<int> _pushProjectNumber = <int>[
  // TODO: paste bytes from encode_secrets.dart once the Firebase project number lands.
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

// Browser version fragments used by the User-Agent builder. XOR-encoded so
// they don't stand out as version literals in static analysis of the binary.

import '../utils/mask.dart';

const List<int> _chromeVersion = <int>[
  0xea, 0xcf, 0x9a, 0xe7, 0x3e, 0x9c, 0x06, 0xf9,
  0x9f, 0xd1, 0x97, 0x66, 0x34, 0xa5,
];

const List<int> _webkitVersion = <int>[
  0xee, 0xc8, 0x94, 0xe7, 0x3d, 0x84,
];

String unmaskChromeVersion() =>
    _chromeVersion.isEmpty ? '' : unmask(_chromeVersion);

String unmaskWebkitVersion() =>
    _webkitVersion.isEmpty ? '' : unmask(_webkitVersion);

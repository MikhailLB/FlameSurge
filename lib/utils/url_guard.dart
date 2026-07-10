// Guards against opaque URIs slipping into the WebView (test payloads such as
// AppsFlyer's `deep_link_test`, malformed strings, etc.). Only http/https URLs
// with a real authority survive.
Uri? sanitiseUrl(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null) return null;
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
  if (!parsed.hasAuthority) return null;
  return parsed;
}

/// Push notification payloads use different key aliases in different
/// campaigns. Walk the well-known keys and return the first URL that passes
/// [sanitiseUrl].
String? extractPushLink(Map<String, dynamic> data) {
  const keys = <String>[
    'url',
    'link',
    'landing_page',
    'redirect_url',
    'deep_link_value',
  ];
  for (final k in keys) {
    final v = data[k];
    if (v is! String) continue;
    final sanitised = sanitiseUrl(v);
    if (sanitised != null) return sanitised.toString();
  }
  return null;
}

// Wire-level model returned by the backend config endpoint.
//
// Successful gray verdict:
//   { "ok": true, "url": "https://...", "expires": 1720000000 }
// Refusal (organic install, etc.):
//   { "ok": false, "message": "organic" }

class BeaconResponse {
  const BeaconResponse({
    required this.ok,
    this.url,
    this.expires,
    this.message,
    this.rawStatus,
  });

  factory BeaconResponse.fromJson(Map<String, dynamic> json) {
    return BeaconResponse(
      ok: json['ok'] == true,
      url: json['url'] as String?,
      expires: (json['expires'] is int) ? json['expires'] as int : null,
      message: json['message'] as String?,
    );
  }

  factory BeaconResponse.error(String message, {int? status}) {
    return BeaconResponse(ok: false, message: message, rawStatus: status);
  }

  final bool ok;
  final String? url;
  final int? expires;
  final String? message;
  final int? rawStatus;

  bool get hasUsableUrl => ok && url != null && url!.trim().isNotEmpty;
}

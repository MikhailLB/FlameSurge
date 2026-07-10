// Small WebView used from the game menu to display privacy policy / support.
// Kept intentionally minimal – no cookies, no third-party file picker – so it
// doesn't accidentally pull in the same fingerprint as the PortalShell.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class LegalReader extends StatefulWidget {
  const LegalReader({
    super.key,
    required this.heading,
    required this.url,
  });

  final String heading;
  final String url;

  @override
  State<LegalReader> createState() => _LegalReaderState();
}

class _LegalReaderState extends State<LegalReader> {
  late final WebViewController _ctrl;
  double _progress = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF120704))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p / 100.0),
        onPageStarted: (_) => setState(() {
          _loading = true;
          _progress = 0;
        }),
        onPageFinished: (_) => setState(() {
          _loading = false;
          _progress = 1;
        }),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF120704),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C0A05),
        foregroundColor: Colors.white,
        title: Text(
          widget.heading,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        elevation: 0,
      ),
      body: Column(
        children: <Widget>[
          if (_loading)
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.black,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFF7A1F),
              ),
              minHeight: 3,
            )
          else
            const SizedBox(height: 3),
          Expanded(child: WebViewWidget(controller: _ctrl)),
        ],
      ),
    );
  }
}

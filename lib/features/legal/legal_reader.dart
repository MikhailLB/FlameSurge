// Small WebView used from the game menu to display privacy policy / support.
// Kept intentionally minimal – no cookies, no third-party file picker – so it
// doesn't accidentally pull in the same fingerprint as the PortalShell.
//
// Two visual modes:
//   * default (`lightMode: false`) – volcanic dark theme, matches the rest of
//     the game menu (used for Support).
//   * `lightMode: true`            – pure white styling: white Scaffold, white
//     AppBar with dark title, white WebView background, and a CSS overlay
//     injected once the page is rendered so partner-hosted HTML that ships a
//     dark stylesheet still reads on a white page (used for Privacy Policy).

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class LegalReader extends StatefulWidget {
  const LegalReader({
    super.key,
    required this.heading,
    required this.url,
    this.lightMode = false,
  });

  final String heading;
  final String url;
  final bool lightMode;

  @override
  State<LegalReader> createState() => _LegalReaderState();
}

class _LegalReaderState extends State<LegalReader> {
  late final WebViewController _ctrl;
  double _progress = 0;
  bool _loading = true;

  static const String _kLightModeCss = '''
    html, body {
      background: #ffffff !important;
      color: #111111 !important;
    }
    body * {
      background-color: transparent !important;
      color: #111111 !important;
      border-color: #d0d0d0 !important;
    }
    a, a:visited { color: #1a4bb8 !important; }
    h1, h2, h3, h4, h5, h6, strong, b { color: #000000 !important; }
    hr { border-color: #d0d0d0 !important; }
    table, td, th { border-color: #d0d0d0 !important; }
  ''';

  Future<void> _applyLightModeCss() async {
    // Inject a <style> tag rather than mutating individual elements so any
    // late-loaded DOM nodes (e.g. from analytics scripts) inherit the theme.
    final escaped = _kLightModeCss
        .replaceAll('\\', '\\\\')
        .replaceAll('`', '\\`')
        .replaceAll('\n', ' ');
    final js = '''
      (function() {
        var s = document.getElementById('__flamesurge_legal_light__');
        if (!s) {
          s = document.createElement('style');
          s.id = '__flamesurge_legal_light__';
          s.type = 'text/css';
          document.head.appendChild(s);
        }
        s.innerHTML = `$escaped`;
      })();
    ''';
    try {
      await _ctrl.runJavaScript(js);
    } catch (_) {
      // Ignore — the page may have navigated away before the injection lands.
    }
  }

  @override
  void initState() {
    super.initState();
    final Color webBg = widget.lightMode
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF120704);

    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(webBg)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p / 100.0),
        onPageStarted: (_) => setState(() {
          _loading = true;
          _progress = 0;
        }),
        onPageFinished: (_) async {
          if (widget.lightMode) {
            await _applyLightModeCss();
          }
          if (mounted) {
            setState(() {
              _loading = false;
              _progress = 1;
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lightMode) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF111111),
          surfaceTintColor: Colors.white,
          iconTheme: const IconThemeData(color: Color(0xFF111111)),
          title: Text(
            widget.heading,
            style: const TextStyle(
              color: Color(0xFF111111),
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
                backgroundColor: const Color(0xFFE0E0E0),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF111111),
                ),
                minHeight: 3,
              )
            else
              const SizedBox(height: 3),
            Expanded(
              child: Container(
                color: Colors.white,
                child: WebViewWidget(controller: _ctrl),
              ),
            ),
          ],
        ),
      );
    }

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

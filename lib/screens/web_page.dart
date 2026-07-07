import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebPageScreen extends StatefulWidget {
  const WebPageScreen({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _controller;
  double _progress = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF120704))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int p) => setState(() => _progress = p / 100.0),
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() {
            _loading = false;
            _progress = 1.0;
          }),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF120704),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F0A05),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: _loading ? _progress : null,
            minHeight: 3,
            backgroundColor: const Color(0xFF3A150B),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF7A1F)),
          ),
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

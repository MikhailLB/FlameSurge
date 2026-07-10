// Full-screen WebView shell (the "gray" surface of the app).
//
// This file exists behind a deferred import so the WebView engine is only
// loaded on devices that reach the gray branch. All of the pitfalls listed
// in `gray_part_pitfalls.md` are addressed inline; comments call out the
// relevant section number when the fix is non-obvious.

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/device_agent.dart';
import '../../core/net_sensor.dart';
import '../../core/push_hub.dart';
import '../../core/vault.dart';
import '../../utils/url_guard.dart';
import '../tempest/tempest_screen.dart';

/// Called by the splash router right after the deferred library loads so the
/// WebView native code can pre-warm before the widget is inserted. Intentionally
/// a stub — the platform view will be created lazily when the widget mounts.
Future<void> primePortal() async {}

class PortalShell extends StatefulWidget {
  const PortalShell({
    super.key,
    required this.entryUrl,
    required this.vault,
    required this.pushHub,
    required this.netSensor,
  });

  final String entryUrl;
  final Vault vault;
  final PushHub pushHub;
  final NetSensor netSensor;

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell>
    with WidgetsBindingObserver {
  late final WebViewController _web;
  bool _isLoading = true;
  // Latch used to keep the spinner up between an error and the navigation to
  // the tempest screen (see pitfalls doc §4). Prevents the black Android robot
  // error page from being revealed for a few frames.
  bool _errored = false;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _offlineDebounce;
  bool _navigatingOffline = false;

  String? _lastMainFrameUrl;
  int _redirectRetries = 0;

  // Snapshot of the shell-level warm-tap handler so dispose() restores it
  // instead of nulling it out (pitfalls §12).
  PushLinkSink? _previousHandler;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _applySystemUi();

    _previousHandler = widget.pushHub.onFreshLink;
    widget.pushHub.onFreshLink = (rawUrl) {
      final safe = sanitiseUrl(rawUrl);
      if (safe == null) return;
      if (!mounted) return;
      _web.loadRequest(safe);
    };

    _web = _buildController();
    _configureAndroid();
    _web.loadRequest(Uri.parse(widget.entryUrl));

    _connSub = widget.netSensor.statusStream.listen((results) {
      final live = widget.netSensor.isAnyLive(results);
      if (live) {
        _offlineDebounce?.cancel();
        _navigatingOffline = false;
        return;
      }
      _offlineDebounce?.cancel();
      // 700ms debounce absorbs the VPN-transition flicker (pitfalls §3.C).
      _offlineDebounce = Timer(const Duration(milliseconds: 700), () {
        _routeToTempest();
      });
    });
  }

  WebViewController _buildController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(deviceAgent.userAgent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            _errored = false;
            _isLoading = true;
          });
        },
        onPageFinished: (_) {
          if (!mounted) return;
          // If an error latched _errored=true, keep the spinner cover up so
          // the OS error page never shows through (pitfalls §4).
          if (_errored) return;
          setState(() => _isLoading = false);
          _redirectRetries = 0;
          _injectRimGuards();
          _injectKeyboardShim();
        },
        onWebResourceError: _handleResourceError,
        onNavigationRequest: _decideNavigation,
        onHttpError: (_) {},
      ));
  }

  void _configureAndroid() {
    if (!Platform.isAndroid) return;
    if (_web.platform is! AndroidWebViewController) return;
    final android = _web.platform as AndroidWebViewController;
    android.setMediaPlaybackRequiresUserGesture(false);
    android.setOnShowFileSelector(_pickFilesForWeb);
    final cookieManager = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookieManager.setAcceptThirdPartyCookies(android, true);
  }

  NavigationDecision _decideNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    const inline = <String>{'http', 'https', 'about', 'data', 'blob'};
    if (inline.contains(uri.scheme)) {
      if (request.isMainFrame) _lastMainFrameUrl = request.url;
      return NavigationDecision.navigate;
    }
    unawaited(_launchExternal(uri));
    return NavigationDecision.prevent;
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<List<String>> _pickFilesForWeb(FileSelectorParams params) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (result == null) return const <String>[];
      return result.files
          .where((f) => f.path != null && f.path!.isNotEmpty)
          .map((f) => Uri.file(f.path!).toString())
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  void _handleResourceError(WebResourceError err) {
    // `isForMainFrame` returns null on some vendor builds — only bail when it
    // is *explicitly* false (pitfalls §4).
    if (err.isForMainFrame == false) return;

    // Cover the WebView while we decide what to do.
    if (mounted) {
      setState(() {
        _errored = true;
        _isLoading = true;
      });
    }

    final desc = err.description.toLowerCase();
    final isRedirectLoop = desc.contains('too_many_redirects') ||
        desc.contains('too many redirects') ||
        err.errorCode == -1007 ||
        err.errorCode == -9;

    if (isRedirectLoop &&
        _lastMainFrameUrl != null &&
        _redirectRetries < 3) {
      _redirectRetries++;
      _web.loadRequest(Uri.parse(_lastMainFrameUrl!));
      return;
    }

    if (_isDnsOrDisconnect(desc, err.errorCode)) {
      _routeToTempest();
    } else {
      unawaited(_probeAndTempest());
    }
  }

  bool _isDnsOrDisconnect(String desc, int code) {
    if (desc.contains('name_not_resolved') ||
        desc.contains('err_name_not_resolved') ||
        desc.contains('internet_disconnected') ||
        desc.contains('network_changed') ||
        desc.contains('address_unreachable') ||
        desc.contains('connection_refused') ||
        desc.contains('connection_reset') ||
        desc.contains('connection_timed_out')) {
      return true;
    }
    switch (code) {
      case -2:
      case -6:
      case -7:
      case -21:
      case -105:
      case -106:
      case -109:
      case -118:
        return true;
      default:
        return false;
    }
  }

  Future<void> _probeAndTempest() async {
    if (_navigatingOffline) return;
    final online = await widget.netSensor.probe();
    if (online) {
      if (!mounted) return;
      setState(() {
        _errored = false;
        _isLoading = false;
      });
      return;
    }
    _routeToTempest();
  }

  Future<void> _routeToTempest() async {
    if (_navigatingOffline || !mounted) return;
    _navigatingOffline = true;
    final currentUrl = await _web.currentUrl() ?? widget.entryUrl;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TempestScreen(
          retryBuilder: (_) => PortalShell(
            entryUrl: currentUrl,
            vault: widget.vault,
            pushHub: widget.pushHub,
            netSensor: widget.netSensor,
          ),
        ),
      ),
    );
  }

  void _applySystemUi() {
    // Immersive sticky is redrawn after any system dialog (permission,
    // keyboard, etc.) — re-apply on every resume through the lifecycle hook.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _applySystemUi();
  }

  // --------------------------------------------------------------------- //
  // JS injections                                                         //
  // --------------------------------------------------------------------- //

  void _injectRimGuards() {
    // Neutralises CSS safe-area insets and forces viewport-fit=contain so
    // notched Android WebViews don't leave a dark band at the top/bottom.
    _web.runJavaScript(r'''
(function(){
  if (window.__fs_rim_guard) return;
  window.__fs_rim_guard = true;
  var STYLE_ID='__fs_rim_style';
  var CSS_RULES =
    ':root{'+
      '--sat:0px!important;--sar:0px!important;'+
      '--sab:0px!important;--sal:0px!important;'+
      '--safe-top:0px!important;--safe-right:0px!important;'+
      '--safe-bottom:0px!important;--safe-left:0px!important;'+
      '--safe-area-inset-top:0px!important;'+
      '--safe-area-inset-right:0px!important;'+
      '--safe-area-inset-bottom:0px!important;'+
      '--safe-area-inset-left:0px!important;'+
    '}'+
    '.app-header,.gameview-mobile-header{padding-top:0!important;}';
  function isKbUp(){
    if(!window.visualViewport)return false;
    return window.visualViewport.height < window.innerHeight * 0.78;
  }
  function paint(){
    if(isKbUp()) return; // pitfalls §3.B: don't repaint mid-keyboard
    var head = document.head || document.documentElement;
    if(!head) return;
    var meta = document.querySelector('meta[name="viewport"]');
    if(meta){
      var content=(meta.getAttribute('content')||'')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig,'').trim();
      meta.setAttribute('content', content + (content?', ':'') + 'viewport-fit=contain');
    }
    var s=document.getElementById(STYLE_ID);
    if(!s){
      s=document.createElement('style');
      s.id=STYLE_ID;
      head.appendChild(s);
    }
    if(s.textContent!==CSS_RULES) s.textContent=CSS_RULES;
    if(head.lastElementChild!==s) head.appendChild(s);
  }
  paint();
  ['pushState','replaceState'].forEach(function(fn){
    var orig=history[fn];
    history[fn]=function(){
      var res=orig.apply(this, arguments);
      setTimeout(paint, 80);
      setTimeout(paint, 480);
      return res;
    };
  });
  window.addEventListener('popstate', function(){ setTimeout(paint, 80); });
  setInterval(paint, 2500);
})();
''');
  }

  void _injectKeyboardShim() {
    // Scrolls the focused element above the keyboard using auto-scroll (never
    // smooth — smooth conflicts with the OS keyboard animation, pitfalls §3.A).
    _web.runJavaScript(r'''
(function(){
  if (window.__fs_kb_shim) return;
  window.__fs_kb_shim = true;

  function editable(el){
    if(!el) return false;
    var t=el.tagName;
    return t==='INPUT' || t==='TEXTAREA' || el.isContentEditable;
  }
  function align(){
    var el=document.activeElement;
    if(!editable(el)) return;
    var vp=window.visualViewport;
    if(vp){
      var box=el.getBoundingClientRect();
      var vpBottom=vp.offsetTop + vp.height;
      if(box.bottom > vpBottom - 20 || box.top < vp.offsetTop){
        el.scrollIntoView({behavior:'auto', block:'nearest'});
      }
    } else {
      el.scrollIntoView({behavior:'auto', block:'nearest'});
    }
  }
  document.addEventListener('focusin', function(e){
    if(editable(e.target)) setTimeout(align, 350);
  });
  if(window.visualViewport){
    var prevH=window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function(){
      var h=window.visualViewport.height;
      if(h < prevH) setTimeout(align, 120);
      prevH=h;
    });
  }
})();
''');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _offlineDebounce?.cancel();
    // Restore the previous handler so the shell-level fallback keeps working.
    widget.pushHub.onFreshLink = _previousHandler;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  Future<bool> _handleBackPress() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final viewPadding = MediaQuery.of(context).viewPadding;
    final isPortrait = orientation == Orientation.portrait;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // pitfalls §1: must be false so Android's adjustResize is authoritative.
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Padding(
              padding: isPortrait
                  ? EdgeInsets.only(top: viewPadding.top)
                  : EdgeInsets.only(
                      left: viewPadding.left,
                      right: viewPadding.right,
                    ),
              child: WebViewWidget(controller: _web),
            ),
            if (_isLoading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFFF7A1F),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


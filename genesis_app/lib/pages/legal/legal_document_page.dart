import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../components/page_header.dart';
import '../../ui/genesis_ui.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import 'legal_document_dark_style.dart';

enum LegalDocument {
  terms(title: 'Terms of Service', url: 'https://worldo.ai/terms/'),
  privacy(title: 'Privacy Policy', url: 'https://worldo.ai/privacy/'),
  eula(title: 'End User License Agreement', url: 'https://worldo.ai/eula/');

  const LegalDocument({required this.title, required this.url});

  final String title;
  final String url;

  static LegalDocument fromRouteValue(String value) {
    return LegalDocument.values.firstWhere(
      (item) => item.name == value,
      orElse: () => LegalDocument.terms,
    );
  }
}

class LegalDocumentPage extends StatefulWidget {
  const LegalDocumentPage({super.key, required this.document});

  final LegalDocument document;

  @override
  State<LegalDocumentPage> createState() => _LegalDocumentPageState();
}

class _LegalDocumentPageState extends State<LegalDocumentPage> {
  WebViewController? _controller;
  var _loadingProgress = 0;
  var _hasError = false;
  var _styleReady = false;
  var _loadGeneration = 0;
  Completer<bool>? _paintCompleter;

  void _cancelPaintWait() {
    final completer = _paintCompleter;
    if (completer != null && !completer.isCompleted) completer.complete(false);
    _paintCompleter = null;
  }

  @override
  void dispose() {
    _cancelPaintWait();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  Future<void> _initializeController() async {
    try {
      final controller = WebViewController();
      _controller = controller;
      await controller.setBackgroundColor(GenesisColors.darkBackground);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'GenesisLegalStyleReady',
        onMessageReceived: (message) {
          final completer = _paintCompleter;
          if (!mounted ||
              _controller != controller ||
              message.message != '$_loadGeneration' ||
              completer == null ||
              completer.isCompleted) {
            return;
          }
          completer.complete(true);
        },
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted || _controller != controller) return;
            setState(() => _loadingProgress = progress);
          },
          onPageStarted: (_) {
            if (!mounted || _controller != controller) return;
            _cancelPaintWait();
            setState(() {
              _loadGeneration++;
              _hasError = false;
              _styleReady = false;
              _loadingProgress = 0;
            });
          },
          onPageFinished: (url) async {
            if (!mounted || _controller != controller) return;
            _cancelPaintWait();
            final generation = ++_loadGeneration;
            try {
              if (isWorldoLegalDocument(url)) {
                final painted = Completer<bool>();
                _paintCompleter = painted;
                final applied = await controller.runJavaScriptReturningResult(
                  legalDocumentDarkStyleScript(readyMessage: '$generation'),
                );
                if (applied != true && applied != 'true') {
                  throw StateError('Legal page dark style was not applied');
                }
                final ready = await painted.future.timeout(
                  const Duration(seconds: 10),
                  onTimeout: () => false,
                );
                if (!ready) throw StateError('Legal page has not painted');
              }
              if (!mounted ||
                  _controller != controller ||
                  generation != _loadGeneration) {
                return;
              }
              setState(() {
                _styleReady = true;
                _loadingProgress = 100;
              });
            } catch (_) {
              if (!mounted ||
                  _controller != controller ||
                  generation != _loadGeneration) {
                return;
              }
              setState(() => _hasError = true);
            }
          },
          onWebResourceError: (error) {
            if (!mounted ||
                _controller != controller ||
                error.isForMainFrame == false) {
              return;
            }
            setState(() => _hasError = true);
          },
        ),
      );
      if (!mounted || _controller != controller) return;
      await controller.loadRequest(Uri.parse(widget.document.url));
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasError = true);
    }
  }

  Future<void> _retry() async {
    _cancelPaintWait();
    setState(() {
      _loadGeneration++;
      _hasError = false;
      _styleReady = false;
      _loadingProgress = 0;
    });
    await _initializeController();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return GenesisDarkTheme(
      child: GenesisBottomSystemBarStyleScope(
        style: const GenesisBottomSystemBarStyle(
          color: GenesisColors.darkBackground,
        ),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: kGenesisLightSystemUiOverlayStyle,
          child: Scaffold(
            backgroundColor: GenesisColors.darkBackground,
            appBar: GenesisBackAppBar(
              pageName: widget.document.title,
              backgroundColor: GenesisColors.darkBackground,
              foregroundColor: GenesisColors.darkTextPrimary,
              systemOverlayStyle: kGenesisLightSystemUiOverlayStyle,
            ),
            body: SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (controller != null)
                    IgnorePointer(
                      ignoring: !_styleReady || _hasError,
                      child: WebViewWidget(controller: controller),
                    ),
                  // Keep the platform view painting underneath an opaque
                  // Flutter layer; Opacity(0) can suppress its initial frame.
                  if (!_styleReady || _hasError)
                    const ColoredBox(
                      key: ValueKey('legal-loading-cover'),
                      color: GenesisColors.darkBackground,
                    ),
                  if (!_hasError && !_styleReady)
                    Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(
                        value: _loadingProgress < 100
                            ? _loadingProgress / 100
                            : null,
                        color: GenesisColors.darkTextSecondary,
                        backgroundColor: GenesisColors.darkFaintFill,
                      ),
                    ),
                  if (_hasError)
                    _LegalWebErrorView(
                      url: widget.document.url,
                      onRetry: _retry,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalWebErrorView extends StatelessWidget {
  const _LegalWebErrorView({required this.url, required this.onRetry});

  final String url;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: GenesisColors.darkBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Load failed',
              style: TextStyle(
                fontSize: 16,
                color: GenesisColors.darkTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                url,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: GenesisColors.darkTextTertiary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: GenesisColors.darkTextPrimary,
                side: const BorderSide(color: GenesisColors.darkFaintFill),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

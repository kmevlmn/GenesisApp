import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Exercise WebView loading through the plugin's native-platform seam.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:genesis_flutter_android/pages/legal/legal_document_page.dart';
import 'package:genesis_flutter_android/pages/legal/legal_document_dark_style.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';

void main() {
  late _WebPlatform platform;
  setUp(() {
    platform = _WebPlatform();
    WebViewPlatform.instance = platform;
  });

  for (final document in LegalDocument.values) {
    testWidgets(
      '${document.name} waits for dark styling before showing content',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: LegalDocumentPage(document: document)),
        );
        await tester.pump();
        final controller = platform.controllers.single;
        expect(controller.loadedUrl, document.url);
        expect(controller.background, GenesisColors.darkBackground);
        expect(_cover, findsOneWidget);
        controller.delegate!.started!(document.url);
        controller.delegate!.finished!(document.url);
        await tester.pump();
        expect(controller.script, contains('genesis-legal-dark-style'));
        expect(
          find.ancestor(
            of: find.byType(WebViewWidget),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
        expect(_cover, findsOneWidget);
        controller.styleApplied.complete(true);
        await tester.pump();
        expect(_cover, findsOneWidget);
        controller.markPainted();
        await tester.pump();
        expect(_cover, findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        controller.delegate!.started!(document.url);
        await tester.pump();
        expect(_cover, findsOneWidget);
      },
    );
  }

  testWidgets('failed styling can be retried without revealing a light page', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LegalDocumentPage(document: LegalDocument.terms)),
    );
    await tester.pump();
    final first = platform.controllers.single;
    first.delegate!.finished!(LegalDocument.terms.url);
    await tester.pump();
    first.styleApplied.completeError(StateError('script failed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Load failed'), findsOneWidget);
    expect(_cover, findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    final retry = platform.controllers.last;
    expect(platform.controllers, hasLength(2));
    retry.delegate!.finished!(LegalDocument.terms.url);
    await tester.pump();
    retry.styleApplied.complete(true);
    await tester.pump();
    expect(_cover, findsOneWidget);
    retry.markPainted();
    await tester.pump();
    expect(find.text('Load failed'), findsNothing);
    expect(_cover, findsNothing);
  });

  test('style scope only includes first-party legal documents', () {
    for (final document in LegalDocument.values) {
      expect(isWorldoLegalDocument(document.url), isTrue);
      expect(isWorldoLegalDocument('${document.url}#section'), isTrue);
    }
    expect(isWorldoLegalDocument('https://worldo.ai/'), isFalse);
    expect(
      isWorldoLegalDocument('https://worldo.ai.evil.test/terms/'),
      isFalse,
    );
    expect(isWorldoLegalDocument('https://example.com/privacy/'), isFalse);
  });

  testWidgets('an old paint callback cannot uncover the next navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LegalDocumentPage(document: LegalDocument.terms)),
    );
    await tester.pump();
    final controller = platform.controllers.single;
    controller.delegate!.finished!(LegalDocument.terms.url);
    await tester.pump();
    controller.styleApplied.complete(true);
    await tester.pump();
    controller.delegate!.started!(LegalDocument.privacy.url);
    controller.markPainted();
    await tester.pump();
    expect(_cover, findsOneWidget);
    expect(find.text('Load failed'), findsNothing);
  });

  testWidgets(
    'missing paint callback keeps the page covered and offers retry',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LegalDocumentPage(document: LegalDocument.terms),
        ),
      );
      await tester.pump();
      final controller = platform.controllers.single;
      controller.delegate!.finished!(LegalDocument.terms.url);
      await tester.pump();
      controller.styleApplied.complete(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 11));
      expect(_cover, findsOneWidget);
      expect(find.text('Load failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );
}

Finder get _cover => find.byKey(const ValueKey('legal-loading-cover'));

class _WebPlatform extends WebViewPlatform {
  final controllers = <_Controller>[];
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _Controller(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Delegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _WebWidget(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  Color? background;
  String? loadedUrl;
  String? script;
  _Delegate? delegate;
  JavaScriptChannelParams? channel;
  void markPainted() {
    final message = RegExp(
      r'postMessage\("(\d+)"\)',
    ).firstMatch(script!)!.group(1)!;
    channel!.onMessageReceived(JavaScriptMessage(message: message));
  }

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  final styleApplied = Completer<Object>();
  @override
  Future<void> setBackgroundColor(Color color) async {
    background = color;
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    delegate = handler as _Delegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    expect(background, GenesisColors.darkBackground);
    loadedUrl = params.uri.toString();
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) {
    script = javaScript;
    return styleApplied.future;
  }
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  PageEventCallback? started;
  PageEventCallback? finished;
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {
    started = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _WebWidget extends PlatformWebViewWidget {
  _WebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.white);
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/gems/gem_wallet_store.dart';
import 'package:genesis_flutter_android/components/common/genesis_modal_routes.dart';
import 'package:genesis_flutter_android/components/gems/purchase_options_sheet.dart';
import 'package:genesis_flutter_android/network/models/gem_wallet.dart';
import 'package:genesis_flutter_android/pages/gems/gem_wallet_page.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

void main() {
  testWidgets('render actual subscription page and sheet with bundled Inter', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await tester.runAsync(() async {
      final font = FontLoader('Inter')..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))..addFont(rootBundle.load('assets/fonts/InterVariable-Italic.ttf'));
      await font.load();
      final icons = FontLoader('MaterialIcons')..addFont(File('/Users/xiaoyi/development/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
      await icons.load();
      final customIcons = FontLoader('MyFlutterApp')..addFont(rootBundle.load('assets/custom-icons/fonts/MyFlutterApp.ttf'));
      await customIcons.load();
    });
    final wallet = GemWalletStore(loadWallet: () async => const GemWallet(balanceCent: 0), readUid: () async => 'preview');
    addTearDown(wallet.dispose);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: boundaryKey, child: MaterialApp(
      debugShowCheckedModeBanner: false, theme: GenesisTheme.light(), scrollBehavior: const GenesisScrollBehavior(),
      home: GemWalletPage(showSubscriptionInitially: true, walletStore: wallet, productsLoader: (_) async => [], tasksLoader: (_) async => []),
    )));
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('../output/subscription-purchase')..createSync(recursive: true);
        File('${directory.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
    }
    await capture('page');
    await tester.tap(find.byKey(const ValueKey('pro-plan-monthly')));
    await tester.pumpAndSettle();
    await capture('page-monthly');
    final context = tester.element(find.byType(GemWalletPage));
    unawaited(showGenesisModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => FractionallySizedBox(heightFactor: .8, child: PurchaseOptionsSheet(initialTab: PurchaseSheetTab.subscription, gemsBuilder: (_) => const SizedBox()))));
    await tester.pumpAndSettle();
    await capture('sheet');
    await tester.tap(find.byKey(const ValueKey('gem-purchase-sheet-close')));
    await tester.pumpAndSettle();
  });
}

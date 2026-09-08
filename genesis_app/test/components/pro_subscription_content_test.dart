import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/membership/membership_catalog.dart';
import 'package:genesis_flutter_android/components/gems/pro_subscription_content.dart';
import 'package:genesis_flutter_android/ui/components/genesis_primary_button.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

import '../support/membership_fixtures.dart';

const surfaceKey = ValueKey('subscription-test-surface');
const buttonKey = ValueKey('pro-subscribe-button');

Widget page(MembershipCatalogLoader loader) => MaterialApp(
  theme: GenesisTheme.light(),
  home: Scaffold(
    body: RepaintBoundary(
      key: surfaceKey,
      child: ProSubscriptionContent(productsLoader: loader),
    ),
  ),
);

void expectOriginalContent(WidgetTester tester) {
  expect(find.text('Monthly bonus Gems'), findsOneWidget);
  expect(find.byKey(const ValueKey('pro-plan-yearly')), findsOneWidget);
  expect(find.byKey(const ValueKey('pro-plan-monthly')), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(
    tester.widget<GenesisPrimaryButton>(find.byKey(buttonKey)).onPressed,
    isNotNull,
  );
}

Future<List<int>> pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(surfaceKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  testWidgets('fills the original cards with store prices after loading', (
    tester,
  ) async {
    final completer = Completer<List<MembershipOffer>>();
    await tester.pumpWidget(page(() => completer.future));
    expectOriginalContent(tester);
    expect(find.text(r'Yearly: $99.99'), findsNothing);
    completer.complete(await loadTestMembershipOffers());
    await tester.pumpAndSettle();
    expectOriginalContent(tester);
    expect(find.text(r'Yearly: $99.99'), findsOneWidget);
    expect(find.text(r'$8.33/mo', findRichText: true), findsOneWidget);
    expect(find.text('Save 17%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pro-plan-monthly')));
    await tester.pump();
    expect(find.text(r'Monthly: $9.99'), findsOneWidget);
    expect(find.text('Monthly bonus Gems'), findsOneWidget);
  });

  testWidgets('failure keeps original content and original button can retry', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      page(() async {
        if (++calls == 1) throw StateError('offline');
        return loadTestMembershipOffers();
      }),
    );
    await tester.pumpAndSettle();
    expectOriginalContent(tester);
    expect(find.text('Unable to load subscriptions.'), findsNothing);
    await tester.tap(find.byKey(buttonKey));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text(r'Yearly: $99.99'), findsOneWidget);
  });

  testWidgets('sale flag does not change pixels and disabled sale is guarded', (
    tester,
  ) async {
    Future<List<MembershipOffer>> offers(bool saleEnabled) async => [
      for (final yearly in [true, false])
        MembershipOffer(
          product: membershipProduct(yearly: yearly, saleEnabled: saleEnabled),
          price: membershipPrice(yearly: yearly),
        ),
    ];
    for (final plan in ['yearly', 'monthly']) {
      await tester.pumpWidget(page(() => offers(true)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('pro-plan-$plan')));
      await tester.pumpAndSettle();
      final enabledPixels = await pixels(tester);
      await tester.pumpWidget(page(() => offers(false)));
      await tester.pumpAndSettle();
      expectOriginalContent(tester);
      expect(await pixels(tester), orderedEquals(enabledPixels));
      await tester.tap(find.byKey(buttonKey));
      await tester.pumpAndSettle();
      expect(find.text('Pro subscriptions are coming soon.'), findsNothing);
      expect(find.text('Currently unavailable'), findsNothing);
    }
  });

  testWidgets('empty and signed-out results preserve original content', (
    tester,
  ) async {
    await tester.pumpWidget(page(() async => []));
    await tester.pumpAndSettle();
    expectOriginalContent(tester);
    expect(find.text('No subscriptions available right now.'), findsNothing);
    expect(find.text(r'Yearly: $99.99'), findsNothing);
    await tester.pumpWidget(page(() async => throw MembershipLoginRequired()));
    await tester.pumpAndSettle();
    expectOriginalContent(tester);
    expect(find.text('Log in to view subscriptions.'), findsNothing);
  });

  testWidgets(
    'missing store prices can be queried again without preview prices',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        page(() async {
          if (++calls == 1) {
            return [MembershipOffer(product: membershipProduct(yearly: true))];
          }
          return loadTestMembershipOffers();
        }),
      );
      await tester.pumpAndSettle();
      expectOriginalContent(tester);
      expect(find.text('Price unavailable'), findsNothing);
      expect(find.text(r'Yearly: $99.99'), findsNothing);
      await tester.tap(find.byKey(buttonKey));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text(r'Yearly: $99.99'), findsOneWidget);
      expect(find.text('Pro subscriptions are coming soon.'), findsNothing);
    },
  );

  testWidgets('plan selection preserves benefit copy and narrow layout', (
    tester,
  ) async {
    final offers = [
      MembershipOffer(
        product: membershipProduct(yearly: true, monthlyGemsCent: 200000),
        price: membershipPrice(yearly: true),
      ),
      MembershipOffer(product: membershipProduct(), price: membershipPrice()),
    ];
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [320.0, 390.0]) {
      tester.view.physicalSize = Size(width, 568);
      await tester.pumpWidget(page(() async => offers));
      await tester.pumpAndSettle();
      for (final plan in ['yearly', 'monthly']) {
        await tester.tap(find.byKey(ValueKey('pro-plan-$plan')));
        await tester.pump();
        expectOriginalContent(tester);
        expect(find.text('Save 17%'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('obsolete request cannot replace a newer catalog', (
    tester,
  ) async {
    final old = Completer<List<MembershipOffer>>();
    await tester.pumpWidget(page(() => old.future));
    await tester.pumpWidget(page(() async => []));
    await tester.pumpAndSettle();
    old.complete(await loadTestMembershipOffers());
    await tester.pumpAndSettle();
    expectOriginalContent(tester);
    expect(find.text(r'Yearly: $99.99'), findsNothing);
    expect(find.text('Save 17%'), findsNothing);
  });
}

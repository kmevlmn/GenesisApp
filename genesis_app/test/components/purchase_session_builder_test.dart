import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/bootstrap/app_services_scope.dart';
import 'package:genesis_flutter_android/app/bootstrap/service_registry.dart';
import 'package:genesis_flutter_android/app/config/app_config.dart';
import 'package:genesis_flutter_android/app/gems/gem_wallet_store.dart';
import 'package:genesis_flutter_android/app/membership/membership_catalog.dart';
import 'package:genesis_flutter_android/components/gems/profile_membership_card.dart';
import 'package:genesis_flutter_android/components/gems/pro_subscription_content.dart';
import 'package:genesis_flutter_android/components/gems/purchase_options_sheet.dart';
import 'package:genesis_flutter_android/components/gems/purchase_session_builder.dart';
import 'package:genesis_flutter_android/components/login_sheet.dart';
import 'package:genesis_flutter_android/network/models/gem_wallet.dart';
import 'package:genesis_flutter_android/pages/gems/gem_wallet_page.dart';
import 'package:genesis_flutter_android/platform/session/memory_user_session_store.dart';
import 'package:genesis_flutter_android/routers/app_router.dart';

import '../support/membership_fixtures.dart';

class _DeferredSession extends MemoryUserSessionStore {
  final uid = Completer<String?>();

  @override
  Future<String?> readUid() => uid.future;
}

AppServices _servicesFor(MemoryUserSessionStore session) {
  // Session and routing checks do not need a native store connection.
  final platform = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  try {
    return ServiceRegistry.build(
      config: const AppConfig(useMock: true),
      sessionStoreOverride: session,
    );
  } finally {
    debugDefaultTargetPlatformOverride = platform;
  }
}

void main() {
  for (final sheet in [false, true]) {
    testWidgets(
      'guest ${sheet ? 'sheet' : 'page'} hides Gems and follows login changes',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = MemoryUserSessionStore();
        await session.saveUid('guest_legacy');
        final services = _servicesFor(session);
        var memberships = 0;
        var gems = 0;
        var balances = 0;
        var tasks = 0;
        final wallet = GemWalletStore(
          readUid: session.readUid,
          loadWallet: () async {
            balances++;
            return const GemWallet(balanceCent: 100);
          },
        );
        addTearDown(wallet.dispose);
        Future<MembershipCatalogData> loadMemberships() {
          memberships++;
          return loadTestMembershipOffers();
        }

        await tester.pumpWidget(
          AppServicesScope(
            services: services,
            child: MaterialApp(
              home: Scaffold(
                body: PurchaseSessionBuilder(
                  builder: (_, showBuyGems) => sheet
                      ? PurchaseOptionsSheet(
                          showBuyGems: showBuyGems,
                          initialTab: PurchaseSheetTab.subscription,
                          membershipProductsLoader: loadMemberships,
                          gemsBuilder: (_) {
                            gems++;
                            return const Text('Gem packs');
                          },
                        )
                      : GemWalletPage(
                          showBuyGems: showBuyGems,
                          showSubscriptionInitially: true,
                          membershipProductsLoader: loadMemberships,
                          walletStore: wallet,
                          productsLoader: (_) async {
                            gems++;
                            return [];
                          },
                          tasksLoader: (_) async {
                            tasks++;
                            return [];
                          },
                        ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Subscription'), findsOneWidget);
        expect(find.text('Buy Gems'), findsNothing);
        expect(find.byType(LoginSheet), findsNothing);
        expect(memberships, 1);
        expect([gems, tasks, balances], [0, 0, 0]);
        final pages = find.byKey(
          ValueKey(sheet ? 'purchase-sheet-pages' : 'wallet-purchase-pages'),
        );
        await tester.drag(pages, const Offset(-500, 0));
        await tester.pumpAndSettle();
        expect(find.byType(ProSubscriptionContent), findsOneWidget);
        expect([gems, tasks, balances], [0, 0, 0]);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect([gems, tasks, balances], [0, 0, 0]);

        await session.saveUid('member');
        services.notifySessionChanged();
        await tester.pumpAndSettle();
        expect(find.text('Buy Gems'), findsOneWidget);
        expect([gems, tasks, balances], [0, 0, 0]);
        await tester.tap(find.text('Buy Gems'));
        await tester.pumpAndSettle();
        expect(gems, 1);
        if (!sheet) expect([tasks, balances], [1, 1]);

        await session.clearUid();
        services.notifySessionChanged();
        await tester.pumpAndSettle();
        expect(find.text('Buy Gems'), findsNothing);
        expect(find.byType(ProSubscriptionContent), findsOneWidget);
        expect(gems, 1);
        expect(find.byType(LoginSheet), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('catalogs wait for the initial login state to resolve', (
    tester,
  ) async {
    final session = _DeferredSession();
    final services = _servicesFor(session);
    var builds = 0;
    await tester.pumpWidget(
      AppServicesScope(
        services: services,
        child: MaterialApp(
          home: Scaffold(
            body: PurchaseSessionBuilder(
              builder: (_, showBuyGems) {
                builds++;
                return Text(showBuyGems ? 'Buy Gems' : 'Subscription');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(builds, 0);
    expect(find.text('Buy Gems'), findsNothing);
    session.uid.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Subscription'), findsOneWidget);
  });

  testWidgets('guest membership card enters the real VIP route without login', (
    tester,
  ) async {
    final services = _servicesFor(MemoryUserSessionStore());
    await tester.pumpWidget(
      AppServicesScope(
        services: services,
        child: MaterialApp(
          home: const Scaffold(body: ProfileMembershipCard()),
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ),
    );
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();
    expect(find.byType(GemWalletPage), findsOneWidget);
    expect(find.byType(ProSubscriptionContent), findsOneWidget);
    expect(find.text('Subscription'), findsOneWidget);
    expect(find.text('Buy Gems'), findsNothing);
    expect(find.byType(LoginSheet), findsNothing);
  });
}

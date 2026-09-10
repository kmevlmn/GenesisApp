import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:genesis_flutter_android/app/debug_page_tracker.dart';
import 'package:genesis_flutter_android/app/gems/gem_wallet_store.dart';
import 'package:genesis_flutter_android/app/telemetry/genesis_telemetry.dart';
import 'package:genesis_flutter_android/components/common/genesis_action_box.dart';
import 'package:genesis_flutter_android/components/gems/gem_purchase_catalog.dart';
import 'package:genesis_flutter_android/components/gems/wallet_purchase_tabs.dart';
import 'package:genesis_flutter_android/components/gems/pro_colors.dart';
import 'package:genesis_flutter_android/network/models/gem_product.dart';
import 'package:genesis_flutter_android/network/models/gem_records.dart';
import 'package:genesis_flutter_android/network/models/gem_task.dart';
import 'package:genesis_flutter_android/network/models/gem_task_action.dart';
import 'package:genesis_flutter_android/network/models/gem_wallet.dart';
import 'package:genesis_flutter_android/pages/gems/gem_records_page.dart';
import 'package:genesis_flutter_android/pages/gems/gem_wallet_page.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/platform/billing/billing_service.dart';
import 'package:genesis_flutter_android/routers/app_router.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_typography.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

import '../../support/membership_fixtures.dart';

const _wrappingTaskDescription =
    'Create an Origin and launch a world, then continue exploring locations '
    'and interacting with characters to move its story forward.';

void main() {
  tearDown(GenesisTelemetry.resetForTesting);

  for (final subscriptionFirst in [true, false]) {
    for (final swipe in [false, true]) {
      testWidgets(
        'wallet loads only initial tab subscription=$subscriptionFirst and visits other via swipe=$swipe',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var memberships = 0;
          var products = 0;
          var tasks = 0;
          var balances = 0;
          final telemetry = _CapturingTelemetrySink();
          GenesisTelemetry.setSinkForTesting(telemetry);
          final wallet = GemWalletStore(
            readUid: () async => 'u_test',
            loadWallet: () async {
              balances++;
              return const GemWallet(balanceCent: 43000);
            },
          );
          final billing = _FakeBillingService();
          addTearDown(wallet.dispose);
          addTearDown(billing.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: GenesisTheme.light(),
              home: GemWalletPage(
                showSubscriptionInitially: subscriptionFirst,
                walletStore: wallet,
                billingService: billing,
                membershipProductsLoader: () {
                  memberships++;
                  return loadTestMembershipOffers();
                },
                productsLoader: (_) async {
                  products++;
                  return _products();
                },
                tasksLoader: (_) async {
                  tasks++;
                  return [];
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            Theme.of(
              tester.element(find.byType(WalletPurchaseTabs)),
            ).brightness,
            Brightness.dark,
          );
          expect(
            tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
            GenesisColors.darkBackground,
          );
          expect(memberships, subscriptionFirst ? 1 : 0);
          expect(products, subscriptionFirst ? 0 : 1);
          expect(tasks, products);
          expect(balances, products);
          expect(billing.startCount, products);
          expect(billing.storeRecoveryCount, products);
          expect(
            telemetry.events
                .where((event) => event.name == 'buy_page_show')
                .length,
            products,
          );

          if (subscriptionFirst) {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pumpAndSettle();
            expect(products, 0);
            expect(tasks, 0);
            expect(balances, 0);
            expect(billing.startCount, 0);
          }
          final pages = find.byKey(const ValueKey('wallet-purchase-pages'));
          final otherTab = find.byKey(
            ValueKey(
              subscriptionFirst
                  ? 'wallet-buy-gems-tab'
                  : 'wallet-subscription-tab',
            ),
          );
          if (swipe) {
            await tester.drag(pages, Offset(subscriptionFirst ? -330 : 330, 0));
          } else {
            await tester.tap(otherTab);
          }
          await tester.pumpAndSettle();
          expect(
            [
              memberships,
              products,
              tasks,
              balances,
              billing.startCount,
              billing.storeRecoveryCount,
            ],
            [1, 1, 1, 1, 1, 1],
          );
          expect(
            telemetry.events
                .where((event) => event.name == 'buy_page_show')
                .length,
            1,
          );

          await tester.tap(
            find.byKey(
              ValueKey(
                subscriptionFirst
                    ? 'wallet-subscription-tab'
                    : 'wallet-buy-gems-tab',
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(otherTab);
          await tester.pumpAndSettle();
          expect(
            [
              memberships,
              products,
              tasks,
              balances,
              billing.startCount,
              billing.storeRecoveryCount,
            ],
            [1, 1, 1, 1, 1, 1],
          );
          // Returning to the foreground while Subscription is selected must
          // not issue background Gems page requests, even after visiting Gems.
          await tester.tap(
            find.byKey(const ValueKey('wallet-subscription-tab')),
          );
          await tester.pumpAndSettle();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          expect([products, tasks, balances], [1, 1, 1]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'only benefits scroll and wallet tabs stay centered on the page',
    (tester) async {
      tester.view.physicalSize = const Size(428, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final wallet = GemWalletStore(
        loadWallet: () async => const GemWallet(balanceCent: 0),
        readUid: () async => 'u_user',
      );
      addTearDown(wallet.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: GenesisTheme.light(),
          scrollBehavior: const GenesisScrollBehavior(),
          home: GemWalletPage(
            membershipProductsLoader: loadTestMembershipOffers,
            walletStore: wallet,
            productsLoader: (_) async => [],
            tasksLoader: (_) async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wallet-subscription-tab')));
      await tester.pumpAndSettle();
      final tabs = find.byKey(const ValueKey('wallet-purchase-tabs'));
      final intro = find.byKey(const ValueKey('pro-introduction'));
      final title = find.byKey(const ValueKey('pro-tier-title'));
      final yearly = find.byKey(const ValueKey('pro-plan-yearly'));
      final cta = find.byKey(const ValueKey('pro-subscribe-button'));
      expect(intro, findsNothing);
      expect(find.text('More possibilities with Pro'), findsNothing);
      final titleRect = tester.getRect(title);
      final planRect = tester.getRect(yearly);
      final ctaRect = tester.getRect(cta);
      final badgeRect = tester.getRect(
        find.byKey(const ValueKey('pro-yearly-savings-badge')),
      );
      expect(badgeRect.left, planRect.left);
      expect(badgeRect.top, planRect.top - 9);
      final list = find.byKey(const PageStorageKey('pro-benefits-scroll'));
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      await tester.drag(list, const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(tester.getRect(title), titleRect);
      expect(tester.getRect(yearly), planRect);
      expect(tester.getRect(cta), ctaRect);
      for (final (label, icon, color) in [
        ('Custom chat backgrounds', null, GenesisColors.brand),
        (
          'Create custom characters',
          Icons.check_rounded,
          GenesisColors.darkTextPrimary,
        ),
        (
          'Download without watermark',
          Icons.lock_outline_rounded,
          GenesisColors.darkTextTertiary,
        ),
      ]) {
        final finder = find.byKey(ValueKey('pro-benefit-status-$label'));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        if (icon == null) {
          final rendered = tester.widget<SvgPicture>(finder);
          expect(
            rendered.colorFilter,
            const ColorFilter.mode(proCopperAccent, BlendMode.srcIn),
          );
          expect(rendered.semanticsLabel, 'Improved with Pro');
        } else {
          final rendered = tester.widget<Icon>(finder);
          expect(rendered.icon, icon);
          expect(rendered.color, color);
        }
      }
      for (final width in [428.0, 390.0, 320.0]) {
        tester.view.physicalSize = Size(width, 926);
        await tester.pumpAndSettle();
        expect(tester.getRect(tabs).center.dx, closeTo(width / 2, .01));
        final subscriptionRect = tester.getRect(
          find.byKey(const ValueKey('wallet-subscription-tab')),
        );
        final gemsRect = tester.getRect(
          find.byKey(const ValueKey('wallet-buy-gems-tab')),
        );
        expect(
          (subscriptionRect.left + gemsRect.right) / 2,
          closeTo(width / 2, .01),
        );
        expect(subscriptionRect.width, closeTo(gemsRect.width, .01));
        expect(subscriptionRect.right, lessThanOrEqualTo(width / 2));
        expect(gemsRect.left, greaterThanOrEqualTo(width / 2));
        expect(
          (subscriptionRect.center.dx + gemsRect.center.dx) / 2,
          closeTo(width / 2, .01),
        );
        for (final iconKey in [
          'subscription-crown-icon',
          'buy-gems-outline-icon',
        ]) {
          final icon = find.byKey(ValueKey(iconKey));
          expect(tester.getSize(icon), const Size(22, 22));
          // Layout size alone does not detect scaling by an ancestor.
          final box = tester.renderObject<RenderBox>(icon);
          expect(
            (box.localToGlobal(const Offset(22, 0)) -
                    box.localToGlobal(Offset.zero))
                .distance,
            closeTo(22, .01),
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'wallet swipe tabs preserve plans and gem state without purchasing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var productLoads = 0;
      final wallet = GemWalletStore(
        loadWallet: () async => const GemWallet(balanceCent: 43000),
        readUid: () async => 'u_user',
      );
      final billing = _FakeBillingService();
      addTearDown(wallet.dispose);
      addTearDown(billing.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: GenesisTheme.light(),
          scrollBehavior: const GenesisScrollBehavior(),
          home: GemWalletPage(
            membershipProductsLoader: loadTestMembershipOffers,
            walletStore: wallet,
            billingService: billing,
            productsLoader: (_) async {
              productLoads++;
              return _products();
            },
            tasksLoader: (_) async => _taskGroups(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gems = find.byType(ListView).first;
      await tester.drag(gems, const Offset(0, -150));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: gems, matching: find.byType(Scrollable)).first,
          )
          .position;
      final offset = position.pixels;
      expect(offset, greaterThan(0));
      await tester.tap(find.byKey(const ValueKey('wallet-subscription-tab')));
      await tester.pumpAndSettle();
      expect(find.text('Premium'), findsOneWidget);
      expect(find.text(r'Yearly: $99.99'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pro-plan-monthly')));
      await tester.pumpAndSettle();
      expect(find.text(r'Monthly: $9.99'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pro-subscribe-button')));
      await tester.pump();
      expect(find.text('Pro subscriptions are coming soon.'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      final pages = find.byKey(const ValueKey('wallet-purchase-pages'));
      final swipe = await tester.startGesture(tester.getCenter(pages));
      await swipe.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await swipe.moveBy(const Offset(-100, 0));
      await tester.pump(const Duration(milliseconds: 16));
      final subscriptionDuringSwipe = tester
          .widget<Text>(find.text('Subscription'))
          .style!
          .color;
      final gemsDuringSwipe = tester
          .widget<Text>(find.text('Buy Gems'))
          .style!
          .color;
      expect(subscriptionDuringSwipe, isNot(GenesisColors.darkTextPrimary));
      expect(subscriptionDuringSwipe, isNot(GenesisColors.darkTextSecondary));
      expect(gemsDuringSwipe, isNot(GenesisColors.darkTextSecondary));
      expect(
        tester
            .widget<SvgPicture>(
              find.byKey(const ValueKey('subscription-crown-icon')),
            )
            .colorFilter,
        ColorFilter.mode(subscriptionDuringSwipe!, BlendMode.srcIn),
      );
      await swipe.moveBy(const Offset(-190, 0));
      await swipe.up();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Buy Gems')).style?.color,
        GenesisColors.darkTextPrimary,
      );
      expect(
        tester.widget<Text>(find.text('Subscription')).style?.color,
        GenesisColors.darkTextSecondary,
      );
      expect(position.pixels, offset);
      expect(productLoads, 1);
      await tester.drag(pages, const Offset(330, 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Subscription')).style?.color,
        GenesisColors.darkTextPrimary,
      );
      expect(find.text(r'Monthly: $9.99'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wallet-buy-gems-tab')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Buy Gems')).style?.color,
        GenesisColors.darkTextPrimary,
      );
      expect(position.pixels, offset);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'subscription remains usable while gem loading fails on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final products = Completer<List<GemProduct>>();
      final tasks = Completer<List<GemTaskGroup>>();
      final wallet = GemWalletStore(
        loadWallet: () async => const GemWallet(balanceCent: 0),
        readUid: () async => 'u_user',
      );
      addTearDown(wallet.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: GenesisTheme.light(),
          scrollBehavior: const GenesisScrollBehavior(),
          home: GemWalletPage(
            membershipProductsLoader: loadTestMembershipOffers,
            walletStore: wallet,
            productsLoader: (_) => products.future,
            tasksLoader: (_) => tasks.future,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('wallet-subscription-tab')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Wait for the newly visited tab without waiting on the unresolved Gems
      // requests and their loading indicators.
      for (
        var frame = 0;
        frame < 10 &&
            find.byKey(const ValueKey('pro-plan-yearly')).evaluate().isEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(const ValueKey('pro-plan-yearly')), findsOneWidget);
      products.completeError(StateError('offline'));
      tasks.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pro-plan-monthly')));
      await tester.pumpAndSettle();
      expect(find.text(r'Monthly: $9.99'), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('pro-subscribe-button')))
            .bottom,
        lessThan(568),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('developer purchase overlay closes when OK is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                unawaited(showGemBillingPurchaseOverlayPreview(context)),
            child: const Text('Open purchase overlay'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open purchase overlay'));
    await tester.pump();
    expect(find.textContaining('Purchasing Gems'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();
    expect(find.text('Purchase successful!'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase successful!'), findsNothing);
  });

  testWidgets('GemWalletPage reports buy gems page view pay event', (
    tester,
  ) async {
    final telemetry = _CapturingTelemetrySink();
    GenesisTelemetry.setSinkForTesting(telemetry);
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async => _products(),
          tasksLoader: (_) async => _taskGroups(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final events = telemetry.events
        .where(
          (event) =>
              event.category == 'collect.log' && event.name == 'buy_page_show',
        )
        .toList();
    expect(events, hasLength(1));
    expect(events.single.data['action_type'], 'pay_event');
    expect(events.single.data['action'], 'buy_page_show');
    expect(events.single.data['object1'], 'buy_gems_page');
    expect(events.single.data['object2'], isA<String>());
    final trackId = '${events.single.data['object2']}';
    final match = RegExp(r'^track_id_([^_]+)$').firstMatch(trackId);
    expect(match, isNotNull);
  });

  testWidgets('GemWalletPage renders split data and refreshes on resume', (
    tester,
  ) async {
    var productsLoadCount = 0;
    var tasksLoadCount = 0;
    var walletLoadCount = 0;
    final walletStore = GemWalletStore(
      loadWallet: () async {
        walletLoadCount += 1;
        return GemWallet(balanceCent: walletLoadCount == 1 ? 43000 : 52000);
      },
      readUid: () async => 'u_user',
    );
    final billingService = _FakeBillingService();
    addTearDown(walletStore.dispose);
    addTearDown(billingService.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          billingService: billingService,
          productsLoader: (_) async {
            productsLoadCount += 1;
            return _products();
          },
          tasksLoader: (_) async {
            tasksLoadCount += 1;
            return _taskGroups();
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Buy Gems'), findsOneWidget);
    expect(find.byTooltip('Records'), findsOneWidget);
    expect(find.text('430.0'), findsOneWidget);
    expect(find.text('+550'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text(r'$1.49'), findsOneWidget);
    expect(find.text('Starter'), findsOneWidget);
    expect(find.text('Create your first worldo'), findsOneWidget);
    expect(find.byType(GemPurchaseCatalogSection), findsOneWidget);
    final taskButton = find.descendant(
      of: find.byKey(
        const ValueKey<String>('gem-task-action-create_first_worldo'),
      ),
      matching: find.byType(Container),
    );
    final taskButtonDecoration =
        tester.widget<Container>(taskButton).decoration! as BoxDecoration;
    expect(taskButtonDecoration.color, Colors.transparent);
    expect(taskButtonDecoration.border, isNull);
    expect(
      tester.widget<Text>(find.text('Go')).style?.color,
      GenesisColors.redSecondary,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('gem-balance-icon'))).dx,
      tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('gem-product-gem_pack_500')),
          )
          .dx,
    );
    expect(
      tester
              .getTopLeft(
                find.byKey(const ValueKey<String>('gem-product-gem_pack_500')),
              )
              .dy -
          tester
              .getBottomLeft(find.byKey(const ValueKey('gem-balance-panel')))
              .dy,
      10,
    );
    expect(
      tester.widget<SizedBox>(find.byKey(const ValueKey('gem-balance-panel'))),
      isA<SizedBox>(),
    );

    final pageTitleStyle = tester.widget<Text>(find.text('Buy Gems')).style;
    expect(pageTitleStyle?.fontSize, 16);
    expect(pageTitleStyle?.fontWeight, FontWeight.w600);
    expect(pageTitleStyle?.color, GenesisColors.darkTextPrimary);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('gem-balance-panel'))).dy -
          tester.getRect(find.byType(AppBar)).bottom,
      10,
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('wallet-records-icon'))),
      const Size(20, 20),
    );

    final groupTitleStyle = tester.widget<Text>(find.text('Starter')).style;
    expect(groupTitleStyle?.fontSize, 16);
    expect(groupTitleStyle?.height, 20 / 16);
    expect(groupTitleStyle?.fontWeight, FontWeight.w600);
    expect(groupTitleStyle?.color, GenesisColors.darkTextPrimary);

    final taskTitleStyle = tester
        .widget<Text>(find.text('Create your first worldo'))
        .style;
    expect(taskTitleStyle?.fontSize, 14);
    expect(taskTitleStyle?.height, 16 / 14);
    expect(taskTitleStyle?.fontWeight, FontWeight.w600);
    expect(taskTitleStyle?.color, GenesisColors.darkTextPrimary);

    final descriptionStyle = tester
        .widget<Text>(find.text(_wrappingTaskDescription))
        .style;
    expect(descriptionStyle?.fontSize, 12);
    expect(descriptionStyle?.height, 14 / 12);
    expect(descriptionStyle?.fontWeight, FontWeight.w400);
    expect(descriptionStyle?.color, GenesisColors.darkTextTertiary);
    final description = tester.widget<Text>(
      find.text(_wrappingTaskDescription),
    );
    expect(description.maxLines, isNull);
    expect(description.overflow, isNull);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('gem-task-row-create_first_worldo'),
            ),
          )
          .height,
      greaterThan(62),
    );

    final actionStyle = tester.widget<Text>(find.text('Go')).style;
    expect(actionStyle?.fontSize, 12);
    expect(actionStyle?.height, 14 / 12);
    expect(actionStyle?.fontWeight, FontWeight.w600);
    expect(
      tester.getSize(
        find.byKey(
          const ValueKey<String>('gem-task-action-create_first_worldo'),
        ),
      ),
      const Size(64, 24),
    );
    expect(
      tester.getRect(find.text('Go')).right,
      closeTo(
        tester
            .getRect(
              find.byKey(
                const ValueKey<String>('gem-task-action-create_first_worldo'),
              ),
            )
            .right,
        0.1,
      ),
    );
    final taskRewardStyle = tester.widget<Text>(find.text('+50')).style;
    expect(taskRewardStyle?.fontSize, 14);
    expect(taskRewardStyle?.fontWeight, FontWeight.w600);
    expect(taskRewardStyle?.color, GenesisColors.darkTextPrimary);
    final taskRewardIconSize = tester.getSize(
      find.byKey(
        const ValueKey<String>('gem-task-reward-icon-create_first_worldo'),
      ),
    );
    expect(taskRewardIconSize.width, closeTo(16 * 164 / 256, 0.1));
    expect(taskRewardIconSize.height, 16);
    expect(
      tester
          .getRect(
            find.byKey(
              const ValueKey<String>('gem-task-reward-create_first_worldo'),
            ),
          )
          .right,
      tester
          .getRect(
            find.byKey(
              const ValueKey<String>(
                'gem-task-reward-icon-create_first_worldo',
              ),
            ),
          )
          .right,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(productsLoadCount, 2);
    expect(tasksLoadCount, 2);
    expect(walletLoadCount, 2);
    expect(billingService.recoverSources, isEmpty);
    expect(find.text('520.0'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();

    expect(find.text('Join us'), findsOneWidget);
    expect(find.text('Discord'), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);

    final joinUsStyle = tester.widget<Text>(find.text('Join us')).style;
    expect(joinUsStyle?.fontSize, 16);
    expect(joinUsStyle?.height, 20 / 16);
    expect(joinUsStyle?.fontWeight, FontWeight.w600);
    expect(joinUsStyle?.color, GenesisColors.darkTextPrimary);

    final discordStyle = tester.widget<Text>(find.text('Discord')).style;
    expect(discordStyle?.fontSize, 14);
    expect(discordStyle?.height, 16 / 14);
    expect(discordStyle?.fontWeight, FontWeight.w600);
    expect(discordStyle?.color, GenesisColors.darkTextPrimary);
    final joinUsRewardStyle = tester.widget<Text>(find.text('+20')).style;
    expect(joinUsRewardStyle?.fontSize, 14);
    expect(joinUsRewardStyle?.fontWeight, FontWeight.w600);
    expect(joinUsRewardStyle?.color, GenesisColors.darkTextPrimary);
    final followRewardIconSize = tester.getSize(
      find.byKey(const ValueKey<String>('gem-task-reward-icon-discord_follow')),
    );
    expect(followRewardIconSize.width, closeTo(16 * 164 / 256, 0.1));
    expect(followRewardIconSize.height, 16);
    expect(
      tester
          .getRect(
            find.byKey(
              const ValueKey<String>('gem-task-reward-discord_follow'),
            ),
          )
          .right,
      tester
          .getRect(
            find.byKey(
              const ValueKey<String>('gem-task-reward-icon-discord_follow'),
            ),
          )
          .right,
    );

    final followStyle = tester.widget<Text>(find.text('Follow')).style;
    expect(followStyle?.fontSize, 12);
    expect(followStyle?.height, 14 / 12);
    expect(followStyle?.fontWeight, FontWeight.w600);
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('gem-task-action-discord_follow')),
      ),
      const Size(64, 24),
    );
  });

  testWidgets('Records opens Gem Records and supports swipe tab switching', (
    tester,
  ) async {
    var productsLoadCount = 0;
    var tasksLoadCount = 0;
    final walletStore = GemWalletStore(
      loadWallet: () async => GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);
    final requestedScenes = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [genesisPageRouteObserver],
        routes: {
          RouteNames.gemRecords: (_) => GemRecordsPage(
            recordsLoader: ({required scene, required pn, required rn}) async {
              requestedScenes.add(scene);
              return GemRecordList(
                items: [
                  GemRecordItem(
                    ledgerId: 'gl_$scene',
                    amountCent: 5000,
                    scene: 'task',
                    reasonCode: 'daily_checkin',
                    title: scene == 'earned'
                        ? 'Earned reward'
                        : 'Daily check-in',
                    subtitle: 'Starter reward',
                    createdAt: 1783586400,
                    expiresAt: 0,
                  ),
                ],
                total: 1,
                page: 1,
                pageSize: 20,
              );
            },
          ),
        },
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async {
            productsLoadCount += 1;
            return _products();
          },
          tasksLoader: (_) async {
            tasksLoadCount += 1;
            return _taskGroups();
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Records'), findsNothing);
    await tester.tap(find.byTooltip('Records'));
    await tester.pumpAndSettle();

    expect(find.text('Gem Records'), findsOneWidget);
    final recordsTitle = tester.widget<Text>(find.text('Gem Records'));
    expect(
      recordsTitle.style,
      GenesisTypography.pageTitle.copyWith(
        color: GenesisColors.darkTextPrimary,
      ),
    );
    expect(
      tester.getTopLeft(find.byType(TabBar)).dy -
          tester.getRect(find.text('Gem Records')).bottom,
      closeTo(11, 0.1),
    );
    expect(find.text('Daily check-in'), findsOneWidget);
    expect(find.text('Starter reward'), findsNothing);
    expect(find.text(formatGemRecordTimestamp(1783586400)), findsOneWidget);
    expect(requestedScenes, contains('all'));

    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.labelStyle?.fontSize, 14);
    expect(tabs.labelStyle?.height, 20 / 14);
    expect(tabs.labelStyle?.fontWeight, FontWeight.w600);
    expect(tabs.labelColor, GenesisColors.darkTextPrimary);
    expect(tabs.unselectedLabelStyle?.fontSize, 14);
    expect(tabs.unselectedLabelStyle?.height, 20 / 14);
    expect(tabs.unselectedLabelStyle?.fontWeight, FontWeight.w400);
    expect(tabs.unselectedLabelColor, GenesisColors.darkTextSecondary);

    final recordTitleStyle = tester
        .widget<Text>(find.text('Daily check-in'))
        .style;
    expect(recordTitleStyle?.fontSize, 14);
    expect(recordTitleStyle?.height, 17 / 14);
    expect(recordTitleStyle?.fontWeight, FontWeight.w600);
    expect(recordTitleStyle?.color, GenesisColors.darkTextPrimary);

    final recordTimeStyle = tester
        .widget<Text>(find.text(formatGemRecordTimestamp(1783586400)))
        .style;
    expect(recordTimeStyle?.fontSize, 12);
    expect(recordTimeStyle?.height, 14 / 12);
    expect(recordTimeStyle?.fontWeight, FontWeight.w400);
    expect(recordTimeStyle?.color, GenesisColors.darkTextTertiary);

    final amountStyle = tester.widget<Text>(find.text('+50.0')).style;
    expect(amountStyle?.fontSize, 14);
    expect(amountStyle?.height, 20 / 14);
    expect(amountStyle?.fontWeight, FontWeight.w600);
    expect(amountStyle?.color, GenesisColors.redSecondary);

    await tester.drag(find.byType(TabBarView), const Offset(-420, 0));
    await tester.pumpAndSettle();

    expect(requestedScenes, contains('earned'));
    expect(find.text('Earned reward'), findsOneWidget);

    Navigator.of(tester.element(find.text('Gem Records'))).pop();
    await tester.pumpAndSettle();

    expect(productsLoadCount, 1);
    expect(tasksLoadCount, 1);
  });

  testWidgets('task section remains available when products fail', (
    tester,
  ) async {
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async => throw Exception('products failed'),
          tasksLoader: (_) async => _taskGroups(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unable to load gem packs.'), findsOneWidget);
    expect(find.text('Starter'), findsOneWidget);
    expect(find.text('Create your first worldo'), findsOneWidget);
  });

  testWidgets('wallet endpoint balance stays independent from catalog data', (
    tester,
  ) async {
    var walletBalance = 43000;
    final walletStore = GemWalletStore(
      loadWallet: () async => GemWallet(balanceCent: walletBalance),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async => _products(),
          tasksLoader: (_) async => _taskGroups(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('430.0'), findsOneWidget);

    walletBalance = 52000;
    await walletStore.refreshAfterEntitlementGranted();
    await tester.pump();

    expect(find.text('520.0'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('520.0'), findsOneWidget);
  });

  testWidgets('loads all data together but only gates on products and wallet', (
    tester,
  ) async {
    final walletResult = Completer<GemWallet>();
    final productsResult = Completer<List<GemProduct>>();
    final tasksResult = Completer<List<GemTaskGroup>>();
    final requests = <String>[];
    final walletStore = GemWalletStore(
      loadWallet: () {
        requests.add('wallet');
        return walletResult.future;
      },
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) {
            requests.add('products');
            return productsResult.future;
          },
          tasksLoader: (_) {
            requests.add('tasks');
            return tasksResult.future;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(requests, containsAll(<String>['products', 'wallet', 'tasks']));
    expect(find.byType(GemPurchaseCatalogSection), findsNothing);

    productsResult.complete(_products());
    await tester.pump();

    expect(find.byType(GemPurchaseCatalogSection), findsNothing);

    walletResult.complete(const GemWallet(balanceCent: 43000));
    await tester.pump();
    await tester.pump();

    expect(find.byType(GemPurchaseCatalogSection), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('gem-wallet-balance')))
          .textSpan!
          .toPlainText(),
      '430.0',
    );
    expect(find.text('Starter'), findsNothing);

    tasksResult.complete(_taskGroups());
    await tester.pumpAndSettle();

    expect(find.text('Starter'), findsOneWidget);
  });

  testWidgets('GemWalletPage hides original amount without bonus gems', (
    tester,
  ) async {
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async => _products(bonusGemsCent: 0),
          tasksLoader: (_) async => _taskGroups(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+500'), findsOneWidget);
  });

  testWidgets('tapping a product immediately shows purchase processing', (
    tester,
  ) async {
    final systemUiOverlayStyleCalls = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
            systemUiOverlayStyleCalls.add(
              Map<dynamic, dynamic>.from(call.arguments as Map),
            );
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final telemetry = _CapturingTelemetrySink();
    GenesisTelemetry.setSinkForTesting(telemetry);
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    final billing = _FakeBillingService();
    final purchaseCompleter = Completer<void>();
    billing.purchaseCompleter = purchaseCompleter;
    addTearDown(walletStore.dispose);
    addTearDown(billing.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          billingService: billing,
          productsLoader: (_) async => _products(),
          tasksLoader: (_) async => _taskGroups(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).systemOverlayStyle,
      SystemUiOverlayStyle.light,
    );
    systemUiOverlayStyleCalls.clear();

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-product-gem_pack_500')),
    );

    expect(
      SystemChrome.latestStyle?.statusBarColor,
      anyOf(isNull, Colors.transparent),
    );
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
    expect(
      systemUiOverlayStyleCalls.where(
        (call) =>
            call['statusBarColor'] != null &&
            call['statusBarColor'] != Colors.transparent.toARGB32(),
      ),
      isEmpty,
    );

    await tester.pump();
    expect(
      SystemChrome.latestStyle?.statusBarColor,
      anyOf(isNull, Colors.transparent),
    );
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);

    await tester.pump(const Duration(milliseconds: 16));

    expect(
      SystemChrome.latestStyle?.statusBarColor,
      anyOf(isNull, Colors.transparent),
    );
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
    expect(
      systemUiOverlayStyleCalls.where(
        (call) =>
            call['statusBarColor'] != null &&
            call['statusBarColor'] != Colors.transparent.toARGB32(),
      ),
      isEmpty,
    );

    expect(billing.purchasedProducts, hasLength(1));
    expect(billing.purchasedProducts.single.productId, 'gem_pack_500');
    expect(billing.storeRecoveryCount, 1);
    expect(
      billing.recoveredProductCatalog?.map((product) => product.productId),
      _products().map((product) => product.productId),
    );
    expect(billing.purchaseSources, [BillingPurchaseSource.buyGemsPage]);
    expect(billing.purchaseTrackIds, hasLength(1));
    final showEvent = telemetry.events.singleWhere(
      (event) =>
          event.category == 'collect.log' && event.name == 'buy_page_show',
    );
    final showMatch = RegExp(
      r'^track_id_([^_]+)$',
    ).firstMatch('${showEvent.data['object2']}');
    final purchaseMatch = RegExp(
      r'^track_id_([^_]+)_([^_]+)$',
    ).firstMatch(billing.purchaseTrackIds.single);
    expect(showMatch, isNotNull);
    expect(purchaseMatch, isNotNull);
    expect(purchaseMatch!.group(1), showMatch!.group(1));
    expect(purchaseMatch.group(2), isNotEmpty);
    expect(find.textContaining('Purchasing Gems'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<PopScope>(find.byType(PopScope))
          .any((scope) => scope.canPop == false),
      isTrue,
    );

    expect(purchaseCompleter.isCompleted, isFalse);
    purchaseCompleter.complete();
    await tester.pump();

    billing.emitProcessing();
    await tester.pump();
    expect(find.textContaining('Purchasing Gems'), findsOneWidget);

    billing.emitSuccess();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.idle();
    expect(
      SystemChrome.latestStyle?.statusBarColor,
      anyOf(isNull, Colors.transparent),
    );
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
  });

  testWidgets('store recovery starts only after products load succeeds', (
    tester,
  ) async {
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    final billing = _FakeBillingService();
    final productsCompleter = Completer<List<GemProduct>>();
    addTearDown(walletStore.dispose);
    addTearDown(billing.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          billingService: billing,
          productsLoader: (_) => productsCompleter.future,
          tasksLoader: (_) async => _taskGroups(),
        ),
      ),
    );
    await tester.pump();

    expect(billing.storeRecoveryCount, 0);

    productsCompleter.complete(_products());
    await tester.pumpAndSettle();

    expect(billing.storeRecoveryCount, 1);
    expect(
      billing.recoveredProductCatalog?.map((product) => product.productId),
      _products().map((product) => product.productId),
    );
  });

  testWidgets('store recovery failure does not prevent a new purchase', (
    tester,
  ) async {
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    final billing = _FakeBillingService()..storeRecoveryResult = false;
    addTearDown(walletStore.dispose);
    addTearDown(billing.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          billingService: billing,
          productsLoader: (_) async => _products(),
          tasksLoader: (_) async => _taskGroups(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-product-gem_pack_500')),
    );
    await tester.pump();

    expect(billing.storeRecoveryCount, 1);
    expect(billing.purchasedProducts, hasLength(1));
    expect(find.textContaining('Purchasing Gems'), findsOneWidget);
  });

  testWidgets('store recovery exception does not escape the page', (
    tester,
  ) async {
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    final billing = _FakeBillingService()
      ..storeRecoveryError = StateError('store recovery failed');
    addTearDown(walletStore.dispose);
    addTearDown(billing.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          billingService: billing,
          productsLoader: (_) async => _products(),
          tasksLoader: (_) async => _taskGroups(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(billing.storeRecoveryCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('other gem products ignore taps during a purchase', (
    tester,
  ) async {
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    final billing = _FakeBillingService();
    addTearDown(walletStore.dispose);
    addTearDown(billing.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          billingService: billing,
          productsLoader: (_) async => [
            _product('gem_pack_500'),
            _product('gem_pack_1100'),
          ],
          tasksLoader: (_) async => _taskGroups(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-product-gem_pack_500')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('gem-product-gem_pack_1100')),
    );
    await tester.pump();

    expect(billing.purchasedProducts, hasLength(1));
    expect(billing.purchasedProducts.single.productId, 'gem_pack_500');
  });

  testWidgets('billing failure closes immediate processing and shows toast', (
    tester,
  ) async {
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    final billing = _FakeBillingService();
    addTearDown(walletStore.dispose);
    addTearDown(billing.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          billingService: billing,
          productsLoader: (_) async => _products(),
          tasksLoader: (_) async => _taskGroups(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-product-gem_pack_500')),
    );
    await tester.pump();
    expect(find.textContaining('Purchasing Gems'), findsOneWidget);

    billing.emitFailure();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Purchasing Gems'), findsNothing);
    expect(find.text('Purchase failed.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('billing success refreshes products tasks and wallet', (
    tester,
  ) async {
    var productsLoadCount = 0;
    var tasksLoadCount = 0;
    var walletLoadCount = 0;
    final walletStore = GemWalletStore(
      loadWallet: () async {
        walletLoadCount += 1;
        return const GemWallet(balanceCent: 43000);
      },
      readUid: () async => 'u_user',
    );
    final billing = _FakeBillingService();
    addTearDown(walletStore.dispose);
    addTearDown(billing.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          billingService: billing,
          productsLoader: (_) async {
            productsLoadCount += 1;
            return _products();
          },
          tasksLoader: (_) async {
            tasksLoadCount += 1;
            return _taskGroups();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    billing.emitSuccess();
    await tester.pumpAndSettle();

    expect(productsLoadCount, 2);
    expect(tasksLoadCount, 2);
    expect(walletLoadCount, 2);
    _expectGrantedSuccessDialog(tester);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('billing processing dialog blocks interaction until success OK', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    final billing = _FakeBillingService();
    addTearDown(walletStore.dispose);
    addTearDown(billing.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          billingService: billing,
          productsLoader: (_) async => _products(),
          tasksLoader: (_) async => _taskGroups(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    billing.emitProcessing();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Purchasing Gems'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<PopScope>(find.byType(PopScope))
          .any((scope) => scope.canPop == false),
      isTrue,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('genesis-action-box-title-row')))
          .height,
      202,
    );
    final processingActionBoxSize = tester.getSize(
      find.byKey(const ValueKey('genesis-action-box-attached-cancel')),
    );

    await tester.tapAt(Offset.zero);
    await tester.pump();
    expect(find.textContaining('Purchasing Gems'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Purchasing Gems'), findsOneWidget);

    billing.emitSuccess(grantedGemsCent: 100000);
    await tester.pumpAndSettle();

    _expectGrantedSuccessDialog(tester, grantedText: '1,000.0');
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('billing-purchase-granted-fit')),
          )
          .width,
      lessThanOrEqualTo(
        tester
            .getSize(find.byKey(const ValueKey('genesis-action-box-title-row')))
            .width,
      ),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('billing-purchase-granted-line')),
          )
          .height,
      lessThanOrEqualTo(21),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('genesis-action-box-title-row')))
          .height,
      150,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('genesis-action-box-attached-cancel')),
      ),
      processingActionBoxSize,
    );

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Purchase successful!'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Purchase successful!'), findsNothing);
    expect(find.text('Go Chat Now.'), findsNothing);
  });

  testWidgets('billing accepted closes processing and shows its message', (
    tester,
  ) async {
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    final billing = _FakeBillingService();
    addTearDown(walletStore.dispose);
    addTearDown(billing.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          billingService: billing,
          productsLoader: (_) async => _products(),
          tasksLoader: (_) async => _taskGroups(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    billing.emitProcessing();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Purchasing Gems'), findsOneWidget);

    billing.emitAccepted();
    await tester.pump();

    expect(
      find.text(
        'Payment received.\nYour Gems will be added shortly. Please check your balance again in a moment.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Purchasing Gems'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('task button always displays backend action text', (
    tester,
  ) async {
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);
    var claimCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async => const [],
          tasksLoader: (_) async => [
            _taskGroup(
              _task(
                taskCode: 'daily_checkin',
                status: 'claimed',
                actionText: 'Received',
              ),
            ),
          ],
          taskClaimer: (_) async {
            claimCalls += 1;
            return const GemTaskActionResult(status: 'claimed');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Received'), findsOneWidget);
    expect(find.text('Claimed'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('gem-task-action-daily_checkin')),
    );
    await tester.pump();
    expect(claimCalls, 0);
  });

  testWidgets('in-progress tasks show user-facing guidance', (tester) async {
    const messages = <String, String>{
      'launch_first_world':
          'Open a Worldo you like, then Launch your own world.',
      'invite_friend': 'Open a World, then tap Invite in the detail panel.',
      'write_comment': 'Open a Worldo you liked, then write a post in Discuss.',
      'request_join_world':
          'Open a World you haven’t joined, then request to join it.',
      'send_message': 'Send messages in your world.',
      'progress_world': 'Open your playing World, then tap Tick Now.',
    };
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    for (final entry in messages.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: GemWalletPage(
            key: ValueKey<String>('guidance-${entry.key}'),
            walletStore: walletStore,
            productsLoader: (_) async => const [],
            tasksLoader: (_) async => [
              _taskGroup(
                _task(
                  taskCode: entry.key,
                  status: 'in_progress',
                  actionText: 'Go',
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(ValueKey<String>('gem-task-action-${entry.key}')),
      );
      await tester.pump();
      if (entry.key == 'daily_checkin') {
        await tester.pumpAndSettle();
        expect(find.text('Daily Check-in'), findsOneWidget);
        await tester.tap(find.text('Check in').last);
        await tester.pumpAndSettle();
      }
      expect(find.text(entry.value), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    }
  });

  testWidgets('progress world task uses Tick Now copy', (tester) async {
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async => const [],
          tasksLoader: (_) async => [
            _taskGroup(
              _task(
                taskCode: 'progress_world',
                status: 'in_progress',
                actionText: 'Go',
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Run a Tick'), findsOneWidget);
    expect(
      find.text('Open one of your playing Worlds and tap Tick Now.'),
      findsOneWidget,
    );
    expect(find.text('Task title'), findsNothing);
    expect(find.text('Task description'), findsNothing);
  });

  testWidgets('daily check-in reports once and refreshes task and wallet', (
    tester,
  ) async {
    final telemetry = _CapturingTelemetrySink();
    GenesisTelemetry.setSinkForTesting(telemetry);
    final reportResult = Completer<GemTaskActionResult>();
    var reportCalls = 0;
    var claimCalls = 0;
    var productsLoadCount = 0;
    var tasksLoadCount = 0;
    var walletLoadCount = 0;
    final walletStore = GemWalletStore(
      loadWallet: () async {
        walletLoadCount += 1;
        return const GemWallet(balanceCent: 43000);
      },
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async {
            productsLoadCount += 1;
            return const [];
          },
          tasksLoader: (_) async {
            tasksLoadCount += 1;
            final completed = tasksLoadCount > 1;
            return [
              _taskGroup(
                _task(
                  taskCode: 'daily_checkin',
                  status: completed ? 'claimed' : 'in_progress',
                  actionText: completed ? 'Received' : 'Check in',
                ),
              ),
            ];
          },
          taskReporter: (taskCode) {
            expect(taskCode, 'daily_checkin');
            reportCalls += 1;
            return reportResult.future;
          },
          taskClaimer: (taskCode) async {
            expect(taskCode, 'daily_checkin');
            claimCalls += 1;
            return const GemTaskActionResult(status: 'claimed');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(
      const ValueKey<String>('gem-task-action-daily_checkin'),
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Daily Check-in'), findsOneWidget);
    expect(reportCalls, 0);
    expect(claimCalls, 0);
    // Dismissing the dialog must not perform the check-in or claim.
    Navigator.of(tester.element(find.text('Daily Check-in'))).pop();
    await tester.pumpAndSettle();
    expect(reportCalls, 0);
    expect(claimCalls, 0);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check in').last);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    expect(reportCalls, 1);

    reportResult.complete(const GemTaskActionResult(status: 'claimable'));
    await tester.pumpAndSettle();

    expect(claimCalls, 1);
    expect(productsLoadCount, 1);
    expect(tasksLoadCount, 2);
    expect(walletLoadCount, 2);
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('Check in successful!'), findsOneWidget);
    _expectTaskClaimedEvent(telemetry, 'daily_checkin');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('daily check-in does not expose intermediate Claim state', (
    tester,
  ) async {
    final claimResult = Completer<GemTaskActionResult>();
    final refreshedTasks = Completer<List<GemTaskGroup>>();
    var tasksLoadCount = 0;
    var claimCalls = 0;
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async => const [],
          tasksLoader: (_) {
            tasksLoadCount += 1;
            if (tasksLoadCount == 1) {
              return Future.value([
                _taskGroup(
                  _task(
                    taskCode: 'daily_checkin',
                    status: 'in_progress',
                    actionText: 'Check in',
                  ),
                ),
              ]);
            }
            return refreshedTasks.future;
          },
          taskReporter: (_) async =>
              const GemTaskActionResult(status: 'claimable'),
          taskClaimer: (_) {
            claimCalls += 1;
            return claimResult.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-task-action-daily_checkin')),
    );
    await tester.pumpAndSettle();
    expect(claimCalls, 0);
    await tester.tap(find.text('Check in').last);
    await tester.pumpAndSettle();

    expect(claimCalls, 1);
    expect(find.text('Claim'), findsNothing);

    claimResult.complete(const GemTaskActionResult(status: 'claimed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Check in successful!'), findsOneWidget);

    refreshedTasks.complete([
      _taskGroup(
        _task(
          taskCode: 'daily_checkin',
          status: 'claimed',
          actionText: 'Received',
        ),
      ),
    ]);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('task reporting shows task-specific failure messages', (
    tester,
  ) async {
    const messages = <String, String>{
      'daily_checkin': 'Check in failed.',
      'discord_follow': 'Follow failed.',
    };
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    for (final entry in messages.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: GemWalletPage(
            key: ValueKey<String>('report-failure-${entry.key}'),
            walletStore: walletStore,
            productsLoader: (_) async => const [],
            tasksLoader: (_) async => [
              _taskGroup(
                _task(
                  taskCode: entry.key,
                  status: 'in_progress',
                  actionText: 'Go',
                ),
              ),
            ],
            taskReporter: (_) async => throw Exception('report failed'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(ValueKey<String>('gem-task-action-${entry.key}')),
      );
      await tester.pump();
      if (entry.key == 'daily_checkin') {
        await tester.pumpAndSettle();
        expect(find.text('Daily Check-in'), findsOneWidget);
        await tester.tap(find.text('Check in').last);
        await tester.pumpAndSettle();
      }
      expect(find.text(entry.value), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    }
  });

  testWidgets('claim failure uses English toast', (tester) async {
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async => const [],
          tasksLoader: (_) async => [
            _taskGroup(
              _task(
                taskCode: 'daily_checkin',
                status: 'claimable',
                actionText: 'Collect',
              ),
            ),
          ],
          taskClaimer: (_) async =>
              const GemTaskActionResult(status: 'claimable'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-task-action-daily_checkin')),
    );
    await tester.pump();

    await tester.pumpAndSettle();
    expect(find.text('Daily Check-in'), findsOneWidget);
    expect(find.text('Claim failed.'), findsNothing);
    await tester.tap(find.text('Claim').last);
    await tester.pumpAndSettle();
    expect(find.text('Claim failed.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Discord follow opens the Me page invite and reports the task', (
    tester,
  ) async {
    final launchedUris = <Uri>[];
    final reportedCodes = <String>[];
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async => const [],
          tasksLoader: (_) async => _taskGroups(),
          discordLauncher: (uri) async {
            launchedUris.add(uri);
            return true;
          },
          taskReporter: (taskCode) async {
            reportedCodes.add(taskCode);
            return const GemTaskActionResult(status: 'claimable');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final followButton = find.byKey(
      const ValueKey<String>('gem-task-action-discord_follow'),
    );
    await tester.scrollUntilVisible(
      followButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(followButton);
    await tester.pumpAndSettle();

    expect(launchedUris, [Uri.parse('https://discord.gg/wuKHk7cyX7')]);
    expect(reportedCodes, ['discord_follow']);
  });

  testWidgets('repeated Discord row taps open every time but report once', (
    tester,
  ) async {
    final reportResult = Completer<GemTaskActionResult>();
    final launchedUris = <Uri>[];
    var reportCalls = 0;
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async => const [],
          tasksLoader: (_) async => [
            _joinUsGroup(status: 'in_progress', actionText: 'Follow'),
          ],
          discordLauncher: (uri) async {
            launchedUris.add(uri);
            return true;
          },
          taskReporter: (_) {
            reportCalls += 1;
            return reportResult.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(
      const ValueKey<String>('gem-join-us-row-discord_follow'),
    );
    await tester.tap(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();

    expect(launchedUris, [
      Uri.parse('https://discord.gg/wuKHk7cyX7'),
      Uri.parse('https://discord.gg/wuKHk7cyX7'),
    ]);
    expect(reportCalls, 1);

    reportResult.complete(const GemTaskActionResult(status: 'claimable'));
    await tester.pumpAndSettle();
  });

  testWidgets('Discord row always opens while claimable button only claims', (
    tester,
  ) async {
    final launchedUris = <Uri>[];
    final reportedCodes = <String>[];
    final claimedCodes = <String>[];
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async => const [],
          tasksLoader: (_) async => [
            _joinUsGroup(status: 'claimable', actionText: 'Claim'),
          ],
          discordLauncher: (uri) async {
            launchedUris.add(uri);
            return true;
          },
          taskReporter: (taskCode) async {
            reportedCodes.add(taskCode);
            return const GemTaskActionResult(status: 'claimable');
          },
          taskClaimer: (taskCode) async {
            claimedCodes.add(taskCode);
            return const GemTaskActionResult(status: 'claimed');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final claimButton = find.descendant(
      of: find.byKey(const ValueKey<String>('gem-task-action-discord_follow')),
      matching: find.byType(Container),
    );
    final claimButtonDecoration =
        tester.widget<Container>(claimButton).decoration! as BoxDecoration;
    expect(claimButtonDecoration.color, Colors.transparent);
    expect(claimButtonDecoration.border, isNull);
    expect(
      tester.widget<Text>(find.text('Claim')).style?.color,
      GenesisColors.redSecondary,
    );

    final row = find.byKey(
      const ValueKey<String>('gem-join-us-row-discord_follow'),
    );
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(launchedUris, [Uri.parse('https://discord.gg/wuKHk7cyX7')]);
    expect(reportedCodes, isEmpty);
    expect(claimedCodes, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-task-action-discord_follow')),
    );
    await tester.pumpAndSettle();

    expect(launchedUris, hasLength(1));
    expect(reportedCodes, isEmpty);
    expect(claimedCodes, ['discord_follow']);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('claimed Discord button is disabled but its row still opens', (
    tester,
  ) async {
    final launchedUris = <Uri>[];
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async => const [],
          tasksLoader: (_) async => [
            _joinUsGroup(status: 'claimed', actionText: 'Claimed'),
          ],
          discordLauncher: (uri) async {
            launchedUris.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final claimedButton = find.descendant(
      of: find.byKey(const ValueKey<String>('gem-task-action-discord_follow')),
      matching: find.byType(Container),
    );
    final claimedButtonDecoration =
        tester.widget<Container>(claimedButton).decoration! as BoxDecoration;
    expect(claimedButtonDecoration.color, Colors.transparent);
    expect(claimedButtonDecoration.border, isNull);
    expect(
      tester.widget<Text>(find.text('Claimed')).style?.color,
      GenesisColors.darkTextTertiary,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-task-action-discord_follow')),
    );
    await tester.pump();
    expect(launchedUris, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-join-us-row-discord_follow')),
    );
    await tester.pumpAndSettle();
    expect(launchedUris, [Uri.parse('https://discord.gg/wuKHk7cyX7')]);
  });

  testWidgets('claimable task shows its reward in success dialog', (
    tester,
  ) async {
    final telemetry = _CapturingTelemetrySink();
    GenesisTelemetry.setSinkForTesting(telemetry);
    var productsLoadCount = 0;
    var tasksLoadCount = 0;
    final claimedCodes = <String>[];
    final walletStore = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 43000),
      readUid: () async => 'u_user',
    );
    addTearDown(walletStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GemWalletPage(
          walletStore: walletStore,
          productsLoader: (_) async {
            productsLoadCount += 1;
            return const [];
          },
          tasksLoader: (_) async {
            tasksLoadCount += 1;
            final claimed = tasksLoadCount > 1;
            return [
              _taskGroup(
                _task(
                  taskCode: 'discord_follow',
                  status: claimed ? 'claimed' : 'claimable',
                  actionText: claimed ? 'Received' : 'Collect',
                ),
              ),
            ];
          },
          taskClaimer: (taskCode) async {
            claimedCodes.add(taskCode);
            return const GemTaskActionResult(status: 'claimed');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-task-action-discord_follow')),
    );
    await tester.pump();
    await tester.pump();

    expect(claimedCodes, ['discord_follow']);
    expect(productsLoadCount, 1);
    expect(tasksLoadCount, 2);
    expect(find.text('Claim successful!'), findsOneWidget);
    _expectTaskClaimedEvent(telemetry, 'discord_follow');
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('gem-task-reward-value')),
          )
          .data,
      '+20',
    );
    expect(
      find.byKey(const ValueKey<String>('gem-task-reward-icon')),
      findsOneWidget,
    );
    expect(find.text('Received'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}

class _CapturingTelemetrySink implements GenesisTelemetrySink {
  final events = <GenesisTelemetryEvent>[];

  @override
  Future<void> captureException(Object error, StackTrace stackTrace) async {}

  @override
  Future<void> record(GenesisTelemetryEvent event) async {
    events.add(event);
  }

  @override
  Future<void> setContext(GenesisTelemetryContext context) async {}

  @override
  Future<void> setUserId(String? uid) async {}
}

void _expectGrantedSuccessDialog(
  WidgetTester tester, {
  String grantedText = '550.0',
}) {
  expect(find.text('Purchase successful!'), findsOneWidget);
  expect(find.text('Go Chat Now.'), findsNothing);
  expect(find.byType(GenesisActionBox<bool>), findsOneWidget);
  final successTitle = tester.widget<Text>(
    find.byKey(const ValueKey<String>('billing-purchase-success-title')),
  );
  expect(successTitle.style?.fontSize, 16);
  expect(successTitle.style?.fontWeight, FontWeight.w600);
  expect(
    tester
        .getSize(
          find.byKey(
            const ValueKey<String>('billing-purchase-success-line-gap'),
          ),
        )
        .height,
    12,
  );
  final grantedLine = tester.widget<Text>(
    find.byKey(const ValueKey<String>('billing-purchase-granted-line')),
  );
  expect(grantedLine.style?.fontSize, 14);
  expect(grantedLine.style?.fontWeight, FontWeight.w400);
  final spans = (grantedLine.textSpan! as TextSpan).children!;
  expect(spans[0], isA<WidgetSpan>());
  expect(
    find.byKey(const ValueKey<String>('billing-purchase-granted-icon')),
    findsOneWidget,
  );
  expect((spans[1] as TextSpan).text, grantedText);
  expect((spans[1] as TextSpan).style?.color, GenesisColors.redSecondary);
  expect((spans[2] as TextSpan).text, ' Gems have been granted.');
  final okText = tester.widget<Text>(find.text('OK'));
  expect(okText.style?.fontSize, 15);
  expect(okText.style?.fontWeight, FontWeight.w600);
  expect(
    tester
        .getSize(find.byKey(const ValueKey('genesis-action-box-action-row')))
        .height,
    GenesisActionBox.defaultRowHeight,
  );
  expect(find.byType(SvgPicture), findsWidgets);
}

void _expectTaskClaimedEvent(
  _CapturingTelemetrySink telemetry,
  String taskCode,
) {
  final events = telemetry.events
      .where(
        (event) =>
            event.category == 'collect.log' && event.name == 'task_claimed',
      )
      .toList();
  expect(events, hasLength(1));
  expect(events.single.data, <String, Object?>{
    'action_type': 'pay_event',
    'action': 'task_claimed',
    'object1': taskCode,
  });
}

class _FakeBillingService implements BillingService {
  final ValueNotifier<BillingState> _state = ValueNotifier<BillingState>(
    BillingState(storeAvailable: true),
  );
  final StreamController<BillingUiEvent> _events =
      StreamController<BillingUiEvent>.broadcast();
  final List<GemProduct> purchasedProducts = <GemProduct>[];
  final List<BillingPurchaseSource> purchaseSources = <BillingPurchaseSource>[];
  final List<String> purchaseTrackIds = <String>[];
  final List<BillingRecoverySource> recoverSources = <BillingRecoverySource>[];
  Completer<void>? purchaseCompleter;
  bool storeRecoveryResult = true;
  Object? storeRecoveryError;
  int storeRecoveryCount = 0;
  int startCount = 0;
  List<GemProduct>? recoveredProductCatalog;

  @override
  Stream<BillingUiEvent> get events => _events.stream;

  @override
  ValueListenable<BillingState> get state => _state;

  @override
  Future<void> purchaseGem(
    GemProduct product, {
    BillingPurchaseSource source = BillingPurchaseSource.buyGemsPage,
    String payTrackId = '',
  }) async {
    purchasedProducts.add(product);
    purchaseSources.add(source);
    purchaseTrackIds.add(payTrackId);
    final completer = purchaseCompleter;
    if (completer != null) await completer.future;
    _state.value = BillingState(
      storeAvailable: true,
      busyProductIds: <String>{product.productId},
    );
  }

  @override
  Future<void> recover(BillingRecoverySource source) async {
    recoverSources.add(source);
  }

  @override
  Future<bool> recoverStorePurchases({List<GemProduct>? productCatalog}) async {
    storeRecoveryCount += 1;
    recoveredProductCatalog = productCatalog;
    final error = storeRecoveryError;
    if (error != null) throw error;
    return storeRecoveryResult;
  }

  @override
  void resetForSession() {}

  @override
  Future<void> start() async {
    startCount++;
  }

  void emitProcessing() {
    _events.add(
      const BillingUiEvent(
        kind: BillingUiEventKind.processing,
        productId: 'gem_pack_500',
        attemptId: 'pay_test',
        message: 'Purchasing Gems',
      ),
    );
  }

  void emitSuccess({int grantedGemsCent = 55000}) {
    _events.add(
      BillingUiEvent(
        kind: BillingUiEventKind.success,
        productId: 'gem_pack_500',
        attemptId: 'pay_test',
        message: 'Purchase successful!',
        grantedGemsCent: grantedGemsCent,
      ),
    );
  }

  void emitAccepted() {
    _events.add(
      const BillingUiEvent(
        kind: BillingUiEventKind.accepted,
        productId: 'gem_pack_500',
        attemptId: 'pay_test',
        message:
            'Payment received.\nYour Gems will be added shortly. Please check your balance again in a moment.',
      ),
    );
  }

  void emitFailure() {
    _state.value = BillingState(storeAvailable: true);
    _events.add(
      const BillingUiEvent(
        kind: BillingUiEventKind.failure,
        productId: 'gem_pack_500',
        attemptId: 'pay_test',
        message: 'Purchase failed.',
      ),
    );
  }

  @override
  void dispose() {
    _state.dispose();
    _events.close();
  }
}

List<GemProduct> _products({int bonusGemsCent = 5000}) {
  return [_product('gem_pack_500', bonusGemsCent: bonusGemsCent)];
}

List<GemTaskGroup> _taskGroups() {
  return const [
    GemTaskGroup(
      groupCode: 'starter',
      groupTitle: 'Starter',
      tasks: [
        GemTask(
          taskCode: 'create_first_worldo',
          title: 'Create your first worldo',
          description: _wrappingTaskDescription,
          rewardGemsCent: 5000,
          rewardValidDays: 30,
          cycleType: 'once',
          cycleKey: '',
          progress: 0,
          targetCount: 1,
          progressText: '0/1',
          status: 'in_progress',
          actionText: 'Go',
        ),
      ],
    ),
    GemTaskGroup(
      groupCode: 'join_us',
      groupTitle: 'Join us',
      tasks: [
        GemTask(
          taskCode: 'discord_follow',
          title: 'Discord',
          description: 'Join our Discord community.',
          rewardGemsCent: 2000,
          rewardValidDays: 30,
          cycleType: 'once',
          cycleKey: '',
          progress: 0,
          targetCount: 1,
          progressText: '0/1',
          status: 'in_progress',
          actionText: 'Follow',
        ),
      ],
    ),
  ];
}

GemTaskGroup _taskGroup(GemTask task) {
  return GemTaskGroup(
    groupCode: 'starter',
    groupTitle: 'Starter',
    tasks: [task],
  );
}

GemTaskGroup _joinUsGroup({
  required String status,
  required String actionText,
}) {
  return GemTaskGroup(
    groupCode: 'join_us',
    groupTitle: 'Join us',
    tasks: [
      _task(taskCode: 'discord_follow', status: status, actionText: actionText),
    ],
  );
}

GemTask _task({
  required String taskCode,
  required String status,
  required String actionText,
}) {
  return GemTask(
    taskCode: taskCode,
    title: 'Task title',
    description: 'Task description',
    rewardGemsCent: 2000,
    rewardValidDays: 30,
    cycleType: 'once',
    cycleKey: '',
    progress: 0,
    targetCount: 1,
    progressText: '0/1',
    status: status,
    actionText: actionText,
  );
}

GemProduct _product(String productId, {int bonusGemsCent = 5000}) {
  final amount = productId == 'gem_pack_1100' ? 590 : 149;
  final gemsCent = productId == 'gem_pack_1100' ? 110000 : 50000;
  return GemProduct(
    productId: productId,
    appleProductId: 'com.worldo.$productId',
    googleProductId: 'worldo_$productId',
    baseGemsCent: gemsCent,
    bonusGemsCent: bonusGemsCent,
    priceCurrencyCode: 'USD',
    priceAmount: amount,
    canPurchase: true,
    activityType: 'none',
  );
}

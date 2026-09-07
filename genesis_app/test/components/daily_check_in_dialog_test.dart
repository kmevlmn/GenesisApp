import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/gems/daily_check_in_dialog.dart';
import 'package:genesis_flutter_android/components/gems/pro_subscription_content.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

void main() {
  testWidgets(
    'daily check-in shows success and dismisses after three seconds',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const GenesisScrollBehavior(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final checkedIn = await showDailyCheckInDialog(
                  context,
                  status: DailyCheckInDialogStatus.checkIn,
                );
                if (checkedIn && context.mounted) {
                  await showDailyCheckInSuccessDialog(context);
                }
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Daily Check-in'), findsOneWidget);
      expect(find.text('+50'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('gem-task-reward-icon')),
        findsOneWidget,
      );
      expect(find.text('Check in'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Get 100'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Check in')).style?.fontWeight,
        FontWeight.w400,
      );
      expect(
        tester.widget<Text>(find.text('Get 100')).style?.color,
        const Color(0xFFFF2442),
      );
      expect(
        tester.widget<Text>(find.text('Check in')).style?.color,
        const Color(0xFF111111),
      );
      expect(
        tester.getCenter(find.text('Get 100')).dy,
        lessThan(tester.getCenter(find.text('Check in')).dy),
      );
      final gem = find.byKey(const ValueKey('daily-check-in-subscription-gem'));
      expect(tester.getSize(gem).height, 16);
      expect(
        tester.getTopLeft(gem).dx - tester.getTopRight(find.text('Get 100')).dx,
        4,
      );

      await tester.tap(find.text('Check in'));
      await tester.pumpAndSettle();

      expect(find.text('Check in successful!'), findsOneWidget);
      expect(find.text('+50'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2999));
      expect(find.text('Check in successful!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Check in successful!'), findsNothing);
    },
  );

  testWidgets('Get 100 opens Subscription without performing check-in', (
    tester,
  ) async {
    bool? checkedIn;
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const GenesisScrollBehavior(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              checkedIn = await showDailyCheckInDialog(
                context,
                status: DailyCheckInDialogStatus.checkIn,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get 100'));
    await tester.pumpAndSettle();
    expect(find.byType(ProSubscriptionContent), findsOneWidget);
    expect(find.text('Daily Check-in'), findsNothing);
    expect(checkedIn, isNull);
    await tester.tap(find.byKey(const ValueKey('gem-purchase-sheet-close')));
    await tester.pumpAndSettle();
    expect(checkedIn, isFalse);
  });

  testWidgets('claimed daily check-in action is disabled', (tester) async {
    var checkedIn = false;
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const GenesisScrollBehavior(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              checkedIn = await showDailyCheckInDialog(
                context,
                status: DailyCheckInDialogStatus.claimed,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Claimed'), findsOneWidget);

    await tester.tap(find.text('Claimed'));
    await tester.pumpAndSettle();
    expect(find.text('Daily Check-in'), findsOneWidget);
    expect(checkedIn, isFalse);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Daily Check-in'), findsNothing);
    expect(checkedIn, isFalse);
  });

  testWidgets('claimable daily check-in shows Claim action', (tester) async {
    var shouldClaim = false;
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const GenesisScrollBehavior(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              shouldClaim = await showDailyCheckInDialog(
                context,
                status: DailyCheckInDialogStatus.claim,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Claim'), findsOneWidget);
    expect(find.text('Check in'), findsNothing);

    await tester.tap(find.text('Claim'));
    await tester.pumpAndSettle();
    expect(shouldClaim, isTrue);
  });

  testWidgets('generic task success uses supplied title and reward', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const GenesisScrollBehavior(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showGemTaskSuccessDialog(
              context,
              title: 'Claim successful!',
              rewardGemsCent: 12000,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Claim successful!'), findsOneWidget);
    expect(find.text('+120'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}

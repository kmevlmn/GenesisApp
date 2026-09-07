import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/gems/daily_check_in_dialog.dart';

void main() {
  testWidgets(
    'daily check-in shows success and dismisses after three seconds',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
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
      expect(find.text('Cancel'), findsOneWidget);

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

  testWidgets('claimed daily check-in action is disabled', (tester) async {
    var checkedIn = false;
    await tester.pumpWidget(
      MaterialApp(
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

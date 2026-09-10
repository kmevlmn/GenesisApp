import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/gems/profile_membership_card.dart';
import 'package:genesis_flutter_android/routers/app_router.dart';

void main() {
  testWidgets('Subscribe opens the wallet membership tab', (tester) async {
    RouteSettings? destination;
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: ProfileMembershipCard()),
        onGenerateRoute: (settings) {
          destination = settings;
          return MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Wallet')),
          );
        },
      ),
    );
    // 9k offers the plan; the balance itself lives in the gems entry below.
    expect(find.byKey(const ValueKey('user-profile-membership-offer')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-profile-membership-active-tag')),
      findsNothing,
    );
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();
    expect(destination?.name, RouteNames.gemWallet);
    expect(destination?.arguments, 'subscription');
    expect(tester.takeException(), isNull);
  });

  testWidgets('9k2 reports the membership expiry and drops the offer', (
    tester,
  ) async {
    final year = DateTime.now().year + 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ProfileMembershipCard(
              isActive: true,
              membershipExpiresAt: DateTime(year, 10, 7),
              blueBalanceCent: 30000,
              blueGemsExpiresAt: DateTime(year, 9, 30),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Subscribe'), findsNothing);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('Expires $year-10-07'), findsOneWidget);
    expect(find.text('Expires $year-09-30'), findsNothing);
    expect(
      find.byKey(const ValueKey('user-profile-membership-offer')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

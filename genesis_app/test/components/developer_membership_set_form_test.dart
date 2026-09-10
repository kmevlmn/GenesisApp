import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/models/membership_manual_set.dart';
import 'package:genesis_flutter_android/pages/me/developer_membership_set_form.dart';

Finder field(String suffix) =>
    find.byKey(ValueKey('developer-membership-set-$suffix'));

const result = MembershipManualSetResult(
  uid: 'u_target',
  planCode: 'pro_yearly',
  expiresAt: 2000000000,
  membershipStatus: 1,
);

Future<void> showForm(
  WidgetTester tester, {
  required Future<MembershipManualSetResult> Function(
    MembershipManualSetRequest,
  )
  onSubmit,
  Future<String?> Function()? loadUid,
  Future<void> Function(MembershipManualSetResult)? onSaved,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: DeveloperMembershipSetForm(
            loadUid: loadUid ?? () async => 'u_current',
            onSubmit: onSubmit,
            onSaved: onSaved ?? (_) async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> fillForm(WidgetTester tester) async {
  await tester.enterText(field('uid'), 'u_target');
  await tester.enterText(field('expires-at'), '2000000000');
  await tester.tap(field('plan'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('pro_yearly').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'entered fields are submitted once and server result is displayed',
    (tester) async {
      final pending = Completer<MembershipManualSetResult>();
      final requests = <MembershipManualSetRequest>[];
      final saved = <MembershipManualSetResult>[];
      await showForm(
        tester,
        onSubmit: (request) {
          requests.add(request);
          return pending.future;
        },
        onSaved: (value) async => saved.add(value),
      );
      expect(
        tester.widget<TextFormField>(field('uid')).controller!.text,
        'u_current',
      );
      await fillForm(tester);
      await tester.enterText(field('reason'), 'manual test');
      await tester.tap(field('submit'));
      await tester.pump();
      expect(requests.single.toJson(), {
        'uid': 'u_target',
        'plan_code': 'pro_yearly',
        'expires_at': 2000000000,
        'reason': 'manual test',
      });
      expect(tester.widget<OutlinedButton>(field('submit')).onPressed, isNull);
      await tester.tap(field('submit'));
      await tester.pump();
      expect(requests, hasLength(1));
      pending.complete(result);
      await tester.pumpAndSettle();
      expect(saved, [result]);
      expect(find.textContaining('VIP updated\nuid: u_target'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(field('submit')).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'invalid fields do not submit and failed requests retain inputs',
    (tester) async {
      var calls = 0;
      await showForm(
        tester,
        onSubmit: (_) async {
          calls++;
          throw StateError('server unavailable');
        },
        onSaved: (_) async =>
            fail('Failed mutation must not refresh the wallet'),
      );
      await tester.enterText(field('uid'), '');
      await tester.tap(field('submit'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Enter a uid with 1–32 characters'), findsOneWidget);
      expect(find.text('Enter positive Unix seconds'), findsOneWidget);
      await fillForm(tester);
      await tester.tap(field('submit'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('VIP request failed:'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(field('uid')).controller!.text,
        'u_target',
      );
      expect(
        tester.widget<TextFormField>(field('expires-at')).controller!.text,
        '2000000000',
      );
      await tester.pump(const Duration(minutes: 5));
      expect(calls, 1);
    },
  );

  testWidgets(
    'wallet refresh failure preserves server success without resubmitting',
    (tester) async {
      var calls = 0;
      await showForm(
        tester,
        onSubmit: (_) async {
          calls++;
          return result;
        },
        onSaved: (_) async => throw StateError('refresh failed'),
      );
      await fillForm(tester);
      await tester.tap(field('submit'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('VIP updated'), findsOneWidget);
      expect(find.textContaining('Wallet refresh failed:'), findsOneWidget);
      expect(find.textContaining('VIP request failed:'), findsNothing);
    },
  );

  testWidgets(
    'late current-account lookup cannot overwrite an entered target uid',
    (tester) async {
      final uid = Completer<String?>();
      await showForm(
        tester,
        loadUid: () => uid.future,
        onSubmit: (_) async => result,
      );
      await tester.enterText(field('uid'), 'u_target');
      uid.complete('u_current');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(field('uid')).controller!.text,
        'u_target',
      );
    },
  );
}

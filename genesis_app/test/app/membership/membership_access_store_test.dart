import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/gems/gem_wallet_store.dart';
import 'package:genesis_flutter_android/app/membership/membership_access_store.dart';
import 'package:genesis_flutter_android/network/models/gem_wallet.dart';

const active = MembershipAccessStatus.active;
const inactive = MembershipAccessStatus.inactive;
const unknown = MembershipAccessStatus.unknown;

GemWallet _response({int status = 1, DateTime? expiry}) => GemWallet(
  balanceCent: 98765,
  membership: GemWalletMembership(
    status: status,
    planCode: status == 0 ? '' : 'pro_yearly',
    expiresAt: expiry,
    autoRenew: false,
    blueGemsCent: 12300,
    hasOverlap: false,
  ),
);

class _Harness {
  _Harness(WidgetTester tester) {
    final initial = tester.binding.clock.now();
    elapsed = () => tester.binding.clock.now().difference(initial);
    load = () async => _response(expiry: epoch.add(const Duration(days: 1)));
    wallet = GemWalletStore(
      readUid: () async => uid,
      loadWallet: () {
        calls++;
        return load();
      },
    );
    access = MembershipAccessStore(
      wallet: wallet,
      readLoginUid: () => readUid(),
      hasBackendSession: () async => hasToken,
      elapsed: elapsed,
      serverNow: () => clockAvailable ? epoch.add(elapsed()) : null,
    );
  }

  // Deliberately far from the device date to catch local-clock comparisons.
  final epoch = DateTime.utc(2040, 1, 1);
  String? uid = 'first';
  bool hasToken = true;
  bool clockAvailable = true;
  int calls = 0;
  late Duration Function() elapsed;
  late Future<GemWallet> Function() load;
  late Future<String?> Function() readUid = () async => uid;
  late GemWalletStore wallet;
  late MembershipAccessStore access;

  void changeAccount(String? next) {
    uid = next;
    wallet.reset();
    access.resetForSession();
  }
}

void main() {
  _testMembership(
    'cache and network each invoke callback once after checkVip returns',
    (tester, h) async {
      final response = Completer<GemWallet>();
      final results = <bool?>[];
      h.load = () => response.future;
      h.access.checkVip(results.add);
      expect(results, isEmpty);
      await tester.pump();
      expect(results, isEmpty);
      response.complete(_response());
      await tester.pump();
      expect(results, [true]);
      expect(h.calls, 1);

      h.access.checkVip(results.add);
      expect(results, [true]);
      await tester.pump();
      expect(results, [true, true]);
      expect(h.calls, 1);
    },
  );

  _testMembership(
    'failure and late recovery do not notify the same callback twice',
    (tester, h) async {
      final response = Completer<GemWallet>();
      final results = <bool?>[];
      h.load = () => response.future;
      h.access.checkVip(results.add);
      await tester.pump();
      await tester.pump(const Duration(seconds: 20));
      expect(results, [null]);
      response.complete(_response());
      await tester.pump();
      expect(results, [null]);
      h.access.checkVip(results.add);
      await tester.pump();
      expect(results, [null, true]);
    },
  );

  _testMembership(
    'an earlier callback changing account invalidates other queued results',
    (tester, h) async {
      final response = Completer<GemWallet>();
      final firstResults = <bool?>[];
      final secondResults = <bool?>[];
      h.load = () => response.future;
      h.access.checkVip((isVip) {
        firstResults.add(isVip);
        h.changeAccount('second');
      });
      h.access.checkVip(secondResults.add);
      await tester.pump();
      response.complete(_response());
      await tester.pump();
      expect(firstResults, [true]);
      expect(secondResults, [null]);
      expect(h.calls, 1);
    },
  );

  _testMembership(
    'disposed service still completes a new callback once with unknown',
    (tester, h) async {
      final results = <bool?>[];
      h.access.dispose();
      h.access.checkVip(results.add);
      expect(results, isEmpty);
      await tester.pump();
      expect(results, [null]);
      expect(h.calls, 0);
    },
  );

  _testMembership(
    'missing membership fetches once and concurrent consumers share the request',
    (tester, h) async {
      final response = Completer<GemWallet>();
      h.load = () => response.future;
      expect(h.access.debugState.isVip, isNull);
      final first = _checkVip(h.access);
      final second = _checkVip(h.access);
      await tester.pump();
      expect(h.calls, 1);
      expect(h.access.debugState.isRefreshing, isTrue);
      response.complete(
        _response(expiry: h.epoch.add(const Duration(days: 1))),
      );
      expect(await first, active);
      expect(await second, active);
      expect(h.access.debugState.isVip, isTrue);
      expect(await _checkVip(h.access), active);
      expect(h.calls, 1);
      expect(h.wallet.state.value.balanceCent, 98765);
      expect(h.access.debugState.membership!.blueGemsCent, 12300);
    },
  );

  _testMembership('membership query joins an existing Me wallet request', (
    tester,
    h,
  ) async {
    final response = Completer<GemWallet>();
    h.load = () => response.future;
    final meRequest = h.wallet.refresh();
    await tester.pump();
    final vipRequest = _checkVip(h.access);
    await tester.pump();
    expect(h.calls, 1);
    response.complete(_response());
    await meRequest;
    expect(await vipRequest, active);
    expect(h.calls, 1);
  });

  for (final status in [0, 2]) {
    _testMembership(
      'server membership status $status is known inactive and cached',
      (tester, h) async {
        h.load = () async => _response(status: status);
        expect(await _checkVip(h.access), inactive);
        await tester.pump(const Duration(minutes: 1));
        expect(await _checkVip(h.access), inactive);
        expect(h.access.debugState.isVip, isFalse);
        expect(h.calls, 1);
      },
    );
  }

  _testMembership('failed lookup stays unknown and retries after cooldown', (
    tester,
    h,
  ) async {
    h.load = () async => throw StateError('offline');
    expect(await _checkVip(h.access), unknown);
    expect(h.access.debugState.isVip, isNull);
    expect(h.access.debugState.lastError, isA<StateError>());
    expect(await _checkVip(h.access), unknown);
    expect(h.calls, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(await _checkVip(h.access), unknown);
    expect(h.calls, 2);
    await tester.pump(const Duration(seconds: 2));
    expect(await _checkVip(h.access), unknown);
    expect(h.calls, 2);
    await tester.pump(const Duration(seconds: 2));
    h.load = () async => _response();
    expect(await _checkVip(h.access), active);
    expect(h.calls, 3);
    expect(h.access.debugState.lastError, isNull);
  });

  _testMembership(
    'missing membership does not erase or reinterpret Gems balance',
    (tester, h) async {
      h.load = () async => const GemWallet(balanceCent: 12345);
      expect(await _checkVip(h.access), unknown);
      expect(h.access.debugState.isVip, isNull);
      expect(h.wallet.state.value.balanceCent, 12345);
      h.load = () async => _response();
      await tester.pump(const Duration(seconds: 2));
      expect(await _checkVip(h.access), active);
    },
  );

  _testMembership(
    'past expiry requires confirmation and renewal refresh grants access',
    (tester, h) async {
      h.load = () async =>
          _response(expiry: h.epoch.subtract(const Duration(seconds: 1)));
      expect(await _checkVip(h.access), unknown);
      expect(h.access.debugState.isVip, isNull);
      await tester.pump(const Duration(seconds: 2));
      h.load = () async =>
          _response(expiry: h.epoch.add(const Duration(days: 1)));
      expect(await _checkVip(h.access), active);
      expect(h.calls, 2);
    },
  );

  _testMembership(
    'unknown expiry honors fresh server status using a short cache',
    (tester, h) async {
      h.load = () async => _response();
      expect(await _checkVip(h.access), active);
      await tester.pump(const Duration(seconds: 29));
      expect(await _checkVip(h.access), active);
      expect(h.calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(h.access.debugState.status, unknown);
      expect(await _checkVip(h.access), active);
      expect(h.calls, 2);
    },
  );

  _testMembership(
    'unsynchronized clock uses fresh server status without device-clock expiry',
    (tester, h) async {
      h.clockAvailable = false;
      h.load = () async => _response(expiry: DateTime.utc(2000));
      expect(await _checkVip(h.access), active);
      await tester.pump(const Duration(seconds: 30));
      expect(h.access.debugState.isVip, isNull);
      expect(await _checkVip(h.access), active);
      expect(h.calls, 2);
    },
  );

  _testMembership(
    'expired cache invalidates reactive state without periodic polling',
    (tester, h) async {
      expect(await _checkVip(h.access), active);
      await tester.pump(const Duration(minutes: 5));
      expect(h.access.debugState.isVip, isNull);
      expect(h.calls, 1);
      expect(await _checkVip(h.access), active);
      expect(h.calls, 2);
    },
  );

  _testMembership(
    'foreground expiry refreshes even after the general cache expires',
    (tester, h) async {
      h.load = () async =>
          _response(expiry: h.epoch.add(const Duration(minutes: 6)));
      await h.access.start();
      h.access.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 5));
      expect(h.calls, 1);
      h.load = () async => _response(status: 2);
      await tester.pump(const Duration(minutes: 1));
      expect(h.calls, 2);
      expect(h.access.debugState.status, inactive);
    },
  );

  _testMembership(
    'background expiry waits for foreground and repeated resumes coalesce',
    (tester, h) async {
      h.load = () async =>
          _response(expiry: h.epoch.add(const Duration(minutes: 1)));
      await h.access.start();
      h.access.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 1));
      expect(h.access.debugState.status, unknown);
      expect(h.calls, 1);
      final response = Completer<GemWallet>();
      h.load = () => response.future;
      h.access.didChangeAppLifecycleState(AppLifecycleState.resumed);
      h.access.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(h.calls, 2);
      response.complete(_response());
      await tester.pump();
      expect(h.access.debugState.isVip, isTrue);
    },
  );

  _testMembership(
    'foreground refresh is throttled even while the main cache is valid',
    (tester, h) async {
      await h.access.start();
      h.access.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(h.calls, 1);
      await tester.pump(const Duration(seconds: 30));
      h.access.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(h.calls, 2);
    },
  );

  _testMembership(
    'anonymous users skip wallet and incomplete login remains unknown',
    (tester, h) async {
      h.uid = null;
      expect(await _checkVip(h.access), inactive);
      h.uid = 'guest_local';
      expect(await _checkVip(h.access), inactive);
      expect(h.calls, 0);
      h.changeAccount('signed_in');
      h.hasToken = false;
      expect(await _checkVip(h.access), unknown);
      expect(h.calls, 0);
    },
  );

  _testMembership('unreadable session stays unknown and can recover', (
    tester,
    h,
  ) async {
    h.readUid = () async => throw StateError('storage unavailable');
    expect(await _checkVip(h.access), unknown);
    expect(h.calls, 0);
    h.readUid = () async => h.uid;
    expect(await _checkVip(h.access), active);
  });

  _testMembership('timed out session read cannot start a late wallet request', (
    tester,
    h,
  ) async {
    final identity = Completer<String?>();
    h.readUid = () => identity.future;
    final lookup = _checkVip(h.access);
    await tester.pump(const Duration(seconds: 20));
    expect(await lookup, unknown);
    identity.complete('first');
    await tester.pump();
    expect(h.calls, 0);
    expect(h.access.debugState.isVip, isNull);
  });

  _testMembership(
    'wallet timeout returns unknown but a valid late response can recover',
    (tester, h) async {
      final response = Completer<GemWallet>();
      h.load = () => response.future;
      final lookup = _checkVip(h.access);
      await tester.pump();
      await tester.pump(const Duration(seconds: 20));
      expect(await lookup, unknown);
      expect(h.access.debugState.isVip, isNull);
      response.complete(_response());
      await tester.pump();
      expect(h.access.debugState.isVip, isTrue);
      expect(h.calls, 1);
    },
  );

  _testMembership(
    'account switch excludes old responses and logout clears access immediately',
    (tester, h) async {
      final oldResponse = Completer<GemWallet>();
      h.load = () => oldResponse.future;
      final oldLookup = _checkVip(h.access);
      await tester.pump();
      h.changeAccount('second');
      expect(h.access.debugState.isVip, isNull);
      h.load = () async => _response(status: 0);
      expect(await _checkVip(h.access), inactive);
      oldResponse.complete(_response());
      expect(await oldLookup, unknown);
      expect(h.access.debugState.ownerUid, 'second');
      expect(h.access.debugState.isVip, isFalse);
      h.changeAccount(null);
      expect(h.access.debugState.membership, isNull);
      expect(await _checkVip(h.access), inactive);
      expect(h.calls, 2);
    },
  );

  _testMembership(
    'purchase and claim wallet refreshes update global access without a second request',
    (tester, h) async {
      h.load = () async => _response(status: 0);
      expect(await _checkVip(h.access), inactive);
      h.load = () async => _response();
      await h.wallet.refreshAfterMembershipChanged();
      expect(h.access.debugState.status, active);
      expect(await _checkVip(h.access), active);
      expect(h.calls, 2);
      h.wallet.reset();
      expect(h.access.debugState.isVip, isNull);
    },
  );

  _testMembership('disposal ignores late responses and cancels expiry work', (
    tester,
    h,
  ) async {
    final response = Completer<GemWallet>();
    h.load = () => response.future;
    final lookup = _checkVip(h.access);
    await tester.pump();
    h.access.dispose();
    response.complete(_response());
    expect(await lookup, unknown);
    await tester.pump(const Duration(days: 1));
    expect(h.calls, 1);
  });
}

void _testMembership(
  String description,
  Future<void> Function(WidgetTester tester, _Harness harness) body,
) {
  testWidgets(description, (tester) async {
    final harness = _Harness(tester);
    try {
      await body(tester, harness);
    } finally {
      harness.access.dispose();
      harness.wallet.dispose();
    }
  });
}

// Adapt the public callback only for awaiting assertions in tests.
Future<MembershipAccessStatus> _checkVip(MembershipAccessStore access) {
  final result = Completer<MembershipAccessStatus>();
  access.checkVip((isVip) {
    result.complete(switch (isVip) {
      true => MembershipAccessStatus.active,
      false => MembershipAccessStatus.inactive,
      null => MembershipAccessStatus.unknown,
    });
  });
  return result.future;
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/gems/gem_wallet_store.dart';
import 'package:genesis_flutter_android/network/models/gem_wallet.dart';

void main() {
  test(
    'VIP refresh waits for an earlier wallet response then requests current state',
    () async {
      var calls = 0;
      final entered = Completer<void>();
      final beforeBinding = Completer<GemWallet>();
      final store = GemWalletStore(
        readUid: () async => 'member',
        loadWallet: () async {
          if (++calls == 1) {
            entered.complete();
            return beforeBinding.future;
          }
          return const GemWallet(
            balanceCent: 100,
            membership: GemWalletMembership(
              status: 1,
              planCode: 'pro_yearly',
              expiresAt: null,
              autoRenew: true,
              blueGemsCent: 30000,
              hasOverlap: false,
            ),
          );
        },
      );
      addTearDown(store.dispose);
      final initial = store.refresh();
      await entered.future;
      final afterBinding = store.refreshAfterMembershipChanged();
      expect(calls, 1);
      beforeBinding.complete(const GemWallet(balanceCent: 100));
      await Future.wait([initial, afterBinding]);
      expect(calls, 2);
      expect(store.state.value.membership!.isActive, isTrue);
      expect(store.state.value.balanceCent, 100);
      expect(store.state.value.membership!.blueGemsCent, 30000);
    },
  );

  test(
    'VIP wallet refresh exposes failure so binding completion can retry it',
    () async {
      final store = GemWalletStore(
        readUid: () async => 'member',
        loadWallet: () async => throw StateError('offline'),
      );
      addTearDown(store.dispose);
      await expectLater(
        store.refreshAfterMembershipChanged(),
        throwsStateError,
      );
      // Existing Gems refresh still retains its nonthrowing behavior.
      await expectLater(store.refreshAfterEntitlementGranted(), completes);
    },
  );
  test(
    'membership and total balance refresh together and are isolated by account',
    () async {
      var uid = 'first';
      var offline = false;
      final store = GemWalletStore(
        readUid: () async => uid,
        loadWallet: () async {
          if (offline) throw StateError('offline');
          return const GemWallet(
            balanceCent: 548240,
            membership: GemWalletMembership(
              status: 1,
              planCode: 'pro_yearly',
              expiresAt: null,
              autoRenew: false,
              blueGemsCent: 30000,
              hasOverlap: false,
            ),
          );
        },
      );
      addTearDown(store.dispose);
      await store.refresh();
      expect(store.state.value.membership!.isActive, isTrue);
      expect(store.state.value.balanceCent, 548240);
      offline = true;
      await store.refresh();
      expect(store.state.value.membership!.blueGemsCent, 30000);
      uid = 'second';
      await store.refresh();
      expect(store.state.value.membership, isNull);
      expect(store.state.value.balanceCent, isNull);
      store.reset();
      expect(store.state.value.membership, isNull);
    },
  );
  test('refresh publishes the exact server balance', () async {
    final store = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 98000),
      readUid: () async => 'u_user',
    );
    addTearDown(store.dispose);

    await store.refresh();

    expect(store.state.value.ownerUid, 'u_user');
    expect(store.state.value.balanceCent, 98000);
    expect(store.state.value.isRefreshing, isFalse);
    expect(store.state.value.lastError, isNull);
  });

  test('failed refresh retains the last successful balance', () async {
    var shouldFail = false;
    final store = GemWalletStore(
      loadWallet: () async {
        if (shouldFail) throw StateError('offline');
        return const GemWallet(balanceCent: 43000);
      },
      readUid: () async => 'u_user',
    );
    addTearDown(store.dispose);

    await store.refresh();
    shouldFail = true;
    await store.refresh();

    expect(store.state.value.balanceCent, 43000);
    expect(store.state.value.lastError, isA<StateError>());
  });

  test('concurrent refresh calls share one wallet request', () async {
    var requestCount = 0;
    final response = Completer<GemWallet>();
    final store = GemWalletStore(
      loadWallet: () {
        requestCount += 1;
        return response.future;
      },
      readUid: () async => 'u_user',
    );
    addTearDown(store.dispose);

    final first = store.refresh();
    final second = store.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(requestCount, 1);
    response.complete(const GemWallet(balanceCent: 98000));
    await Future.wait<void>([first, second]);
    expect(store.state.value.balanceCent, 98000);
  });

  test('an old account response is ignored after reset', () async {
    var uid = 'u_first';
    final response = Completer<GemWallet>();
    final store = GemWalletStore(
      loadWallet: () => response.future,
      readUid: () async => uid,
    );
    addTearDown(store.dispose);

    final refresh = store.refresh();
    await Future<void>.delayed(Duration.zero);

    uid = 'u_second';
    store.reset();
    response.complete(const GemWallet(balanceCent: 43000));
    await refresh;

    expect(store.state.value.ownerUid, isNull);
    expect(store.state.value.balanceCent, isNull);
  });

  test('refresh ignores an in-flight response after dispose', () async {
    final response = Completer<GemWallet>();
    final store = GemWalletStore(
      loadWallet: () => response.future,
      readUid: () async => 'u_user',
    );

    final refresh = store.refresh();
    await Future<void>.delayed(Duration.zero);
    store.dispose();
    response.complete(const GemWallet(balanceCent: 98000));

    await expectLater(refresh, completes);
    store.dispose();
  });

  test('refresh after dispose is a no-op', () async {
    final store = GemWalletStore(
      loadWallet: () async => const GemWallet(balanceCent: 98000),
      readUid: () async => 'u_user',
    );
    store.dispose();

    await expectLater(store.refresh(), completes);
  });
}

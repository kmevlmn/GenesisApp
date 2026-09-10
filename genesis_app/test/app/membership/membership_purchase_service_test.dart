import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/membership/membership_purchase_service.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/network/models/membership_claim.dart';
import 'package:genesis_flutter_android/network/models/membership_guest_purchase_check.dart';
import 'package:genesis_flutter_android/platform/billing/membership_guest_claim_record.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/platform/billing/membership_checkout_platform.dart';
import 'package:genesis_flutter_android/platform/billing/membership_pending_store.dart';
import 'package:genesis_flutter_android/platform/billing/membership_restore_record.dart';
import 'package:genesis_flutter_android/platform/billing/membership_store_purchase.dart';

import '../../support/membership_fixtures.dart';

const accountUuid = '4b74ec68-7abc-4cce-a223-e997e31dc811';
const guest = MembershipGuestIdentity(
  accountUuid: '8b74ec68-7abc-4cce-a223-e997e31dc811',
);
const completed = MembershipPurchaseReport(
  status: MembershipReportStatus.completed,
  reportId: 'report-test',
  membershipId: 'membership-test',
);

class PendingStore implements MembershipPendingStore {
  final records = <String, MembershipPurchaseRecord>{};
  final confirmed = <String, MembershipPurchaseRecord>{};
  final restores = <String, MembershipRestoreRecord>{};
  final claims = <String, MembershipGuestClaimRecord>{};
  bool fail = false;
  bool failComplete = false;
  bool failRestoreCleanup = false;
  bool failClaim = false;
  bool failClaimCleanup = false;
  Future<void> Function(MembershipPurchaseRecord)? onSave;
  Future<void> Function()? onLoad;
  @override
  Future<List<MembershipGuestClaimRecord>> loadGuestClaims() async {
    await onLoad?.call();
    return claims.values.toList();
  }

  @override
  Future<void> saveGuestClaim(MembershipGuestClaimRecord record) async {
    if (fail || failClaim) throw StateError('claim storage unavailable');
    claims[record.guest.accountUuid] = record;
  }

  @override
  Future<void> completeGuestClaim(MembershipGuestClaimRecord record) async {
    if (fail || failClaimCleanup) throw StateError('claim cleanup unavailable');
    if (record.status != 'completed' || record.ownerUid == null) {
      throw StateError('claim is not completed');
    }
    confirmed.removeWhere(
      (_, p) => p.guest?.accountUuid == record.guest.accountUuid,
    );
    claims[record.guest.accountUuid] = record.boundIdentity;
  }

  @override
  Future<List<MembershipPurchaseRecord>> loadConfirmedReceipts() async =>
      confirmed.values.toList();
  @override
  Future<void> complete(MembershipPurchaseRecord record) async {
    if (fail || failComplete) throw StateError('storage unavailable');
    if (record.guest != null &&
        record.paid &&
        record.hasReceipt &&
        record.reportStatus != 'rejected') {
      confirmed[record.requestId] = record;
    } else {
      confirmed.remove(record.requestId);
    }
    records.remove(record.requestId);
  }

  @override
  Future<void> saveGuestPurchase(MembershipPurchaseRecord record) async {
    if (fail || failClaim) throw StateError('guest storage unavailable');
    confirmed[record.requestId] = record;
  }

  @override
  Future<void> removeRestore(String requestId) async {
    if (fail || failRestoreCleanup) throw StateError('storage unavailable');
    restores.remove(requestId);
  }

  @override
  Future<List<MembershipPurchaseRecord>> loadAll() async =>
      records.values.toList();
  @override
  Future<void> save(MembershipPurchaseRecord record) async {
    if (fail) throw StateError('storage unavailable');
    await onSave?.call(record);
    records[record.requestId] = record;
  }

  @override
  Future<List<MembershipRestoreRecord>> loadRestores() async =>
      restores.values.toList();
  @override
  Future<void> saveRestore(MembershipRestoreRecord record) async {
    if (fail) throw StateError('storage unavailable');
    restores[record.requestId] = record;
  }
}

class Checkout implements MembershipCheckoutPlatform {
  int launches = 0;
  int finishes = 0;
  int queries = 0;
  String? uuid;
  MembershipProduct? product;
  bool launchResult = true;
  bool finishFails = false;
  Future<void> Function()? onPrepare;
  Future<void> Function()? onLaunch;
  bool autoHandoff = true;
  bool Function()? handoff;
  @override
  Future<Object> prepare(MembershipProduct product) async {
    this.product = product;
    await onPrepare?.call();
    return product;
  }

  @override
  Future<bool> launch(
    Object product,
    String accountUuid, {
    bool Function()? onStoreHandoff,
  }) async {
    launches++;
    uuid = accountUuid;
    handoff = onStoreHandoff;
    await onLaunch?.call();
    if (launchResult && autoHandoff) onStoreHandoff?.call();
    return launchResult;
  }

  @override
  Future<bool> isSubscription(String productId) async {
    queries++;
    return !productId.startsWith('gem');
  }

  @override
  Future<void> finishAppleTransaction(String transactionId) async {
    finishes++;
    if (finishFails) throw StateError('finish failed');
  }
}

class Harness {
  Harness({
    this.provider = MembershipProvider.google,
    PendingStore? storage,
    bool restoreEnabled = false,
    bool claimEnabled = false,
    bool guestRecoveryEnabled = false,
    Duration retryDelay = const Duration(days: 1),
    Duration attemptTimeout = const Duration(seconds: 90),
  }) : store = storage ?? PendingStore() {
    service = MembershipPurchaseService(
      platform: platform,
      store: store,
      provider: provider,
      readLoginUid: () async =>
          loginUidHandler == null ? uid : await loginUidHandler!(),
      loadProducts: () async {
        eligibilityQueries++;
        return productsHandler == null
            ? [product(), product(yearly: true)]
            : await productsHandler!();
      },
      loadAccountUuid: () async => accountUuidHandler == null
          ? accountUuid
          : await accountUuidHandler!(),
      prepareGuest: () async {
        guestPrepares++;
        return guestHandler == null ? guest : await guestHandler!();
      },
      reportPurchase: (request) async {
        reports.add(request);
        expectSync(
          request.purchaseToken.isNotEmpty || request.transactionId.isNotEmpty,
          isTrue,
        );
        return reportHandler == null
            ? completed
            : await reportHandler!(request);
      },
      claimGuest: claimEnabled
          ? (request) async {
              claimRequests.add(request);
              expectSync(
                store.claims[request.guest.accountUuid]?.ownerUid,
                uid,
              );
              return claimHandler == null
                  ? MembershipClaimResult(
                      status: MembershipReportStatus.completed,
                    )
                  : await claimHandler!(request);
            }
          : null,
      loadSignedTransaction: (request) async {
        signedTransactionQueries++;
        return signedTransactionHandler == null
            ? 'test.header.signature'
            : await signedTransactionHandler!(request);
      },
      checkGuestPurchase: guestRecoveryEnabled
          ? (uuid) async {
              guestChecks.add(uuid);
              return guestCheckHandler == null
                  ? const MembershipGuestPurchaseCheck(hasUnboundOrder: true)
                  : await guestCheckHandler!(uuid);
            }
          : null,
      discoverGuestPurchases: guestRecoveryEnabled
          ? () async {
              guestDiscoveries++;
              return guestPurchasesHandler == null
                  ? guestPurchases
                  : await guestPurchasesHandler!();
            }
          : null,
      queryRestorePurchases: restoreEnabled
          ? (ids) async {
              restoreQueries++;
              return storeQuery == null ? recoverable : await storeQuery!();
            }
          : null,
      queryPurchases: () async {
        recoverQueries++;
        return recoverable;
      },
      refreshWallet: () async {
        refreshes++;
        await walletRefreshHandler?.call();
      },
      otherPurchaseBusy: () => gemsBusy,
      retryDelay: retryDelay,
      attemptTimeout: attemptTimeout,
    );
    addTearDown(service.dispose);
  }
  final MembershipProvider provider;
  final PendingStore store;
  final Checkout platform = Checkout();
  late final MembershipPurchaseService service;
  String? uid = 'user-test';
  List<MembershipStorePurchase> guestPurchases = [];
  Future<List<MembershipStorePurchase>> Function()? guestPurchasesHandler;
  Future<String?> Function()? loginUidHandler;
  Future<String> Function()? accountUuidHandler;
  Future<MembershipGuestIdentity> Function()? guestHandler;
  bool gemsBusy = false;
  int guestPrepares = 0;
  int guestDiscoveries = 0;
  final guestChecks = <String>[];
  Future<MembershipGuestPurchaseCheck> Function(String)? guestCheckHandler;
  int eligibilityQueries = 0;
  Future<List<MembershipProduct>> Function()? productsHandler;
  int refreshes = 0;
  Future<void> Function()? walletRefreshHandler;
  int recoverQueries = 0;
  int restoreQueries = 0;
  final claimRequests = <MembershipClaimRequest>[];
  Future<MembershipClaimResult> Function(MembershipClaimRequest)? claimHandler;
  int signedTransactionQueries = 0;
  Future<String> Function(MembershipClaimRequest)? signedTransactionHandler;
  Future<List<BillingPurchase>> Function()? storeQuery;
  List<BillingPurchase> recoverable = [];
  final reports = <MembershipPurchaseRequest>[];
  Future<MembershipPurchaseReport> Function(MembershipPurchaseRequest)?
  reportHandler;
  MembershipProduct product({bool yearly = false}) =>
      membershipProduct(provider: provider, yearly: yearly);
  BillingPurchase purchase({
    bool yearly = false,
    BillingPurchaseStatus status = BillingPurchaseStatus.purchased,
    String token = 'test-token',
    String transaction = '100',
    String? uuid,
  }) => BillingPurchase(
    provider: provider == MembershipProvider.google
        ? BillingProvider.googlePlay
        : BillingProvider.appStore,
    productId: product(yearly: yearly).storeProductId,
    purchaseToken: token,
    transactionId: transaction,
    originalTransactionId: 'original-test',
    originalJson: '',
    signedTransaction: provider == MembershipProvider.apple
        ? 'test.header.signature'
        : '',
    purchaseTime: '',
    status: status,
    obfuscatedAccountId:
        uuid ?? (uid == null ? guest.accountUuid : accountUuid),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('successful logged-in report leaves no durable order history', () async {
    final h = Harness();
    await h.service.purchase(h.product(yearly: true));
    await h.service.interceptPurchase(h.purchase(yearly: true));
    expect(h.store.records, isEmpty);
    final restarted = Harness(storage: h.store, restoreEnabled: true);
    restarted.recoverable = [h.purchase(yearly: true)];
    await restarted.service.restorePurchases(
      products: [h.product(), h.product(yearly: true)],
    );
    expect(restarted.reports, isEmpty);
    expect(restarted.store.confirmed, isEmpty);
    expect(restarted.store.restores, isEmpty);
  });
  test(
    'cleanup failure keeps acknowledged order and retries without another report',
    () async {
      final h = Harness(provider: MembershipProvider.apple);
      h.store.failComplete = true;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      expect(h.service.state.value, MembershipCheckoutState.deferred);
      expect(h.store.records.values.single.reportStatus, 'completed');
      expect(h.platform.finishes, 1);
      h.store.failComplete = false;
      await h.service.recover();
      expect(h.reports, hasLength(1));
      expect(h.platform.finishes, 1);
      expect(h.store.records, isEmpty);
    },
  );
  test(
    'accepted order retries its same request then cleans up only after completed',
    () async {
      final h = Harness();
      h.reportHandler = (_) async => const MembershipPurchaseReport(
        status: MembershipReportStatus.accepted,
        reportId: 'accepted',
      );
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      expect(h.store.records.values.single.reportStatus, 'accepted');
      expect(h.store.confirmed, isEmpty);
      h.reportHandler = null;
      await h.service.recover();
      expect(h.reports, hasLength(2));
      expect(h.reports.first.toJson(), h.reports.last.toJson());
      expect(h.store.records, isEmpty);
      expect(h.refreshes, 1);
    },
  );
  test(
    'stream errors release the lock and a late callback can still report',
    () async {
      final h = Harness();
      await h.service.purchase(h.product());
      h.service.handleStreamError();
      expect(h.service.isBusy, isFalse);
      await h.service.recover();
      expect(h.reports, isEmpty);
      await h.service.interceptPurchase(h.purchase());
      expect(h.reports, hasLength(1));
    },
  );
  test(
    'keeps selected yearly plan in memory, then reports and deduplicates',
    () async {
      final h = Harness();
      h.platform.onLaunch = () async {
        expect(h.store.records, isEmpty);
        expect(h.platform.product!.isYearly, isTrue);
      };
      await h.service.purchase(h.product(yearly: true));
      expect(h.platform.launches, 1);
      expect(h.platform.uuid, accountUuid);
      expect(h.reports, isEmpty);
      final event = h.purchase(yearly: true);
      expect(await h.service.interceptPurchase(event), isTrue);
      await h.service.interceptPurchase(event);
      expect(h.reports, hasLength(1));
      expect(h.reports.single.product.basePlanId, 'test-annual');
      expect(h.refreshes, 1);
      expect(h.platform.finishes, 0);
      expect(h.service.isBusy, isFalse);
    },
  );
  test(
    'parallel taps only launch once and Gems purchase blocks VIP launch',
    () async {
      final h = Harness();
      final gate = Completer<void>();
      h.platform.onPrepare = () => gate.future;
      final first = h.service.purchase(h.product());
      await h.service.purchase(h.product(yearly: true));
      gate.complete();
      await first;
      expect(h.platform.launches, 1);
      await h.service.interceptPurchase(
        h.purchase(status: BillingPurchaseStatus.canceled),
      );
      h.gemsBusy = true;
      await h.service.purchase(h.product());
      expect(h.platform.launches, 1);
    },
  );
  test(
    'guest proof is cached after payment and guest report does not refresh account wallet',
    () async {
      final h = Harness()..uid = null;
      h.platform.onLaunch = () async {
        expect(h.store.records, isEmpty);
        expect(h.store.claims, isEmpty);
      };
      await h.service.purchase(h.product());
      expect(h.guestPrepares, 1);
      expect(h.platform.uuid, guest.accountUuid);
      await h.service.interceptPurchase(h.purchase());
      expect(h.reports.single.guest?.accountUuid, guest.accountUuid);
      expect(h.refreshes, 0);
      expect(h.store.records, isEmpty);
      expect(
        h.store.confirmed.values.single.guest?.accountUuid,
        guest.accountUuid,
      );
    },
  );
  test('purchase launch does not persist a speculative order', () async {
    final h = Harness()..uid = null;
    h.store.fail = true;
    await h.service.purchase(h.product());
    expect(h.platform.launches, 1);
    expect(h.store.records, isEmpty);
  });
  test(
    'launch rejection and cancellation allow another attempt without reporting',
    () async {
      final h = Harness();
      h.platform.launchResult = false;
      await h.service.purchase(h.product());
      expect(h.service.isBusy, isFalse);
      h.platform.launchResult = true;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(
        h.purchase(status: BillingPurchaseStatus.canceled),
      );
      await h.service.purchase(h.product());
      expect(h.platform.launches, 3);
      expect(h.reports, isEmpty);
    },
  );
  test(
    'Google cancellation without product id releases the active VIP purchase',
    () async {
      final h = Harness();
      await h.service.purchase(h.product());
      const canceled = BillingPurchase(
        provider: BillingProvider.googlePlay,
        productId: '',
        purchaseToken: '',
        transactionId: '',
        originalTransactionId: '',
        originalJson: '',
        purchaseTime: '',
        status: BillingPurchaseStatus.canceled,
      );
      expect(await h.service.interceptPurchase(canceled), isTrue);
      expect(h.service.isBusy, isFalse);
      expect(h.service.state.value, MembershipCheckoutState.canceled);
      expect(h.reports, isEmpty);
      expect(await h.service.interceptPurchase(canceled), isFalse);
    },
  );
  test(
    'report failure survives restart and retries identical proof without a request ID',
    () async {
      final h = Harness();
      h.reportHandler = (_) async => throw StateError('offline');
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      expect(h.service.state.value, MembershipCheckoutState.deferred);
      final restarted = Harness(storage: h.store);
      await restarted.service.recover();
      expect(restarted.reports.single.toJson(), h.reports.single.toJson());
      expect(restarted.reports.single.toJson(), isNot(contains('request_id')));
    },
  );
  test(
    'cleanup storage failure does not prevent report or cause a duplicate report',
    () async {
      final h = Harness();
      await h.service.purchase(h.product());
      h.store.fail = true;
      await h.service.interceptPurchase(h.purchase());
      expect(h.reports, hasLength(1));
      h.store.fail = false;
      await h.service.recover();
      expect(h.reports, hasLength(1));
    },
  );
  test(
    'Apple finishes only after durable server takeover and retries finish without reposting',
    () async {
      final h = Harness(provider: MembershipProvider.apple);
      h.platform.finishFails = true;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      expect(h.reports, hasLength(1));
      expect(h.platform.finishes, 1);
      h.platform.finishFails = false;
      await h.service.recover();
      expect(h.platform.finishes, 2);
      expect(h.reports, hasLength(1));
      expect(h.store.records, isEmpty);
      expect(h.store.confirmed, isEmpty);
    },
  );
  test('accepted keeps its order while rejected completes its order', () async {
    for (final status in [
      MembershipReportStatus.accepted,
      MembershipReportStatus.rejected,
    ]) {
      final h = Harness();
      h.reportHandler = (_) async => MembershipPurchaseReport(
        status: status,
        reportId: 'test-report',
        reason: status == MembershipReportStatus.rejected
            ? 'product_mismatch'
            : null,
      );
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      await h.service.recover();
      expect(
        h.reports,
        hasLength(status == MembershipReportStatus.accepted ? 2 : 1),
      );
      expect(
        h.store.records.length,
        status == MembershipReportStatus.accepted ? 1 : 0,
      );
      expect(h.refreshes, 0);
    }
  });
  test(
    'pending Apple payment is not completed or reported without a transaction',
    () async {
      final h = Harness(provider: MembershipProvider.apple);
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(
        h.purchase(
          status: BillingPurchaseStatus.pending,
          transaction: '',
          token: '',
        ),
      );
      expect(h.platform.finishes, 0);
      expect(h.reports, isEmpty);
      await h.service.interceptPurchase(h.purchase());
      expect(h.reports, hasLength(1));
      expect(h.platform.finishes, 1);
    },
  );
  test(
    'session changes during preparation cannot launch for the new user',
    () async {
      final h = Harness();
      h.platform.onPrepare = () async {
        h.uid = 'another-user';
      };
      await h.service.purchase(h.product());
      expect(h.platform.launches, 0);
    },
  );
  test(
    'receipt from previous account is retained and not reported under new account',
    () async {
      final h = Harness();
      await h.service.purchase(h.product());
      h.uid = 'another-user';
      await h.service.interceptPurchase(h.purchase());
      expect(h.reports, isEmpty);
      h.uid = 'user-test';
      await h.service.recover();
      expect(h.reports, hasLength(1));
    },
  );
  test(
    'unknown subscription never becomes a Gems purchase or guessed base plan',
    () async {
      final h = Harness();
      expect(await h.service.interceptPurchase(h.purchase()), isTrue);
      expect(h.reports, isEmpty);
      final gem = BillingPurchase(
        provider: BillingProvider.googlePlay,
        productId: 'gem-test',
        purchaseToken: 'gem-token',
        transactionId: '',
        originalTransactionId: '',
        originalJson: '',
        purchaseTime: '',
        status: BillingPurchaseStatus.purchased,
      );
      expect(await h.service.interceptPurchase(gem), isFalse);
    },
  );
  test(
    'new Google renewal using same token reports once per transaction',
    () async {
      final h = Harness();
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase(transaction: 'order-1'));
      await h.service.interceptPurchase(h.purchase(transaction: 'order-2'));
      expect(h.reports, hasLength(2));
      expect(h.reports.map((r) => r.transactionId), ['order-1', 'order-2']);
      expect(h.reports.last.toJson(), h.reports.first.toJson());
      await h.service.interceptPurchase(h.purchase(transaction: 'order-1'));
      await h.service.interceptPurchase(h.purchase(transaction: 'order-2'));
      expect(h.reports, hasLength(2));
      expect(h.store.records, isEmpty);
      expect(h.store.confirmed, isEmpty);
    },
  );
  test(
    'callback and foreground retry cannot double-report a receipt',
    () async {
      final h = Harness();
      final gate = Completer<MembershipPurchaseReport>();
      h.reportHandler = (_) => gate.future;
      await h.service.purchase(h.product());
      final callback = h.service.interceptPurchase(h.purchase());
      await pumpEventQueue();
      final recovery = h.service.recover();
      gate.complete(completed);
      await Future.wait([callback, recovery]);
      expect(h.reports, hasLength(1));
    },
  );
}

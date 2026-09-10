import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/telemetry/firebase_analytics_monitoring.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/models/gem_product.dart';
import 'package:genesis_flutter_android/network/models/gem_purchase_report.dart';
import 'package:genesis_flutter_android/platform/billing/billing_analytics.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/platform/billing/billing_service.dart';
import 'package:genesis_flutter_android/platform/billing/google_play_billing_platform.dart';
import 'package:genesis_flutter_android/platform/billing/pending_purchase_store.dart';

class _FakeBillingPlatform implements BillingPlatform {
  _FakeBillingPlatform({
    this.providerValue = BillingProvider.googlePlay,
    this.expectedStoreProductId = 'worldo_gems_500',
  });

  final StreamController<List<BillingPurchase>> _controller =
      StreamController<List<BillingPurchase>>.broadcast(sync: true);
  final BillingProvider providerValue;
  String expectedStoreProductId;
  late BillingProductQueryResult queryResult =
      BillingProductQueryResult.success(
        BillingStoreProduct(
          id: expectedStoreProductId,
          type: BillingStoreProductType.inApp,
          nativeProduct: const Object(),
        ),
      );
  bool available = true;
  bool buyAccepted = true;
  int availabilityCheckCount = 0;
  int queryCount = 0;
  int recoverableQueryCount = 0;
  int buyCount = 0;
  List<BillingPurchase> recoverablePurchases = <BillingPurchase>[];
  Object? recoverableQueryError;
  String? queriedPurchaseOptionId;
  String? queriedOfferId;
  String? purchasedOfferToken;
  FutureOr<bool> Function()? buyHandler;
  bool Function()? handoff;
  FutureOr<bool> Function()? availabilityHandler;
  FutureOr<BillingProductQueryResult> Function(String storeProductId)?
  queryHandler;
  final List<String> queriedStoreProductIds = <String>[];
  final Set<String> analyticsTransactionIds = <String>{};

  @override
  BillingProvider get provider => providerValue;

  @override
  Stream<List<BillingPurchase>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async {
    availabilityCheckCount += 1;
    final handler = availabilityHandler;
    if (handler != null) return handler();
    return available;
  }

  @override
  Future<List<BillingPurchase>> queryRecoverablePurchases() async {
    recoverableQueryCount += 1;
    final error = recoverableQueryError;
    if (error != null) throw error;
    return recoverablePurchases;
  }

  @override
  void recordVerifiedPurchaseForAnalytics(BillingPurchase purchase) {
    if (purchase.provider == BillingProvider.appStore &&
        purchase.transactionId.trim().isNotEmpty) {
      analyticsTransactionIds.add(purchase.transactionId.trim());
    }
  }

  @override
  Future<bool> buyConsumable({
    required BillingStoreProduct product,
    required String billingAccountId,
    bool Function()? onStoreHandoff,
  }) async {
    buyCount += 1;
    purchasedOfferToken = product.offerToken;
    expect(product.id, expectedStoreProductId);
    expect(product.type, BillingStoreProductType.inApp);
    expect(billingAccountId, '4b74ec68-7abc-4cce-a223-e997e31dc811');
    handoff = onStoreHandoff;
    final handler = buyHandler;
    final accepted = handler == null ? buyAccepted : await handler();
    if (accepted) onStoreHandoff?.call();
    return accepted;
  }

  @override
  Future<BillingProductQueryResult> queryProduct(
    String storeProductId,
    BillingStoreProductType expectedType, {
    String? purchaseOptionId,
    String? offerId,
  }) async {
    queryCount += 1;
    queriedStoreProductIds.add(storeProductId);
    queriedPurchaseOptionId = purchaseOptionId;
    queriedOfferId = offerId;
    final handler = queryHandler;
    if (handler != null) return handler(storeProductId);
    expect(storeProductId, expectedStoreProductId);
    expect(expectedType, BillingStoreProductType.inApp);
    return queryResult;
  }

  void emit(BillingPurchase purchase) => _controller.add([purchase]);

  void emitError(Object error) =>
      _controller.addError(error, StackTrace.current);

  Future<void> close() => _controller.close();
}

class _BillingAnalyticsRecord {
  const _BillingAnalyticsRecord(this.action, this.properties);

  final String action;
  final Map<String, Object?> properties;
}

class _FakeBillingAnalytics implements BillingAnalytics {
  final records = <_BillingAnalyticsRecord>[];

  @override
  void track(
    String action, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) {
    records.add(_BillingAnalyticsRecord(action, Map.of(properties)));
  }
}

class _RecordingFirebaseAnalyticsClient implements AppAnalyticsClient {
  final List<_FirebaseAnalyticsRecord> events = <_FirebaseAnalyticsRecord>[];

  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    events.add(
      _FirebaseAnalyticsRecord(
        name,
        Map<String, Object>.of(parameters ?? const <String, Object>{}),
      ),
    );
  }
}

class _MemoryFirebaseAnalyticsOnceEventStore
    implements FirebaseAnalyticsOnceEventStore {
  final Set<String> sentEvents = <String>{};

  @override
  Future<void> markSent(String eventName) async {
    sentEvents.add(eventName);
  }

  @override
  Future<bool> wasSent(String eventName) async {
    return sentEvents.contains(eventName);
  }
}

class _FirebaseAnalyticsRecord {
  const _FirebaseAnalyticsRecord(this.name, this.parameters);

  final String name;
  final Map<String, Object> parameters;

  @override
  bool operator ==(Object other) {
    return other is _FirebaseAnalyticsRecord &&
        other.name == name &&
        _firebaseAnalyticsMapsEqual(other.parameters, parameters);
  }

  @override
  int get hashCode =>
      Object.hash(name, Object.hashAllUnordered(parameters.entries));
}

bool _firebaseAnalyticsMapsEqual(
  Map<String, Object> first,
  Map<String, Object> second,
) {
  if (first.length != second.length) return false;
  for (final entry in first.entries) {
    if (second[entry.key] != entry.value) return false;
  }
  return true;
}

class _ControllablePendingPurchaseStore
    extends MemoryBillingPendingPurchaseStore {
  bool failNextUpsert = false;
  bool failNextFind = false;
  int findCount = 0;

  @override
  Future<BillingPendingPurchase?> find({
    required BillingProvider provider,
    required String purchaseToken,
  }) {
    findCount += 1;
    if (failNextFind) {
      failNextFind = false;
      throw StateError('local read failed');
    }
    return super.find(provider: provider, purchaseToken: purchaseToken);
  }

  @override
  Future<void> upsert(BillingPendingPurchase purchase) async {
    if (failNextUpsert) {
      failNextUpsert = false;
      throw StateError('local write failed');
    }
    await super.upsert(purchase);
  }
}

void main() {
  late _FakeBillingPlatform platform;
  late _ControllablePendingPurchaseStore pendingStore;
  late List<GemPurchaseReportRequest> reports;
  late List<BillingUiEvent> uiEvents;
  late _FakeBillingAnalytics analytics;
  late GooglePlayBillingService service;
  var refreshCount = 0;
  var reportError = false;
  var reportStatus = GemPurchaseReportStatus.completed;
  var reportTransactionId = '';
  var reportReason = '';
  var billingAccountId = '4b74ec68-7abc-4cce-a223-e997e31dc811';
  var currentUid = 'u_1';
  var productCatalogLoadCount = 0;

  setUp(() {
    platform = _FakeBillingPlatform();
    pendingStore = _ControllablePendingPurchaseStore();
    reports = <GemPurchaseReportRequest>[];
    uiEvents = <BillingUiEvent>[];
    analytics = _FakeBillingAnalytics();
    refreshCount = 0;
    reportError = false;
    reportStatus = GemPurchaseReportStatus.completed;
    reportTransactionId = '';
    reportReason = '';
    billingAccountId = '4b74ec68-7abc-4cce-a223-e997e31dc811';
    currentUid = 'u_1';
    productCatalogLoadCount = 0;
    service = GooglePlayBillingService(
      platform: platform,
      pendingPurchaseStore: pendingStore,
      loadBillingAccountId: () async => billingAccountId,
      loadProductCatalog: () async {
        productCatalogLoadCount += 1;
        return [_product];
      },
      reportPurchase: (request) async {
        reports.add(request);
        if (reportError) {
          throw ApiException(
            message: 'offline',
            kind: ApiExceptionKind.transport,
          );
        }
        return GemPurchaseReport(
          status: reportStatus,
          grantedGemsCent: 55000,
          transactionId: reportTransactionId,
          reason: reportReason,
        );
      },
      refreshWallet: () async => refreshCount += 1,
      readUid: () async => currentUid,
      analytics: analytics,
    );
    service.events.listen(uiEvents.add);
  });

  tearDown(() async {
    service.dispose();
    await platform.close();
  });

  test(
    'VIP callbacks and recovery are intercepted before Gems UI, reporting and analytics',
    () async {
      service.dispose();
      var interceptions = 0;
      service = GooglePlayBillingService(
        platform: platform,
        pendingPurchaseStore: pendingStore,
        loadBillingAccountId: () async => billingAccountId,
        loadProductCatalog: () async => [_product],
        reportPurchase: (request) async {
          reports.add(request);
          return const GemPurchaseReport(
            status: GemPurchaseReportStatus.completed,
            grantedGemsCent: 55000,
          );
        },
        refreshWallet: () async => refreshCount++,
        readUid: () async => currentUid,
        analytics: analytics,
        interceptPurchase: (purchase) async {
          interceptions++;
          return purchase.productId == 'vip-test';
        },
      );
      service.events.listen(uiEvents.add);
      const vip = BillingPurchase(
        provider: BillingProvider.googlePlay,
        productId: 'vip-test',
        purchaseToken: 'vip-token',
        transactionId: 'vip-order',
        originalTransactionId: '',
        originalJson: '',
        purchaseTime: '',
        status: BillingPurchaseStatus.purchased,
        obfuscatedAccountId: '4b74ec68-7abc-4cce-a223-e997e31dc811',
      );
      await service.start();
      platform.emit(vip);
      await _settle();
      platform.recoverablePurchases = [vip];
      await service.recoverStorePurchases(productCatalog: [_product]);
      expect(interceptions, 2);
      expect(reports, isEmpty);
      expect(uiEvents, isEmpty);
      expect(analytics.records, isEmpty);
      expect(await pendingStore.loadAll(), isEmpty);

      await service.purchaseGem(_product);
      platform.emit(_purchase(BillingPurchaseStatus.purchased));
      await _settle();
      expect(reports.single.productId, _product.productId);
      expect(uiEvents.last.kind, BillingUiEventKind.success);
      expect(interceptions, 2);
    },
  );

  test(
    'purchased callbacks repeat purchase and record purchase_first once',
    () async {
      final firebaseAnalytics = _RecordingFirebaseAnalyticsClient();
      FirebaseAnalyticsMonitoring.resetForTesting();
      FirebaseAnalyticsMonitoring.setClientForTesting(firebaseAnalytics);
      FirebaseAnalyticsMonitoring.setOnceEventStoreForTesting(
        _MemoryFirebaseAnalyticsOnceEventStore(),
      );
      FirebaseAnalyticsMonitoring.setEnabledForTesting(true);
      FirebaseAnalyticsMonitoring.setReadinessForTesting(Future<void>.value());
      FirebaseAnalyticsMonitoring.setDeviceIdReaderForTesting(
        () async => 'test-device-id',
      );
      addTearDown(FirebaseAnalyticsMonitoring.resetForTesting);

      await service.start();
      platform.emit(_purchase(BillingPurchaseStatus.purchased));
      await _settle();
      platform.emit(
        _purchase(
          BillingPurchaseStatus.purchased,
          purchaseToken: 'purchase-token-2',
          transactionId: 'GPA.2',
          originalJson: '{"purchaseToken":"purchase-token-2"}',
        ),
      );
      await _settle();

      expect(firebaseAnalytics.events, <_FirebaseAnalyticsRecord>[
        const _FirebaseAnalyticsRecord('purchase', <String, Object>{
          'provider': 'google',
          'product_id': 'worldo_gems_500',
          'device_id': 'test-device-id',
        }),
        const _FirebaseAnalyticsRecord('purchase_first', <String, Object>{
          'provider': 'google',
          'product_id': 'worldo_gems_500',
          'device_id': 'test-device-id',
        }),
        const _FirebaseAnalyticsRecord('purchase', <String, Object>{
          'provider': 'google',
          'product_id': 'worldo_gems_500',
          'device_id': 'test-device-id',
        }),
      ]);
    },
  );

  test(
    'start only initializes billing and recovery reports local orders',
    () async {
      await pendingStore.upsert(
        _localPurchase(status: BillingPendingPurchaseStatus.received),
      );

      await service.start();
      expect(reports, isEmpty);

      await service.recover(BillingRecoverySource.appStart);

      expect(reports, hasLength(1));
      expect(await pendingStore.loadAll(), isEmpty);
    },
  );

  test('recovery ignores local orders owned by another UUID', () async {
    await pendingStore.upsert(
      _localPurchase(
        status: BillingPendingPurchaseStatus.received,
        billingAccountId: 'another-user-uuid',
      ),
    );

    await service.recover(BillingRecoverySource.appStart);

    expect(reports, isEmpty);
    expect(await pendingStore.loadAll(), hasLength(1));
  });

  test('local recovery does not depend on store availability', () async {
    platform.available = false;
    await pendingStore.upsert(
      _localPurchase(status: BillingPendingPurchaseStatus.received),
    );

    await service.recover(BillingRecoverySource.foreground);

    expect(reports, hasLength(1));
    expect(await pendingStore.loadAll(), isEmpty);
  });

  test(
    'purchase rechecks an unavailable store and continues with the same attempt',
    () async {
      platform.availabilityHandler = () => platform.availabilityCheckCount > 1;
      platform.buyAccepted = false;

      await service.start();
      expect(service.state.value.storeAvailable, isFalse);

      await service.purchaseGem(
        _product,
        payTrackId: 'track_id_availability_retry',
      );

      expect(platform.availabilityCheckCount, 2);
      expect(service.state.value.storeAvailable, isTrue);
      expect(platform.queryCount, 1);
      expect(platform.buyCount, 1);
      final click = analytics.records.singleWhere(
        (record) => record.action == 'product_click',
      );
      final failed = analytics.records.singleWhere(
        (record) => record.action == 'purchase_failed',
      );
      expect(click.properties['attempt_id'], 'track_id_availability_retry');
      expect(failed.properties['attempt_id'], 'track_id_availability_retry');
      expect(failed.properties['reason'], 'launch_failed');
    },
  );

  test(
    'purchase reports gp unavailable after the recheck is still false',
    () async {
      platform.availabilityHandler = () => false;

      await service.start();
      await service.purchaseGem(
        _product,
        payTrackId: 'track_id_still_unavailable',
      );

      expect(platform.availabilityCheckCount, 2);
      expect(platform.queryCount, 0);
      expect(platform.buyCount, 0);
      final failed = analytics.records.singleWhere(
        (record) => record.action == 'purchase_failed',
      );
      expect(failed.properties['attempt_id'], 'track_id_still_unavailable');
      expect(failed.properties['reason'], 'gp_unavailable');
    },
  );

  test('purchase reports gp unavailable when the recheck throws', () async {
    platform.availabilityHandler = () {
      if (platform.availabilityCheckCount == 1) return false;
      throw StateError('billing unavailable');
    };

    await service.start();
    await service.purchaseGem(
      _product,
      payTrackId: 'track_id_availability_exception',
    );

    expect(platform.availabilityCheckCount, 2);
    expect(platform.queryCount, 0);
    expect(platform.buyCount, 0);
    final failed = analytics.records.singleWhere(
      (record) => record.action == 'purchase_failed',
    );
    expect(failed.properties['attempt_id'], 'track_id_availability_exception');
    expect(failed.properties['reason'], 'gp_unavailable');
  });

  test(
    'store recovery reports another account local order without side effects',
    () async {
      await pendingStore.upsert(
        _localPurchase(
          attemptId: 'track_id_original',
          billingAccountId: 'another-user-uuid',
          status: BillingPendingPurchaseStatus.received,
        ),
      );
      platform.recoverablePurchases = <BillingPurchase>[
        _purchase(
          BillingPurchaseStatus.purchased,
          obfuscatedAccountId: 'another-user-uuid',
        ),
      ];

      final recovered = await service.recoverStorePurchases();
      await _settle();

      expect(recovered, isTrue);
      expect(platform.recoverableQueryCount, 1);
      expect(pendingStore.findCount, 1);
      expect(reports, hasLength(1));
      expect(reports.single.requestId, 'track_id_original');
      expect(reports.single.productId, _product.productId);
      expect(await pendingStore.loadAll(), hasLength(1));
      expect(uiEvents, isEmpty);
      expect(refreshCount, 0);
      expect(
        analytics.records.where(
          (record) => record.action == 'purchase_success',
        ),
        isEmpty,
      );
    },
  );

  test(
    'store recovery reports another account missing local order silently',
    () async {
      platform.recoverablePurchases = <BillingPurchase>[
        _purchase(
          BillingPurchaseStatus.purchased,
          obfuscatedAccountId: 'another-user-uuid',
        ),
      ];

      final recovered = await service.recoverStorePurchases();
      await _settle();

      expect(recovered, isTrue);
      expect(pendingStore.findCount, 1);
      expect(reports, hasLength(1));
      expect(reports.single.productId, _product.productId);
      expect(reports.single.storeProductId, _product.googleProductId);
      expect(reports.single.purchaseToken, 'purchase-token-1');
      expect(reports.single.requestId, isNotEmpty);
      expect(await pendingStore.loadAll(), isEmpty);
      expect(uiEvents, isEmpty);
      expect(refreshCount, 0);
      expect(
        analytics.records.where(
          (record) => record.action == 'purchase_success',
        ),
        isEmpty,
      );
    },
  );

  test('store recovery reuses the supplied product catalog', () async {
    platform.recoverablePurchases = <BillingPurchase>[
      _purchase(BillingPurchaseStatus.purchased),
    ];

    final recovered = await service.recoverStorePurchases(
      productCatalog: <GemProduct>[_product],
    );
    await _settle();

    expect(recovered, isTrue);
    expect(productCatalogLoadCount, 0);
    expect(reports, hasLength(1));
    expect(reports.single.productId, _product.productId);
  });

  test(
    'store recovery ignores every report result for another account',
    () async {
      for (final status in <GemPurchaseReportStatus>[
        GemPurchaseReportStatus.accepted,
        GemPurchaseReportStatus.rejected,
      ]) {
        reportStatus = status;
        final index = reports.length + 1;
        platform.recoverablePurchases = <BillingPurchase>[
          _purchase(
            BillingPurchaseStatus.purchased,
            purchaseToken: 'foreign-token-$index',
            transactionId: 'GPA.foreign.$index',
            obfuscatedAccountId: 'another-user-uuid',
          ),
        ];

        await service.recoverStorePurchases();
        await _settle();
      }

      expect(reports, hasLength(2));
      expect(await pendingStore.loadAll(), isEmpty);
      expect(uiEvents, isEmpty);
      expect(refreshCount, 0);
      expect(analytics.records, isEmpty);
    },
  );

  test(
    'store recovery processes a current account local order normally',
    () async {
      await pendingStore.upsert(
        _localPurchase(
          attemptId: 'track_id_original',
          status: BillingPendingPurchaseStatus.received,
        ),
      );
      platform.recoverablePurchases = <BillingPurchase>[
        _purchase(BillingPurchaseStatus.purchased),
      ];

      final recovered = await service.recoverStorePurchases();
      await _settle();

      expect(recovered, isTrue);
      expect(reports, hasLength(1));
      expect(await pendingStore.loadAll(), isEmpty);
      expect(
        uiEvents.where((event) => event.kind == BillingUiEventKind.success),
        hasLength(1),
      );
      expect(refreshCount, 1);
      expect(
        analytics.records.where(
          (record) => record.action == 'purchase_success',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'store recovery processes a current account missing local order normally',
    () async {
      platform.recoverablePurchases = <BillingPurchase>[
        _purchase(BillingPurchaseStatus.purchased),
      ];

      final recovered = await service.recoverStorePurchases();
      await _settle();

      expect(recovered, isTrue);
      expect(reports, hasLength(1));
      expect(await pendingStore.loadAll(), isEmpty);
      expect(
        uiEvents.where((event) => event.kind == BillingUiEventKind.success),
        hasLength(1),
      );
      expect(refreshCount, 1);
      expect(
        analytics.records.where(
          (record) => record.action == 'purchase_success',
        ),
        hasLength(1),
      );
    },
  );

  test('store recovery does not emit after the service is disposed', () async {
    final reportStarted = Completer<void>();
    final reportCompleter = Completer<GemPurchaseReport>();
    service.dispose();
    uiEvents.clear();
    service = GooglePlayBillingService(
      platform: platform,
      pendingPurchaseStore: pendingStore,
      loadBillingAccountId: () async => billingAccountId,
      loadProductCatalog: () async => [_product],
      reportPurchase: (request) {
        reports.add(request);
        reportStarted.complete();
        return reportCompleter.future;
      },
      refreshWallet: () async => refreshCount += 1,
      readUid: () async => currentUid,
      analytics: analytics,
    );
    service.events.listen(uiEvents.add);
    platform.recoverablePurchases = <BillingPurchase>[
      _purchase(BillingPurchaseStatus.purchased),
    ];

    final recovery = service.recoverStorePurchases();
    await reportStarted.future;
    service.dispose();
    reportCompleter.complete(
      const GemPurchaseReport(
        status: GemPurchaseReportStatus.completed,
        grantedGemsCent: 55000,
      ),
    );

    await expectLater(recovery, completion(isTrue));
    await _settle();
    expect(uiEvents, isEmpty);
  });

  test(
    'store recovery report failure leaves a missing local order unpersisted',
    () async {
      reportError = true;
      platform.recoverablePurchases = <BillingPurchase>[
        _purchase(BillingPurchaseStatus.purchased),
      ];

      final recovered = await service.recoverStorePurchases();

      expect(recovered, isTrue);
      expect(reports, hasLength(1));
      expect(await pendingStore.loadAll(), isEmpty);
    },
  );

  test('store recovery query failure is reported to the caller', () async {
    platform.recoverableQueryError = const BillingPlatformException(
      'query_purchases_failed',
    );

    final recovered = await service.recoverStorePurchases();

    expect(recovered, isFalse);
    expect(platform.recoverableQueryCount, 1);
    expect(reports, isEmpty);
  });

  test('store recovery deduplicates repeated platform results', () async {
    final purchase = _purchase(BillingPurchaseStatus.purchased);
    platform.recoverablePurchases = <BillingPurchase>[purchase, purchase];

    final recovered = await service.recoverStorePurchases();

    expect(recovered, isTrue);
    expect(pendingStore.findCount, 1);
    expect(reports, hasLength(1));
  });

  test('a recovered SKU does not prevent a normal purchase', () async {
    platform.recoverablePurchases = <BillingPurchase>[
      _purchase(BillingPurchaseStatus.purchased),
    ];
    await service.recoverStorePurchases();
    await _settle();
    uiEvents.clear();

    await service.purchaseGem(_product);
    await _settle();

    expect(platform.buyCount, 1);
    expect(uiEvents, isEmpty);
  });

  test('a new session recovery follows an older in-flight recovery', () async {
    final firstReport = Completer<GemPurchaseReport>();
    service.dispose();
    service = GooglePlayBillingService(
      platform: platform,
      pendingPurchaseStore: pendingStore,
      loadBillingAccountId: () async => billingAccountId,
      loadProductCatalog: () async => [_product],
      reportPurchase: (request) {
        reports.add(request);
        if (reports.length == 1) return firstReport.future;
        return Future<GemPurchaseReport>.value(
          const GemPurchaseReport(
            status: GemPurchaseReportStatus.completed,
            grantedGemsCent: 55000,
          ),
        );
      },
      refreshWallet: () async => refreshCount += 1,
      readUid: () async => currentUid,
      analytics: analytics,
    );
    service.events.listen(uiEvents.add);
    await pendingStore.upsert(
      _localPurchase(
        purchaseToken: 'purchase-token-first',
        attemptId: 'track_id_first',
        status: BillingPendingPurchaseStatus.received,
      ),
    );

    final firstRecovery = service.recover(BillingRecoverySource.appStart);
    await _settle();
    service.resetForSession();
    await pendingStore.upsert(
      _localPurchase(
        purchaseToken: 'purchase-token-second',
        attemptId: 'track_id_second',
        status: BillingPendingPurchaseStatus.received,
      ),
    );
    final secondRecovery = service.recover(BillingRecoverySource.foreground);
    firstReport.complete(
      const GemPurchaseReport(
        status: GemPurchaseReportStatus.completed,
        grantedGemsCent: 55000,
      ),
    );

    await Future.wait([firstRecovery, secondRecovery]);

    expect(reports, hasLength(2));
    expect(await pendingStore.loadAll(), isEmpty);
  });

  test(
    'callback without UUID uses the matching current-session attempt',
    () async {
      await service.purchaseGem(_product);
      platform.emit(
        _purchase(BillingPurchaseStatus.pending, obfuscatedAccountId: null),
      );
      await _settle();

      expect(
        uiEvents.map((event) => event.kind),
        contains(BillingUiEventKind.pending),
      );
      expect(uiEvents.last.kind, BillingUiEventKind.success);
      expect(
        analytics.records.where((record) => record.action == 'purchase_failed'),
        isEmpty,
      );
      expect(
        analytics.records.where(
          (record) => record.action == 'purchase_pending',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'callback owned by another UUID does not affect the active attempt',
    () async {
      await service.purchaseGem(_product);
      platform.emit(
        _purchase(
          BillingPurchaseStatus.pending,
          obfuscatedAccountId: 'another-user-uuid',
        ),
      );
      await _settle();

      expect(service.state.value.hasBusyPurchase, isTrue);
      expect(uiEvents, isEmpty);
      expect(
        analytics.records.where((record) => record.action == 'purchase_failed'),
        isEmpty,
      );
      expect(reports, isEmpty);
    },
  );

  test('completed report refreshes and ignores duplicate callback', () async {
    await service.purchaseGem(_product);
    platform.emit(_purchase(BillingPurchaseStatus.purchased));
    await _settle();

    expect(platform.queryCount, 1);
    expect(platform.buyCount, 1);
    expect(reports, hasLength(1));
    expect(reports.single.purchaseToken, 'purchase-token-1');
    expect(refreshCount, 1);
    expect(await pendingStore.loadAll(), isEmpty);
    expect(uiEvents, hasLength(2));
    expect(uiEvents.first.kind, BillingUiEventKind.processing);
    expect(uiEvents.first.message, 'Purchasing Gems');
    expect(uiEvents.last.kind, BillingUiEventKind.success);
    expect(uiEvents.last.grantedGemsCent, 55000);
    final click = analytics.records.singleWhere(
      (record) => record.action == 'product_click',
    );
    expect(click.properties['source'], 'buy_gems_page');

    platform.emit(_purchase(BillingPurchaseStatus.purchased));
    await _settle();
    expect(reports, hasLength(1));
    expect(
      analytics.records.where((record) => record.action == 'purchase_success'),
      hasLength(1),
    );
  });

  test(
    'completed report emits success before wallet refresh finishes',
    () async {
      service.dispose();
      await platform.close();
      platform = _FakeBillingPlatform(
        providerValue: BillingProvider.appStore,
        expectedStoreProductId: 'com.worldo.gems.500',
      );
      final releaseRefresh = Completer<void>();
      service = GooglePlayBillingService(
        platform: platform,
        pendingPurchaseStore: pendingStore,
        loadBillingAccountId: () async =>
            '4b74ec68-7abc-4cce-a223-e997e31dc811',
        loadProductCatalog: () async => [_product],
        reportPurchase: (request) async {
          reports.add(request);
          return const GemPurchaseReport(
            status: GemPurchaseReportStatus.completed,
            grantedGemsCent: 55000,
          );
        },
        refreshWallet: () => releaseRefresh.future,
        readUid: () async => 'u_1',
        analytics: analytics,
      );
      service.events.listen(uiEvents.add);

      await service.purchaseGem(_product);
      platform.emit(
        _purchase(
          BillingPurchaseStatus.purchased,
          provider: BillingProvider.appStore,
          storeProductId: 'com.worldo.gems.500',
          purchaseToken: '2000000123456790',
          transactionId: '2000000123456790',
        ),
      );
      await _settle();

      expect(reports, hasLength(1));
      expect(uiEvents.last.kind, BillingUiEventKind.success);

      releaseRefresh.complete();
      await _settle();
    },
  );

  test('pending callback persists its original purchase context', () async {
    reportStatus = GemPurchaseReportStatus.accepted;
    await service.purchaseGem(_product, payTrackId: 'track_id_original');
    platform.emit(_purchase(BillingPurchaseStatus.pending, transactionId: ''));
    await _settle();

    final pending = (await pendingStore.loadAll()).single;
    expect(pending.status, BillingPendingPurchaseStatus.accepted);
    expect(pending.attemptId, 'track_id_original');
    expect(pending.billingAccountId, '4b74ec68-7abc-4cce-a223-e997e31dc811');
    expect(
      uiEvents.map((event) => event.kind),
      contains(BillingUiEventKind.pending),
    );
    expect(reports, hasLength(1));
    final pendingEvent = analytics.records.singleWhere(
      (record) => record.action == 'purchase_pending',
    );
    expect(pendingEvent.properties['product_id'], 'gem_pack_500');
    expect(pendingEvent.properties['attempt_id'], 'track_id_original');
  });

  test('pending recovery reuses the original track id after reset', () async {
    reportStatus = GemPurchaseReportStatus.accepted;
    await service.purchaseGem(_product, payTrackId: 'track_id_original');
    platform.emit(_purchase(BillingPurchaseStatus.pending));
    await _settle();

    analytics.records.clear();
    uiEvents.clear();
    service.resetForSession();
    reportStatus = GemPurchaseReportStatus.completed;
    reportTransactionId = 'GPA.server-confirmed';

    await service.recover(BillingRecoverySource.appStart);

    expect(reports, hasLength(2));
    expect(reports.last.requestId, 'track_id_original');
    final success = analytics.records.singleWhere(
      (record) => record.action == 'purchase_success',
    );
    expect(success.properties['attempt_id'], 'track_id_original');
    expect(success.properties['transaction_id'], 'GPA.server-confirmed');
    expect(await pendingStore.loadAll(), isEmpty);
  });

  test('repeated pending callback is tracked only once', () async {
    reportStatus = GemPurchaseReportStatus.accepted;
    await service.purchaseGem(_product, payTrackId: 'track_id_original');

    platform.emit(_purchase(BillingPurchaseStatus.pending));
    await _settle();
    platform.emit(_purchase(BillingPurchaseStatus.pending));
    await _settle();

    final pendingEvents = analytics.records.where(
      (record) => record.action == 'purchase_pending',
    );
    expect(pendingEvents, hasLength(1));
    expect(
      (await pendingStore.loadAll()).single.attemptId,
      'track_id_original',
    );
  });

  test('pending purchase success keeps the original track id', () async {
    reportStatus = GemPurchaseReportStatus.accepted;
    await service.purchaseGem(_product, payTrackId: 'track_id_original');
    platform.emit(_purchase(BillingPurchaseStatus.pending));
    await _settle();

    analytics.records.clear();
    uiEvents.clear();
    service.resetForSession();
    reportStatus = GemPurchaseReportStatus.completed;

    await service.recover(BillingRecoverySource.appStart);

    expect(reports.last.requestId, 'track_id_original');
    final success = analytics.records.singleWhere(
      (record) => record.action == 'purchase_success',
    );
    expect(success.properties['attempt_id'], 'track_id_original');
  });

  test('multiple pending orders keep separate track ids by token', () async {
    reportStatus = GemPurchaseReportStatus.accepted;
    await service.purchaseGem(_product, payTrackId: 'track_id_first');
    platform.emit(
      _purchase(
        BillingPurchaseStatus.pending,
        purchaseToken: 'purchase-token-1',
      ),
    );
    await _settle();

    await service.purchaseGem(_product, payTrackId: 'track_id_second');
    platform.emit(
      _purchase(
        BillingPurchaseStatus.pending,
        purchaseToken: 'purchase-token-2',
        originalJson: '{"purchaseToken":"purchase-token-2"}',
      ),
    );
    await _settle();

    final stored = await pendingStore.loadAll();
    expect(stored, hasLength(2));
    expect(stored.map((record) => record.attemptId).toSet(), {
      'track_id_first',
      'track_id_second',
    });

    analytics.records.clear();
    uiEvents.clear();
    service.resetForSession();
    reportStatus = GemPurchaseReportStatus.completed;

    await service.recover(BillingRecoverySource.foreground);

    expect(reports, hasLength(4));
    expect(
      analytics.records
          .where((record) => record.action == 'purchase_success')
          .map((record) => record.properties['attempt_id'])
          .toSet(),
      {'track_id_first', 'track_id_second'},
    );
    expect(await pendingStore.loadAll(), isEmpty);
  });

  test('pending purchase context is isolated by UUID', () async {
    reportStatus = GemPurchaseReportStatus.accepted;
    await service.purchaseGem(_product, payTrackId: 'track_id_first_user');
    platform.emit(_purchase(BillingPurchaseStatus.pending));
    await _settle();

    analytics.records.clear();
    uiEvents.clear();
    reports.clear();
    billingAccountId = 'second-user-uuid';
    currentUid = 'u_2';
    service.resetForSession();

    await service.recover(BillingRecoverySource.foreground);

    expect(analytics.records, isEmpty);
    expect(uiEvents, isEmpty);
    expect(reports, isEmpty);
    expect(
      (await pendingStore.loadAll()).single.attemptId,
      'track_id_first_user',
    );
  });

  test(
    'recovery reports a retained local purchase without querying the store',
    () async {
      reportStatus = GemPurchaseReportStatus.accepted;
      await service.purchaseGem(_product, payTrackId: 'track_id_recovery');
      platform.emit(_purchase(BillingPurchaseStatus.pending));
      await _settle();
      analytics.records.clear();

      service.resetForSession();
      reportStatus = GemPurchaseReportStatus.completed;

      await service.recover(BillingRecoverySource.foreground);

      expect(await pendingStore.loadAll(), isEmpty);
      expect(reports, hasLength(2));
      expect(
        analytics.records
            .singleWhere((record) => record.action == 'purchase_success')
            .properties['attempt_id'],
        'track_id_recovery',
      );
    },
  );

  test('error callback keeps the normalized store error code', () async {
    await service.purchaseGem(_product);
    platform.emit(
      _purchase(
        BillingPurchaseStatus.error,
        errorCode: 'network_error',
        errorMessage: 'BillingResponse.networkError',
      ),
    );
    await _settle();

    final failed = analytics.records.singleWhere(
      (record) => record.action == 'purchase_failed',
    );
    expect(failed.properties['reason'], 'purchase_callback_error');
    expect(failed.properties['error_code'], 'network_error');
  });

  test('paid callback defers when persisted context cannot be read', () async {
    await service.purchaseGem(_product, payTrackId: 'track_id_original');
    pendingStore.failNextFind = true;

    platform.emit(_purchase(BillingPurchaseStatus.purchased));
    await _settle();

    expect(reports, isEmpty);
    expect(await pendingStore.loadAll(), isEmpty);
    expect(uiEvents.single.kind, BillingUiEventKind.deferred);
    expect(uiEvents.single.attemptId, 'track_id_original');
  });

  test('error callback falls back to store_error without a code', () async {
    await service.purchaseGem(_product);
    platform.emit(_purchase(BillingPurchaseStatus.error));
    await _settle();

    final failed = analytics.records.singleWhere(
      (record) => record.action == 'purchase_failed',
    );
    expect(failed.properties['reason'], 'purchase_callback_error');
    expect(failed.properties['error_code'], 'store_error');
  });

  test(
    'product query failure is tracked and does not launch billing',
    () async {
      platform.queryResult = const BillingProductQueryResult.failure(
        'product_not_found',
      );

      await service.purchaseGem(_product);
      await _settle();

      expect(platform.buyCount, 0);
      final failed = analytics.records.singleWhere(
        (record) => record.action == 'purchase_failed',
      );
      expect(failed.properties['product_id'], 'gem_pack_500');
      expect(failed.properties['reason'], 'query_failed');
      expect(failed.properties['error_code'], 'product_not_found');
    },
  );

  test(
    'product not found reloads catalog and retries with the latest id',
    () async {
      const refreshedProduct = GemProduct(
        productId: 'gem_pack_500',
        appleProductId: 'com.worldo.gems.500',
        googleProductId: 'worldo_gems_500_v2',
        baseGemsCent: 50000,
        bonusGemsCent: 5000,
        priceCurrencyCode: 'USD',
        priceAmount: 499,
        canPurchase: true,
        activityType: 'none',
      );
      var firstQuery = true;
      platform.expectedStoreProductId = refreshedProduct.googleProductId;
      platform.queryHandler = (storeProductId) {
        if (firstQuery) {
          firstQuery = false;
          expect(storeProductId, _product.googleProductId);
          return const BillingProductQueryResult.failure('product_not_found');
        }
        expect(storeProductId, refreshedProduct.googleProductId);
        return BillingProductQueryResult.success(
          BillingStoreProduct(
            id: refreshedProduct.googleProductId,
            type: BillingStoreProductType.inApp,
            nativeProduct: const Object(),
          ),
        );
      };
      service.dispose();
      service = GooglePlayBillingService(
        platform: platform,
        pendingPurchaseStore: pendingStore,
        loadBillingAccountId: () async =>
            '4b74ec68-7abc-4cce-a223-e997e31dc811',
        loadProductCatalog: () async => const [refreshedProduct],
        reportPurchase: (request) async {
          reports.add(request);
          return const GemPurchaseReport(
            status: GemPurchaseReportStatus.completed,
            grantedGemsCent: 55000,
          );
        },
        refreshWallet: () async => refreshCount += 1,
        readUid: () async => 'u_1',
        analytics: analytics,
      );
      service.events.listen(uiEvents.add);

      await service.purchaseGem(_product);

      expect(platform.queriedStoreProductIds, [
        _product.googleProductId,
        refreshedProduct.googleProductId,
      ]);
      expect(platform.buyCount, 1);
    },
  );

  test('billing launch rejection is tracked', () async {
    platform.buyAccepted = false;

    await service.purchaseGem(_product);
    await _settle();

    final failed = analytics.records.singleWhere(
      (record) => record.action == 'purchase_failed',
    );
    expect(failed.properties['reason'], 'launch_failed');
  });

  test(
    'purchase stream errors are contained and clear the active checkout',
    () async {
      await service.purchaseGem(_product, payTrackId: 'track_id_stream_error');
      expect(service.state.value.hasBusyPurchase, isTrue);

      platform.emitError(StateError('store stream failed'));
      await _settle();

      expect(service.state.value.hasBusyPurchase, isFalse);
      expect(uiEvents.last.kind, BillingUiEventKind.failure);
      expect(uiEvents.last.attemptId, 'track_id_stream_error');
      expect(uiEvents.last.message, 'Payment service is unavailable.');
    },
  );

  test('billing launch failure tracks the platform error code', () async {
    platform.buyHandler = () {
      throw PlatformException(code: 'storekit_duplicate_product_object');
    };

    await service.purchaseGem(_product);
    await _settle();

    final failed = analytics.records.singleWhere(
      (record) => record.action == 'purchase_failed',
    );
    expect(failed.properties['reason'], 'launch_failed');
    expect(
      failed.properties['error_code'],
      'storekit_duplicate_product_object',
    );
  });

  for (final stage in ['initialization', 'account', 'query', 'catalog']) {
    test(
      'click deadline covers a stuck $stage and ignores its late result',
      () async {
        service.dispose();
        final availability = Completer<bool>();
        final account = Completer<String>();
        final query = Completer<BillingProductQueryResult>();
        final catalog = Completer<List<GemProduct>>();
        var accountCalls = 0;
        var finished = false;
        if (stage == 'initialization') {
          platform.availabilityHandler = () => availability.future;
        }
        if (stage == 'query') platform.queryHandler = (_) => query.future;
        if (stage == 'catalog') {
          platform.queryHandler = (_) =>
              const BillingProductQueryResult.failure('product_not_found');
        }
        service = GooglePlayBillingService(
          platform: platform,
          pendingPurchaseStore: pendingStore,
          loadBillingAccountId: () async {
            accountCalls++;
            return stage == 'account' ? account.future : billingAccountId;
          },
          loadProductCatalog: () => catalog.future,
          reportPurchase: (_) async => const GemPurchaseReport(
            status: GemPurchaseReportStatus.completed,
          ),
          refreshWallet: () async {},
          readUid: () async => currentUid,
          analytics: analytics,
          attemptTimeout: const Duration(milliseconds: 30),
        );
        service.events.listen(uiEvents.add);
        final purchase = service
            .purchaseGem(_product, payTrackId: 'stuck-$stage')
            .then((_) => finished = true);
        await _settle();
        expect(service.state.value.hasBusyPurchase, isTrue);
        await service.purchaseGem(_product, payTrackId: 'duplicate-$stage');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await _settle();
        expect(finished, isTrue);
        expect(service.state.value.hasBusyPurchase, isFalse);
        expect(platform.buyCount, 0);
        expect(
          analytics.records.where((e) => e.action == 'purchase_timeout'),
          hasLength(1),
        );
        expect(uiEvents.single.kind, BillingUiEventKind.deferred);
        expect(uiEvents.single.attemptId, 'stuck-$stage');
        expect(
          uiEvents.single.message,
          'Purchase timed out. Please try again.',
        );
        availability.complete(true);
        account.complete(billingAccountId);
        query.complete(platform.queryResult);
        catalog.complete([_product]);
        await purchase;
        await _settle();
        expect(platform.buyCount, 0);
        expect(accountCalls, stage == 'initialization' ? 0 : 1);
        expect(uiEvents, hasLength(1));
      },
    );
  }

  test('late query failure cannot release a newer checkout', () async {
    service.dispose();
    final query = Completer<BillingProductQueryResult>();
    platform.queryHandler = (_) => query.future;
    service = GooglePlayBillingService(
      platform: platform,
      pendingPurchaseStore: pendingStore,
      loadBillingAccountId: () async => billingAccountId,
      loadProductCatalog: () async => [_product],
      reportPurchase: (_) async =>
          const GemPurchaseReport(status: GemPurchaseReportStatus.completed),
      refreshWallet: () async {},
      readUid: () async => currentUid,
      analytics: analytics,
      attemptTimeout: const Duration(milliseconds: 50),
    );
    await service.purchaseGem(_product, payTrackId: 'old-query');
    platform.queryHandler = (_) => platform.queryResult;
    await service.purchaseGem(_product, payTrackId: 'new-query');
    expect(platform.buyCount, 1);
    query.completeError(StateError('late failure'));
    await _settle();
    expect(service.state.value.hasBusyPurchase, isTrue);
    expect(
      analytics.records.where((e) => e.action == 'purchase_failed'),
      isEmpty,
    );
  });

  test('account failure cancels the click deadline', () async {
    service.dispose();
    service = GooglePlayBillingService(
      platform: platform,
      pendingPurchaseStore: pendingStore,
      loadBillingAccountId: () async => throw StateError('lookup failed'),
      loadProductCatalog: () async => [_product],
      reportPurchase: (_) async =>
          const GemPurchaseReport(status: GemPurchaseReportStatus.completed),
      refreshWallet: () async {},
      readUid: () async => currentUid,
      analytics: analytics,
      attemptTimeout: const Duration(milliseconds: 20),
    );
    await service.purchaseGem(_product);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(service.state.value.hasBusyPurchase, isFalse);
    expect(platform.buyCount, 0);
    expect(
      analytics.records.where((e) => e.action == 'purchase_timeout'),
      isEmpty,
    );
  });

  test(
    'completed callback cannot become a timeout when launch returns late',
    () async {
      service.dispose();
      final launch = Completer<bool>();
      platform.buyHandler = () => launch.future;
      service = GooglePlayBillingService(
        platform: platform,
        pendingPurchaseStore: pendingStore,
        loadBillingAccountId: () async => billingAccountId,
        loadProductCatalog: () async => [_product],
        reportPurchase: (request) async {
          reports.add(request);
          return const GemPurchaseReport(
            status: GemPurchaseReportStatus.completed,
            grantedGemsCent: 55000,
          );
        },
        refreshWallet: () async {},
        readUid: () async => currentUid,
        analytics: analytics,
        attemptTimeout: const Duration(milliseconds: 30),
      );
      final purchase = service.purchaseGem(_product);
      await _settle();
      platform.emit(_purchase(BillingPurchaseStatus.purchased));
      await _settle();
      expect(reports, hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      launch.complete(false);
      await purchase;
      expect(
        analytics.records.where((e) => e.action == 'purchase_success'),
        hasLength(1),
      );
      expect(
        analytics.records.where(
          (e) =>
              e.action == 'purchase_timeout' || e.action == 'purchase_failed',
        ),
        isEmpty,
      );
    },
  );

  test('old handoff cannot stop the next purchase preparation timer', () async {
    service.dispose();
    final oldLaunch = Completer<bool>();
    platform.buyHandler = () => oldLaunch.future;
    service = GooglePlayBillingService(
      platform: platform,
      pendingPurchaseStore: pendingStore,
      loadBillingAccountId: () async => billingAccountId,
      loadProductCatalog: () async => [_product],
      reportPurchase: (_) async => throw StateError('unexpected report'),
      refreshWallet: () async {},
      readUid: () async => currentUid,
      analytics: analytics,
      attemptTimeout: const Duration(milliseconds: 60),
    );
    final old = service.purchaseGem(_product, payTrackId: 'old');
    await _settle();
    final oldHandoff = platform.handoff!;
    platform.emit(_purchase(BillingPurchaseStatus.canceled));
    await _settle();

    final newQuery = Completer<BillingProductQueryResult>();
    platform.queryHandler = (_) => newQuery.future;
    final current = service.purchaseGem(_product, payTrackId: 'new');
    await _settle();
    expect(oldHandoff(), isFalse);
    oldLaunch.complete(true);
    await old;
    await current;
    expect(
      analytics.records
          .where((r) => r.action == 'purchase_timeout')
          .map((r) => r.properties['attempt_id']),
      ['new'],
    );
    expect(service.state.value.hasBusyPurchase, isFalse);
    newQuery.complete(platform.queryResult);
    await _settle();
    expect(platform.buyCount, 1);
  });

  test(
    'preparation timeout covers a purchase launch without handoff',
    () async {
      service.dispose();
      final releaseLaunch = Completer<bool>();
      platform.buyHandler = () => releaseLaunch.future;
      service = GooglePlayBillingService(
        platform: platform,
        pendingPurchaseStore: pendingStore,
        loadBillingAccountId: () async =>
            '4b74ec68-7abc-4cce-a223-e997e31dc811',
        loadProductCatalog: () async => [_product],
        reportPurchase: (request) async {
          reports.add(request);
          return const GemPurchaseReport(
            status: GemPurchaseReportStatus.completed,
            grantedGemsCent: 55000,
          );
        },
        refreshWallet: () async => refreshCount += 1,
        readUid: () async => 'u_1',
        analytics: analytics,
        attemptTimeout: const Duration(milliseconds: 10),
      );

      final purchase = service.purchaseGem(
        _product,
        payTrackId: 'track_id_launch_timeout',
      );
      await _settle();
      expect(platform.buyCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await _settle();

      final timeout = analytics.records.singleWhere(
        (record) => record.action == 'purchase_timeout',
      );
      expect(timeout.properties['attempt_id'], 'track_id_launch_timeout');
      expect(timeout.properties['timeout_type'], 'store_no_callback');
      expect(service.state.value.hasBusyPurchase, isFalse);

      releaseLaunch.complete(true);
      await purchase;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        analytics.records.where(
          (record) => record.action == 'purchase_timeout',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'unsupported product type is tracked before launching billing',
    () async {
      const subscriptionProduct = GemProduct(
        productId: 'gem_subscription',
        appleProductId: 'com.worldo.gems.subscription',
        googleProductId: 'worldo_gems_subscription',
        baseGemsCent: 50000,
        bonusGemsCent: 0,
        priceCurrencyCode: 'USD',
        priceAmount: 149,
        canPurchase: true,
        activityType: 'none',
        billingType: 'subscription',
      );

      await service.purchaseGem(subscriptionProduct);
      await _settle();

      expect(platform.queryCount, 0);
      expect(platform.buyCount, 0);
      final failed = analytics.records.singleWhere(
        (record) => record.action == 'purchase_failed',
      );
      expect(failed.properties['product_id'], 'gem_subscription');
      expect(failed.properties['reason'], 'unsupported_product_type');
    },
  );

  test('local order write failure is tracked and blocks report', () async {
    pendingStore.failNextUpsert = true;

    await service.purchaseGem(_product);
    platform.emit(_purchase(BillingPurchaseStatus.purchased));
    await _settle();

    expect(reports, isEmpty);
    expect(await pendingStore.loadAll(), isEmpty);
    expect(uiEvents.last.kind, BillingUiEventKind.deferred);
  });

  test('server report failure keeps the received purchase for retry', () async {
    reportError = true;
    await service.purchaseGem(_product);
    platform.emit(_purchase(BillingPurchaseStatus.purchased));
    await _settle();

    final pending = await pendingStore.loadAll();
    expect(pending, hasLength(1));
    expect(pending.single.status, BillingPendingPurchaseStatus.received);
    expect(pending.single.retryCount, 1);
    expect(uiEvents, hasLength(2));
    expect(uiEvents.first.kind, BillingUiEventKind.processing);
    expect(uiEvents.last.kind, BillingUiEventKind.deferred);
    final failed = analytics.records.singleWhere(
      (record) => record.action == 'purchase_failed',
    );
    expect(failed.properties['reason'], 'report_failed');
    expect(failed.properties['error_code'], 'transport');
    expect(
      analytics.records.where((record) => record.action == 'purchase_timeout'),
      isEmpty,
    );

    reportError = false;
    await service.recover(BillingRecoverySource.foreground);
    await _settle();

    expect(reports, hasLength(2));
  });

  test('network report timeout keeps the order for recovery', () async {
    service.dispose();
    uiEvents = <BillingUiEvent>[];
    var shouldTimeout = true;
    service = GooglePlayBillingService(
      platform: platform,
      pendingPurchaseStore: pendingStore,
      loadBillingAccountId: () async => '4b74ec68-7abc-4cce-a223-e997e31dc811',
      loadProductCatalog: () async => [_product],
      reportPurchase: (request) async {
        reports.add(request);
        if (shouldTimeout) {
          throw ApiException(
            message: 'timeout',
            kind: ApiExceptionKind.timeout,
          );
        }
        return const GemPurchaseReport(
          status: GemPurchaseReportStatus.completed,
          grantedGemsCent: 55000,
        );
      },
      refreshWallet: () async => refreshCount += 1,
      readUid: () async => 'u_1',
      analytics: analytics,
    );
    service.events.listen(uiEvents.add);

    await service.purchaseGem(_product);
    platform.emit(_purchase(BillingPurchaseStatus.purchased));
    await _settle();

    expect(uiEvents, hasLength(2));
    expect(uiEvents.first.kind, BillingUiEventKind.processing);
    expect(uiEvents.last.kind, BillingUiEventKind.deferred);
    expect(uiEvents.last.message, 'Payment is being confirmed.');
    expect(service.state.value.hasBusyPurchase, isFalse);
    final timeout = analytics.records.singleWhere(
      (record) => record.action == 'purchase_timeout',
    );
    expect(timeout.properties['product_id'], 'gem_pack_500');
    expect(timeout.properties['timeout_type'], 'report');
    final pending = (await pendingStore.loadAll()).single;
    expect(pending.retryCount, 1);
    expect(pending.reportTimeoutTracked, isTrue);

    shouldTimeout = false;
    await service.recover(BillingRecoverySource.foreground);
    await _settle();

    expect(reports, hasLength(2));
    expect(refreshCount, 1);
    expect(await pendingStore.loadAll(), isEmpty);
    expect(
      analytics.records.where((record) => record.action == 'purchase_success'),
      hasLength(1),
    );
  });

  test(
    'opened store flow has no deadline while waiting for the user',
    () async {
      service.dispose();
      service = GooglePlayBillingService(
        platform: platform,
        pendingPurchaseStore: pendingStore,
        loadBillingAccountId: () async =>
            '4b74ec68-7abc-4cce-a223-e997e31dc811',
        loadProductCatalog: () async => [_product],
        reportPurchase: (request) async {
          reports.add(request);
          return const GemPurchaseReport(
            status: GemPurchaseReportStatus.completed,
            grantedGemsCent: 55000,
          );
        },
        refreshWallet: () async => refreshCount += 1,
        readUid: () async => 'u_1',
        analytics: analytics,
        attemptTimeout: const Duration(milliseconds: 10),
      );

      await service.purchaseGem(_product, payTrackId: 'track_id_timeout');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await _settle();

      expect(
        analytics.records.where(
          (record) => record.action == 'purchase_timeout',
        ),
        isEmpty,
      );
      expect(
        analytics.records.where((record) => record.action == 'purchase_failed'),
        isEmpty,
      );
      expect(service.state.value.hasBusyPurchase, isTrue);

      platform.emit(_purchase(BillingPurchaseStatus.purchased));
      await _settle();

      final success = analytics.records.singleWhere(
        (record) => record.action == 'purchase_success',
      );
      expect(success.properties['attempt_id'], 'track_id_timeout');
    },
  );

  for (final provider in BillingProvider.values) {
    for (final outcome in [
      BillingPurchaseStatus.purchased,
      BillingPurchaseStatus.canceled,
      BillingPurchaseStatus.error,
      BillingPurchaseStatus.pending,
    ]) {
      test(
        '$provider store handoff ends preparation timeout before $outcome',
        () async {
          service.dispose();
          await platform.close();
          platform = _FakeBillingPlatform(
            providerValue: provider,
            expectedStoreProductId: provider == BillingProvider.appStore
                ? _product.appleProductId
                : _product.googleProductId,
          );
          final result = Completer<bool>();
          if (provider == BillingProvider.appStore) {
            platform.buyHandler = () async {
              expect(platform.handoff!(), isTrue);
              return result.future;
            };
          }
          service = GooglePlayBillingService(
            platform: platform,
            pendingPurchaseStore: pendingStore,
            loadBillingAccountId: () async => billingAccountId,
            loadProductCatalog: () async => [_product],
            reportPurchase: (request) async {
              reports.add(request);
              return const GemPurchaseReport(
                status: GemPurchaseReportStatus.completed,
                grantedGemsCent: 55000,
              );
            },
            refreshWallet: () async {},
            readUid: () async => currentUid,
            analytics: analytics,
            attemptTimeout: const Duration(milliseconds: 30),
          );
          final purchase = service.purchaseGem(_product);
          await _settle();
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(service.state.value.hasBusyPurchase, isTrue);
          expect(
            analytics.records.where((r) => r.action == 'purchase_timeout'),
            isEmpty,
          );
          platform.emit(
            _purchase(
              outcome,
              provider: provider,
              storeProductId: platform.expectedStoreProductId,
              transactionId: '12345',
            ),
          );
          await _settle();
          result.complete(true);
          await purchase;
          expect(
            analytics.records.where((r) => r.action == 'purchase_timeout'),
            isEmpty,
          );
          expect(service.state.value.hasBusyPurchase, isFalse);
        },
      );
    }
  }

  test('report timeout is not tracked again after app recovery', () async {
    service.dispose();
    await pendingStore.upsert(
      _localPurchase(
        status: BillingPendingPurchaseStatus.accepted,
        reportTimeoutTracked: true,
      ),
    );
    service = GooglePlayBillingService(
      platform: platform,
      pendingPurchaseStore: pendingStore,
      loadBillingAccountId: () async => '4b74ec68-7abc-4cce-a223-e997e31dc811',
      loadProductCatalog: () async => [_product],
      reportPurchase: (request) async {
        reports.add(request);
        throw ApiException(message: 'timeout', kind: ApiExceptionKind.timeout);
      },
      refreshWallet: () async => refreshCount += 1,
      readUid: () async => 'u_1',
      analytics: analytics,
    );

    await service.recover(BillingRecoverySource.foreground);

    expect(
      analytics.records.where((record) => record.action == 'purchase_timeout'),
      isEmpty,
    );
    final pending = (await pendingStore.loadAll()).single;
    expect(pending.retryCount, 1);
    expect(pending.reportTimeoutTracked, isTrue);
  });

  test('records only the simplified purchase telemetry stages', () async {
    platform.queryResult = BillingProductQueryResult.success(
      const BillingStoreProduct(
        id: 'worldo_gems_500',
        type: BillingStoreProductType.inApp,
        nativeProduct: Object(),
        purchaseOptionId: '500-gems-new',
        offerId: '500-gems-new-discount',
        offerToken: 'sensitive-offer-token',
        formattedPrice: r'$1.49',
        priceAmountMicros: 1490000,
        priceCurrencyCode: 'USD',
      ),
    );

    await service.purchaseGem(
      _product,
      source: BillingPurchaseSource.buyGemsSheet,
      payTrackId: 'pay_sheet_track',
    );
    platform.emit(_purchase(BillingPurchaseStatus.purchased));
    await _settle();

    final actions = analytics.records.map((record) => record.action).toList();
    expect(
      actions,
      containsAllInOrder(<String>['product_click', 'purchase_success']),
    );
    expect(
      actions.where(
        (action) => action == 'product_click' || action == 'purchase_success',
      ),
      hasLength(actions.length),
    );
    final click = analytics.records.singleWhere(
      (record) => record.action == 'product_click',
    );
    expect(click.properties['source'], 'buy_gems_sheet');
    expect(click.properties['attempt_id'], 'pay_sheet_track');
    final success = analytics.records.singleWhere(
      (record) => record.action == 'purchase_success',
    );
    expect(success.properties['product_id'], 'gem_pack_500');
    expect(success.properties['attempt_id'], 'pay_sheet_track');
    expect(success.properties['transaction_id'], 'GPA.1');

    final serialized = analytics.records
        .expand((record) => record.properties.entries)
        .map((entry) => '${entry.key}=${entry.value}')
        .join('|');
    expect(serialized, isNot(contains('purchase-token-1')));
    expect(serialized, isNot(contains('sensitive-offer-token')));
    expect(serialized, isNot(contains('4b74ec68-7abc-4cce-a223-e997e31dc811')));
    expect(serialized, isNot(contains('original_json')));
  });

  test('accepted is retained and reported again until completed', () async {
    reportStatus = GemPurchaseReportStatus.accepted;
    reportTransactionId = 'GPA.accepted-confirmed';
    await service.purchaseGem(_product);
    platform.emit(_purchase(BillingPurchaseStatus.purchased));
    await _settle();

    final reported = await pendingStore.loadAll();
    expect(reported.single.status, BillingPendingPurchaseStatus.accepted);
    expect(reported.single.transactionId, 'GPA.accepted-confirmed');
    expect(refreshCount, 0);
    expect(uiEvents, hasLength(2));
    expect(uiEvents.first.kind, BillingUiEventKind.processing);
    expect(uiEvents.last.kind, BillingUiEventKind.accepted);
    expect(
      uiEvents.last.message,
      'Payment received.\n'
      'Your Gems will be added shortly. Please check your balance again in a moment.',
    );

    service.resetForSession();
    await service.recover(BillingRecoverySource.foreground);
    await _settle();

    expect(reports, hasLength(2));
    expect(await pendingStore.loadAll(), hasLength(1));
    expect(
      uiEvents.where((event) => event.kind == BillingUiEventKind.accepted),
      hasLength(1),
    );

    reportStatus = GemPurchaseReportStatus.completed;
    reportTransactionId = '';
    await service.recover(BillingRecoverySource.foreground);
    await _settle();

    expect(reports, hasLength(3));
    expect(await pendingStore.loadAll(), isEmpty);
    expect(
      uiEvents.where((event) => event.kind == BillingUiEventKind.accepted),
      hasLength(1),
    );
    expect(
      analytics.records
          .singleWhere((record) => record.action == 'purchase_success')
          .properties['transaction_id'],
      'GPA.accepted-confirmed',
    );
  });

  test('rejected is terminal and does not refresh the wallet', () async {
    reportStatus = GemPurchaseReportStatus.rejected;
    reportReason = 'account_mismatch';
    await service.purchaseGem(_product);
    platform.emit(_purchase(BillingPurchaseStatus.purchased));
    await _settle();

    expect(await pendingStore.loadAll(), isEmpty);
    expect(refreshCount, 0);
    expect(uiEvents, hasLength(2));
    expect(uiEvents.first.kind, BillingUiEventKind.processing);
    expect(uiEvents.last.kind, BillingUiEventKind.failure);
    expect(uiEvents.last.message, 'Purchase was refunded.');
    final failed = analytics.records.singleWhere(
      (record) => record.action == 'purchase_failed',
    );
    expect(failed.properties['product_id'], 'gem_pack_500');
    expect(failed.properties['reason'], 'report_rejected');
    expect(failed.properties['error_code'], 'account_mismatch');
  });

  test('local recovery does not change an active platform checkout', () async {
    await service.purchaseGem(_product);
    expect(service.state.value.hasBusyPurchase, isTrue);

    await service.recover(BillingRecoverySource.foreground);

    expect(service.state.value.hasBusyPurchase, isTrue);
  });

  test(
    'passes the selected Google offer through to the purchase flow',
    () async {
      platform.queryResult = BillingProductQueryResult.success(
        const BillingStoreProduct(
          id: 'worldo_gems_500',
          type: BillingStoreProductType.inApp,
          nativeProduct: Object(),
          purchaseOptionId: '500-gems-new',
          offerId: '500-gems-new-discount',
          offerToken: 'offer-token-1',
        ),
      );
      const product = GemProduct(
        productId: 'gem_pack_500',
        appleProductId: 'com.worldo.gems.500',
        googleProductId: 'worldo_gems_500',
        googlePurchaseOptionId: '500-gems-new',
        googleOfferId: '500-gems-new-discount',
        baseGemsCent: 50000,
        bonusGemsCent: 5000,
        priceCurrencyCode: 'USD',
        priceAmount: 149,
        canPurchase: true,
        activityType: 'none',
      );

      await service.purchaseGem(product);

      expect(platform.queriedPurchaseOptionId, '500-gems-new');
      expect(platform.queriedOfferId, '500-gems-new-discount');
      expect(platform.purchasedOfferToken, 'offer-token-1');
    },
  );

  test(
    'ignores Google offer fields unless purchase option and offer id are both present',
    () async {
      const product = GemProduct(
        productId: 'gem_pack_500',
        appleProductId: 'com.worldo.gems.500',
        googleProductId: 'worldo_gems_500',
        googlePurchaseOptionId: '500-gems-new',
        baseGemsCent: 50000,
        bonusGemsCent: 5000,
        priceCurrencyCode: 'USD',
        priceAmount: 149,
        canPurchase: true,
        activityType: 'none',
      );

      await service.purchaseGem(product);

      expect(platform.queriedPurchaseOptionId, isNull);
      expect(platform.queriedOfferId, isNull);
      expect(platform.purchasedOfferToken, isNull);
    },
  );

  test(
    'app store purchases report apple store product id without token',
    () async {
      service.dispose();
      await platform.close();
      platform = _FakeBillingPlatform(
        providerValue: BillingProvider.appStore,
        expectedStoreProductId: 'com.worldo.gems.500',
      );
      reports = <GemPurchaseReportRequest>[];
      uiEvents = <BillingUiEvent>[];
      service = GooglePlayBillingService(
        platform: platform,
        pendingPurchaseStore: pendingStore,
        loadBillingAccountId: () async =>
            '4b74ec68-7abc-4cce-a223-e997e31dc811',
        loadProductCatalog: () async => [_product],
        reportPurchase: (request) async {
          reports.add(request);
          return const GemPurchaseReport(
            status: GemPurchaseReportStatus.completed,
            grantedGemsCent: 55000,
          );
        },
        refreshWallet: () async => refreshCount += 1,
        readUid: () async => 'u_1',
        analytics: analytics,
      );
      service.events.listen(uiEvents.add);

      await service.purchaseGem(_product, payTrackId: 'track_id_page_click');
      platform.emit(
        _purchase(
          BillingPurchaseStatus.purchased,
          provider: BillingProvider.appStore,
          storeProductId: 'com.worldo.gems.500',
          purchaseToken: '2000000123456789',
          transactionId: '2000000123456789',
          originalJson: '{"transactionId":"2000000123456789"}',
        ),
      );
      await _settle();

      expect(platform.queryCount, 1);
      expect(platform.buyCount, 1);
      expect(reports, hasLength(1));
      final request = reports.single;
      expect(request.provider, 'apple');
      expect(request.productId, 'gem_pack_500');
      expect(request.storeProductId, 'com.worldo.gems.500');
      expect(request.transactionId, '2000000123456789');
      expect(request.purchaseToken, isNull);
      expect(request.requestId, 'track_id_page_click');
      expect(request.payload, {'purchase_time': '1000'});
      final success = analytics.records.singleWhere(
        (record) => record.action == 'purchase_success',
      );
      expect(success.properties['transaction_id'], '2000000123456789');
      expect(platform.analyticsTransactionIds, {'2000000123456789'});
    },
  );

  test('app store local recovery does not clear an active checkout', () async {
    service.dispose();
    await platform.close();
    platform = _FakeBillingPlatform(
      providerValue: BillingProvider.appStore,
      expectedStoreProductId: 'com.worldo.gems.500',
    );
    reports = <GemPurchaseReportRequest>[];
    service = GooglePlayBillingService(
      platform: platform,
      pendingPurchaseStore: pendingStore,
      loadBillingAccountId: () async => '4b74ec68-7abc-4cce-a223-e997e31dc811',
      loadProductCatalog: () async => [_product],
      reportPurchase: (request) async {
        reports.add(request);
        return const GemPurchaseReport(
          status: GemPurchaseReportStatus.completed,
          grantedGemsCent: 55000,
        );
      },
      refreshWallet: () async => refreshCount += 1,
      readUid: () async => 'u_1',
      analytics: analytics,
    );

    await service.purchaseGem(_product, payTrackId: 'track_id_original');
    await service.recover(BillingRecoverySource.foreground);
    platform.emit(
      _purchase(
        BillingPurchaseStatus.purchased,
        provider: BillingProvider.appStore,
        storeProductId: 'com.worldo.gems.500',
        purchaseToken: '2000000123456790',
        transactionId: '2000000123456790',
      ),
    );
    await _settle();

    expect(reports, hasLength(1));
    expect(reports.single.requestId, 'track_id_original');
  });

  test(
    'app store recovery does not report while the stream is processing the same purchase',
    () async {
      service.dispose();
      await platform.close();
      platform = _FakeBillingPlatform(
        providerValue: BillingProvider.appStore,
        expectedStoreProductId: 'com.worldo.gems.500',
      );
      reports = <GemPurchaseReportRequest>[];
      final reportStarted = Completer<void>();
      final releaseReport = Completer<GemPurchaseReport>();
      service = GooglePlayBillingService(
        platform: platform,
        pendingPurchaseStore: pendingStore,
        loadBillingAccountId: () async =>
            '4b74ec68-7abc-4cce-a223-e997e31dc811',
        loadProductCatalog: () async => [_product],
        reportPurchase: (request) {
          reports.add(request);
          if (!reportStarted.isCompleted) reportStarted.complete();
          return releaseReport.future;
        },
        refreshWallet: () async => refreshCount += 1,
        readUid: () async => 'u_1',
        analytics: analytics,
      );

      await service.purchaseGem(_product, payTrackId: 'track_id_ios');
      platform.emit(
        _purchase(
          BillingPurchaseStatus.purchased,
          provider: BillingProvider.appStore,
          storeProductId: 'com.worldo.gems.500',
          purchaseToken: '2000000123456791',
          transactionId: '2000000123456791',
        ),
      );
      await reportStarted.future;

      final recovery = service.recover(BillingRecoverySource.foreground);
      await _settle();

      expect(reports, hasLength(1));
      releaseReport.complete(
        const GemPurchaseReport(
          status: GemPurchaseReportStatus.completed,
          grantedGemsCent: 55000,
        ),
      );
      await recovery;
      await _settle();
      expect(reports, hasLength(1));
    },
  );

  test(
    'app store recovery does not report while recovery handles the same purchase',
    () async {
      service.dispose();
      await platform.close();
      platform = _FakeBillingPlatform(
        providerValue: BillingProvider.appStore,
        expectedStoreProductId: 'com.worldo.gems.500',
      );
      reports = <GemPurchaseReportRequest>[];
      final reportStarted = Completer<void>();
      final releaseReport = Completer<GemPurchaseReport>();
      service = GooglePlayBillingService(
        platform: platform,
        pendingPurchaseStore: pendingStore,
        loadBillingAccountId: () async =>
            '4b74ec68-7abc-4cce-a223-e997e31dc811',
        loadProductCatalog: () async => [_product],
        reportPurchase: (request) {
          reports.add(request);
          if (!reportStarted.isCompleted) reportStarted.complete();
          return releaseReport.future;
        },
        refreshWallet: () async => refreshCount += 1,
        readUid: () async => 'u_1',
        analytics: analytics,
      );

      await service.start();
      final now = DateTime.now();
      await pendingStore.upsert(
        BillingPendingPurchase(
          provider: BillingProvider.appStore,
          purchaseToken: '2000000123456792',
          attemptId: 'track_id_recovery',
          billingAccountId: '4b74ec68-7abc-4cce-a223-e997e31dc811',
          productId: _product.productId,
          storeProductId: _product.appleProductId,
          transactionId: '2000000123456792',
          originalJson: '{}',
          purchaseTime: '1000',
          status: BillingPendingPurchaseStatus.received,
          retryCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final recovery = service.recover(BillingRecoverySource.foreground);
      await reportStarted.future;
      platform.emit(
        _purchase(
          BillingPurchaseStatus.purchased,
          provider: BillingProvider.appStore,
          storeProductId: 'com.worldo.gems.500',
          purchaseToken: '2000000123456792',
          transactionId: '2000000123456792',
        ),
      );
      await _settle();
      expect(reports, hasLength(1));

      releaseReport.complete(
        const GemPurchaseReport(
          status: GemPurchaseReportStatus.completed,
          grantedGemsCent: 55000,
        ),
      );
      await recovery;
      await _settle();

      expect(await pendingStore.loadAll(), isEmpty);
    },
  );
}

const _product = GemProduct(
  productId: 'gem_pack_500',
  appleProductId: 'com.worldo.gems.500',
  googleProductId: 'worldo_gems_500',
  baseGemsCent: 50000,
  bonusGemsCent: 5000,
  priceCurrencyCode: 'USD',
  priceAmount: 149,
  canPurchase: true,
  activityType: 'none',
);

BillingPendingPurchase _localPurchase({
  BillingProvider provider = BillingProvider.googlePlay,
  String purchaseToken = 'purchase-token-1',
  String attemptId = 'track_id_local',
  String billingAccountId = '4b74ec68-7abc-4cce-a223-e997e31dc811',
  BillingPendingPurchaseStatus status = BillingPendingPurchaseStatus.received,
  bool reportTimeoutTracked = false,
}) {
  final now = DateTime(2026);
  return BillingPendingPurchase(
    provider: provider,
    purchaseToken: purchaseToken,
    attemptId: attemptId,
    billingAccountId: billingAccountId,
    productId: _product.productId,
    storeProductId: provider == BillingProvider.appStore
        ? _product.appleProductId
        : _product.googleProductId,
    transactionId: provider == BillingProvider.appStore
        ? purchaseToken
        : 'GPA.$purchaseToken',
    originalJson: '{"purchaseToken":"$purchaseToken"}',
    purchaseTime: '1000',
    status: status,
    retryCount: 0,
    reportTimeoutTracked: reportTimeoutTracked,
    createdAt: now,
    updatedAt: now,
  );
}

BillingPurchase _purchase(
  BillingPurchaseStatus status, {
  BillingProvider provider = BillingProvider.googlePlay,
  String storeProductId = 'worldo_gems_500',
  String purchaseToken = 'purchase-token-1',
  String transactionId = 'GPA.1',
  String originalJson = '{"purchaseToken":"purchase-token-1"}',
  String? obfuscatedAccountId = '4b74ec68-7abc-4cce-a223-e997e31dc811',
  String? errorCode,
  String? errorMessage,
}) {
  return BillingPurchase(
    provider: provider,
    productId: storeProductId,
    purchaseToken: purchaseToken,
    transactionId: transactionId,
    originalTransactionId: '',
    originalJson: originalJson,
    purchaseTime: '1000',
    status: status,
    obfuscatedAccountId: obfuscatedAccountId,
    errorCode: errorCode,
    errorMessage: errorMessage,
  );
}

Future<void> _settle() async {
  for (var index = 0; index < 8; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

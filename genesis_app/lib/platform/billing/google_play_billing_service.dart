import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../app/telemetry/firebase_analytics_monitoring.dart';
import '../../network/api_exception.dart';
import '../../network/models/gem_product.dart';
import '../../network/models/gem_purchase_report.dart';
import 'billing_analytics.dart';
import 'billing_contract.dart';
import 'billing_models.dart';
import 'google_play_billing_platform.dart';
import 'pending_purchase_store.dart';

part 'billing_checkout.dart';
part 'billing_recovery.dart';
part 'billing_attempt_registry.dart';
part 'billing_tracking.dart';

class GooglePlayBillingService implements BillingService {
  GooglePlayBillingService({
    required BillingPlatform platform,
    required BillingPendingPurchaseStore pendingPurchaseStore,
    required BillingAccountIdLoader loadBillingAccountId,
    required BillingProductCatalogLoader loadProductCatalog,
    required BillingPurchaseReporter reportPurchase,
    required BillingWalletRefresher refreshWallet,
    required BillingUidReader readUid,
    BillingAnalytics analytics = const GenesisBillingAnalytics(),
    Duration attemptTimeout = const Duration(seconds: 90),
    Future<bool> Function(BillingPurchase)? interceptPurchase,
    bool Function()? otherPurchaseBusy,
    VoidCallback? onPurchaseStreamError,
  }) : _platform = platform,
       _pendingPurchaseStore = pendingPurchaseStore,
       _loadBillingAccountId = loadBillingAccountId,
       _loadProductCatalog = loadProductCatalog,
       _reportPurchase = reportPurchase,
       _refreshWallet = refreshWallet,
       _readUid = readUid,
       _analytics = analytics,
       _attemptTimeout = attemptTimeout,
       _interceptPurchase = interceptPurchase,
       _otherPurchaseBusy = otherPurchaseBusy,
       _onPurchaseStreamError = onPurchaseStreamError;

  final BillingPlatform _platform;
  final BillingPendingPurchaseStore _pendingPurchaseStore;
  final BillingAccountIdLoader _loadBillingAccountId;
  final BillingProductCatalogLoader _loadProductCatalog;
  final BillingPurchaseReporter _reportPurchase;
  final BillingWalletRefresher _refreshWallet;
  final BillingUidReader _readUid;
  final BillingAnalytics _analytics;
  final Duration _attemptTimeout;
  final Future<bool> Function(BillingPurchase)? _interceptPurchase;
  final bool Function()? _otherPurchaseBusy;
  final VoidCallback? _onPurchaseStreamError;
  final ValueNotifier<BillingState> _state = ValueNotifier<BillingState>(
    BillingState(),
  );
  final StreamController<BillingUiEvent> _events =
      StreamController<BillingUiEvent>.broadcast();
  final Map<String, BillingPurchaseAttempt> _attemptByStoreProductId =
      <String, BillingPurchaseAttempt>{};
  final Map<String, BillingPurchaseAttempt> _attemptByPurchaseToken =
      <String, BillingPurchaseAttempt>{};
  final Set<String> _processingPurchaseKeys = <String>{};
  final Set<String> _completedPurchaseKeys = <String>{};
  final Set<String> _trackedPendingAttemptIds = <String>{};
  final Map<String, Timer> _attemptTimeouts = <String, Timer>{};

  StreamSubscription<List<BillingPurchase>>? _purchaseSubscription;
  Future<void>? _startFuture;
  Future<void>? _recoverFuture;
  Future<bool>? _storeRecoveryFuture;
  var _sessionGeneration = 0;
  var _lastRecoveredSessionGeneration = -1;
  String? _cachedBillingAccountId;
  String? _cachedBillingAccountOwnerUid;
  bool _disposed = false;

  @override
  ValueListenable<BillingState> get state => _state;

  @override
  Stream<BillingUiEvent> get events => _events.stream;

  void _emitUiEvent(BillingUiEvent event) {
    if (_disposed || _events.isClosed) return;
    _events.add(event);
  }

  @override
  Future<void> start() {
    final inFlight = _startFuture;
    if (inFlight != null) return inFlight;
    final future = _start();
    _startFuture = future;
    return future;
  }

  @override
  Future<void> purchaseGem(
    GemProduct product, {
    BillingPurchaseSource source = BillingPurchaseSource.buyGemsPage,
    String payTrackId = '',
  }) async {
    final startedAt = DateTime.now();
    final attemptId = payTrackId.trim().isNotEmpty
        ? payTrackId.trim()
        : newBillingAttemptId();
    var activeProduct = product;
    var storeProductId = _storeProductIdFor(product, _platform.provider);
    _trackProduct(
      'product_click',
      product: product,
      attemptId: attemptId,
      data: <String, Object?>{'source': source.value},
    );
    if (_disposed) return;
    if (_state.value.hasBusyPurchase || (_otherPurchaseBusy?.call() ?? false)) {
      _trackPrecheckFailure(product, attemptId, 'purchase_in_progress');
      return;
    }
    if (!product.canPurchase || storeProductId.trim().isEmpty) {
      _trackPrecheckFailure(
        product,
        attemptId,
        !product.canPurchase
            ? 'product_not_purchasable'
            : 'store_product_id_missing',
      );
      _emitFailure(
        product.productId,
        attemptId,
        'This product is unavailable.',
      );
      return;
    }
    if (billingProductKindFrom(product.billingType) !=
        BillingProductKind.consumable) {
      _trackPrecheckFailure(product, attemptId, 'unsupported_product_type');
      _emitFailure(
        product.productId,
        attemptId,
        'This product type is not supported.',
      );
      return;
    }

    final session = _sessionGeneration;
    final expired = Completer<void>();
    var timedOut = false;
    var launchRequested = false;
    var storeHandedOff = false;
    // Keep preflight separate from receipt timers: an older store callback
    // must not cancel this deadline while account lookup is still pending.
    final preflightTimerKey = 'checkout:$attemptId';
    bool isCurrent() =>
        !timedOut && !_disposed && session == _sessionGeneration;
    void onTimeout() {
      if (!isCurrent() || storeHandedOff) return;
      timedOut = true;
      _cancelAttemptTimeout(preflightTimerKey);
      _cancelAttemptTimeout(storeProductId);
      _trackTimeoutById(
        attemptId: attemptId,
        productId: activeProduct.productId,
        storeProductId: storeProductId,
        timeoutType: 'store_no_callback',
      );
      if (!launchRequested) {
        final attempt = _attemptByStoreProductId[storeProductId];
        if (attempt?.id == attemptId) {
          _clearActiveAttempt(storeProductId, attempt!);
        }
      }
      _setBusy(activeProduct.productId, false);
      if (launchRequested) {
        _emitDeferred(activeProduct.productId, attemptId);
      } else {
        _emitUiEvent(
          BillingUiEvent(
            kind: BillingUiEventKind.deferred,
            productId: activeProduct.productId,
            attemptId: attemptId,
            message: 'Purchase timed out. Please try again.',
          ),
        );
      }
      expired.complete();
    }

    bool canContinue() {
      if (!isCurrent()) return false;
      if (!storeHandedOff &&
          DateTime.now().difference(startedAt) >= _attemptTimeout) {
        onTimeout();
        return false;
      }
      return true;
    }

    bool onStoreHandoff() {
      if (_attemptByStoreProductId[storeProductId]?.id != attemptId ||
          !canContinue()) {
        return false;
      }
      storeHandedOff = true;
      _cancelAttemptTimeout(preflightTimerKey);
      _cancelAttemptTimeout(storeProductId);
      return true;
    }

    void scheduleTimeout(String key) => _scheduleAttemptTimeout(
      key,
      startedAt: startedAt,
      onTimeout: onTimeout,
    );

    _setBusy(product.productId, true);
    scheduleTimeout(preflightTimerKey);
    Future<void> runCheckout() async {
      try {
        await start();
        if (!canContinue()) return;
        if (!_state.value.storeAvailable) {
          final available = await _refreshStoreAvailability();
          if (!canContinue()) return;
          if (!available) {
            _trackPrecheckFailure(product, attemptId, 'gp_unavailable');
            _emitFailure(
              product.productId,
              attemptId,
              _storeUnavailableMessage(),
            );
            return;
          }
        }

        late final String billingAccountId;
        try {
          billingAccountId = await _resolveBillingAccountId();
        } catch (_) {
          if (!canContinue()) return;
          _trackPrecheckFailure(product, attemptId, 'uuid_unavailable');
          _emitFailure(product.productId, attemptId, 'Purchase failed.');
          return;
        }
        if (!canContinue()) return;
        if (billingAccountId.isEmpty) {
          _trackPrecheckFailure(product, attemptId, 'uuid_unavailable');
          _emitFailure(product.productId, attemptId, 'Purchase failed.');
          return;
        }
        var attempt = BillingPurchaseAttempt(
          id: attemptId,
          product: activeProduct,
          billingAccountId: billingAccountId,
          source: BillingRecoverySource.direct,
          startedAt: startedAt,
        );
        _attemptByStoreProductId[storeProductId] = attempt;
        _cancelAttemptTimeout(preflightTimerKey);
        scheduleTimeout(storeProductId);

        late BillingProductQueryResult queryResult;
        try {
          queryResult = await _queryStoreProduct(activeProduct, storeProductId);
          if (!canContinue()) return;
          if (!queryResult.isSuccess &&
              queryResult.errorCode?.trim() == 'product_not_found') {
            final refreshedProduct = await _reloadProduct(product.productId);
            if (!canContinue()) return;
            if (refreshedProduct != null &&
                refreshedProduct.canPurchase &&
                billingProductKindFrom(refreshedProduct.billingType) ==
                    BillingProductKind.consumable) {
              final refreshedStoreProductId = _storeProductIdFor(
                refreshedProduct,
                _platform.provider,
              );
              if (refreshedStoreProductId.isNotEmpty) {
                if (refreshedStoreProductId != storeProductId) {
                  _clearActiveAttempt(storeProductId, attempt);
                  activeProduct = refreshedProduct;
                  storeProductId = refreshedStoreProductId;
                  attempt = BillingPurchaseAttempt(
                    id: attemptId,
                    product: activeProduct,
                    billingAccountId: billingAccountId,
                    source: BillingRecoverySource.direct,
                    startedAt: startedAt,
                  );
                  _attemptByStoreProductId[storeProductId] = attempt;
                  _setBusy(activeProduct.productId, true);
                  scheduleTimeout(storeProductId);
                }
                queryResult = await _queryStoreProduct(
                  activeProduct,
                  storeProductId,
                );
                if (!canContinue()) return;
              }
            }
          }
        } catch (error) {
          if (!canContinue()) return;
          _clearActiveAttempt(storeProductId, attempt);
          _emitFailure(
            activeProduct.productId,
            attemptId,
            _purchaseFailureMessage(error),
          );
          _trackFlowResult(
            activeProduct,
            attemptId,
            'query_failed',
            errorCode: _queryFailureErrorCode(error),
          );
          return;
        }
        if (!queryResult.isSuccess) {
          final errorCode = queryResult.errorCode?.trim().isNotEmpty == true
              ? queryResult.errorCode!.trim()
              : 'unknown';
          _clearActiveAttempt(storeProductId, attempt);
          _emitFailure(
            activeProduct.productId,
            attemptId,
            _productQueryFailureMessage(queryResult.errorCode),
          );
          _trackFlowResult(
            activeProduct,
            attemptId,
            'query_failed',
            errorCode: errorCode,
          );
          return;
        }

        try {
          launchRequested = true;
          final accepted = await _platform.buyConsumable(
            product: queryResult.product!,
            billingAccountId: billingAccountId,
            onStoreHandoff: onStoreHandoff,
          );
          if (_attemptByStoreProductId[storeProductId]?.id != attemptId ||
              !canContinue()) {
            return;
          }
          if (!accepted) {
            _clearActiveAttempt(storeProductId, attempt);
            _emitFailure(
              activeProduct.productId,
              attemptId,
              'Purchase failed.',
            );
            _trackFlowResult(activeProduct, attemptId, 'launch_rejected');
          }
        } catch (error) {
          if (_attemptByStoreProductId[storeProductId]?.id != attemptId ||
              !canContinue()) {
            return;
          }
          debugPrint('[Billing] purchase launch failed: $error');
          _clearActiveAttempt(storeProductId, attempt);
          _emitFailure(
            activeProduct.productId,
            attemptId,
            _purchaseFailureMessage(error),
          );
          _trackFlowResult(
            activeProduct,
            attemptId,
            'launch_failed',
            errorCode: _purchaseLaunchErrorCode(error),
          );
        }
      } catch (_) {
        if (!canContinue()) return;
        _setBusy(activeProduct.productId, false);
        rethrow;
      } finally {
        _cancelAttemptTimeout(preflightTimerKey);
      }
    }

    // Let callers dismiss loading even if an SDK/account Future never resolves.
    await Future.any<void>([runCheckout(), expired.future]);
  }

  @override
  Future<void> recover(BillingRecoverySource source) async {
    await start();
    if (_disposed) return;
    final requestedGeneration = _sessionGeneration;
    while (true) {
      final inFlight = _recoverFuture;
      if (inFlight != null) {
        await inFlight;
        if (_lastRecoveredSessionGeneration >= requestedGeneration) return;
        continue;
      }

      final runGeneration = _sessionGeneration;
      late final Future<void> tracked;
      tracked = _recoverInternal(source, sessionGeneration: runGeneration)
          .whenComplete(() {
            if (_lastRecoveredSessionGeneration < runGeneration) {
              _lastRecoveredSessionGeneration = runGeneration;
            }
            if (identical(_recoverFuture, tracked)) {
              _recoverFuture = null;
            }
          });
      _recoverFuture = tracked;
      await tracked;
      return;
    }
  }

  @override
  Future<bool> recoverStorePurchases({List<GemProduct>? productCatalog}) {
    final inFlight = _storeRecoveryFuture;
    if (inFlight != null) return inFlight;
    late final Future<bool> tracked;
    tracked = _recoverStorePurchases(productCatalog: productCatalog)
        .whenComplete(() {
          if (identical(_storeRecoveryFuture, tracked)) {
            _storeRecoveryFuture = null;
          }
        });
    _storeRecoveryFuture = tracked;
    return tracked;
  }

  @override
  void resetForSession() {
    _sessionGeneration += 1;
    _cachedBillingAccountId = null;
    _cachedBillingAccountOwnerUid = null;
    _attemptByStoreProductId.clear();
    _attemptByPurchaseToken.clear();
    _completedPurchaseKeys.clear();
    _trackedPendingAttemptIds.clear();
    for (final timeout in _attemptTimeouts.values) {
      timeout.cancel();
    }
    _attemptTimeouts.clear();
    _setState(busyProductIds: const <String>{});
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _purchaseSubscription?.cancel();
    for (final timeout in _attemptTimeouts.values) {
      timeout.cancel();
    }
    _attemptTimeouts.clear();
    _events.close();
    _state.dispose();
  }
}

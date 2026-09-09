import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../network/models/membership_product.dart';
import '../../network/models/membership_purchase.dart';
import '../../network/models/membership_claim.dart';
import '../../platform/billing/billing_models.dart';
import '../../platform/billing/membership_checkout_platform.dart';
import '../../platform/billing/membership_pending_store.dart';
import '../../platform/billing/membership_restore_record.dart';
import '../../platform/billing/membership_guest_claim_record.dart';
import 'membership_purchase_eligibility.dart';

part 'membership_purchase_restore.dart';
part 'membership_guest_claim.dart';
part 'membership_receipt_reconciliation.dart';

enum MembershipCheckoutState {
  idle,
  preparing,
  store,
  pending,
  reporting,
  completed,
  accepted,
  rejected,
  canceled,
  failed,
  deferred,
}

class MembershipCheckoutEvent {
  const MembershipCheckoutEvent({
    required this.attemptId,
    required this.state,
    this.reason,
  });
  final String attemptId;
  final MembershipCheckoutState state;
  final String? reason;
}

/// Owns subscription attempts and receipts independently of the Gems queue/UI.
class MembershipPurchaseService with WidgetsBindingObserver {
  MembershipPurchaseService({
    required this.platform,
    required this.store,
    required this.readLoginUid,
    required this.loadAccountUuid,
    required this.prepareGuest,
    required this.reportPurchase,
    required this.queryPurchases,
    required this.provider,
    required this.loadProducts,
    this.otherPurchaseBusy,
    this.refreshWallet,
    this.restorePurchase,
    this.claimGuest,
    this.queryRestorePurchases,
    this.retryDelay = const Duration(seconds: 15),
    this.attemptTimeout = const Duration(seconds: 90),
  });

  final MembershipCheckoutPlatform platform;
  final MembershipPendingStore store;
  final Future<String?> Function() readLoginUid;
  final Future<String> Function() loadAccountUuid;
  final Future<MembershipGuestIdentity> Function() prepareGuest;
  final Future<MembershipPurchaseReport> Function(MembershipPurchaseRequest)
  reportPurchase;
  final Future<List<BillingPurchase>> Function() queryPurchases;
  final MembershipProvider provider;
  final Future<List<MembershipProduct>> Function() loadProducts;
  final ValueNotifier<int> catalogRevision = ValueNotifier(0);
  final bool Function()? otherPurchaseBusy;
  final Future<void> Function()? refreshWallet;
  final Future<MembershipPurchaseReport> Function(MembershipPurchaseRequest)?
  restorePurchase;
  final Future<MembershipClaimResult> Function(MembershipGuestIdentity)?
  claimGuest;
  final ValueNotifier<String?> guestLoginRequestId = ValueNotifier(null);
  final Set<String> _presentedAttempts = {};
  final Map<String, MembershipGuestClaimRecord> _guestClaims = {};
  final Set<String> _pendingGuestClaimWrites = {};
  final Map<String, _MembershipClaimRetry> _claimRetries = {};
  final Map<String, int> _claimWalletRefreshSessions = {};
  final Set<String> _claimReportsRequeued = {};
  final Future<List<BillingPurchase>> Function(Set<String>)?
  queryRestorePurchases;
  final Duration retryDelay;
  final Duration attemptTimeout;
  final _checkoutEvents = StreamController<MembershipCheckoutEvent>.broadcast();
  Stream<MembershipCheckoutEvent> get checkoutEvents => _checkoutEvents.stream;
  final Map<String, _MembershipCheckoutWait> _checkoutWaits = {};
  final ValueNotifier<MembershipCheckoutState> state = ValueNotifier(
    MembershipCheckoutState.idle,
  );
  final Map<String, MembershipPurchaseRecord> _records = {};
  final Set<String> _pendingRequestIds = {};
  final Map<String, MembershipRestoreRecord> _restoreRecords = {};
  final Set<String> _pendingRestoreIds = {};
  List<MembershipProduct> _restoreProducts = [];
  Future<void>? _restoring;
  int _lastRestoreSession = -1;
  bool _restoreEnabled = false;
  bool _retryStoreRestore = false;
  Future<void>? _loading;
  Future<void>? _recovery;
  bool _recoverAgain = false;
  Future<void> _events = Future.value();
  Timer? _retry;
  String? _activeRequestId;
  bool _busy = false;
  bool _disposed = false;
  bool _observing = false;
  int _session = 0;
  int _retryCount = 0;

  bool get isBusy => _busy;

  void attachCheckoutPresentation(String requestId) {
    _presentedAttempts.add(requestId);
  }

  Future<void> detachCheckoutPresentation(String requestId) async {
    _presentedAttempts.remove(requestId);
    await _refreshGuestLoginRequest();
  }

  bool hasAcknowledgedGuestPurchase(String requestId) =>
      _guestClaims[_records[requestId]?.guest?.guestId]?.loginRequired ?? false;

  Future<void> confirmGuestPurchase(String requestId) async {
    await _serialize(() async {
      final purchase = _records[requestId];
      final claim = _guestClaims[purchase?.guest?.guestId];
      if (_disposed || claim == null || purchase?.reportStatus != 'completed') {
        return;
      }
      try {
        await _saveGuestClaim(claim.copyWith(loginRequired: true));
      } catch (error) {
        _scheduleRetry();
        _log('guest login persistence deferred', error);
      }
    });
  }

  Future<void> start() async {
    if (_disposed) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    await recover();
  }

  Future<void> _load() async {
    if (_loading != null) return _loading!;
    final task = () async {
      // The login gate depends only on the guest cache, not receipt recovery.
      for (final record in await store.loadGuestClaims()) {
        _guestClaims[record.guest.guestId] = record;
      }
      await _refreshGuestLoginRequest();
      for (final record in await store.loadConfirmedReceipts()) {
        _records[record.requestId] = record;
      }
      for (final record in await store.loadAll()) {
        _records[record.requestId] = record;
        _pendingRequestIds.add(record.requestId);
      }
      for (final record in await store.loadRestores()) {
        _restoreRecords[record.requestId] = record;
        _pendingRestoreIds.add(record.requestId);
      }
    }();
    _loading = task;
    try {
      await task;
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Future<void> _save(MembershipPurchaseRecord record) async {
    // Keep the in-memory receipt if the disk write fails; do not report/finish it.
    _records[record.requestId] = record;
    _pendingRequestIds.add(record.requestId);
    await store.save(record);
  }

  Future<void> purchase(MembershipProduct product, {String? attemptId}) async {
    final startedAt = DateTime.now();
    attemptId ??= newBillingAttemptId();
    if (_disposed) return;
    if (_busy || (otherPurchaseBusy?.call() ?? false)) {
      _emitCheckout(MembershipCheckoutState.failed, attemptId);
      return;
    }
    final id = attemptId;
    _busy = true;
    _activeRequestId = id;
    final session = _session;
    final wait = _MembershipCheckoutWait();
    _checkoutWaits[id] = wait;
    bool isCurrent() =>
        !_disposed &&
        session == _session &&
        _activeRequestId == id &&
        identical(_checkoutWaits[id], wait) &&
        !wait.storeCallbackReceived;
    void onTimeout() {
      if (!isCurrent() || wait.storeHandedOff) return;
      _release(id);
      _setState(MembershipCheckoutState.deferred, attemptId: id);
      if (wait.launchRequested) _scheduleRetry();
    }

    bool canContinue() {
      if (!isCurrent()) return false;
      if (!wait.storeHandedOff &&
          DateTime.now().difference(startedAt) >= attemptTimeout) {
        onTimeout();
        return false;
      }
      return true;
    }

    bool onStoreHandoff() {
      if (!canContinue()) return false;
      wait.storeHandedOff = true;
      wait.timer?.cancel();
      wait.timer = null;
      return true;
    }

    Future<bool> canContinueForOwner(String? uid) async {
      if (!canContinue()) return false;
      final currentUid = await readLoginUid();
      if (!canContinue()) return false;
      if (currentUid == uid) return true;
      _release(id);
      _setState(MembershipCheckoutState.idle, attemptId: id);
      return false;
    }

    final elapsed = DateTime.now().difference(startedAt);
    wait.timer = Timer(
      elapsed < attemptTimeout ? attemptTimeout - elapsed : Duration.zero,
      onTimeout,
    );
    _setState(MembershipCheckoutState.preparing, attemptId: id);
    Future<void> runCheckout() async {
      try {
        if (product.provider != provider) {
          throw StateError('membership_provider_mismatch');
        }
        await _load();
        if (!canContinue()) return;
        final uid = await readLoginUid();
        if (!canContinue()) return;
        await _reconcileMissingReceipts(uid, canContinue: canContinue);
        if (!await canContinueForOwner(uid)) return;
        if (_hasUnsettledPurchase(uid)) {
          _scheduleRetry();
          throw const MembershipPurchaseBlocked('purchase_processing');
        }
        final List<MembershipProduct> products;
        try {
          products = await loadProducts();
        } catch (_) {
          throw const MembershipPurchaseBlocked('eligibility_unavailable');
        }
        if (!await canContinueForOwner(uid)) return;
        final matches = products.where(
          (p) => p.provider == provider && p.planCode == product.planCode,
        );
        if (matches.length != 1) {
          throw const MembershipPurchaseBlocked('eligibility_unavailable');
        }
        final current = matches.single;
        if (current.storeProductId != product.storeProductId ||
            current.basePlanId != product.basePlanId ||
            current.offerId != product.offerId) {
          throw const MembershipPurchaseBlocked('eligibility_unavailable');
        }
        final reason = membershipPurchaseBlockReason(current);
        if (reason != null) throw MembershipPurchaseBlocked(reason);
        // A receipt may arrive while the eligibility request is in flight.
        if (_hasUnsettledPurchase(uid)) {
          throw const MembershipPurchaseBlocked('purchase_processing');
        }
        product = current;
        final nativeProduct = await platform.prepare(product);
        if (!await canContinueForOwner(uid)) return;
        if (_hasUnsettledPurchase(uid)) {
          throw const MembershipPurchaseBlocked('purchase_processing');
        }
        final guest = uid == null ? await prepareGuest() : null;
        if (!canContinue()) return;
        final uuid = guest?.accountUuid ?? await loadAccountUuid();
        if (!canContinue()) return;
        if (!isMembershipAccountUuid(uuid)) {
          throw StateError('membership_account_uuid_missing');
        }
        final record = MembershipPurchaseRecord(
          requestId: id,
          product: product,
          accountUuid: uuid,
          ownerUid: uid,
          guest: guest,
        );
        // Guest secrets and the exact selected base plan survive process death.
        await _save(record);
        if (!await canContinueForOwner(uid)) return;
        _setState(MembershipCheckoutState.store, attemptId: id);
        wait.launchRequested = true;
        final launched = await platform.launch(
          nativeProduct,
          uuid,
          onStoreHandoff: onStoreHandoff,
        );
        if (!canContinue()) return;
        if (!launched) throw StateError('membership_launch_rejected');
      } catch (error) {
        // Expired operations and completed callbacks cannot overwrite a newer UI.
        if (!canContinue()) return;
        final record = _records[attemptId];
        if (record != null && record.state == 'prepared') {
          try {
            await _save(record.copyWith(state: 'error'));
          } catch (_) {}
        }
        if (!canContinue()) return;
        _release(attemptId);
        _setState(
          MembershipCheckoutState.failed,
          attemptId: id,
          reason: error is MembershipPurchaseBlocked ? error.reason : null,
        );
        _log('launch failed', error);
      } finally {
        // A delayed pre-launch write must not leave a recoverable prepared order.
        final record = _records[id];
        if (!wait.launchRequested &&
            record != null &&
            record.state == 'prepared' &&
            !record.hasReceipt) {
          try {
            await _save(record.copyWith(state: 'canceled'));
          } catch (error) {
            _log('unlaunched checkout cleanup deferred', error);
          }
        }
      }
    }

    // Release the caller even if the platform or identity request never returns.
    await Future.any<void>([runCheckout(), wait.done.future]);
  }

  bool _hasUnsettledPurchase(String? uid) {
    bool unresolved(String? status) =>
        status != 'completed' && status != 'rejected';
    for (final record in _records.values) {
      final guest = record.guest;
      final belongsToCaller = guest == null
          ? record.ownerUid == uid
          : uid == null ||
                _guestClaims[guest.guestId]?.ownerUid == null ||
                _guestClaims[guest.guestId]?.ownerUid == uid;
      if (belongsToCaller &&
          unresolved(record.reportStatus) &&
          (record.paid || record.state == 'pending')) {
        return true;
      }
    }
    return uid != null &&
        _restoreRecords.values.any(
          (record) =>
              record.ownerUid == uid &&
              _pendingRestoreIds.contains(record.requestId) &&
              unresolved(record.reportStatus),
        );
  }

  void _catalogChanged() {
    if (!_disposed) catalogRevision.value++;
  }

  /// Returns true when a callback belongs to subscriptions, before Gems sees it.
  Future<bool> interceptPurchase(BillingPurchase purchase) async {
    return _serialize(() async {
      try {
        await _load();
        if (purchase.productId.isEmpty) {
          final active = _records[_activeRequestId];
          if (active == null) return false;
          await _handle(purchase, productId: active.product.storeProductId);
          return true;
        }
        final known = _records.values.any(
          (r) => r.product.storeProductId == purchase.productId,
        );
        if (!known && !await platform.isSubscription(purchase.productId)) {
          return false;
        }
        await _handle(purchase);
      } catch (error) {
        _setState(MembershipCheckoutState.deferred);
        _scheduleRetry();
        _log('callback deferred', error);
      }
      return true;
    });
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final previous = _events;
    final task = () async {
      await previous;
      return action();
    }();
    _events = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  Future<void> _handle(BillingPurchase purchase, {String? productId}) async {
    productId ??= purchase.productId;
    if (_disposed || purchase.provider.apiValue != provider.name) return;
    MembershipPurchaseRecord? record;
    final candidates = _records.values
        .where((r) => r.product.storeProductId == productId)
        .toList();
    MembershipPurchaseRecord? tokenMatch;
    for (final candidate in candidates.reversed) {
      if (provider == MembershipProvider.google) {
        if (purchase.purchaseToken.isEmpty ||
            candidate.purchaseToken != purchase.purchaseToken) {
          continue;
        }
        tokenMatch ??= candidate;
      }
      if (purchase.transactionId.isNotEmpty &&
          candidate.transactionId == purchase.transactionId) {
        record = candidate;
        break;
      }
    }
    // Prefer the exact renewal transaction so a late older callback stays deduplicated.
    record ??= tokenMatch;
    final accountUuid = purchase.obfuscatedAccountId?.trim() ?? '';
    bool sameAccount(MembershipPurchaseRecord r) =>
        accountUuid.isEmpty ||
        accountUuid.toLowerCase() == r.accountUuid.toLowerCase();
    if (record == null) {
      final active = _records[_activeRequestId];
      if (active != null &&
          active.product.storeProductId == productId &&
          sameAccount(active)) {
        record = active;
      }
    }
    if (record == null) {
      final pending = candidates
          .where(
            (r) =>
                (r.state == 'prepared' ||
                    r.state == 'pending' ||
                    r.needsReceiptRecovery) &&
                sameAccount(r),
          )
          .toList();
      if (pending.length == 1) record = pending.single;
    }
    if (record == null) {
      await _restoreReceipt(purchase);
      return;
    }
    if (!sameAccount(record)) return;
    // Only this order's callback ends its store deadline. Reporting has its own
    // HTTP timeout; keep the wait registered so session/stream resets close UI.
    final wait = _checkoutWaits[record.requestId];
    if (wait != null && wait.launchRequested) wait.receiveStoreCallback();
    try {
      await _handleCheckoutRecord(record, purchase);
    } catch (error) {
      _release(record.requestId);
      _setState(MembershipCheckoutState.deferred, attemptId: record.requestId);
      _scheduleRetry();
      _log('callback deferred', error);
    }
  }

  Future<void> _handleCheckoutRecord(
    MembershipPurchaseRecord record,
    BillingPurchase purchase,
  ) async {
    if (!_pendingRequestIds.contains(record.requestId) &&
        record.paid &&
        (purchase.transactionId.isEmpty ||
            purchase.transactionId == record.transactionId)) {
      return;
    }
    if (purchase.status == BillingPurchaseStatus.canceled ||
        purchase.status == BillingPurchaseStatus.error) {
      if (!record.paid) {
        await _save(record.copyWith(state: purchase.status.name));
      }
      _release(record.requestId);
      _setState(
        purchase.status == BillingPurchaseStatus.canceled
            ? MembershipCheckoutState.canceled
            : MembershipCheckoutState.failed,
        attemptId: record.requestId,
      );
      return;
    }
    // A new Google renewal can reuse its token; retain a separate operation key.
    if (record.paid &&
        record.transactionId.isNotEmpty &&
        purchase.transactionId.isNotEmpty &&
        record.transactionId != purchase.transactionId) {
      record = record.copyWith(
        requestId: newBillingAttemptId(),
        newReport: true,
      );
    }
    record = record.copyWith(
      transactionId: purchase.transactionId.isEmpty
          ? null
          : purchase.transactionId,
      originalTransactionId: purchase.originalTransactionId.isEmpty
          ? null
          : purchase.originalTransactionId,
      purchaseToken: purchase.purchaseToken.isEmpty
          ? null
          : purchase.purchaseToken,
      state: record.paid && purchase.status == BillingPurchaseStatus.pending
          ? null
          : purchase.status.name,
    );
    await _save(record);
    _release(record.requestId);
    if (record.needsReceiptRecovery) {
      _setState(MembershipCheckoutState.deferred, attemptId: record.requestId);
      _scheduleRetry();
      return;
    }
    await _prepareGuestClaim(record);
    if (purchase.status == BillingPurchaseStatus.pending) {
      _setState(MembershipCheckoutState.pending, attemptId: record.requestId);
    }
    await _report(record);
    await _claimPendingGuests();
  }

  Future<void> _report(MembershipPurchaseRecord record) async {
    if (_disposed ||
        !_pendingRequestIds.contains(record.requestId) ||
        !record.hasReceipt ||
        (!record.paid && record.state != 'pending')) {
      return;
    }
    if (record.guest == null && await readLoginUid() != record.ownerUid) return;
    final session = _session;
    final previousResult = (record.reportStatus, record.reportReason);
    try {
      // Retry a failed persistence operation before sending any receipt.
      await _save(record);
      if (record.reportStatus == null || record.reportStatus == 'accepted') {
        if (_disposed ||
            session != _session ||
            record.guest == null && await readLoginUid() != record.ownerUid) {
          return;
        }
        _setState(
          MembershipCheckoutState.reporting,
          attemptId: record.requestId,
        );
        final report = await reportPurchase(record.request);
        record = record.copyWith(
          reportStatus: report.status.name,
          reportId: report.reportId,
          reportReason: report.reason,
          state:
              report.status == MembershipReportStatus.completed && !record.paid
              ? 'purchased'
              : null,
          finished: report.reason == 'account_mismatch' ? true : null,
        );
        await _save(record);
      }
      // Pending payments can become verified through report retry alone.
      // Preserve guest claim/login state before clearing that pending receipt.
      await _prepareGuestClaim(record);
      if (record.reportStatus == 'completed' &&
          record.guest == null &&
          await readLoginUid() == record.ownerUid) {
        try {
          await refreshWallet?.call();
        } catch (_) {}
      }
      // All three statuses acknowledge durable server takeover. Never finish pending payments.
      if (provider == MembershipProvider.apple &&
          record.paid &&
          !record.finished) {
        await platform.finishAppleTransaction(record.transactionId);
        record = record.copyWith(finished: true);
        await _save(record);
      }
      if ((record.paid || record.reportStatus == 'rejected') &&
          (record.reportStatus == 'completed' ||
              record.reportStatus == 'rejected')) {
        await store.complete(record);
        _pendingRequestIds.remove(record.requestId);
      } else if (record.reportStatus == 'accepted') {
        _scheduleRetry();
      }
      _setState(
        switch (record.reportStatus) {
          'completed' => MembershipCheckoutState.completed,
          'accepted' => MembershipCheckoutState.accepted,
          'rejected' => MembershipCheckoutState.rejected,
          _ => MembershipCheckoutState.deferred,
        },
        attemptId: record.requestId,
        reason: record.reportReason,
      );
      _release(record.requestId);
      if (record.reportStatus != 'accepted') _retryCount = 0;
    } catch (error) {
      _setState(MembershipCheckoutState.deferred, attemptId: record.requestId);
      _scheduleRetry();
      _log('report deferred', error);
    } finally {
      if (session == _session &&
          record.reportStatus != null &&
          previousResult != (record.reportStatus, record.reportReason)) {
        _catalogChanged();
      }
    }
  }

  Future<void> recover() {
    final existing = _recovery;
    if (existing != null) return existing;
    final session = _session;
    late final Future<void> task;
    task =
        () async {
          try {
            await _load();
            if (_disposed) return;
            // A cached purchase must require login before network retries.
            await _refreshGuestLoginRequest();
            await _serialize(() async {
              await _flushGuestClaims();
              for (final record in _records.values.toList()) {
                await _prepareGuestClaim(record);
              }
              await _refreshGuestLoginRequest();
              for (final record in _records.values.toList()) {
                if (record.product.provider == provider &&
                    _pendingRequestIds.contains(record.requestId)) {
                  await _report(record);
                }
              }
              for (final record in _restoreRecords.values.toList()) {
                if (_pendingRestoreIds.contains(record.requestId)) {
                  await _processRestore(record);
                }
              }
              await _claimPendingGuests();
            });
            await _reconcileMissingReceipts(await readLoginUid());
            // No product-list request or store recovery without a known VIP attempt.
            if (_records.values.any(
              (r) =>
                  r.product.provider == provider &&
                  (r.state == 'prepared' || r.state == 'pending'),
            )) {
              for (final purchase in await queryPurchases()) {
                if (_records.values.any(
                  (r) => r.product.storeProductId == purchase.productId,
                )) {
                  await interceptPurchase(purchase);
                }
              }
            }
          } catch (error) {
            _scheduleRetry();
            _log('recovery deferred', error);
          }
        }().whenComplete(() {
          if (identical(_recovery, task)) _recovery = null;
          if (!_disposed && (_recoverAgain || session != _session)) {
            _recoverAgain = false;
            unawaited(recover());
          }
        });
    _recovery = task;
    return task;
  }

  void _scheduleRetry() {
    if (_disposed || _retry != null) return;
    final delay = Duration(
      milliseconds: math.min(
        300000,
        retryDelay.inMilliseconds * (1 << math.min(_retryCount++, 5)),
      ),
    );
    _retry = Timer(delay, () {
      _retry = null;
      unawaited(_retryStoreRestore ? restorePurchases() : recover());
    });
  }

  void _release(String? requestId) {
    if (_activeRequestId == requestId || _activeRequestId == null) {
      _activeRequestId = null;
      _busy = false;
    }
  }

  void _setState(
    MembershipCheckoutState value, {
    String? attemptId,
    String? reason,
  }) {
    if (_disposed) return;
    state.value = value;
    if (attemptId != null) _emitCheckout(value, attemptId, reason: reason);
  }

  void _emitCheckout(
    MembershipCheckoutState value,
    String attemptId, {
    String? reason,
  }) {
    if (_disposed) return;
    if (value != MembershipCheckoutState.preparing &&
        value != MembershipCheckoutState.store &&
        value != MembershipCheckoutState.reporting) {
      _checkoutWaits.remove(attemptId)?.finish();
    }
    _checkoutEvents.add(
      MembershipCheckoutEvent(
        attemptId: attemptId,
        state: value,
        reason: reason,
      ),
    );
  }

  void _endCheckoutWaits(MembershipCheckoutState value) {
    for (final id in _checkoutWaits.keys.toList()) {
      _emitCheckout(value, id);
    }
  }

  void _log(String operation, Object error) =>
      debugPrint('[Membership] $operation: ${error.runtimeType}');

  void resetForSession() {
    _endCheckoutWaits(MembershipCheckoutState.idle);
    _session++;
    _resetGuestClaimRetries();
    _activeRequestId = null;
    _busy = false;
    _setState(MembershipCheckoutState.idle);
    // An in-flight HTTP retry must not delay the forced-login gate on expiry.
    unawaited(_refreshGuestLoginRequest());
    unawaited(recover());
    if (_restoreEnabled) unawaited(restorePurchases());
  }

  void handleStreamError() {
    _endCheckoutWaits(MembershipCheckoutState.deferred);
    _activeRequestId = null;
    _busy = false;
    _setState(MembershipCheckoutState.deferred);
    _scheduleRetry();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(recover());
      if (_restoreEnabled) unawaited(restorePurchases());
    }
  }

  /// Called when Subscription data is loaded; never loads the Gems catalog.
  Future<void> restorePurchases({List<MembershipProduct>? products}) =>
      _restoreStorePurchases(products: products);

  void dispose() {
    if (_disposed) return;
    _endCheckoutWaits(MembershipCheckoutState.idle);
    _disposed = true;
    unawaited(_checkoutEvents.close());
    _session++;
    _retry?.cancel();
    _resetGuestClaimRetries();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    state.dispose();
    guestLoginRequestId.dispose();
    catalogRevision.dispose();
  }
}

class _MembershipCheckoutWait {
  Timer? timer;
  final done = Completer<void>();
  bool launchRequested = false;
  bool storeHandedOff = false;
  bool storeCallbackReceived = false;

  void receiveStoreCallback() {
    storeCallbackReceived = true;
    finish();
  }

  void finish() {
    timer?.cancel();
    timer = null;
    if (!done.isCompleted) done.complete();
  }
}

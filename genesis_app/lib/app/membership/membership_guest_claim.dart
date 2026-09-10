part of 'membership_purchase_service.dart';

class _MembershipClaimRetry {
  int attempts = 0;
  Timer? timer;

  // One initial request and at most five additional attempts in this session.
  bool get canAttempt => timer == null && attempts < 6;
}

extension _MembershipGuestClaim on MembershipPurchaseService {
  Future<MembershipPurchaseRequest> _guestPurchaseRequest(
    MembershipPurchaseRecord purchase,
  ) async {
    final request = purchase.request;
    if (request.guest == null || provider != MembershipProvider.apple) {
      return request;
    }
    final key = '${purchase.accountUuid}:${purchase.transactionId}';
    var signed = _signedTransactions[key];
    if (signed == null || signed.isEmpty) {
      signed = await loadSignedTransaction?.call(request);
      if (signed == null || signed.isEmpty) {
        throw const BillingPlatformException(
          'membership_signed_transaction_missing',
        );
      }
      if (!_disposed) _signedTransactions[key] = signed;
    }
    return request.withSignedTransaction(signed);
  }

  MembershipPurchaseRecord? _claimPurchase(MembershipGuestClaimRecord claim) {
    bool matches(MembershipPurchaseRecord p) =>
        p.product.provider == provider &&
        p.guest?.accountUuid == claim.guest.accountUuid &&
        p.paid &&
        p.hasReceipt;
    final saved = _records[claim.purchaseRequestId];
    if (saved != null && matches(saved)) return saved;
    // Legacy claims may not yet have an associated request ID. Recover the
    // original persisted receipt, never invent a new idempotency key.
    for (final purchase in _records.values.toList().reversed) {
      if (matches(purchase)) return purchase;
    }
    return null;
  }

  void _resetGuestClaimRetries() {
    for (final retry in _claimRetries.values) {
      retry.timer?.cancel();
    }
    _claimRetries.clear();
    _claimReportsRequeued.clear();
    _claimWalletRefreshSessions.clear();
  }

  void _scheduleGuestClaimRetry(
    String accountUuid,
    _MembershipClaimRetry retry,
  ) {
    if (_disposed ||
        !identical(_claimRetries[accountUuid], retry) ||
        retry.timer != null ||
        retry.attempts >= 6) {
      return;
    }
    final session = _session;
    final delay = Duration(
      milliseconds: retryDelay.inMilliseconds * (1 << (retry.attempts - 1)),
    );
    retry.timer = Timer(delay, () {
      retry.timer = null;
      if (_disposed || session != _session) return;
      if (_recovery != null) _recoverAgain = true;
      unawaited(recover());
    });
  }

  Future<void> _saveGuestClaim(MembershipGuestClaimRecord record) async {
    // Keep an in-flight login's ownership even if persistence must be retried.
    _guestClaims[record.guest.accountUuid] = record;
    _pendingGuestClaimWrites.add(record.guest.accountUuid);
    await store.saveGuestClaim(record);
    _pendingGuestClaimWrites.remove(record.guest.accountUuid);
  }

  Future<void> _prepareGuestClaim(MembershipPurchaseRecord purchase) async {
    final guest = purchase.guest;
    if (_disposed || guest == null || !purchase.paid || !purchase.hasReceipt) {
      return;
    }
    final previous = _guestClaims[guest.accountUuid];
    var claim =
        previous ??
        MembershipGuestClaimRecord(
          guest: guest,
          purchaseRequestId: purchase.requestId,
        );
    if (purchase.reportStatus == 'completed' && !claim.purchaseConfirmed) {
      claim = claim.copyWith(
        purchaseRequestId: purchase.requestId,
        purchaseConfirmed: true,
      );
    }
    if (!identical(previous, claim) ||
        _pendingGuestClaimWrites.contains(guest.accountUuid)) {
      await _saveGuestClaim(claim);
    }
  }

  Future<void> _refreshGuestLoginRequest() async {
    if (_disposed) return;
    final uid = await readLoginUid();
    if (_disposed) return;
    String? requestId;
    if (uid == null) {
      for (final claim in _guestClaims.values) {
        final id = claim.purchaseRequestId ?? claim.guest.accountUuid;
        if (claim.requiresLogin && !_presentedAttempts.contains(id)) {
          requestId = id;
          break;
        }
      }
    }
    guestLoginRequestId.value = requestId;
  }

  Future<void> _completeGuestClaim(MembershipGuestClaimRecord record) async {
    if (record.status != 'completed' || record.ownerUid == null) return;
    final accountUuid = record.guest.accountUuid;
    final session = _session;
    if (_claimWalletRefreshSessions[accountUuid] != session &&
        !_disposed &&
        await readLoginUid() == record.ownerUid) {
      // Refresh even when a local report or cleanup is still pending. A failed
      // wallet request retries this completed claim's cleanup, never its POST.
      await refreshWallet?.call();
      if (!_disposed && session == _session) {
        _claimWalletRefreshSessions[accountUuid] = session;
      }
    }
    // Keep the original guest report body until every receipt has a terminal
    // report result; a completed claim can arrive before a local report retry.
    if (_records.values.any(
      (purchase) =>
          purchase.guest?.accountUuid == record.guest.accountUuid &&
          purchase.hasReceipt &&
          (purchase.paid || purchase.state == 'pending') &&
          purchase.reportStatus != 'completed' &&
          purchase.reportStatus != 'rejected',
    )) {
      _scheduleRetry();
      return;
    }
    await store.completeGuestClaim(record);
    for (final purchase in _records.values.toList()) {
      if (purchase.guest?.accountUuid == record.guest.accountUuid) {
        _records[purchase.requestId] = purchase.bindGuestToAccount(
          record.ownerUid!,
        );
      }
    }
    _guestClaims.remove(record.guest.accountUuid);
    _pendingGuestClaimWrites.remove(record.guest.accountUuid);
    _claimRetries.remove(accountUuid)?.timer?.cancel();
    _claimWalletRefreshSessions.remove(accountUuid);
    _claimReportsRequeued.remove(accountUuid);
    _signedTransactions.removeWhere(
      (key, _) => key.startsWith('$accountUuid:'),
    );
  }

  Future<void> _flushGuestClaims() async {
    for (final claim in _guestClaims.values.toList()) {
      if (_disposed) return;
      try {
        if (_pendingGuestClaimWrites.contains(claim.guest.accountUuid)) {
          await _saveGuestClaim(claim);
        }
        if (claim.status == 'completed') await _completeGuestClaim(claim);
      } catch (error) {
        _scheduleRetry();
        _log('guest claim cleanup deferred', error);
      }
    }
  }

  Future<void> _claimPendingGuests() async {
    if (_disposed) return;
    await _flushGuestClaims();
    final uid = await readLoginUid();
    if (_disposed) return;
    await _refreshGuestLoginRequest();
    if (uid == null || claimGuest == null) return;
    for (var record in _guestClaims.values.toList()) {
      if (_disposed || await readLoginUid() != uid) return;
      if (!record.needsRetry ||
          record.ownerUid != null && record.ownerUid != uid) {
        continue;
      }
      final session = _session;
      final previousStatus = record.status;
      final accountUuid = record.guest.accountUuid;
      final retry = _claimRetries.putIfAbsent(
        accountUuid,
        _MembershipClaimRetry.new,
      );
      if (!retry.canAttempt) continue;
      var requested = false;
      try {
        final purchase = _claimPurchase(record);
        if (purchase == null) {
          _scheduleRetry();
          continue;
        }
        final request = await _guestPurchaseRequest(purchase);
        if (_disposed || session != _session || await readLoginUid() != uid) {
          return;
        }
        record = record.copyWith(ownerUid: uid);
        // Pin the first login before sending a request. A timeout must never
        // cause this receipt to be claimed by a later, different account.
        await _saveGuestClaim(record);
        if (_disposed || session != _session || await readLoginUid() != uid) {
          return;
        }
        retry.attempts++;
        requested = true;
        final result = await claimGuest!(request);
        record = record.copyWith(status: result.status.name);
        await _saveGuestClaim(record);
        if (result.status == MembershipReportStatus.completed) {
          await _completeGuestClaim(record);
        }
        if (result.status == MembershipReportStatus.accepted &&
            !_claimReportsRequeued.contains(accountUuid)) {
          // The response model deliberately retains only status. Reconcile
          // known guest receipts once per session so accepted cannot strand an
          // awaiting-purchase-report claim; the original report is idempotent.
          for (final purchase in _records.values.toList()) {
            if (purchase.guest?.accountUuid == record.guest.accountUuid &&
                purchase.paid &&
                purchase.hasReceipt &&
                purchase.reportStatus == 'completed') {
              // Preserve the receipt, request key and any completed Apple finish.
              await _save(purchase.copyWith(retryReport: true));
            }
          }
          _claimReportsRequeued.add(accountUuid);
        }
        if (record.needsRetry) _scheduleGuestClaimRetry(accountUuid, retry);
      } catch (error) {
        if (requested && record.needsRetry) {
          _scheduleGuestClaimRetry(accountUuid, retry);
        } else {
          _scheduleRetry();
        }
        _log('guest claim deferred', error);
      } finally {
        if (session == _session &&
            record.status != null &&
            record.status != previousStatus) {
          _catalogChanged();
        }
      }
    }
  }
}

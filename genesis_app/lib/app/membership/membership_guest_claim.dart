part of 'membership_purchase_service.dart';

class _MembershipClaimRetry {
  int attempts = 0;
  Timer? timer;

  // One initial request and at most five additional attempts in this session.
  bool get canAttempt => timer == null && attempts < 6;
}

extension _MembershipGuestClaim on MembershipPurchaseService {
  void _resetGuestClaimRetries() {
    for (final retry in _claimRetries.values) {
      retry.timer?.cancel();
    }
    _claimRetries.clear();
    _claimReportsRequeued.clear();
    _claimWalletRefreshSessions.clear();
  }

  void _scheduleGuestClaimRetry(String guestId, _MembershipClaimRetry retry) {
    if (_disposed ||
        !identical(_claimRetries[guestId], retry) ||
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
    _guestClaims[record.guest.guestId] = record;
    _pendingGuestClaimWrites.add(record.guest.guestId);
    await store.saveGuestClaim(record);
    _pendingGuestClaimWrites.remove(record.guest.guestId);
  }

  Future<void> _prepareGuestClaim(MembershipPurchaseRecord purchase) async {
    final guest = purchase.guest;
    if (_disposed || guest == null || !purchase.paid || !purchase.hasReceipt) {
      return;
    }
    final previous = _guestClaims[guest.guestId];
    var claim = previous ?? MembershipGuestClaimRecord(guest: guest);
    if (purchase.reportStatus == 'completed' && !claim.purchaseConfirmed) {
      claim = claim.copyWith(
        purchaseRequestId: purchase.requestId,
        purchaseConfirmed: true,
      );
    }
    if (!identical(previous, claim) ||
        _pendingGuestClaimWrites.contains(guest.guestId)) {
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
        final id = claim.purchaseRequestId ?? claim.guest.guestId;
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
    final guestId = record.guest.guestId;
    final session = _session;
    if (_claimWalletRefreshSessions[guestId] != session &&
        !_disposed &&
        await readLoginUid() == record.ownerUid) {
      // Refresh even when a local report or cleanup is still pending. A failed
      // wallet request retries this completed claim's cleanup, never its POST.
      await refreshWallet?.call();
      if (!_disposed && session == _session) {
        _claimWalletRefreshSessions[guestId] = session;
      }
    }
    // Keep the original guest report body until every receipt has a terminal
    // report result; a completed claim can arrive before a local report retry.
    if (_records.values.any(
      (purchase) =>
          purchase.guest?.guestId == record.guest.guestId &&
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
      if (purchase.guest?.guestId == record.guest.guestId) {
        _records[purchase.requestId] = purchase.bindGuestToAccount(
          record.ownerUid!,
        );
      }
    }
    _guestClaims.remove(record.guest.guestId);
    _pendingGuestClaimWrites.remove(record.guest.guestId);
    _claimRetries.remove(guestId)?.timer?.cancel();
    _claimWalletRefreshSessions.remove(guestId);
    _claimReportsRequeued.remove(guestId);
  }

  Future<void> _flushGuestClaims() async {
    for (final claim in _guestClaims.values.toList()) {
      if (_disposed) return;
      try {
        if (_pendingGuestClaimWrites.contains(claim.guest.guestId)) {
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
      final guestId = record.guest.guestId;
      final retry = _claimRetries.putIfAbsent(
        guestId,
        _MembershipClaimRetry.new,
      );
      if (!retry.canAttempt) continue;
      var requested = false;
      try {
        record = record.copyWith(ownerUid: uid);
        // Pin the first login before sending a request. A timeout must never
        // cause this receipt to be claimed by a later, different account.
        await _saveGuestClaim(record);
        if (_disposed || session != _session || await readLoginUid() != uid) {
          return;
        }
        retry.attempts++;
        requested = true;
        final result = await claimGuest!(record.guest);
        record = record.copyWith(status: result.status.name);
        await _saveGuestClaim(record);
        if (result.status == MembershipReportStatus.completed) {
          await _completeGuestClaim(record);
        }
        if (result.status == MembershipReportStatus.accepted &&
            !_claimReportsRequeued.contains(guestId)) {
          // The response model deliberately retains only status. Reconcile
          // known guest receipts once per session so accepted cannot strand an
          // awaiting-purchase-report claim; the original report is idempotent.
          for (final purchase in _records.values.toList()) {
            if (purchase.guest?.guestId == record.guest.guestId &&
                purchase.paid &&
                purchase.hasReceipt &&
                purchase.reportStatus == 'completed') {
              // Preserve the receipt, request key and any completed Apple finish.
              await _save(purchase.copyWith(retryReport: true));
            }
          }
          _claimReportsRequeued.add(guestId);
        }
        if (record.needsRetry) _scheduleGuestClaimRetry(guestId, retry);
      } catch (error) {
        if (requested && record.needsRetry) {
          _scheduleGuestClaimRetry(guestId, retry);
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

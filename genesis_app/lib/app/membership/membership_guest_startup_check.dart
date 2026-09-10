part of 'membership_purchase_service.dart';

extension _MembershipGuestStartupCheck on MembershipPurchaseService {
  Future<void> _checkGuestPurchasesOnHome() {
    _guestHomeSeen = true;
    if (_disposed || checkGuestPurchase == null) return Future.value();
    final running = _guestHomeCheck;
    if (running != null) return running;
    final session = _session;
    late final Future<void> task;
    task =
        (() async {
          try {
            if (!await _guestStartupIsCurrent(session)) return;
            await _load();
            if (!await _guestStartupIsCurrent(session) ||
                _busy ||
                _presentedAttempts.isNotEmpty ||
                _guestStartupResolved) {
              return;
            }
            _guestStartupRefreshNeeded = false;
            final uuids = _guestClaims.keys.toSet();
            final discovered = <String, Map<String, BillingPurchase>>{};
            if (uuids.isEmpty && discoverGuestPurchases != null) {
              final purchases = await discoverGuestPurchases!();
              if (!await _guestStartupIsCurrent(session) ||
                  _busy ||
                  _presentedAttempts.isNotEmpty) {
                return;
              }
              final storeProvider = provider == MembershipProvider.google
                  ? BillingProvider.googlePlay
                  : BillingProvider.appStore;
              for (final candidate in purchases) {
                final purchase = candidate.purchase;
                final uuid = purchase.obfuscatedAccountId ?? '';
                if (purchase.provider == storeProvider &&
                    (purchase.status == BillingPurchaseStatus.purchased ||
                        purchase.status == BillingPurchaseStatus.restored) &&
                    candidate.isCurrent(DateTime.now()) &&
                    isMembershipAccountUuid(uuid)) {
                  final accountUuid = uuid.toLowerCase();
                  uuids.add(accountUuid);
                  final credential = provider == MembershipProvider.google
                      ? purchase.purchaseToken
                      : purchase.transactionId;
                  if (credential.isNotEmpty && purchase.productId.isNotEmpty) {
                    discovered.putIfAbsent(
                      accountUuid,
                      () => {},
                    )['${purchase.productId}:$credential'] = purchase;
                  }
                }
              }
            }
            var allChecked = true;
            for (final uuid in uuids) {
              if (!await _guestStartupIsCurrent(session)) return;
              try {
                final result = await checkGuestPurchase!(uuid);
                if (!await _guestStartupIsCurrent(session) ||
                    _busy ||
                    _presentedAttempts.isNotEmpty) {
                  return;
                }
                _guestOrderChecks[uuid] = result;
                if (result.hasUnboundOrder && _guestClaims[uuid] == null) {
                  final candidates = discovered[uuid]?.values.toList() ?? [];
                  // Do not choose an arbitrary independent subscription chain:
                  // claiming it can replace the user's other subscription.
                  if (candidates.length == 1) {
                    final purchase = candidates.single;
                    await _serialize(() async {
                      if (!await _guestStartupIsCurrent(session) ||
                          _guestClaims.containsKey(uuid)) {
                        return;
                      }
                      final proof = MembershipGuestClaimProof(
                        provider: provider,
                        storeProductId: purchase.productId,
                        requestId: newBillingAttemptId(),
                        purchaseToken: purchase.purchaseToken,
                        transactionId: purchase.transactionId,
                      );
                      if (provider == MembershipProvider.apple &&
                          purchase.signedTransaction.isNotEmpty) {
                        _signedTransactions['$uuid:${purchase.transactionId}'] =
                            purchase.signedTransaction;
                      }
                      // This is login claim state, never a report failure or a
                      // synthetic completed purchase in the recovery queue.
                      await _saveGuestClaim(
                        MembershipGuestClaimRecord(
                          guest: MembershipGuestIdentity(accountUuid: uuid),
                          loginRequired: true,
                          recoveredProof: proof,
                        ),
                      );
                    });
                  }
                }
                // A false result is not an error and does not delete the UUID.
                // It also prevents a later unrelated login from claiming this cache.
                final claim = _guestClaims[uuid];
                if (claim != null &&
                    claim.status != 'completed' &&
                    claim.ownerUid == null) {
                  await _serialize(() async {
                    if (!await _guestStartupIsCurrent(session)) return;
                    final current = _guestClaims[uuid];
                    if (current == null ||
                        current.ownerUid != null ||
                        current.status == 'completed') {
                      return;
                    }
                    await _saveGuestClaim(
                      current.copyWith(
                        autoClaimAllowed: result.hasUnboundOrder,
                      ),
                    );
                  });
                }
              } catch (error) {
                allChecked = false;
                _log('guest purchase check deferred', error);
              }
            }
            if (!await _guestStartupIsCurrent(session)) return;
            _guestStartupResolved = allChecked;
            await _refreshGuestLoginRequest();
          } catch (error) {
            _log('guest startup check deferred', error);
          }
        })().whenComplete(() {
          if (identical(_guestHomeCheck, task)) _guestHomeCheck = null;
          if (_guestStartupRefreshNeeded && !_disposed) {
            _guestStartupRefreshNeeded = false;
            unawaited(checkGuestPurchasesOnHome());
          }
        });
    _guestHomeCheck = task;
    return task;
  }

  Future<bool> _guestStartupIsCurrent(int session) async =>
      !_disposed && session == _session && await readLoginUid() == null;
}

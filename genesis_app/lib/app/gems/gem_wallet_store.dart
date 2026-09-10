import 'package:flutter/foundation.dart';

import '../../network/models/gem_wallet.dart';

typedef GemWalletLoader = Future<GemWallet> Function();
typedef GemWalletUidReader = Future<String?> Function();

@immutable
class GemWalletState {
  const GemWalletState({
    this.ownerUid,
    this.balanceCent,
    this.membership,
    this.isRefreshing = false,
    this.updatedAt,
    this.lastError,
  });

  final String? ownerUid;
  final int? balanceCent;
  final GemWalletMembership? membership;
  final bool isRefreshing;
  final DateTime? updatedAt;
  final Object? lastError;

  bool get hasWalletBalance => balanceCent != null;
}

class GemWalletStore {
  GemWalletStore({required this.loadWallet, required this.readUid});

  final GemWalletLoader loadWallet;
  final GemWalletUidReader readUid;
  final ValueNotifier<GemWalletState> _state = ValueNotifier<GemWalletState>(
    const GemWalletState(),
  );

  ValueListenable<GemWalletState> get state => _state;

  int _requestGeneration = 0;
  Future<void>? _refreshFuture;
  bool _disposed = false;

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;

    final future = _refreshInternal();
    late Future<void> trackedFuture;
    trackedFuture = future.whenComplete(() {
      if (identical(_refreshFuture, trackedFuture)) _refreshFuture = null;
    });
    _refreshFuture = trackedFuture;
    return trackedFuture;
  }

  Future<void> _refreshInternal() async {
    final uid = await _readCurrentUid();
    if (_disposed) return;
    if (uid.isEmpty || uid.startsWith('guest_')) {
      reset();
      return;
    }

    final requestGeneration = ++_requestGeneration;
    if (_disposed) return;
    final current = _state.value;
    final retainedBalanceCent = current.ownerUid == uid
        ? current.balanceCent
        : null;
    final retainedUpdatedAt = current.ownerUid == uid
        ? current.updatedAt
        : null;
    final retainedMembership = current.ownerUid == uid
        ? current.membership
        : null;
    _state.value = GemWalletState(
      ownerUid: uid,
      balanceCent: retainedBalanceCent,
      membership: retainedMembership,
      isRefreshing: true,
      updatedAt: retainedUpdatedAt,
    );

    try {
      final wallet = await loadWallet();
      if (_disposed) return;
      final currentUid = await _readCurrentUid();
      if (_disposed) return;
      if (requestGeneration != _requestGeneration) return;
      if (currentUid != uid) {
        reset();
        return;
      }
      _state.value = GemWalletState(
        ownerUid: uid,
        balanceCent: wallet.balanceCent,
        membership: wallet.membership,
        updatedAt: DateTime.now(),
      );
    } catch (error) {
      if (_disposed) return;
      if (requestGeneration != _requestGeneration) return;
      final currentUid = await _readCurrentUid();
      if (_disposed) return;
      if (requestGeneration != _requestGeneration) return;
      if (currentUid != uid) {
        reset();
        return;
      }
      _state.value = GemWalletState(
        ownerUid: uid,
        balanceCent: retainedBalanceCent,
        membership: retainedMembership,
        updatedAt: retainedUpdatedAt,
        lastError: error,
      );
    }
  }

  Future<void> refreshAfterEntitlementGranted() => refresh();

  /// VIP mutations need a request made after the server confirms the change.
  /// Leave the existing Gems refresh/coalescing behavior unchanged.
  Future<void> refreshAfterMembershipChanged() async {
    final earlierRequest = _refreshFuture;
    if (earlierRequest != null) await earlierRequest;
    if (_disposed) return;
    await refresh();
    if (_disposed) return;
    final error = _state.value.lastError;
    if (error != null) throw error;
  }

  void reset() {
    if (_disposed) return;
    _requestGeneration += 1;
    _refreshFuture = null;
    _state.value = const GemWalletState();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requestGeneration += 1;
    _refreshFuture = null;
    _state.dispose();
  }

  Future<String> _readCurrentUid() async {
    try {
      return (await readUid())?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }
}

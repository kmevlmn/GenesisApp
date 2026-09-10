import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../network/models/gem_wallet.dart';
import '../gems/gem_wallet_store.dart';

enum MembershipAccessStatus { unknown, active, inactive }

@immutable
class MembershipAccessState {
  const MembershipAccessState({
    this.status = MembershipAccessStatus.unknown,
    this.ownerUid,
    this.membership,
    this.isRefreshing = false,
    this.lastError,
  });

  final MembershipAccessStatus status;
  final String? ownerUid;
  final GemWalletMembership? membership;
  final bool isRefreshing;
  final Object? lastError;

  /// Unknown must not be presented as a confirmed non-member.
  bool? get isVip => switch (status) {
    MembershipAccessStatus.unknown => null,
    MembershipAccessStatus.active => true,
    MembershipAccessStatus.inactive => false,
  };
}

/// Global membership access derived from the existing account-scoped wallet.
/// No purchase receipts, Gems balance rules, or additional wallet cache here.
class MembershipAccessStore with WidgetsBindingObserver {
  MembershipAccessStore({
    required this.wallet,
    required this.readLoginUid,
    required this.serverNow,
    this.hasBackendSession,
    Duration Function()? elapsed,
    this.maxCacheAge = const Duration(minutes: 5),
    this.shortCacheAge = const Duration(seconds: 30),
    this.requestTimeout = const Duration(seconds: 20),
    this.retryDelay = const Duration(seconds: 2),
  }) : _elapsed = elapsed ?? _startElapsedClock() {
    wallet.state.addListener(_walletChanged);
  }

  final GemWalletStore wallet;
  final Future<String?> Function() readLoginUid;
  final Future<bool> Function()? hasBackendSession;
  final DateTime? Function() serverNow;
  final Duration Function() _elapsed;
  final Duration maxCacheAge;
  final Duration shortCacheAge;
  final Duration requestTimeout;
  final Duration retryDelay;
  final _state = ValueNotifier(const MembershipAccessState());

  @visibleForTesting
  MembershipAccessState get debugState => _state.value;

  /// The single business entry point for checking VIP access.
  /// Calls [callback] once, asynchronously, whether using cache or the network.
  /// True means VIP, false means non-VIP, and null means not yet confirmed.
  void checkVip(ValueChanged<bool?> callback) {
    final session = _session;
    unawaited(
      _ensureFresh().then((status) {
        final result = _disposed || _session != session
            ? MembershipAccessStatus.unknown
            : status;
        callback(switch (result) {
          MembershipAccessStatus.active => true,
          MembershipAccessStatus.inactive => false,
          MembershipAccessStatus.unknown => null,
        });
      }),
    );
  }

  String? _ownerUid;
  bool _sessionKnown = false;
  GemWalletMembership? _membership;
  GemWalletState? _lastWalletResponse;
  GemWalletState? _lastWalletFailure;
  GemWalletState? _observedResponse;
  Duration? _observedAt;
  Duration? _receivedAt;
  Duration? _retryAfter;
  Object? _lastError;
  int _failures = 0;
  int _session = 0;
  Object? _operation;
  Future<MembershipAccessStatus>? _inFlight;
  Timer? _expiryTimer;
  Timer? _cacheTimer;
  bool _started = false;
  bool _foreground = true;
  bool _disposed = false;

  Future<void> start() async {
    if (_disposed) return;
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addObserver(this);
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    }
    await _ensureFresh();
  }

  /// At most one wallet request per lookup. Concurrent callers share the result.
  /// Errors remain unknown; a later lookup may retry after a short cooldown.
  Future<MembershipAccessStatus> _ensureFresh({Duration? maxAge}) {
    if (_disposed) return Future.value(MembershipAccessStatus.unknown);
    final pending = _inFlight;
    if (pending != null) return pending;
    final session = _session;
    final operation = Object();
    _operation = operation;
    bool current() =>
        !_disposed && _session == session && identical(_operation, operation);
    late final Future<MembershipAccessStatus> future;
    future = _resolve(current, maxAge)
        .timeout(
          requestTimeout,
          onTimeout: () {
            if (current()) {
              _operation = null;
              _failed(TimeoutException('Membership lookup timed out'));
              _publish();
            }
            return MembershipAccessStatus.unknown;
          },
        )
        .catchError((Object error) {
          if (current()) {
            _failed(error);
            _publish();
          }
          return MembershipAccessStatus.unknown;
        })
        .whenComplete(() {
          if (identical(_operation, operation)) _operation = null;
          if (identical(_inFlight, future)) _inFlight = null;
        });
    _inFlight = future;
    return future;
  }

  Future<MembershipAccessStatus> _resolve(
    bool Function() current,
    Duration? maxAge,
  ) async {
    final rawUid = (await readLoginUid())?.trim() ?? '';
    if (!current()) return MembershipAccessStatus.unknown;
    final uid = rawUid.isEmpty || rawUid.startsWith('guest_') ? null : rawUid;
    if (!_sessionKnown || uid != _ownerUid) {
      _clearSnapshot();
      _ownerUid = uid;
      _sessionKnown = true;
    }
    if (uid == null) {
      _publish();
      return MembershipAccessStatus.inactive;
    }
    _consumeWallet();
    final cached = _status();
    final age = _receivedAt == null ? null : _elapsed() - _receivedAt!;
    if (cached != MembershipAccessStatus.unknown &&
        (maxAge == null || age != null && age < maxAge)) {
      _scheduleExpiry();
      _publish();
      return cached;
    }
    if (_retryAfter != null && _elapsed() < _retryAfter!) {
      _publish();
      return MembershipAccessStatus.unknown;
    }
    if (hasBackendSession != null && !await hasBackendSession!()) {
      if (!current()) return MembershipAccessStatus.unknown;
      throw StateError('Membership backend session unavailable');
    }
    if (!current()) return MembershipAccessStatus.unknown;
    _publish(refreshing: true);
    await wallet.refresh();
    if (!current()) return MembershipAccessStatus.unknown;
    // Session notifications normally cancel this lookup. Also verify the UID
    // before returning access if a caller changed credentials without one.
    if ((await readLoginUid())?.trim() != uid) {
      if (current()) resetForSession();
      return MembershipAccessStatus.unknown;
    }
    if (!current()) return MembershipAccessStatus.unknown;
    _consumeWallet();
    final result = _status();
    if (result == MembershipAccessStatus.unknown && _lastError == null) {
      _failed(StateError('Membership information unavailable'));
    }
    _publish();
    return result;
  }

  void _walletChanged() {
    if (_disposed) return;
    final snapshot = wallet.state.value;
    if (_ownerUid != null && snapshot.ownerUid != _ownerUid) {
      _clearSnapshot();
    }
    if (!snapshot.isRefreshing &&
        snapshot.lastError == null &&
        snapshot.updatedAt != null) {
      _observedResponse = snapshot;
      _observedAt = _elapsed();
    }
    _consumeWallet();
    _publish(refreshing: wallet.state.value.isRefreshing);
  }

  void _consumeWallet() {
    final snapshot = wallet.state.value;
    if (!_sessionKnown ||
        _ownerUid == null ||
        snapshot.ownerUid != _ownerUid ||
        snapshot.isRefreshing) {
      return;
    }
    if (snapshot.lastError != null) {
      if (!identical(snapshot, _lastWalletFailure)) {
        _lastWalletFailure = snapshot;
        _failed(snapshot.lastError!);
      }
      return;
    }
    if (!identical(snapshot, _observedResponse) ||
        snapshot.updatedAt == null ||
        identical(snapshot, _lastWalletResponse)) {
      return;
    }
    _lastWalletResponse = snapshot;
    _lastWalletFailure = null;
    _membership = snapshot.membership;
    _receivedAt = _observedAt;
    _lastError = null;
    _retryAfter = null;
    _failures = 0;
    if (_membership == null || _status() == MembershipAccessStatus.unknown) {
      _failed(StateError('Membership information unavailable'));
    }
    _scheduleExpiry();
  }

  Duration get _cacheAge =>
      _membership?.status == 1 &&
          (_membership?.expiresAt == null || serverNow() == null)
      ? shortCacheAge
      : maxCacheAge;

  MembershipAccessStatus _status() {
    if (_disposed || !_sessionKnown) return MembershipAccessStatus.unknown;
    if (_ownerUid == null) return MembershipAccessStatus.inactive;
    final membership = _membership;
    if (membership == null ||
        _receivedAt == null ||
        _elapsed() - _receivedAt! >= _cacheAge) {
      return MembershipAccessStatus.unknown;
    }
    if (membership.status != 1) return MembershipAccessStatus.inactive;
    final expiry = membership.expiresAt;
    final now = serverNow();
    if (expiry != null && now != null && !expiry.isAfter(now)) {
      return MembershipAccessStatus.unknown;
    }
    // A fresh server status remains authoritative when expiry is unknown.
    return MembershipAccessStatus.active;
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _cacheTimer?.cancel();
    if (_receivedAt == null || _membership == null) return;
    final cacheRemaining = _cacheAge - (_elapsed() - _receivedAt!);
    if (cacheRemaining > Duration.zero) {
      _cacheTimer = Timer(cacheRemaining, _publish);
    }
    final expiry = _membership!.expiresAt;
    final now = serverNow();
    if (_membership!.status == 1 && expiry != null && now != null) {
      final remaining = expiry.difference(now);
      if (remaining > Duration.zero) {
        _expiryTimer = Timer(remaining, () {
          if (_disposed) return;
          _publish();
          if (_started && _foreground) unawaited(_ensureFresh());
        });
      }
    }
  }

  void _failed(Object error) {
    _lastError = error;
    final factor = 1 << math.min(_failures++, 4);
    _retryAfter =
        _elapsed() +
        Duration(
          milliseconds: math.min(30000, retryDelay.inMilliseconds * factor),
        );
  }

  void _publish({bool refreshing = false}) {
    if (_disposed) return;
    _state.value = MembershipAccessState(
      status: _status(),
      ownerUid: _ownerUid,
      membership: _membership,
      isRefreshing: refreshing,
      lastError: _lastError,
    );
  }

  void resetForSession() {
    if (_disposed) return;
    _session++;
    _operation = null;
    _inFlight = null;
    _ownerUid = null;
    _sessionKnown = false;
    _clearSnapshot();
    _publish();
  }

  void _clearSnapshot() {
    _expiryTimer?.cancel();
    _cacheTimer?.cancel();
    _membership = null;
    _receivedAt = null;
    _lastWalletResponse = null;
    _lastWalletFailure = null;
    _retryAfter = null;
    _lastError = null;
    _failures = 0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_started && _foreground) unawaited(_ensureFresh(maxAge: shortCacheAge));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _session++;
    _expiryTimer?.cancel();
    _cacheTimer?.cancel();
    wallet.state.removeListener(_walletChanged);
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
  }

  static Duration Function() _startElapsedClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}

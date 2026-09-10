part of 'google_play_billing_service.dart';

extension _GooglePlayBillingTracking on GooglePlayBillingService {
  void _emitFailure(
    String productId,
    String attemptId,
    String message, {
    required String debugInfo,
  }) {
    _emitUiEvent(
      BillingUiEvent(
        kind: BillingUiEventKind.failure,
        productId: productId,
        attemptId: attemptId,
        message: message,
        debugInfo: debugInfo,
      ),
    );
    _setBusy(productId, false);
  }

  void _emitDeferred(
    String productId,
    String attemptId, {
    required String debugInfo,
  }) {
    _emitUiEvent(
      BillingUiEvent(
        kind: BillingUiEventKind.deferred,
        productId: productId,
        attemptId: attemptId,
        message: 'Payment is being confirmed.',
        debugInfo: debugInfo,
      ),
    );
  }

  void _scheduleAttemptTimeout(
    String timerKey, {
    required DateTime startedAt,
    required VoidCallback onTimeout,
  }) {
    _cancelAttemptTimeout(timerKey);
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = elapsed < _attemptTimeout
        ? _attemptTimeout - elapsed
        : Duration.zero;
    _attemptTimeouts[timerKey] = Timer(remaining, () {
      _attemptTimeouts.remove(timerKey);
      onTimeout();
    });
  }

  void _cancelAttemptTimeout(String storeProductId) {
    _attemptTimeouts.remove(storeProductId)?.cancel();
  }

  void _setBusy(String productId, bool busy) {
    if (_disposed || productId.isEmpty) return;
    final next = <String>{..._state.value.busyProductIds};
    if (busy) {
      next.add(productId);
    } else {
      next.remove(productId);
    }
    _setState(busyProductIds: next);
  }

  void _setState({bool? storeAvailable, Set<String>? busyProductIds}) {
    if (_disposed) return;
    _state.value = BillingState(
      storeAvailable: storeAvailable ?? _state.value.storeAvailable,
      busyProductIds: busyProductIds ?? _state.value.busyProductIds,
    );
  }

  String _purchaseFailureMessage(Object error) {
    if (error is BillingPlatformException && error.code.isNotEmpty) {
      return 'Purchase failed (${error.code}).';
    }
    return 'Purchase failed.';
  }

  String _queryFailureErrorCode(Object error) {
    if (error is BillingPlatformException && error.code.trim().isNotEmpty) {
      return error.code.trim();
    }
    return 'unknown';
  }

  String? _purchaseLaunchErrorCode(Object error) {
    final code = switch (error) {
      PlatformException(:final code) => code,
      BillingPlatformException(:final code) => code,
      _ => '',
    }.trim();
    return code.isEmpty ? null : code;
  }

  String _productQueryFailureMessage(String? errorCode) {
    final code = errorCode?.trim() ?? '';
    if (code.isNotEmpty) return 'Purchase failed ($code).';
    return 'This product is currently unavailable.';
  }

  String _purchaseDetailsFailureMessage(BillingPurchase purchase) {
    final code = purchase.errorCode?.trim() ?? '';
    final detail = purchase.errorMessage?.trim() ?? '';
    if (detail.isNotEmpty && code.isNotEmpty) {
      return 'Purchase failed ($code: $detail).';
    }
    if (detail.isNotEmpty) return 'Purchase failed ($detail).';
    if (code.isNotEmpty) return 'Purchase failed ($code).';
    return 'Purchase failed.';
  }

  void _track(
    String action, {
    String attemptId = '',
    String productId = '',
    String storeProductId = '',
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    try {
      _analytics.track(
        action,
        properties: <String, Object?>{
          'attempt_id': attemptId,
          'product_id': productId,
          'store_product_id': storeProductId,
          ...data,
        },
      );
    } catch (_) {
      // A custom analytics sink must not be able to break billing.
    }
  }

  void _trackProduct(
    String action, {
    required GemProduct product,
    required String attemptId,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    _track(
      action,
      attemptId: attemptId,
      productId: product.productId,
      storeProductId: _storeProductIdFor(product, _platform.provider),
      data: <String, Object?>{
        'provider': _platform.provider.apiValue,
        'trigger': BillingRecoverySource.direct.value,
        ...data,
      },
    );
  }

  void _trackPrecheckFailure(
    GemProduct product,
    String attemptId,
    String errorCode,
  ) {
    _trackFlowResult(
      product,
      attemptId,
      'precheck_failed',
      errorCode: errorCode,
    );
  }

  void _trackFlowResult(
    GemProduct product,
    String attemptId,
    String status, {
    String? errorCode,
  }) {
    _trackFlowResultById(
      attemptId: attemptId,
      productId: product.productId,
      storeProductId: _storeProductIdFor(product, _platform.provider),
      status: status,
      source: BillingRecoverySource.direct,
      errorCode: errorCode,
    );
  }

  void _trackFlowResultById({
    required String attemptId,
    required String productId,
    required String storeProductId,
    required String status,
    required BillingRecoverySource source,
    String? errorCode,
  }) {
    final failedReason = _failedReasonForFlowResult(
      status: status,
      errorCode: errorCode,
    );
    if (failedReason != null) {
      _trackFailedById(
        attemptId: attemptId,
        productId: productId,
        storeProductId: storeProductId,
        reason: failedReason,
        errorCode:
            failedReason == 'purchase_callback_error' ||
                failedReason == 'query_failed' ||
                failedReason == 'launch_failed' ||
                failedReason == 'report_failed' ||
                failedReason == 'report_rejected'
            ? errorCode
            : null,
      );
    }
  }

  void _trackFailedById({
    required String attemptId,
    required String productId,
    required String storeProductId,
    required String reason,
    String? errorCode,
  }) {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) return;
    final normalizedErrorCode = errorCode?.trim() ?? '';
    _track(
      'purchase_failed',
      attemptId: attemptId,
      productId: productId,
      storeProductId: storeProductId,
      data: <String, Object?>{
        'reason': normalizedReason,
        if (normalizedErrorCode.isNotEmpty) 'error_code': normalizedErrorCode,
      },
    );
  }

  void _trackPendingById({
    required String attemptId,
    required String productId,
    required String storeProductId,
  }) {
    _track(
      'purchase_pending',
      attemptId: attemptId,
      productId: productId,
      storeProductId: storeProductId,
    );
  }

  void _trackTimeoutById({
    required String attemptId,
    required String productId,
    required String storeProductId,
    required String timeoutType,
  }) {
    _track(
      'purchase_timeout',
      attemptId: attemptId,
      productId: productId,
      storeProductId: storeProductId,
      data: <String, Object?>{'timeout_type': timeoutType},
    );
  }

  String? _failedReasonForFlowResult({
    required String status,
    String? errorCode,
  }) {
    return switch (status) {
      'completed' || 'accepted' => null,
      'precheck_failed' => _precheckFailedReason(errorCode),
      'query_failed' => 'query_failed',
      'launch_rejected' || 'launch_failed' => 'launch_failed',
      'canceled' => 'canceled',
      'store_failed' =>
        errorCode == 'purchase_token_missing'
            ? 'purchase_token_missing'
            : 'purchase_callback_error',
      _ => 'report_rejected',
    };
  }

  String? _precheckFailedReason(String? errorCode) {
    return switch (errorCode) {
      'gp_unavailable' => 'gp_unavailable',
      'uuid_unavailable' => 'uuid_unavailable',
      'product_not_purchasable' => 'product_not_purchasable',
      'store_product_id_missing' => 'store_product_id_missing',
      'purchase_in_progress' => 'purchase_in_progress',
      'unsupported_product_type' => 'unsupported_product_type',
      _ => null,
    };
  }

  String _reportFailureReason(Object error) {
    if (error is ApiException) {
      final code = error.code;
      if (code != null) return '$code';
      final transportKind = error.transportErrorKind;
      if (transportKind != null) return transportKind.name;
      if (error.kind != ApiExceptionKind.unknown) return error.kind.name;
      final message = error.message.trim();
      if (message.isNotEmpty) return message;
    }
    return error.runtimeType.toString();
  }
}

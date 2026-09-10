import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/membership/membership_purchase_service.dart';
import '../../app/membership/membership_purchase_eligibility.dart';
import '../../icons/custom_icon_assets.dart';
import '../../network/models/membership_product.dart';
import '../../platform/billing/billing_models.dart';
import '../../platform/billing/purchase_toast_diagnostics.dart';
import '../common/genesis_center_toast.dart';
import '../common/genesis_modal_routes.dart';
import 'gem_billing_purchase_dialog.dart';

/// Owns only the dialog for this user's purchase, never background restore UI.
class MembershipPurchasePresentation {
  MembershipPurchasePresentation({
    required this.context,
    required this.service,
  });

  final BuildContext context;
  final MembershipPurchaseService service;
  RawDialogRoute<bool>? _route;
  NavigatorState? _navigator;
  StreamSubscription<MembershipCheckoutEvent>? _subscription;
  bool _disposed = false;
  bool _resolved = false;
  bool _closing = false;

  Future<bool> purchase(MembershipProduct product) async {
    if (_disposed || _route != null || service.isBusy) return false;
    final attemptId = newBillingAttemptId();
    service.attachCheckoutPresentation(attemptId);
    final state = ValueNotifier(
      GemBillingPurchaseDialogState.processing(attemptId: attemptId),
    );
    final navigator = Navigator.of(context, rootNavigator: true);
    _navigator = navigator;
    _resolved = false;
    _closing = false;
    final route = RawDialogRoute<bool>(
      barrierColor: kGenesisModalBarrierColor,
      barrierDismissible: false,
      pageBuilder: (_, _, _) => Center(
        child: GemBillingPurchaseDialog(
          state: state,
          processingLabel: 'Purchasing VIP',
          successTitle: 'VIP purchase successful!',
          successMessage: 'Your VIP purchase is confirmed.',
          successIconAsset: proCrownFilledIconAsset,
          onConfirm: () => _close(true),
        ),
      ),
    );
    _route = route;
    _subscription = service.checkoutEvents.listen((event) {
      if (_disposed || _resolved || event.attemptId != attemptId) return;
      switch (event.state) {
        case MembershipCheckoutState.preparing:
        case MembershipCheckoutState.store:
        case MembershipCheckoutState.reporting:
          return;
        case MembershipCheckoutState.completed:
          _resolved = true;
          state.value = GemBillingPurchaseDialogState.success(
            attemptId: attemptId,
            grantedText: '',
          );
          return;
        case MembershipCheckoutState.idle:
          _resolved = true;
          _close(false);
          return;
        case MembershipCheckoutState.accepted:
        case MembershipCheckoutState.pending:
        case MembershipCheckoutState.deferred:
        case MembershipCheckoutState.canceled:
        case MembershipCheckoutState.failed:
        case MembershipCheckoutState.rejected:
          _resolved = true;
          _close(false);
          if (context.mounted) {
            final debugInfo =
                event.debugInfo ??
                purchaseDebugInfo(
                  'vip.checkout',
                  status: event.state.name,
                  reason: event.reason,
                );
            showGenesisToast(
              context,
              event.reason == null
                  ? purchaseToastMessage(
                      _message(event.state),
                      debugInfo: debugInfo,
                    )
                  : membershipPurchaseFailureMessage(
                      event.reason!,
                      debugInfo: debugInfo,
                    ),
            );
          }
      }
    }, onDone: () => _close(false));
    final result = navigator.push(route);
    unawaited(
      service.purchase(product, attemptId: attemptId).catchError((
        Object error,
      ) {
        if (_disposed || _resolved) return;
        _resolved = true;
        _close(false);
        if (context.mounted) {
          showGenesisToast(
            context,
            purchaseToastMessage(
              'VIP purchase failed.',
              debugInfo: purchaseDebugInfo(
                'vip.checkout_exception',
                error: error,
              ),
            ),
          );
        }
      }),
    );
    try {
      final confirmed = await result == true;
      if (confirmed) await service.confirmGuestPurchase(attemptId);
      return confirmed;
    } finally {
      _resolved = true;
      unawaited(_subscription?.cancel());
      _subscription = null;
      // The route still renders during its dismissal transition.
      await route.completed;
      state.dispose();
      if (identical(_route, route)) _route = null;
      await service.detachCheckoutPresentation(attemptId);
    }
  }

  String _message(MembershipCheckoutState state) => switch (state) {
    MembershipCheckoutState.canceled => 'VIP purchase cancelled.',
    MembershipCheckoutState.pending => 'VIP payment is pending.',
    MembershipCheckoutState.accepted => 'Your VIP purchase is being confirmed.',
    MembershipCheckoutState.deferred =>
      'VIP purchase confirmation is delayed. Please check again later.',
    _ => 'VIP purchase failed.',
  };

  void _close(bool confirmed) {
    final route = _route;
    final navigator = _navigator;
    if (_closing ||
        route == null ||
        navigator == null ||
        !navigator.mounted ||
        !route.isActive) {
      return;
    }
    _closing = true;
    if (route.isCurrent) {
      navigator.pop(confirmed);
    } else {
      navigator.removeRoute(route, confirmed);
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    // Parent disposal can run while the Navigator is locked for a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _close(false));
  }
}

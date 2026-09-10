import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/debug/membership_guest_login_debug_settings.dart';
import '../../app/membership/membership_purchase_service.dart';
import '../auth/login_guard.dart';

/// Keeps paid guest purchases actionable after leaving a page or restarting.
class MembershipGuestLoginGate extends StatefulWidget {
  const MembershipGuestLoginGate({
    super.key,
    required this.service,
    required this.navigatorKey,
    required this.child,
    this.requestLogin,
  });

  final MembershipPurchaseService? service;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final Future<bool> Function(BuildContext)? requestLogin;

  @override
  State<MembershipGuestLoginGate> createState() =>
      _MembershipGuestLoginGateState();
}

class _MembershipGuestLoginGateState extends State<MembershipGuestLoginGate> {
  bool _showing = false;
  bool _settingsReady = !kDebugMode;

  bool get _forceLogin =>
      !kDebugMode ||
      (_settingsReady && membershipGuestLoginDebugSettings.forceLogin);

  @override
  void initState() {
    super.initState();
    widget.service?.guestLoginRequestId.addListener(_schedule);
    if (kDebugMode) {
      membershipGuestLoginDebugSettings.listenable.addListener(_schedule);
      unawaited(_loadDebugSetting());
    }
    _schedule();
  }

  Future<void> _loadDebugSetting() async {
    await membershipGuestLoginDebugSettings.load();
    if (!mounted) return;
    _settingsReady = true;
    _schedule();
  }

  @override
  void didUpdateWidget(MembershipGuestLoginGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.service, oldWidget.service)) {
      oldWidget.service?.guestLoginRequestId.removeListener(_schedule);
      widget.service?.guestLoginRequestId.addListener(_schedule);
      _schedule();
    }
  }

  void _schedule() {
    if (!mounted || _showing || !_forceLogin) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_showing) unawaited(_show());
    });
    // Secure storage may finish while Home is idle, with no frame pending.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _show() async {
    if (!_forceLogin) return;
    final service = widget.service;
    final requestId = service?.guestLoginRequestId.value;
    final context = widget.navigatorKey.currentState?.overlay?.context;
    if (service == null || requestId == null || context == null) return;
    _showing = true;
    try {
      // The active checkout owns its success/OK dialog. A cached purchase on
      // startup goes straight to mandatory login, even without its old page.
      if (!mounted || !context.mounted) return;
      final login = widget.requestLogin;
      final loggedIn = login != null
          ? await login(context)
          : await ensureGenesisLogin(
              context,
              continueAfterLogin: true,
              isDismissible: false,
              forceLoginRequired: kDebugMode
                  ? membershipGuestLoginDebugSettings.listenable
                  : null,
            );
      if (loggedIn) await service.recover();
    } finally {
      _showing = false;
      if (mounted && service.guestLoginRequestId.value != null) _schedule();
    }
  }

  @override
  void dispose() {
    widget.service?.guestLoginRequestId.removeListener(_schedule);
    if (kDebugMode) {
      membershipGuestLoginDebugSettings.listenable.removeListener(_schedule);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

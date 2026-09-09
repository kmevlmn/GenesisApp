import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'common/genesis_bottom_sheet_panel.dart';
import 'common/genesis_center_toast.dart';
import 'common/genesis_modal_routes.dart';
import 'login_provider_button.dart';
import '../app/telemetry/genesis_telemetry.dart';
import '../platform/auth/auth_cancelled_exception.dart';
import '../platform/auth/auth_session.dart';
import '../ui/tokens/genesis_colors.dart';

class LoginSheet extends StatefulWidget {
  const LoginSheet({
    super.key,
    required this.onLogin,
    this.isDismissible = true,
  });

  final Future<bool> Function(IdentityProvider provider) onLogin;
  final bool isDismissible;

  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  IdentityProvider? _submittingProvider;

  Future<void> _submit(IdentityProvider provider) async {
    if (_submittingProvider != null) return;
    setState(() => _submittingProvider = provider);
    debugPrint('[Auth][LoginSheet] submit start');
    try {
      debugPrint('[Auth][LoginSheet] requesting sign-in');
      final ok = await widget.onLogin(provider);
      debugPrint('[Auth][LoginSheet] login result: $ok');
      if (!mounted) return;
      if (ok) {
        debugPrint('[Auth][LoginSheet] login success, closing sheet');
        Navigator.of(context).pop(true);
      } else {
        debugPrint('[Auth][LoginSheet] login failed: onLogin returned false');
        showGenesisToast(context, 'Sign-in failed');
      }
    } on AuthCancelledException {
      debugPrint('[Auth][LoginSheet] login cancelled');
      GenesisTelemetry.event(
        'login_cancel',
        category: 'auth',
        data: <String, Object?>{'provider': provider.name},
      );
    } catch (e, st) {
      debugPrint('[Auth][LoginSheet] login exception: $e');
      debugPrint('[Auth][LoginSheet] stacktrace:\n$st');
      if (!mounted) return;
      final message = e.toString().trim();
      showGenesisToast(context, message.isEmpty ? 'Sign-in failed' : message);
    } finally {
      debugPrint('[Auth][LoginSheet] submit end');
      if (mounted) setState(() => _submittingProvider = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height - media.padding.top - 18;
    final targetHeight = maxHeight < 342 ? maxHeight : 342.0;

    return PopScope(
      canPop: widget.isDismissible,
      child: GenesisBottomSheetPanel(
        title: 'Sign up to continue',
        height: targetHeight,
        trailing: widget.isDismissible
            ? GenesisBottomSheetCloseButton(
                onPressed: _submittingProvider != null
                    ? null
                    : () {
                        GenesisTelemetry.event(
                          'login_cancel',
                          category: 'auth',
                          data: const <String, Object?>{
                            'source': 'close_button',
                          },
                        );
                        Navigator.of(context).pop(false);
                      },
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: double.infinity,
              child: Text(
                'Sign up and get 250 Gems!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: GenesisColors.brand,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 12),
            LoginProviderButtons(
              loggingInProvider: _submittingProvider,
              onLogin: _submit,
              spacing: 12,
            ),
            const SizedBox(height: 14),
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: LoginLegalText(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showLoginSheet({
  required BuildContext context,
  required Future<bool> Function(IdentityProvider provider) onLogin,
  bool isDismissible = true,
  ValueListenable<bool>? forceLoginRequired,
}) async {
  if (forceLoginRequired?.value == false) return false;
  // Forget the field's focus before pushing the route so closing login cannot
  // restore it and briefly reopen the keyboard.
  FocusManager.instance.primaryFocus?.unfocus();
  ModalRoute<bool>? loginRoute;
  void dismissWhenNoLongerRequired() {
    if (forceLoginRequired?.value != false) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (forceLoginRequired?.value != false) return;
      final route = loginRoute;
      final navigator = route?.navigator;
      if (route == null || !route.isActive || navigator == null) return;
      // Debug Page may be above login: dismiss only this login route.
      if (route.isCurrent) {
        navigator.pop(false);
      } else {
        navigator.removeRoute(route, false);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  forceLoginRequired?.addListener(dismissWhenNoLongerRequired);
  try {
    final loggedIn = await showGenesisModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      useRootNavigator: !isDismissible,
      builder: (context) {
        loginRoute = ModalRoute.of<bool>(context);
        dismissWhenNoLongerRequired();
        return LoginSheet(onLogin: onLogin, isDismissible: isDismissible);
      },
    );
    return loggedIn == true;
  } finally {
    forceLoginRequired?.removeListener(dismissWhenNoLongerRequired);
  }
}

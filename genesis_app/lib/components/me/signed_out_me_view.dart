import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';
import '../../app/debug_floating_button_unlock.dart';
import '../../platform/auth/auth_session.dart';
import '../login_provider_button.dart';

class SignedOutMeView extends StatefulWidget {
  const SignedOutMeView({
    super.key,
    required this.loggingInProvider,
    required this.onLogin,
    this.reselectionListenable,
    this.isActiveListenable,
  });

  final IdentityProvider? loggingInProvider;
  final ValueChanged<IdentityProvider> onLogin;
  final ValueListenable<int>? reselectionListenable;
  final ValueListenable<bool>? isActiveListenable;

  @override
  State<SignedOutMeView> createState() => _SignedOutMeViewState();
}

class _SignedOutMeViewState extends State<SignedOutMeView> {
  static const int _debugButtonUnlockTapCount = 10;

  int _topTapCount = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.reselectionListenable?.addListener(_handleMainNavReselected);
    widget.isActiveListenable?.addListener(_handleTabActivityChanged);
  }

  @override
  void didUpdateWidget(covariant SignedOutMeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reselectionListenable != widget.reselectionListenable) {
      oldWidget.reselectionListenable?.removeListener(_handleMainNavReselected);
      widget.reselectionListenable?.addListener(_handleMainNavReselected);
    }
    if (oldWidget.isActiveListenable != widget.isActiveListenable) {
      oldWidget.isActiveListenable?.removeListener(_handleTabActivityChanged);
      widget.isActiveListenable?.addListener(_handleTabActivityChanged);
    }
  }

  @override
  void dispose() {
    widget.reselectionListenable?.removeListener(_handleMainNavReselected);
    widget.isActiveListenable?.removeListener(_handleTabActivityChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleTabActivityChanged() {
    if (widget.isActiveListenable?.value != false ||
        !_scrollController.hasClients) {
      return;
    }
    _scrollController.jumpTo(_scrollController.position.minScrollExtent);
  }

  void _handleMainNavReselected() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels <= position.minScrollExtent) return;
    unawaited(
      position.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _handleTopTap() {
    final nextCount = _topTapCount + 1;
    if (nextCount < _debugButtonUnlockTapCount) {
      _topTapCount = nextCount;
      return;
    }
    _topTapCount = 0;
    unawaited(requestGenesisDebugFloatingButtonUnlock(context));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 38),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          SizedBox(height: constraints.maxHeight * 0.15),
                          GestureDetector(
                            key: const ValueKey<String>(
                              'signed-out-debug-button-restore',
                            ),
                            behavior: HitTestBehavior.opaque,
                            onTap: _handleTopTap,
                            child: ClipRRect(
                              key: const Key('signed_out_worldo_logo'),
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                'assets/images/app_icon.png',
                                width: 96,
                                height: 96,
                                fit: BoxFit.contain,
                                semanticLabel: 'Worldo',
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          Text(
                            'LIVE YOUR WORLD',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 9,
                              color: dark
                                  ? GenesisColors.darkTextPrimary
                                  : const Color(0xFF7A7A7A),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Play world, create worldo, invite friends,\n'
                            'and continue them anywhere.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: dark
                                  ? GenesisColors.darkTextSecondary
                                  : const Color(0xFF666666),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          'Sign up and get 250 Gems!',
                          key: const ValueKey<String>('signed-out-gems-promo'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: dark
                                ? GenesisColors.redSecondary
                                : GenesisColors.redPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        LoginProviderButtons(
                          key: const ValueKey<String>(
                            'signed-out-login-buttons',
                          ),
                          loggingInProvider: widget.loggingInProvider,
                          onLogin: widget.onLogin,
                        ),
                        const SizedBox(height: 38),
                        const LoginLegalText(),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

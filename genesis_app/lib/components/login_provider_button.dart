import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../ui/tokens/genesis_colors.dart';
import '../app/config/app_flavor_config.dart';
import '../platform/auth/auth_session.dart';
import '../pages/legal/legal_document_page.dart';
import '../routers/app_router.dart';

const String _googleOauthIconAsset = 'assets/custom-icons/svg/login_google.svg';
const String _appleOauthIconAsset = 'assets/custom-icons/svg/login_apple.svg';
const double _loginProviderIconSlotSize = 36;
const double _googleProviderIconSize = 22;
const double _appleProviderIconSize = 22;
const double _loginProviderSpinnerSize = 22;

class LoginProviderButtons extends StatelessWidget {
  const LoginProviderButtons({
    super.key,
    required this.loggingInProvider,
    required this.onLogin,
    this.spacing = 18,
    this.showApple = AppFlavorConfig.currentSupportsAppleSignIn,
  });

  final IdentityProvider? loggingInProvider;
  final FutureOr<void> Function(IdentityProvider provider) onLogin;
  final double spacing;
  final bool showApple;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LoginProviderButton(
          provider: IdentityProvider.google,
          label: 'Continue with Google',
          onPressed: loggingInProvider == null
              ? () => onLogin(IdentityProvider.google)
              : null,
          isLoading: loggingInProvider == IdentityProvider.google,
        ),
        if (showApple) ...[
          SizedBox(height: spacing),
          LoginProviderButton(
            provider: IdentityProvider.apple,
            label: 'Continue with Apple',
            onPressed: loggingInProvider == null
                ? () => onLogin(IdentityProvider.apple)
                : null,
            isLoading: loggingInProvider == IdentityProvider.apple,
          ),
        ],
      ],
    );
  }
}

class LoginLegalText extends StatefulWidget {
  const LoginLegalText({super.key});

  @override
  State<LoginLegalText> createState() => _LoginLegalTextState();
}

class _LoginLegalTextState extends State<LoginLegalText> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;
  late final TapGestureRecognizer _eulaRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument(LegalDocument.terms);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument(LegalDocument.privacy);
    _eulaRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument(LegalDocument.eula);
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    _eulaRecognizer.dispose();
    super.dispose();
  }

  void _openDocument(LegalDocument document) {
    Navigator.of(
      context,
    ).pushNamed(RouteNames.legal, arguments: {'document': document.name});
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final baseStyle = TextStyle(
      fontSize: 12,
      height: 1.35,
      color: dark ? GenesisColors.darkTextTertiary : const Color(0xFF8A8A8A),
    );
    final linkStyle = TextStyle(
      fontSize: 12,
      height: 1.35,
      color: dark ? GenesisColors.darkTextSecondary : const Color(0xFF3E5B8A),
      decoration: TextDecoration.none,
    );
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'By continuing, you agree to our '),
          TextSpan(
            text: 'Terms',
            style: linkStyle,
            recognizer: _termsRecognizer,
          ),
          const TextSpan(text: ', '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: _privacyRecognizer,
          ),
          const TextSpan(text: ', and '),
          TextSpan(
            text: 'End User License Agreement',
            style: linkStyle,
            recognizer: _eulaRecognizer,
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class LoginProviderButton extends StatelessWidget {
  const LoginProviderButton({
    super.key,
    required this.provider,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.height = 56,
    this.borderRadius = 16,
    this.backgroundColor,
    this.foregroundColor,
  });

  final IdentityProvider provider;
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        this.backgroundColor ??
        (dark ? GenesisColors.darkFaintFill : const Color(0xFFF0F0F0));
    final foregroundColor =
        this.foregroundColor ??
        (dark ? GenesisColors.darkTextPrimary : Colors.black);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          disabledBackgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledForegroundColor: dark
              ? GenesisColors.darkTextTertiary
              : foregroundColor.withValues(alpha: 0.55),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          alignment: Alignment.center,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: _loginProviderIconSlotSize,
                  child: Center(
                    child: isLoading
                        ? SizedBox.square(
                            dimension: _loginProviderSpinnerSize,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: dark
                                  ? GenesisColors.darkTextSecondary
                                  : foregroundColor.withValues(alpha: 0.75),
                            ),
                          )
                        : LoginProviderIcon(provider: provider),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    height: 1.1,
                    color: foregroundColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LoginProviderIcon extends StatelessWidget {
  const LoginProviderIcon({super.key, required this.provider});

  final IdentityProvider provider;

  @override
  Widget build(BuildContext context) {
    return switch (provider) {
      IdentityProvider.google => SvgPicture.asset(
        _googleOauthIconAsset,
        width: _googleProviderIconSize,
        height: _googleProviderIconSize,
        fit: BoxFit.contain,
      ),
      IdentityProvider.apple => SvgPicture.asset(
        _appleOauthIconAsset,
        colorFilter: Theme.of(context).brightness == Brightness.dark
            ? const ColorFilter.mode(
                GenesisColors.darkTextPrimary,
                BlendMode.srcIn,
              )
            : null,
        width: _appleProviderIconSize,
        height: _appleProviderIconSize,
        fit: BoxFit.contain,
      ),
    };
  }
}

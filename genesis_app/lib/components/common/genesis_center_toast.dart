import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';
import '../../ui/tokens/genesis_typography.dart';

OverlayEntry? _currentGenesisToast;
Timer? _currentGenesisToastTimer;

void showGenesisToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
  Brightness? brightness,
}) {
  final trimmedMessage = message.trim();
  if (trimmedMessage.isEmpty) return;

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  showGenesisToastInOverlay(
    overlay,
    trimmedMessage,
    duration: duration,
    brightness: brightness ?? Theme.of(context).brightness,
  );
}

void showGenesisToastInOverlay(
  OverlayState overlay,
  String message, {
  Duration duration = const Duration(seconds: 2),
  Brightness brightness = Brightness.light,
}) {
  final trimmedMessage = message.trim();
  if (trimmedMessage.isEmpty) return;
  final isDark = brightness == Brightness.dark;

  _currentGenesisToastTimer?.cancel();
  _currentGenesisToast?.remove();

  final entry = OverlayEntry(
    builder: (context) {
      return Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isDark
                      ? GenesisColors.darkFaintSurface
                      : Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(8),
                  border: isDark
                      ? Border.all(color: GenesisColors.darkFaintFill)
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    trimmedMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      inherit: false,
                      fontFamily: GenesisTypography.fontFamily,
                      fontFamilyFallback: GenesisTypography.fontFamilyFallback,
                      color: isDark
                          ? GenesisColors.darkTextPrimary
                          : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  _currentGenesisToast = entry;
  overlay.insert(entry);
  _currentGenesisToastTimer = Timer(duration, () {
    if (_currentGenesisToast == entry) {
      _currentGenesisToast = null;
      _currentGenesisToastTimer = null;
    }
    entry.remove();
  });
}

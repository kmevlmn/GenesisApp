import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ui/components/genesis_soft_italic_text.dart';
import '../ui/tokens/genesis_colors.dart';
import '../ui/tokens/genesis_typography.dart';

/// Marks world content that was added since the user's previous visit.
class WorldNewBadge extends StatelessWidget {
  const WorldNewBadge({super.key, this.compact = false});

  static const double compactWidth = 28;
  static const double compactHeight = 14;
  static const double width = 36;
  static const double height = 16;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'New',
      excludeSemantics: true,
      child: SizedBox(
        width: compact ? compactWidth : width,
        height: compact ? compactHeight : height,
        child: Transform.translate(
          offset: compact ? Offset.zero : const Offset(0, 1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: GenesisColors.brand,
              borderRadius: BorderRadius.all(Radius.circular(compact ? 3 : 4)),
            ),
            child: Center(
              child: GenesisSoftItalicText(
                'New',
                maxLines: 1,
                style: TextStyle(
                  inherit: false,
                  fontFamily: GenesisTypography.fontFamily,
                  fontFamilyFallback: GenesisTypography.fontFamilyFallback,
                  color: GenesisColors.darkTextPrimary,
                  fontSize: 9.5,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  fontVariations: const <ui.FontVariation>[
                    ui.FontVariation('wght', 800),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

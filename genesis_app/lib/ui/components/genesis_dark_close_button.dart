import 'package:flutter/material.dart';

import '../tokens/genesis_colors.dart';

/// Standard circular close action for dark sheets and panels.
class GenesisDarkCloseButton extends StatelessWidget {
  const GenesisDarkCloseButton({super.key, required this.onPressed});

  static const double dimension = 28;
  static const double iconSize = 17;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: dimension,
      child: IconButton(
        tooltip: 'Close',
        onPressed: onPressed,
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(dimension),
          maximumSize: const Size.square(dimension),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: GenesisColors.darkFaintFill,
          disabledBackgroundColor: GenesisColors.darkFaintFill,
          foregroundColor: GenesisColors.darkTextPrimary,
          disabledForegroundColor: GenesisColors.darkTextTertiary,
          shape: const CircleBorder(),
        ),
        icon: const Icon(Icons.close_rounded, size: iconSize),
      ),
    );
  }
}

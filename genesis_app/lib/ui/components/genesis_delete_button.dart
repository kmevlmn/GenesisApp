import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../tokens/genesis_colors.dart';

/// Shared delete control for image previews and editable cards.
class GenesisDeleteButton extends StatelessWidget {
  const GenesisDeleteButton({
    super.key,
    required this.onPressed,
    this.buttonKey,
    this.decorationKey,
    this.size = 24,
    this.iconSize = 14,
    this.enabled = true,
    this.onDisabledPressed,
  });

  static const String iconAsset = 'assets/custom-icons/svg/delete-icon.svg';

  final VoidCallback onPressed;
  final Key? buttonKey;
  final Key? decorationKey;
  final double size;
  final double iconSize;
  final bool enabled;
  final VoidCallback? onDisabledPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? null : onDisabledPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                key: decorationKey,
                decoration: BoxDecoration(
                  color: GenesisColors.darkFaintSurface,
                  border: Border.all(color: GenesisColors.darkFaintFill),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              IconButton(
                key: buttonKey,
                onPressed: enabled ? onPressed : null,
                padding: EdgeInsets.all((size - iconSize) / 2),
                constraints: BoxConstraints.tightFor(width: size, height: size),
                icon: SvgPicture.asset(
                  iconAsset,
                  width: iconSize,
                  height: iconSize,
                  colorFilter: const ColorFilter.mode(
                    GenesisColors.darkTextPrimary,
                    BlendMode.srcIn,
                  ),
                ),
                splashRadius: size / 2,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

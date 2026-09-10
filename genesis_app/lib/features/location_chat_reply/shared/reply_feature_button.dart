import '../../../ui/tokens/genesis_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Shared visual primitive. Feature directories own the semantic label, icon,
/// availability, and invocation policy.
class LocationChatReplyFeatureButton extends StatelessWidget {
  const LocationChatReplyFeatureButton({
    super.key,
    required this.label,
    required this.iconAsset,
    required this.onTap,
    this.expanded,
  });

  static const double size = 32;
  static const double iconSize = 17;

  final String label;
  final String iconAsset;
  final VoidCallback? onTap;
  final bool? expanded;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    enabled: onTap != null,
    button: true,
    expanded: expanded,
    child: Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: SvgPicture.asset(
              iconAsset,
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(
                onTap == null
                    ? GenesisColors.darkTextTertiary
                    : GenesisColors.darkTextPrimary,
                BlendMode.srcIn,
              ),
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    ),
  );
}

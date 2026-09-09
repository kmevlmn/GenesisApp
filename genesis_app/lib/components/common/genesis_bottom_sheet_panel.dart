import 'package:flutter/material.dart';

import '../../ui/components/genesis_dark_close_button.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/tokens/genesis_radii.dart';

class GenesisBottomSheetCloseButton extends StatelessWidget {
  const GenesisBottomSheetCloseButton({
    super.key,
    required this.onPressed,
    this.buttonKey,
  });

  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return GenesisDarkCloseButton(key: buttonKey, onPressed: onPressed);
    }
    return SizedBox.square(
      key: buttonKey,
      dimension: 24,
      child: IconButton(
        tooltip: 'Close',
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 24, height: 24),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(24),
          maximumSize: const Size.square(24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.close, size: 24, color: Color(0xFF111111)),
      ),
    );
  }
}

class GenesisBottomSheetPanel extends StatelessWidget {
  const GenesisBottomSheetPanel({
    super.key,
    required this.title,
    required this.height,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 14),
    this.titleBottomSpacing = 20,
    this.titleTextStyle,
    this.backgroundColor,
    this.maintainBottomViewPadding = false,
    this.showHeader = true,
  });

  static const BorderRadius borderRadius = GenesisRadii.sheet;

  static const TextStyle titleStyle = TextStyle(
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    color: Color(0xFF111111),
  );

  final String title;
  final double height;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;
  final double titleBottomSpacing;
  final TextStyle? titleTextStyle;
  final Color? backgroundColor;
  final bool maintainBottomViewPadding;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color:
          backgroundColor ??
          (dark ? GenesisColors.darkRaisedBackground : Colors.white),
      borderRadius: borderRadius,
      child: SafeArea(
        top: false,
        maintainBottomViewPadding: maintainBottomViewPadding,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHeader) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style:
                              titleTextStyle ??
                              (dark
                                  ? titleStyle.copyWith(
                                      color: GenesisColors.darkTextPrimary,
                                    )
                                  : titleStyle),
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
                  SizedBox(height: titleBottomSpacing),
                ],
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../app/telemetry/genesis_telemetry.dart';
import '../tokens/genesis_colors.dart';
import '../tokens/genesis_radii.dart';
import '../tokens/genesis_spacing.dart';
import '../tokens/genesis_typography.dart';

class GenesisPrimaryButton extends StatelessWidget {
  const GenesisPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.onDisabledPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.side,
    this.height,
    this.width,
    this.fullWidth = true,
    this.padding = const EdgeInsets.symmetric(horizontal: GenesisSpacing.page),
    this.fontWeight,
    this.fontSize,
    this.borderRadius,
    this.minimumSize,
    this.tapTargetSize,
    this.isLoading = false,
    this.loadingSize = 18,
    this.loadingStrokeWidth = 2,
    this.leadingIcon,
    this.iconGap = 8,
  });

  static const double defaultHeight = 42;
  static const BorderRadius defaultBorderRadius = GenesisRadii.button;
  static const TextStyle defaultTextStyle = TextStyle(
    fontFamily: GenesisTypography.fontFamily,
    fontFamilyFallback: GenesisTypography.fontFamilyFallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const Color defaultBackgroundColor = GenesisColors.brand;
  static const Color defaultForegroundColor = Colors.white;
  static const Color defaultDisabledBackgroundColor = GenesisColors.brandSoft;
  static const Color defaultDisabledForegroundColor = Colors.white;

  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onDisabledPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? disabledBackgroundColor;
  final Color? disabledForegroundColor;
  final BorderSide? side;
  final double? height;
  final double? width;
  final bool fullWidth;
  final EdgeInsetsGeometry padding;
  final FontWeight? fontWeight;
  final double? fontSize;
  final BorderRadius? borderRadius;
  final Size? minimumSize;
  final MaterialTapTargetSize? tapTargetSize;
  final bool isLoading;
  final double loadingSize;
  final double loadingStrokeWidth;
  final Widget? leadingIcon;
  final double iconGap;

  @override
  Widget build(BuildContext context) {
    final disabled = isLoading || onPressed == null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final resolvedDisabledBackground =
        disabledBackgroundColor ??
        (dark
            ? GenesisColors.darkButtonDisabledBackground
            : defaultDisabledBackgroundColor);
    final resolvedDisabledForeground =
        disabledForegroundColor ??
        (dark
            ? GenesisColors.darkButtonDisabledForeground
            : defaultDisabledForegroundColor);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled && onDisabledPressed != null
          ? () {
              GenesisTelemetry.click(
                actionId: 'button.primary.${_actionSlug(label)}',
                component: 'GenesisPrimaryButton',
                enabled: false,
              );
              onDisabledPressed!();
            }
          : null,
      child: SizedBox(
        height: height ?? defaultHeight,
        width: width ?? (fullWidth ? double.infinity : null),
        child: FilledButton(
          onPressed: disabled
              ? null
              : () {
                  GenesisTelemetry.click(
                    actionId: 'button.primary.${_actionSlug(label)}',
                    component: 'GenesisPrimaryButton',
                    enabled: true,
                  );
                  onPressed!();
                },
          style: FilledButton.styleFrom(
            backgroundColor: backgroundColor ?? defaultBackgroundColor,
            foregroundColor: foregroundColor ?? defaultForegroundColor,
            disabledBackgroundColor: resolvedDisabledBackground,
            disabledForegroundColor: resolvedDisabledForeground,
            side: side,
            textStyle: defaultTextStyle.copyWith(
              fontSize: fontSize,
              fontWeight: fontWeight,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius ?? defaultBorderRadius,
            ),
            padding: padding,
            minimumSize: minimumSize,
            tapTargetSize: tapTargetSize,
          ),
          child: isLoading
              ? SizedBox.square(
                  dimension: loadingSize,
                  child: CircularProgressIndicator(
                    strokeWidth: loadingStrokeWidth,
                    color: resolvedDisabledForeground,
                  ),
                )
              : _PrimaryButtonLabel(
                  label: label,
                  leadingIcon: leadingIcon,
                  iconGap: iconGap,
                ),
        ),
      ),
    );
  }
}

class _PrimaryButtonLabel extends StatelessWidget {
  const _PrimaryButtonLabel({
    required this.label,
    required this.leadingIcon,
    required this.iconGap,
  });

  final String label;
  final Widget? leadingIcon;
  final double iconGap;

  @override
  Widget build(BuildContext context) {
    final icon = leadingIcon;
    if (icon == null) {
      return Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        SizedBox(width: iconGap),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class GenesisSecondaryButton extends StatelessWidget {
  const GenesisSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.foregroundColor = const Color(0xFF111111),
    this.disabledForegroundColor,
    this.side = const BorderSide(color: Color(0xFFD9D9DF), width: 1.2),
    this.height,
    this.width,
    this.fontWeight,
    this.borderRadius,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? foregroundColor;
  final Color? disabledForegroundColor;
  final BorderSide? side;
  final double? height;
  final double? width;
  final FontWeight? fontWeight;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height ?? GenesisPrimaryButton.defaultHeight,
      width: width ?? double.infinity,
      child: OutlinedButton(
        onPressed: onPressed == null
            ? null
            : () {
                GenesisTelemetry.click(
                  actionId: 'button.secondary.${_actionSlug(label)}',
                  component: 'GenesisSecondaryButton',
                  enabled: true,
                );
                onPressed!();
              },
        style: OutlinedButton.styleFrom(
          foregroundColor: foregroundColor,
          disabledForegroundColor: disabledForegroundColor,
          side: side,
          textStyle: GenesisPrimaryButton.defaultTextStyle.copyWith(
            fontWeight: fontWeight,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
                borderRadius ?? GenesisPrimaryButton.defaultBorderRadius,
          ),
          padding: const EdgeInsets.symmetric(horizontal: GenesisSpacing.page),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

String _actionSlug(String label) {
  final normalized = label
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return normalized.isEmpty ? 'unknown' : normalized;
}

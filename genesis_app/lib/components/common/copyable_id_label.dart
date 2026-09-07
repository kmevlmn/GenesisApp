import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'genesis_center_toast.dart';

const double genesisCopyableIdIconSize = 14;

class CopyableIdLabel extends StatelessWidget {
  const CopyableIdLabel({
    super.key,
    required this.label,
    required this.value,
    this.displayValue,
    this.showCopyIcon = true,
    this.enabled = true,
    this.customTextStyle,
    this.customIconColor,
  });

  static const TextStyle textStyle = TextStyle(
    fontSize: 12,
    height: 1.1,
    fontWeight: FontWeight.w400,
    color: Color(0xFF666666),
  );

  static const Color iconColor = Color(0xFF666666);

  final String label;
  final String value;
  final String? displayValue;
  final bool showCopyIcon;
  final bool enabled;
  final TextStyle? customTextStyle;
  final Color? customIconColor;

  @override
  Widget build(BuildContext context) {
    final resolvedDisplayValue = displayValue ?? formatCopyableIdValue(value);
    final normalizedLabel = label.trim().toUpperCase();
    return GenesisInlineMetaLabel(
      text: '$normalizedLabel: $resolvedDisplayValue',
      onTap: enabled
          ? () => _copy(context, resolvedDisplayValue, normalizedLabel)
          : null,
      style: customTextStyle ?? CopyableIdLabel.textStyle,
      trailingIcon: enabled && showCopyIcon ? Icons.copy_outlined : null,
      trailingIconColor: customIconColor ?? CopyableIdLabel.iconColor,
      trailingIconSize: genesisCopyableIdIconSize,
      trailingGap: 6,
    );
  }

  Future<void> _copy(
    BuildContext context,
    String displayValue,
    String normalizedLabel,
  ) async {
    await Clipboard.setData(ClipboardData(text: displayValue));
    if (!context.mounted) return;
    showGenesisToast(context, '$normalizedLabel copied');
  }
}

class GenesisInlineMetaLabel extends StatelessWidget {
  const GenesisInlineMetaLabel({
    super.key,
    required this.text,
    this.onTap,
    this.style = CopyableIdLabel.textStyle,
    this.textAlign = TextAlign.left,
    this.trailing,
    this.trailingIcon,
    this.trailingIconColor = CopyableIdLabel.iconColor,
    this.trailingIconSize = 16,
    this.trailingGap = 4,
  });

  final String text;
  final VoidCallback? onTap;
  final TextStyle style;
  final TextAlign textAlign;

  /// Optional content between the label and its navigation/action icon.
  final Widget? trailing;
  final IconData? trailingIcon;
  final Color trailingIconColor;
  final double trailingIconSize;
  final double trailingGap;

  @override
  Widget build(BuildContext context) {
    final trailingIcon = this.trailingIcon;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: trailingIconSize),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  text,
                  textAlign: textAlign,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[
                SizedBox(width: trailingGap),
                trailing!,
              ],
              if (trailingIcon != null) ...[
                SizedBox(width: trailingGap),
                Icon(
                  trailingIcon,
                  size: trailingIconSize,
                  color: trailingIconColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GenesisPairedMetaRow extends StatelessWidget {
  const GenesisPairedMetaRow({
    super.key,
    required this.leftLabel,
    required this.leftValue,
    this.leftDisplayValue,
    this.leftCopyEnabled = true,
    this.leftStyle = CopyableIdLabel.textStyle,
    this.leftIconColor = CopyableIdLabel.iconColor,
    required this.rightText,
    this.rightOnTap,
    this.rightStyle = CopyableIdLabel.textStyle,
    this.rightIconColor = CopyableIdLabel.iconColor,
  });

  final String leftLabel;
  final String leftValue;
  final String? leftDisplayValue;
  final bool leftCopyEnabled;
  final TextStyle leftStyle;
  final Color leftIconColor;
  final String rightText;
  final VoidCallback? rightOnTap;
  final TextStyle rightStyle;
  final Color rightIconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: CopyableIdLabel(
            label: leftLabel,
            value: leftValue,
            displayValue: leftDisplayValue,
            enabled: leftCopyEnabled,
            customTextStyle: leftStyle,
            customIconColor: leftIconColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            heightFactor: 1,
            child: GenesisInlineMetaLabel(
              text: rightText,
              onTap: rightOnTap,
              style: rightStyle,
              textAlign: TextAlign.right,
              trailingIcon: rightOnTap == null ? null : Icons.chevron_right,
              trailingIconColor: rightIconColor,
              trailingIconSize: genesisCopyableIdIconSize,
              trailingGap: 4,
            ),
          ),
        ),
      ],
    );
  }
}

String formatCopyableIdValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '-';
  return trimmed.substring(0, 1).toLowerCase() + trimmed.substring(1);
}

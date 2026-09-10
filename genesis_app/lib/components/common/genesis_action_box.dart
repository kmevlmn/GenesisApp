import 'dart:ui' show ImageFilter;

import '../../ui/tokens/genesis_blur.dart';

import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import 'genesis_modal_routes.dart';

const Color _genesisActionBoxText = GenesisColors.darkTextPrimary;
const Color _genesisActionBoxAccent = GenesisColors.redSecondary;
const Color _genesisActionBoxDivider = GenesisColors.darkFaintFill;

class GenesisActionBoxAction<T> {
  const GenesisActionBoxAction({
    required this.label,
    required this.value,
    this.color,
    this.enabled = true,
    this.trailing,
    this.fontWeight = FontWeight.w600,
  });

  final String label;
  final T value;
  final Color? color;
  final bool enabled;
  final Widget? trailing;
  final FontWeight fontWeight;
}

Future<T?> showGenesisActionBox<T>({
  required BuildContext context,
  required String title,
  required List<GenesisActionBoxAction<T>> actions,
  Widget? content,
  Widget? titleWidget,
  Widget? titleContent,
  double titleContentSpacing = 8,
  double titleHorizontalPadding = 18,
  String cancelLabel = 'Cancel',
  bool showCancel = true,
  bool detachCancel = false,
  double? titleHeight = GenesisActionBox.defaultTitleHeight,
  double actionRowHeight = GenesisActionBox.defaultRowHeight,
  double cancelRowHeight = GenesisActionBox.defaultRowHeight,
}) {
  return showGenesisDialog<T>(
    context: context,
    barrierColor: const Color(0x52000000),
    builder: (dialogContext) {
      return GenesisActionBox<T>(
        title: title,
        content: content,
        titleWidget: titleWidget,
        titleContent: titleContent,
        titleContentSpacing: titleContentSpacing,
        titleHorizontalPadding: titleHorizontalPadding,
        actions: actions,
        cancelLabel: cancelLabel,
        showCancel: showCancel,
        detachCancel: detachCancel,
        titleHeight: titleHeight,
        actionRowHeight: actionRowHeight,
        cancelRowHeight: cancelRowHeight,
        onActionSelected: (value) => Navigator.of(dialogContext).pop(value),
        onCancel: () => Navigator.of(dialogContext).pop(),
      );
    },
  );
}

class GenesisActionBox<T> extends StatelessWidget {
  const GenesisActionBox({
    super.key,
    required this.title,
    required this.actions,
    required this.onActionSelected,
    required this.onCancel,
    this.content,
    this.titleWidget,
    this.titleContent,
    this.titleContentSpacing = 8,
    this.titleHorizontalPadding = 18,
    this.cancelLabel = 'Cancel',
    this.showCancel = true,
    this.detachCancel = false,
    this.titleHeight = defaultTitleHeight,
    this.actionRowHeight = defaultRowHeight,
    this.cancelRowHeight = defaultRowHeight,
  });

  static const double defaultRowHeight = 51;
  static const double defaultTitleHeight = 82;
  static const double _maxWidth = 800;

  final String title;
  final Widget? content;
  final Widget? titleWidget;
  final Widget? titleContent;
  final double titleContentSpacing;
  final double titleHorizontalPadding;
  final List<GenesisActionBoxAction<T>> actions;
  final ValueChanged<T> onActionSelected;
  final VoidCallback onCancel;
  final String cancelLabel;
  final bool showCancel;
  final bool detachCancel;
  final double? titleHeight;
  final double actionRowHeight;
  final double cancelRowHeight;

  @override
  Widget build(BuildContext context) {
    final useDetachedCancelStyle =
        showCancel && (detachCancel || actions.length > 1);
    final dialogWidth = (MediaQuery.sizeOf(context).width * 0.7)
        .clamp(0.0, _maxWidth)
        .toDouble();
    return GenesisDarkTheme(
      child: Dialog(
        elevation: 0,
        insetPadding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: dialogWidth),
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: dialogWidth,
          child: useDetachedCancelStyle
              ? _buildDetachedCancelStyle()
              : _buildAttachedCancelStyle(),
        ),
      ),
    );
  }

  Widget _buildAttachedCancelStyle() {
    return _ActionBoxSurface(
      key: const ValueKey('genesis-action-box-attached-cancel'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TitleRow(
            title: title,
            height: titleHeight,
            titleWidget: titleWidget,
            content: titleContent,
            contentSpacing: titleContentSpacing,
            horizontalPadding: titleHorizontalPadding,
          ),
          if (content case final content?)
            DefaultTextStyle.merge(
              style: const TextStyle(color: GenesisColors.darkTextSecondary),
              child: content,
            ),
          if (actions.isNotEmpty) ...[
            const _Divider(),
            for (var index = 0; index < actions.length; index++) ...[
              _ActionRow<T>(
                action: actions[index],
                height: actionRowHeight,
                isPreferred: true,
                onSelected: onActionSelected,
              ),
              if (showCancel || index != actions.length - 1) const _Divider(),
            ],
          ],
          if (showCancel)
            _CancelRow(
              label: cancelLabel,
              height: cancelRowHeight,
              onCancel: onCancel,
            ),
        ],
      ),
    );
  }

  Widget _buildDetachedCancelStyle() {
    return Column(
      key: const ValueKey('genesis-action-box-detached-cancel'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionBoxSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TitleRow(
                title: title,
                height: titleHeight,
                titleWidget: titleWidget,
                content: titleContent,
                contentSpacing: titleContentSpacing,
                horizontalPadding: titleHorizontalPadding,
              ),
              if (content case final content?)
                DefaultTextStyle.merge(
                  style: const TextStyle(
                    color: GenesisColors.darkTextSecondary,
                  ),
                  child: content,
                ),
              if (actions.isNotEmpty) ...[
                const _Divider(),
                for (var index = 0; index < actions.length; index++) ...[
                  _ActionRow<T>(
                    action: actions[index],
                    height: actionRowHeight,
                    isPreferred: index == 0,
                    onSelected: onActionSelected,
                  ),
                  if (index != actions.length - 1) const _Divider(),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ActionBoxSurface(
          child: _CancelRow(
            label: cancelLabel,
            height: cancelRowHeight,
            onCancel: onCancel,
          ),
        ),
      ],
    );
  }
}

/// Clip the backdrop blur to each panel and keep text and actions opaque.
class _ActionBoxSurface extends StatelessWidget {
  const _ActionBoxSurface({super.key, required this.child});

  static const _borderRadius = BorderRadius.all(Radius.circular(18));
  static final _blur = ImageFilter.blur(
    sigmaX: GenesisBlur.strong,
    sigmaY: GenesisBlur.strong,
  );

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: _borderRadius,
      child: BackdropFilter(
        filter: _blur,
        child: Material(
          color: GenesisColors.darkOverlayBackground,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: _borderRadius,
            side: BorderSide(color: GenesisColors.darkFaintFill, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    required this.height,
    required this.titleWidget,
    required this.content,
    required this.contentSpacing,
    required this.horizontalPadding,
  });

  final String title;
  final double? height;
  final Widget? titleWidget;
  final Widget? content;
  final double contentSpacing;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final titleBody = Align(
      alignment: Alignment.center,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            titleWidget ??
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _genesisActionBoxText,
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            if (content case final content?) ...[
              SizedBox(height: contentSpacing),
              DefaultTextStyle.merge(
                style: const TextStyle(color: GenesisColors.darkTextSecondary),
                child: content,
              ),
            ],
          ],
        ),
      ),
    );
    final fixedHeight = height;
    if (fixedHeight != null) {
      return SizedBox(
        key: const ValueKey('genesis-action-box-title-row'),
        height: fixedHeight,
        width: double.infinity,
        child: titleBody,
      );
    }
    return ConstrainedBox(
      key: const ValueKey('genesis-action-box-title-row'),
      constraints: const BoxConstraints(
        minWidth: double.infinity,
        minHeight: GenesisActionBox.defaultTitleHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: titleBody,
      ),
    );
  }
}

class _ActionRow<T> extends StatelessWidget {
  const _ActionRow({
    required this.action,
    required this.height,
    required this.isPreferred,
    required this.onSelected,
  });

  final GenesisActionBoxAction<T> action;
  final double height;
  final bool isPreferred;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final color = !action.enabled
        ? GenesisColors.darkTextTertiary
        : action.color ??
              (isPreferred ? _genesisActionBoxAccent : _genesisActionBoxText);
    final label = Text(
      action.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 15,
        height: 1.2,
        fontWeight: action.fontWeight,
      ),
    );
    return InkWell(
      onTap: !action.enabled
          ? null
          : () {
              GenesisTelemetry.click(
                actionId: 'action_box.${_actionSlug(action.label)}',
                component: 'GenesisActionBoxAction',
                enabled: true,
                data: <String, Object?>{'label': action.label},
              );
              onSelected(action.value);
            },
      child: SizedBox(
        key: const ValueKey('genesis-action-box-action-row'),
        height: height,
        width: double.infinity,
        child: Align(
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: action.trailing == null
                ? label
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: label),
                      const SizedBox(width: 4),
                      action.trailing!,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _CancelRow extends StatelessWidget {
  const _CancelRow({
    required this.label,
    required this.height,
    required this.onCancel,
  });

  final String label;
  final double height;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        GenesisTelemetry.click(
          actionId: 'action_box.${_actionSlug(label)}',
          component: 'GenesisActionBoxCancel',
          enabled: true,
          data: <String, Object?>{'label': label},
        );
        onCancel();
      },
      child: SizedBox(
        key: const ValueKey('genesis-action-box-cancel-row'),
        height: height,
        width: double.infinity,
        child: Align(
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _genesisActionBoxText,
                fontSize: 15,
                height: 1.2,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
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

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: _genesisActionBoxDivider,
    );
  }
}

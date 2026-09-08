import 'package:flutter/material.dart';

import '../tokens/genesis_colors.dart';

Color? _indicatorColor(BuildContext context, Color? override) {
  return override ??
      (Theme.of(context).brightness == Brightness.dark
          ? GenesisColors.darkTextSecondary
          : null);
}

/// Shared pull-to-refresh appearance; scrolling and refresh callbacks stay local.
class GenesisRefreshIndicator extends StatelessWidget {
  const GenesisRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color,
    this.backgroundColor,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  final Widget child;
  final RefreshCallback onRefresh;
  final Color? color;
  final Color? backgroundColor;
  final ScrollNotificationPredicate notificationPredicate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      color: _indicatorColor(context, color),
      backgroundColor:
          backgroundColor ??
          (theme.brightness == Brightness.dark
              ? GenesisColors.darkRaisedBackground
              : theme.scaffoldBackgroundColor),
      notificationPredicate: notificationPredicate,
      onRefresh: onRefresh,
      child: child,
    );
  }
}

/// Inline loading uses the same foreground as pull-to-refresh, without a disc.
class GenesisLoadingIndicator extends StatelessWidget {
  const GenesisLoadingIndicator({
    super.key,
    this.strokeWidth = 2.4,
    this.color,
  });

  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CircularProgressIndicator(
      color: _indicatorColor(context, color),
      strokeWidth: strokeWidth,
    );
  }
}

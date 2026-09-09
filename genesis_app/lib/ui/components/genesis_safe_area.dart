import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum GenesisSystemNavigationMode { gesture, threeButton }

@immutable
class GenesisBottomSystemBarStyle {
  const GenesisBottomSystemBarStyle({
    this.color,
    this.transparentForGesture = true,
  });

  final Color? color;
  final bool transparentForGesture;

  GenesisBottomSystemBarStyle copyWith({
    Color? color,
    bool? transparentForGesture,
  }) {
    return GenesisBottomSystemBarStyle(
      color: color ?? this.color,
      transparentForGesture:
          transparentForGesture ?? this.transparentForGesture,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GenesisBottomSystemBarStyle &&
        other.color == color &&
        other.transparentForGesture == transparentForGesture;
  }

  @override
  int get hashCode => Object.hash(color, transparentForGesture);
}

class GenesisBottomSystemBarController {
  GenesisBottomSystemBarController._();

  static final ValueNotifier<GenesisBottomSystemBarStyle> listenable =
      ValueNotifier<GenesisBottomSystemBarStyle>(
        const GenesisBottomSystemBarStyle(),
      );

  static final List<_GenesisBottomSystemBarStyleEntry> _styleStack =
      <_GenesisBottomSystemBarStyleEntry>[];
  static bool _notifyScheduled = false;

  static Object push(GenesisBottomSystemBarStyle style) {
    final token = Object();
    _styleStack.add(_GenesisBottomSystemBarStyleEntry(token, style));
    _notify();
    return token;
  }

  static void replace(Object token, GenesisBottomSystemBarStyle style) {
    final index = _styleStack.indexWhere((entry) => entry.token == token);
    if (index < 0) return;
    _styleStack[index] = _GenesisBottomSystemBarStyleEntry(token, style);
    _notify();
  }

  static void pop(Object token) {
    _styleStack.removeWhere((entry) => entry.token == token);
    _notify();
  }

  static void _notify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      final nextStyle = _styleStack.isEmpty
          ? const GenesisBottomSystemBarStyle()
          : _styleStack.last.style;
      if (listenable.value != nextStyle) {
        listenable.value = nextStyle;
      }
    });
  }
}

class _GenesisBottomSystemBarStyleEntry {
  const _GenesisBottomSystemBarStyleEntry(this.token, this.style);

  final Object token;
  final GenesisBottomSystemBarStyle style;
}

class GenesisBottomSystemBarStyleScope extends StatefulWidget {
  const GenesisBottomSystemBarStyleScope({
    super.key,
    required this.style,
    required this.child,
  });

  final GenesisBottomSystemBarStyle style;
  final Widget child;

  @override
  State<GenesisBottomSystemBarStyleScope> createState() =>
      _GenesisBottomSystemBarStyleScopeState();
}

class _GenesisBottomSystemBarStyleScopeState
    extends State<GenesisBottomSystemBarStyleScope> {
  Object? _token;

  @override
  void initState() {
    super.initState();
    _token = GenesisBottomSystemBarController.push(widget.style);
  }

  @override
  void didUpdateWidget(covariant GenesisBottomSystemBarStyleScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    final token = _token;
    if (token != null && widget.style != oldWidget.style) {
      GenesisBottomSystemBarController.replace(token, widget.style);
    }
  }

  @override
  void dispose() {
    final token = _token;
    if (token != null) {
      GenesisBottomSystemBarController.pop(token);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class GenesisSafeAreaInsets {
  const GenesisSafeAreaInsets._();

  static double top(BuildContext context) {
    return MediaQuery.viewPaddingOf(context).top;
  }

  static double bottom(BuildContext context, {double minimum = 0}) {
    return math.max(MediaQuery.viewPaddingOf(context).bottom, minimum);
  }
}

class GenesisTopSafeArea extends StatelessWidget {
  const GenesisTopSafeArea({
    super.key,
    required this.child,
    this.backgroundColor,
  });

  final Widget child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final topPadding = GenesisSafeAreaInsets.top(context);
    final paddedChild = Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: child,
    );

    if (backgroundColor == null) {
      return paddedChild;
    }
    return ColoredBox(color: backgroundColor!, child: paddedChild);
  }
}

class GenesisBottomSafePadding extends StatelessWidget {
  const GenesisBottomSafePadding({
    super.key,
    required this.child,
    this.minimum = 0,
  });

  final Widget child;
  final double minimum;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: GenesisSafeAreaInsets.bottom(context, minimum: minimum),
      ),
      child: child,
    );
  }
}

class GenesisBottomSystemBarBoundary extends StatelessWidget {
  const GenesisBottomSystemBarBoundary({
    super.key,
    required this.child,
    this.backgroundColor,
  });

  final Widget child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewPadding.bottom;
    if (bottomInset <= 0) return child;

    final navigationMode = _navigationModeOf(mediaQuery);

    final childMediaQuery =
        navigationMode == GenesisSystemNavigationMode.gesture
        ? mediaQuery
        : mediaQuery.copyWith(
            padding: mediaQuery.padding.copyWith(bottom: 0),
            viewPadding: mediaQuery.viewPadding.copyWith(bottom: 0),
            systemGestureInsets: mediaQuery.systemGestureInsets.copyWith(
              bottom: 0,
            ),
          );

    return ValueListenableBuilder<GenesisBottomSystemBarStyle>(
      valueListenable: GenesisBottomSystemBarController.listenable,
      builder: (context, style, _) {
        final resolvedBackgroundColor =
            backgroundColor ??
            style.color ??
            Theme.of(context).scaffoldBackgroundColor;
        final transparent =
            navigationMode == GenesisSystemNavigationMode.gesture &&
            style.transparentForGesture;

        return ColoredBox(
          color: resolvedBackgroundColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                bottom: navigationMode == GenesisSystemNavigationMode.gesture
                    ? 0
                    : bottomInset,
                child: MediaQuery(data: childMediaQuery, child: child),
              ),
              if (!transparent)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: bottomInset,
                  child: IgnorePointer(
                    child: AnnotatedRegion<SystemUiOverlayStyle>(
                      value: SystemUiOverlayStyle(
                        systemNavigationBarIconBrightness:
                            ThemeData.estimateBrightnessForColor(
                                  resolvedBackgroundColor,
                                ) ==
                                Brightness.dark
                            ? Brightness.light
                            : Brightness.dark,
                      ),
                      child: ColoredBox(
                        key: const ValueKey<String>(
                          'genesis-bottom-system-bar-opaque-overlay',
                        ),
                        color: resolvedBackgroundColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  GenesisSystemNavigationMode _navigationModeOf(MediaQueryData mediaQuery) {
    final hasHorizontalBackGesture =
        mediaQuery.systemGestureInsets.left > 0 ||
        mediaQuery.systemGestureInsets.right > 0;
    if (hasHorizontalBackGesture) return GenesisSystemNavigationMode.gesture;

    final hasLikelyThreeButtonBottomBar =
        mediaQuery.viewPadding.bottom >= 32 &&
        mediaQuery.systemGestureInsets.bottom >= 32;
    if (hasLikelyThreeButtonBottomBar) {
      return GenesisSystemNavigationMode.threeButton;
    }

    return GenesisSystemNavigationMode.gesture;
  }
}

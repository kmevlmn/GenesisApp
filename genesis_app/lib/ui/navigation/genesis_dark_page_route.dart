import 'package:flutter/material.dart';

import '../tokens/genesis_colors.dart';

/// Material route whose Android transition fallback matches dark page surfaces.
class GenesisDarkPageRoute<T> extends MaterialPageRoute<T> {
  GenesisDarkPageRoute({required super.builder, super.settings});

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _darkDelegatedTransition;

  static Widget? _darkDelegatedTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    if (Theme.of(context).platform == TargetPlatform.android) {
      // The outgoing route also paints a background while fading away.
      return const FadeForwardsPageTransitionsBuilder(
        backgroundColor: GenesisColors.darkBackground,
      ).delegatedTransition!(
        context,
        animation,
        secondaryAnimation,
        allowSnapshotting,
        child,
      );
    }
    return Theme.of(context).pageTransitionsTheme
        .delegatedTransition(Theme.of(context).platform)
        ?.call(
          context,
          animation,
          secondaryAnimation,
          allowSnapshotting,
          child,
        );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Route transitions live above the page's local dark Theme. Supply the
    // dark fallback explicitly so Android never paints the app's light surface.
    if (Theme.of(context).platform == TargetPlatform.android) {
      return const PredictiveBackPageTransitionsBuilder(
        fallbackColor: GenesisColors.darkBackground,
      ).buildTransitions(this, context, animation, secondaryAnimation, child);
    }
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

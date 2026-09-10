import 'package:flutter/material.dart';

import 'genesis_theme.dart';

/// Local dark scope using the same defaults as the application root.
class GenesisDarkTheme extends StatelessWidget {
  const GenesisDarkTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: GenesisTheme.asDark(Theme.of(context)), child: child);
}

import 'package:flutter/material.dart';

import '../ui/components/genesis_count_badge.dart';

/// Compact event count shown beside a map location label.
class WorldEventCountBadge extends StatelessWidget {
  const WorldEventCountBadge({super.key, required this.count});

  static const double minWidth = 14;
  static const double height = 14;
  static const double borderRadius = height / 2;
  static const double horizontalPadding = 4;
  static const double fontSize = 9.5;

  final int count;

  @override
  Widget build(BuildContext context) {
    return GenesisCountBadge(
      count: count,
      height: height,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      horizontalPadding: horizontalPadding,
    );
  }
}

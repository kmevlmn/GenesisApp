import 'package:flutter/material.dart';

import 'genesis_count_badge.dart';

class GenesisUnreadBadge extends StatelessWidget {
  const GenesisUnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return GenesisCountBadge(count: count);
  }
}

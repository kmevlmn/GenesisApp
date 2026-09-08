import 'package:flutter/material.dart';

import '../tokens/genesis_spacing.dart';
import 'genesis_page_title.dart';
import 'genesis_safe_area.dart';
import 'genesis_search_field.dart';

class GenesisPageHeader extends StatelessWidget {
  const GenesisPageHeader({
    super.key,
    required this.title,
    this.horizontalPadding = GenesisSpacing.page,
    this.topPadding = GenesisSpacing.md,
    this.showSearchField = true,
    this.searchHintText = genesisSearchHintText,
    this.onSearchTap,
  });

  final String title;
  final double horizontalPadding;
  final double topPadding;
  final bool showSearchField;
  final String searchHintText;
  final VoidCallback? onSearchTap;

  @override
  Widget build(BuildContext context) {
    return GenesisTopSafeArea(
      backgroundColor: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          topPadding,
          horizontalPadding,
          0,
        ),
        child: Column(
          children: [
            GenesisPageTitle(text: title),
            if (showSearchField) ...[
              const SizedBox(height: GenesisSpacing.sm),
              GenesisSearchField(hintText: searchHintText, onTap: onSearchTap),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../ui/components/genesis_refresh_indicator.dart';
import '../../ui/tokens/genesis_colors.dart';
import 'gem_purchase_catalog.dart';

/// Shared loading, placeholder and retry states for purchase pages and sheets.
class GemPurchaseLoading extends StatelessWidget {
  const GemPurchaseLoading({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox.square(
      dimension: size,
      child: const GenesisLoadingIndicator(),
    ),
  );
}

class GemProductGridSkeleton extends StatelessWidget {
  const GemProductGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        mainAxisExtent: kGemProductCardHeight,
      ),
      itemBuilder: (_, _) => Container(
        decoration: BoxDecoration(
          color: GenesisColors.darkFaintFill,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class GemPurchaseState extends StatelessWidget {
  const GemPurchaseState({
    super.key,
    required this.message,
    this.onRetry,
    this.height = 160,
  });

  final String message;
  final VoidCallback? onRetry;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GenesisColors.darkTextTertiary,
              fontSize: 13,
              height: 18 / 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: GenesisColors.darkTextSecondary,
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

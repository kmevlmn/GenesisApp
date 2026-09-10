import 'package:flutter/material.dart';

import '../tokens/genesis_image_radii.dart';
import 'genesis_list_image.dart';

/// Shared outer layout for World cards shown in list contexts.
///
/// The caller owns the content on the right so each page can retain its own
/// metadata rows while sharing the same cover geometry and horizontal rhythm.
class GenesisWorldListCardLayout extends StatelessWidget {
  const GenesisWorldListCardLayout({
    super.key,
    required this.imageUrl,
    required this.content,
    this.placeholder,
    this.thumbnailBorderRadius = GenesisImageRadii.contentValue,
  });

  static const double coverWidth = 60;
  static const double coverHeight = 90;
  static const double contentGap = 14;

  final String imageUrl;
  final Widget content;
  final Widget? placeholder;
  final double thumbnailBorderRadius;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GenesisListImage(
          imageUrl: imageUrl,
          placeholder: placeholder,
          width: coverWidth,
          height: coverHeight,
          borderRadius: BorderRadius.circular(thumbnailBorderRadius),
          maxDevicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
        const SizedBox(width: contentGap),
        Expanded(child: content),
      ],
    );
  }
}

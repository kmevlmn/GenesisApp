import 'package:flutter/material.dart';

import '../../app/config/genesis_image_config.dart';
import '../tokens/genesis_avatar_radii.dart';
import 'genesis_avatar.dart';

class GenesisCharacterAvatar extends StatelessWidget {
  const GenesisCharacterAvatar({
    super.key,
    required this.url,
    required this.name,
    this.size = 48,
    this.borderRadius = GenesisAvatarRadii.character,
    this.boxShadow = const <BoxShadow>[],
    this.showFallbackWhileLoading = false,
    this.showFallbackWhenUnavailable = true,
    this.border,
    this.maxDevicePixelRatio = GenesisImageConfig.maxDevicePixelRatio,
  });

  final String url;
  final String name;
  final double size;
  final double borderRadius;
  final List<BoxShadow> boxShadow;
  final bool showFallbackWhileLoading;
  final bool showFallbackWhenUnavailable;
  final BoxBorder? border;
  final double maxDevicePixelRatio;

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = url.trim();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: boxShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: SizedBox(
                width: size,
                height: size,
                child: GenesisAvatar(
                  url: resolvedUrl,
                  name: name,
                  size: size,
                  borderRadius: borderRadius,
                  showFallbackWhileLoading: showFallbackWhileLoading,
                  showFallbackWhenUnavailable: showFallbackWhenUnavailable,
                  maxDevicePixelRatio: maxDevicePixelRatio,
                ),
              ),
            ),
          ),
          if (border != null)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: border,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

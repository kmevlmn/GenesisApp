import 'package:flutter/material.dart';

import '../../app/config/genesis_image_config.dart';
import 'genesis_static_network_image.dart';
import '../tokens/genesis_image_radii.dart';
import '../../utils/genesis_image_resource.dart';

const String genesisDefaultListImageAsset =
    'assets/images/default_list_image.png';

class GenesisListImage extends StatelessWidget {
  const GenesisListImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = GenesisImageRadii.content,
    this.placeholderAsset = genesisDefaultListImageAsset,
    this.placeholder,
    this.maxDevicePixelRatio = GenesisImageConfig.maxDevicePixelRatio,
    this.onImageLoaded,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadiusGeometry borderRadius;
  final String placeholderAsset;
  final Widget? placeholder;
  final double maxDevicePixelRatio;
  final VoidCallback? onImageLoaded;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolved = _selectUrl(context, constraints);
        final image = resolved.isEmpty
            ? _placeholder()
            : resolved.startsWith('assets/')
            ? _LoadedAssetImage(
                assetName: resolved,
                width: _finite(width),
                height: _finite(height),
                fit: fit,
                onImageLoaded: onImageLoaded,
                errorWidget: _placeholder,
              )
            : GenesisStaticNetworkImage(
                imageUrl: resolved,
                width: _finite(width),
                height: _finite(height),
                fit: fit,
                maxDevicePixelRatio: maxDevicePixelRatio,
                placeholder: (_) => _placeholder(),
                errorWidget: (_, _) => _placeholder(),
                onImageLoaded: onImageLoaded,
              );

        return ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(width: width, height: height, child: image),
        );
      },
    );
  }

  String _selectUrl(BuildContext context, BoxConstraints constraints) {
    return selectGenesisImageUrl(
      imageUrl,
      logicalWidth: _finite(width) ?? _finite(constraints.maxWidth),
      logicalHeight: _finite(height) ?? _finite(constraints.maxHeight),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      maxDevicePixelRatio: maxDevicePixelRatio,
    ).trim();
  }

  Widget _placeholder() {
    final customPlaceholder = placeholder;
    if (customPlaceholder != null) return customPlaceholder;
    return Image.asset(
      placeholderAsset,
      width: _finite(width),
      height: _finite(height),
      fit: fit,
    );
  }
}

class _LoadedAssetImage extends StatefulWidget {
  const _LoadedAssetImage({
    required this.assetName,
    required this.width,
    required this.height,
    required this.fit,
    required this.onImageLoaded,
    required this.errorWidget,
  });

  final String assetName;
  final double? width;
  final double? height;
  final BoxFit fit;
  final VoidCallback? onImageLoaded;
  final Widget Function() errorWidget;

  @override
  State<_LoadedAssetImage> createState() => _LoadedAssetImageState();
}

class _LoadedAssetImageState extends State<_LoadedAssetImage> {
  var _didNotifyLoaded = false;

  @override
  void didUpdateWidget(covariant _LoadedAssetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetName != widget.assetName) {
      _didNotifyLoaded = false;
    }
  }

  void _notifyLoaded() {
    if (_didNotifyLoaded) return;
    _didNotifyLoaded = true;
    widget.onImageLoaded?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      widget.assetName,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          _notifyLoaded();
        }
        return child;
      },
      errorBuilder: (context, error, stackTrace) => widget.errorWidget(),
    );
  }
}

double? _finite(double? value) {
  if (value == null || !value.isFinite) return null;
  return value;
}

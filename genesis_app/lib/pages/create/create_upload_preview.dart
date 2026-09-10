part of 'create_form_library.dart';

class _EmptyUpload extends StatelessWidget {
  const _EmptyUpload(
    this.label,
    this.iconSize,
    this.labelFontWeight,
    this.labelFontSize,
    this.iconLabelGap,
    this.iconColor,
    this.labelColor,
  );

  final String label;
  final double iconSize;
  final FontWeight labelFontWeight;
  final double labelFontSize;
  final double iconLabelGap;
  final Color iconColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.add_photo_alternate_outlined,
          color: iconColor,
          size: iconSize,
        ),
        SizedBox(height: iconLabelGap),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: labelColor,
            fontSize: labelFontSize,
            fontWeight: labelFontWeight,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.imageUrl,
    required this.imageBytes,
    required this.isUploading,
    required this.isProcessing,
    required this.progress,
    required this.alignment,
    required this.useMessageImageSizing,
    required this.displaySize,
    required this.downsampleMemoryImage,
    required this.maxDevicePixelRatio,
  });

  final String imageUrl;
  final Uint8List? imageBytes;
  final bool isUploading;
  final bool isProcessing;
  final double progress;
  final Alignment alignment;
  final bool useMessageImageSizing;
  final Size? displaySize;
  final bool downsampleMemoryImage;
  final double maxDevicePixelRatio;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    final bytes = imageBytes;
    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePixelRatio =
            MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1;
        final selectedUrl = useMessageImageSizing && displaySize != null
            ? resizeGenesisMessageImageUrl(
                url,
                displaySize: displaySize!,
                devicePixelRatio: devicePixelRatio,
              )
            : selectGenesisImageUrl(
                url,
                logicalWidth: constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : null,
                logicalHeight: constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : null,
                devicePixelRatio: devicePixelRatio,
                maxDevicePixelRatio: maxDevicePixelRatio,
              );
        final imageFit = useMessageImageSizing ? BoxFit.contain : BoxFit.cover;
        final cacheWidth = downsampleMemoryImage
            ? _previewDecodeDimension(constraints.maxWidth, devicePixelRatio)
            : null;
        final cacheHeight = downsampleMemoryImage
            ? _previewDecodeDimension(constraints.maxHeight, devicePixelRatio)
            : null;
        final memoryImage = bytes == null ? null : MemoryImage(bytes);
        final ImageProvider<Object>? memoryImageProvider = memoryImage == null
            ? null
            : downsampleMemoryImage &&
                  (cacheWidth != null || cacheHeight != null)
            ? ResizeImage(
                memoryImage,
                width: cacheWidth,
                height: cacheHeight,
                policy: ResizeImagePolicy.fit,
              )
            : memoryImage;
        final Widget image = memoryImageProvider != null
            ? Image(
                image: memoryImageProvider,
                width: double.infinity,
                height: double.infinity,
                fit: imageFit,
                alignment: alignment,
              )
            : selectedUrl.isEmpty
            ? const _PreviewPlaceholder(showSpinner: false)
            : selectedUrl.startsWith('assets/')
            ? Image.asset(
                selectedUrl,
                width: double.infinity,
                height: double.infinity,
                fit: imageFit,
                alignment: alignment,
                errorBuilder: (_, error, ___) {
                  return const _PreviewErrorIcon();
                },
              )
            : GenesisStaticNetworkImage(
                imageUrl: selectedUrl,
                width: double.infinity,
                height: double.infinity,
                fit: imageFit,
                alignment: alignment,
                maxDevicePixelRatio: maxDevicePixelRatio,
                onImageLoaded: () {
                  debugPrint(
                    '[CreateUploadBox] static image ready: "$selectedUrl"',
                  );
                },
                placeholder: (_) {
                  debugPrint(
                    '[CreateUploadBox] static image loading: "$selectedUrl"',
                  );
                  return const _PreviewPlaceholder(showSpinner: false);
                },
                errorWidget: (_, error) {
                  debugPrint(
                    '[CreateUploadBox] static image failed: '
                    'url="$selectedUrl", error="$error"',
                  );
                  return const _PreviewErrorIcon();
                },
              );
        return Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (isUploading)
              GenesisUploadProgressOverlay(
                progress: progress,
                processing: isProcessing,
              ),
          ],
        );
      },
    );
  }
}

int? _previewDecodeDimension(double logicalDimension, double devicePixelRatio) {
  if (!logicalDimension.isFinite ||
      logicalDimension <= 0 ||
      !devicePixelRatio.isFinite ||
      devicePixelRatio <= 0) {
    return null;
  }
  final physicalDimension = logicalDimension * devicePixelRatio;
  if (!physicalDimension.isFinite || physicalDimension <= 0) return null;
  return physicalDimension.ceil().clamp(1, 0x7fffffff).toInt();
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({this.showSpinner = true});

  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CreateFormTheme.colorOf(
        context,
        const Color(0xFFEFEFF2),
        GenesisColors.darkFaintSurface,
      ),
      child: showSpinner
          ? Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CreateFormTheme.colorOf(
                    context,
                    createFormGreen,
                    GenesisColors.darkTextSecondary,
                  ),
                ),
              ),
            )
          : const SizedBox.expand(),
    );
  }
}

class _PreviewErrorIcon extends StatelessWidget {
  const _PreviewErrorIcon();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CreateFormTheme.colorOf(
        context,
        const Color(0xFFEFEFF2),
        GenesisColors.darkFaintSurface,
      ),
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: CreateFormTheme.colorOf(
            context,
            createFormGreen,
            GenesisColors.darkTextSecondary,
          ),
          size: 34,
        ),
      ),
    );
  }
}

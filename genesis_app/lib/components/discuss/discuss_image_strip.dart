part of 'discuss_post_library.dart';

class _DiscussImageStrip extends StatelessWidget {
  const _DiscussImageStrip({
    required this.images,
    required this.showAddButton,
    required this.submitting,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_DiscussImageAttachment> images;
  final bool showAddButton;
  final bool submitting;
  final VoidCallback onAdd;
  final ValueChanged<_DiscussImageAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = _discussImageGap(constraints.maxWidth);
        final tileSize = _discussImageTileSize(constraints.maxWidth, gap);
        final itemCount = images.length + (showAddButton ? 1 : 0);

        return SizedBox(
          key: const ValueKey('discuss-image-strip'),
          height: tileSize + 8,
          child: itemCount == 0
              ? const SizedBox.expand()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var index = 0; index < itemCount; index++) ...[
                      if (index == images.length)
                        _DiscussImageAddTile(
                          size: tileSize,
                          enabled: !submitting,
                          onTap: onAdd,
                        )
                      else
                        _DiscussImageTile(
                          size: tileSize,
                          attachment: images[index],
                          submitting: submitting,
                          onRemove: () => onRemove(images[index]),
                        ),
                      if (index != itemCount - 1) SizedBox(width: gap),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _DiscussImageAddTile extends StatelessWidget {
  const _DiscussImageAddTile({
    required this.size,
    required this.enabled,
    required this.onTap,
  });

  final double size;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('discuss-image-add-button'),
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _discussComposerBorder, width: 1.4),
        ),
        child: const Icon(
          Icons.add,
          size: 28,
          color: _discussComposerSecondary,
        ),
      ),
    );
  }
}

class _DiscussImageTile extends StatelessWidget {
  const _DiscussImageTile({
    required this.size,
    required this.attachment,
    required this.submitting,
    required this.onRemove,
  });

  final double size;
  final _DiscussImageAttachment attachment;
  final bool submitting;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: GenesisImageRadii.content,
              child: SizedBox(
                key: ValueKey('discuss-image-thumb-${attachment.id}'),
                width: size,
                height: size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(attachment.image.bytes, fit: BoxFit.cover),
                    if (attachment.uploading)
                      GenesisUploadProgressOverlay(
                        progress: attachment.progress,
                        processing: attachment.processing,
                      ),
                    if (attachment.failed)
                      ColoredBox(
                        color: Colors.black.withValues(alpha: 0.48),
                        child: const Center(
                          child: Icon(
                            Icons.error_outline,
                            color: _discussComposerPrimary,
                            size: 22,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: InkWell(
              key: ValueKey('discuss-image-remove-${attachment.id}'),
              onTap: submitting ? null : onRemove,
              customBorder: const CircleBorder(),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _discussComposerSurface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.close,
                  color: _discussComposerPrimary,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _imagePickErrorText(Object error) {
  if (error is UnsupportedGifImageException) {
    return unsupportedGifImageMessage;
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (code.contains('denied') || code.contains('permission')) {
      return 'Photo access denied';
    }
  }
  return 'Image selection failed';
}

double _discussImageGap(double maxWidth) {
  if (maxWidth <= 0) return 8;
  return (maxWidth * 0.026).clamp(6.0, 12.0).toDouble();
}

double _discussImageTileSize(double maxWidth, double gap) {
  if (maxWidth <= 0) return 52;
  return ((maxWidth - gap * (discussPostMaxImages - 1)) / discussPostMaxImages)
      .clamp(36.0, maxWidth)
      .toDouble();
}

part of 'chat_ui_library.dart';

class ChatThumbnailImage extends StatefulWidget {
  const ChatThumbnailImage({
    super.key,
    required this.imageUrl,
    required this.maxWidth,
    this.placeholderColor = const Color(0xE6111111),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.onTap,
    this.onLongPressStart,
  });

  final String imageUrl;
  final double maxWidth;
  final Color placeholderColor;
  final BorderRadiusGeometry borderRadius;
  final ValueChanged<ImageProvider<Object>?>? onTap;
  final GestureLongPressStartCallback? onLongPressStart;

  @override
  State<ChatThumbnailImage> createState() => _ChatThumbnailImageState();
}

class _ChatThumbnailImageState extends State<ChatThumbnailImage> {
  ImageProvider<Object>? _provider;
  Size? _sourceSize;
  Size? _displaySize;
  bool _failed = false;
  int _generation = 0;
  double _devicePixelRatio = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextDevicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (_provider == null ||
        (nextDevicePixelRatio - _devicePixelRatio).abs() > 0.01) {
      _devicePixelRatio = nextDevicePixelRatio;
      final sourceSize = _sourceSize;
      if (sourceSize == null) {
        _resolveImage();
      } else {
        _configureImage(sourceSize);
      }
    }
  }

  @override
  void didUpdateWidget(covariant ChatThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _resolveImage();
    } else if (oldWidget.maxWidth != widget.maxWidth) {
      final sourceSize = _sourceSize;
      if (sourceSize != null) _configureImage(sourceSize);
    }
  }

  void _resolveImage() {
    final generation = ++_generation;
    final source = widget.imageUrl.trim();
    _provider = null;
    _sourceSize = null;
    _displaySize = null;
    _failed = false;
    if (source.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    final cachedSourceSize = cachedGenesisMessageImageSourceSize(source);
    if (cachedSourceSize != null) {
      _configureImage(cachedSourceSize, notify: false);
      return;
    }
    if (source.startsWith('assets/')) {
      _resolveAssetImage(source, generation);
      return;
    }
    resolveGenesisMessageImageSourceSize(source).then((sourceSize) {
      if (!mounted || generation != _generation) return;
      if (sourceSize == null) {
        setState(() => _failed = true);
        return;
      }
      _configureImage(sourceSize);
    });
  }

  void _resolveAssetImage(String source, int generation) {
    final provider = AssetImage(source);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (imageInfo, _) {
        stream.removeListener(listener);
        if (!mounted || generation != _generation) return;
        final scale = imageInfo.scale.isFinite && imageInfo.scale > 0
            ? imageInfo.scale
            : 1.0;
        _configureImage(
          Size(imageInfo.image.width / scale, imageInfo.image.height / scale),
        );
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        if (!mounted || generation != _generation) return;
        setState(() => _failed = true);
      },
    );
    stream.addListener(listener);
  }

  void _configureImage(Size sourceSize, {bool notify = true}) {
    final displaySize = fitGenesisMessageImageSize(
      sourceSize: sourceSize,
      maxWidth: widget.maxWidth,
    );
    if (displaySize.isEmpty) {
      if (notify) {
        setState(() => _failed = true);
      } else {
        _failed = true;
      }
      return;
    }
    final source = widget.imageUrl.trim();
    final resolvedSource = resizeGenesisMessageImageUrl(
      source,
      displaySize: displaySize,
      devicePixelRatio: _devicePixelRatio,
    );
    void applyImage() {
      _sourceSize = sourceSize;
      _displaySize = displaySize;
      _provider = source.startsWith('assets/')
          ? AssetImage(source)
          : GenesisStaticNetworkImageProvider(imageUrl: resolvedSource);
      _failed = false;
    }

    if (notify) {
      setState(applyImage);
    } else {
      applyImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final displaySize = _displaySize;
    final Widget thumbnail;
    if (_failed || provider == null || displaySize == null) {
      thumbnail = _buildPlaceholder();
    } else {
      thumbnail = ClipRRect(
        borderRadius: widget.borderRadius,
        child: SizedBox(
          width: displaySize.width,
          height: displaySize.height,
          child: Image(
            image: provider,
            width: displaySize.width,
            height: displaySize.height,
            fit: BoxFit.contain,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              return _buildPlaceholder(size: displaySize);
            },
            errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap == null ? null : () => widget.onTap!(provider),
      onLongPressStart: widget.onLongPressStart,
      child: thumbnail,
    );
  }

  Widget _buildPlaceholder({Size? size}) {
    final resolvedSize = size ?? Size(widget.maxWidth, widget.maxWidth);
    return SizedBox(
      width: resolvedSize.width,
      height: resolvedSize.height,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: ColoredBox(color: widget.placeholderColor),
      ),
    );
  }
}

String _rawImageUrl(ChatMessageVm message) {
  final imageUrl = message.imageUrl.trim();
  return imageUrl.isNotEmpty ? imageUrl : message.text.trim();
}

double chatNormalBubbleMaxWidth(BuildContext context, ChatUiStyleConfig style) {
  return _normalBubbleMaxWidthForWidth(MediaQuery.sizeOf(context).width, style);
}

double _normalBubbleMaxWidthForWidth(double width, ChatUiStyleConfig style) {
  final rowAvailableWidth =
      width -
      style.avatarSize -
      style.avatarBubbleGap -
      style.avatarSideSpacerWidth;
  return rowAvailableWidth > 0 ? rowAvailableWidth : width;
}

class _ChatAvatarSideSpacer extends StatelessWidget {
  const _ChatAvatarSideSpacer({required this.style});

  final ChatUiStyleConfig style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: style.avatarSideSpacerWidth);
  }
}

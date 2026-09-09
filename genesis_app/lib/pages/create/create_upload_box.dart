part of 'create_form_library.dart';

@visibleForTesting
Size? createUploadImageSizeFromEncodedBytes(Uint8List bytes) {
  return genesisMessageImageSizeFromEncodedBytes(bytes);
}

class CreateUploadBox extends StatefulWidget {
  const CreateUploadBox({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.onInteractionActiveChanged,
    this.initialPreviewBytes,
    this.onPreviewBytesChanged,
    this.width = 132,
    this.height = 176,
    this.iconSize = 38,
    this.borderRadius = GenesisImageRadii.contentValue,
    this.cropSize,
    this.maxOutputSize,
    this.uploadOriginalImage = false,
    this.preserveImageAspectRatio = false,
    this.useMessageImageSizing = false,
    this.previewAlignment = Alignment.center,
    this.showRemoveLinkWhenFilled = true,
    this.emptyLabelFontWeight = FontWeight.w600,
    this.emptyLabelFontSize = 12,
    this.removeLinkFontWeight = FontWeight.w600,
    this.emptyIconLabelGap = 12,
    this.emptyBackgroundColor = const Color(0x6BF4F4F6),
    this.emptyBorderColor = createFormUploadBorder,
    this.emptyIconColor = GenesisColors.createAdd,
    this.emptyLabelColor = createFormMuted,
    this.previewMaxDevicePixelRatio = GenesisImageConfig.maxDevicePixelRatio,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;
  final ValueChanged<bool>? onInteractionActiveChanged;
  final Uint8List? initialPreviewBytes;
  final ValueChanged<Uint8List?>? onPreviewBytesChanged;
  final double width;
  final double height;
  final double iconSize;
  final double borderRadius;
  final Size? cropSize;

  /// Opts this upload into a physical-pixel ceiling without upscaling.
  final Size? maxOutputSize;
  final bool uploadOriginalImage;
  final bool preserveImageAspectRatio;
  final bool useMessageImageSizing;
  final Alignment previewAlignment;
  final bool showRemoveLinkWhenFilled;
  final FontWeight emptyLabelFontWeight;
  final double emptyLabelFontSize;
  final FontWeight removeLinkFontWeight;
  final double emptyIconLabelGap;
  final Color emptyBackgroundColor;
  final Color emptyBorderColor;
  final Color emptyIconColor;
  final Color emptyLabelColor;
  final double previewMaxDevicePixelRatio;

  @override
  State<CreateUploadBox> createState() => _CreateUploadBoxState();
}

class _CreateUploadBoxState extends State<CreateUploadBox> {
  Uint8List? _previewBytes;
  double? _imageAspectRatio;
  Size? _imageLogicalSize;
  bool _isUploading = false;
  bool _isUploadProcessing = false;
  double _uploadProgress = 0;
  int _imageSizeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _previewBytes = widget.initialPreviewBytes;
    widget.controller.addListener(_handleControllerChanged);
    unawaited(_resolveControllerImageSize());
  }

  @override
  void didUpdateWidget(CreateUploadBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _previewBytes = widget.initialPreviewBytes;
      _imageAspectRatio = null;
      _imageLogicalSize = null;
      _isUploading = false;
      _isUploadProcessing = false;
      _uploadProgress = 0;
      unawaited(_resolveControllerImageSize());
    } else {
      if (!identical(
        oldWidget.initialPreviewBytes,
        widget.initialPreviewBytes,
      )) {
        _previewBytes = widget.initialPreviewBytes;
      }
      if (!oldWidget.useMessageImageSizing && widget.useMessageImageSizing) {
        unawaited(_resolveControllerImageSize());
      } else if (oldWidget.useMessageImageSizing &&
          !widget.useMessageImageSizing) {
        _imageLogicalSize = null;
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted || _isUploading) return;
    if (_previewBytes != null) {
      setState(() {
        _previewBytes = null;
        _imageAspectRatio = null;
        _imageLogicalSize = null;
        _isUploadProcessing = false;
        _uploadProgress = 0;
      });
      unawaited(_resolveControllerImageSize());
      return;
    }
    setState(() {});
    unawaited(_resolveControllerImageSize());
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.controller.text.trim();
    final hasImage = _previewBytes != null || imageUrl.isNotEmpty;
    final messageDisplaySize =
        hasImage && widget.useMessageImageSizing && _imageLogicalSize != null
        ? fitGenesisMessageImageSize(
            sourceSize: _imageLogicalSize!,
            maxWidth: widget.width,
          )
        : null;
    final previewWidth = messageDisplaySize?.width ?? widget.width;
    final previewHeight =
        messageDisplaySize?.height ??
        (hasImage &&
                widget.preserveImageAspectRatio &&
                _imageAspectRatio != null &&
                _imageAspectRatio! > 0
            ? widget.width / _imageAspectRatio!
            : widget.height);
    final uploadBox = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _isUploading
          ? () => showGenesisToast(context, 'Image upload is in progress.')
          : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          onTap: _isUploading ? null : () => _pickCropAndUpload(context),
          child: CustomPaint(
            key: const ValueKey<String>('create-upload-border'),
            painter: CreateDashedRRectPainter(
              color: widget.emptyBorderColor,
              radius: widget.borderRadius,
              strokeWidth: 1.2,
            ),
            child: Container(
              key: const ValueKey<String>('create-upload-surface'),
              width: previewWidth,
              height: previewHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.emptyBackgroundColor,
                borderRadius: BorderRadius.circular(widget.borderRadius),
              ),
              clipBehavior: Clip.antiAlias,
              child: !hasImage
                  ? _EmptyUpload(
                      widget.label,
                      widget.iconSize,
                      widget.emptyLabelFontWeight,
                      widget.emptyLabelFontSize,
                      widget.emptyIconLabelGap,
                      widget.emptyIconColor,
                      widget.emptyLabelColor,
                    )
                  : _Preview(
                      imageUrl: imageUrl,
                      imageBytes: _previewBytes,
                      isUploading: _isUploading,
                      isProcessing: _isUploadProcessing,
                      progress: _uploadProgress,
                      alignment: widget.previewAlignment,
                      useMessageImageSizing: widget.useMessageImageSizing,
                      displaySize: messageDisplaySize,
                      downsampleMemoryImage: widget.uploadOriginalImage,
                      maxDevicePixelRatio: widget.previewMaxDevicePixelRatio,
                    ),
            ),
          ),
        ),
      ),
    );
    if (!widget.showRemoveLinkWhenFilled || !hasImage) return uploadBox;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        uploadBox,
        Positioned(
          right: 4,
          top: 4,
          child: GenesisDeleteButton(
            buttonKey: const ValueKey('create-upload-remove'),
            decorationKey: const ValueKey('create-upload-remove-container'),
            onPressed: _removeImage,
            enabled: !_isUploading,
            onDisabledPressed: () =>
                showGenesisToast(context, 'Image upload is in progress.'),
          ),
        ),
      ],
    );
  }

  void _removeImage() {
    setState(() {
      _previewBytes = null;
      _imageAspectRatio = null;
      _imageLogicalSize = null;
      _isUploading = false;
      _isUploadProcessing = false;
      _uploadProgress = 0;
    });
    widget.onPreviewBytesChanged?.call(null);
    widget.controller.clear();
    widget.onChanged();
  }

  Future<void> _pickCropAndUpload(BuildContext context) async {
    widget.onInteractionActiveChanged?.call(true);
    try {
      if (widget.onInteractionActiveChanged != null) {
        // Let callers commit their focus and layout freeze before presenting a
        // native picker, whose transition can otherwise begin in this frame.
        await WidgetsBinding.instance.endOfFrame;
        if (!context.mounted) return;
      }
      final picked = await pickGenesisImages(
        limit: 1,
        normalizeForUpload: widget.uploadOriginalImage,
      );
      if (picked.isEmpty) return;
      final image = picked.first;
      if (!context.mounted) return;

      if (widget.uploadOriginalImage) {
        await _uploadOriginalSelection(context, image);
        return;
      }

      final crop = await Navigator.of(context).push<LocalImageCropResult>(
        MaterialPageRoute<LocalImageCropResult>(
          builder: (_) => LocalImageCropPage(
            imageBytes: image.bytes,
            cropSize: _resolvedCropSize,
            maxOutputSize: widget.maxOutputSize,
            filename: _pngFilenameFor(image.filename),
            contentType: 'image/png',
            uploadOnConfirm: false,
          ),
        ),
      );
      if (crop == null || !context.mounted) return;

      final previousUrl = widget.controller.text;
      setState(() {
        _previewBytes = crop.bytes;
        _isUploading = true;
        _isUploadProcessing = true;
        _uploadProgress = 0;
      });
      widget.controller.clear();
      widget.onChanged();
      unawaited(_uploadCroppedImage(context, crop, previousUrl));
    } on UnsupportedGifImageException {
      if (!context.mounted) return;
      _showMessage(unsupportedGifImageMessage);
    } catch (_) {
      if (!context.mounted) return;
      _showMessage('Image upload failed.');
    } finally {
      widget.onInteractionActiveChanged?.call(false);
    }
  }

  void _showMessage(String message) {
    showGenesisToast(context, message);
  }

  Future<void> _uploadOriginalSelection(
    BuildContext context,
    DiscussPickedImage image,
  ) async {
    final previousUrl = widget.controller.text;
    final imageSize =
        widget.preserveImageAspectRatio || widget.useMessageImageSizing
        ? createUploadImageSizeFromEncodedBytes(image.bytes)
        : null;
    final aspectRatio = imageSize == null
        ? null
        : imageSize.width / imageSize.height;
    if (!context.mounted) return;
    setState(() {
      _previewBytes = image.bytes;
      _imageAspectRatio = aspectRatio;
      _imageLogicalSize = imageSize;
      _isUploading = true;
      _isUploadProcessing = true;
      _uploadProgress = 0;
    });
    widget.controller.clear();
    widget.onChanged();

    try {
      final uploaded = await AppServicesScope.read(context).api.v1.upload.image(
        bytes: image.bytes,
        filename: image.filename,
        contentType: image.contentType,
      );
      if (!mounted) return;
      final url = GenesisImageResourceRegistry.resolve(uploaded).displayUrl;
      if (url.isEmpty) {
        throw StateError('Upload returned an empty URL');
      }
      setState(() {
        _isUploadProcessing = false;
        _uploadProgress = 0;
      });
      widget.controller.text = url;
      setState(() {
        _isUploading = false;
      });
      widget.onPreviewBytesChanged?.call(image.bytes);
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _isUploadProcessing = false;
        _uploadProgress = 0;
        _previewBytes = null;
        _imageAspectRatio = null;
        _imageLogicalSize = null;
      });
      widget.controller.text = previousUrl;
      widget.onChanged();
      _showMessage('Image upload failed.');
    }
  }

  Size get _resolvedCropSize {
    final cropSize = widget.cropSize;
    if (cropSize != null) return cropSize;
    return Size(
      (widget.width * 4).roundToDouble().clamp(1, 4096).toDouble(),
      (widget.height * 4).roundToDouble().clamp(1, 4096).toDouble(),
    );
  }

  Future<void> _uploadCroppedImage(
    BuildContext context,
    LocalImageCropResult crop,
    String previousUrl,
  ) async {
    try {
      final uploaded = await AppServicesScope.read(context).api.v1.upload.image(
        bytes: crop.bytes,
        filename: crop.filename,
        contentType: crop.contentType,
      );
      if (!mounted) return;
      final url = GenesisImageResourceRegistry.resolve(uploaded).displayUrl;
      if (url.isEmpty) {
        throw StateError('Upload returned an empty URL');
      }
      setState(() {
        _isUploadProcessing = false;
        _uploadProgress = 0;
      });
      widget.controller.text = url;
      setState(() {
        _isUploading = false;
      });
      widget.onPreviewBytesChanged?.call(crop.bytes);
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _isUploadProcessing = false;
        _uploadProgress = 0;
        _previewBytes = null;
        _imageAspectRatio = null;
        _imageLogicalSize = null;
      });
      widget.controller.text = previousUrl;
      widget.onChanged();
      _showMessage('Image upload failed.');
    }
  }

  String _pngFilenameFor(String filename) {
    final normalized = filename.trim();
    if (normalized.isEmpty) return 'crop.png';
    final withoutExtension = normalized.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final base = withoutExtension.trim().isEmpty ? 'crop' : withoutExtension;
    return '$base.png';
  }

  Future<void> _resolveControllerImageSize() async {
    final generation = ++_imageSizeGeneration;
    if (!widget.useMessageImageSizing || _previewBytes != null) return;
    final source = widget.controller.text.trim();
    if (source.isEmpty) {
      if (mounted && _imageLogicalSize != null) {
        setState(() {
          _imageLogicalSize = null;
          _imageAspectRatio = null;
        });
      }
      return;
    }
    final size = await resolveGenesisMessageImageSourceSize(source);
    if (!mounted ||
        generation != _imageSizeGeneration ||
        source != widget.controller.text.trim()) {
      return;
    }
    if (size == null) return;
    setState(() {
      _imageLogicalSize = size;
      _imageAspectRatio = size.width / size.height;
    });
  }
}

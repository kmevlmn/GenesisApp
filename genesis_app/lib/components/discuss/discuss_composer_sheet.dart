part of 'discuss_post_library.dart';

class _DiscussComposerSheet extends StatefulWidget {
  const _DiscussComposerSheet({
    required this.title,
    required this.placeholder,
    required this.pickImages,
    this.pickImageResult,
    required this.uploadImage,
    this.uploadImageWithProgress,
    required this.showImagePickerButton,
    required this.onSubmit,
  });

  final String title;
  final String placeholder;
  final DiscussImagePicker pickImages;
  final DiscussImageResultPicker? pickImageResult;
  final DiscussImageUploader uploadImage;
  final DiscussImageProgressUploader? uploadImageWithProgress;
  final bool showImagePickerButton;
  final Future<void> Function(String content, List<String> images) onSubmit;

  @override
  State<_DiscussComposerSheet> createState() => _DiscussComposerSheetState();
}

class _DiscussComposerSheetState extends State<_DiscussComposerSheet>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode();
  late final AnimationController _scrimController = AnimationController(
    vsync: this,
    duration: _discussComposerScrimFadeDuration,
    reverseDuration: _discussComposerSheetDismissDuration,
  );
  late final AnimationController _sheetDismissController = AnimationController(
    vsync: this,
    duration: _discussComposerSheetDismissDuration,
  );
  final List<_DiscussImageAttachment> _images = <_DiscussImageAttachment>[];
  Timer? _pickerReturnScrimGuardTimer;
  bool _submitting = false;
  bool _pickerOpen = false;
  bool _closing = false;
  bool _keyboardWasVisible = false;
  bool _ignoreKeyboardDismissAfterPicker = false;
  bool _ignoreScrimDismissAfterPicker = false;
  bool _keyboardHideDismissQueued = false;
  int _nextImageId = 0;

  bool get _canSend {
    if (_submitting || _images.any((image) => image.failed)) return false;
    return !isGenesisUgcTextBlank(_controller.text);
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
    _sheetDismissController.addListener(_handleSheetDismissTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_scrimController.forward());
      _composerFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pickerReturnScrimGuardTimer?.cancel();
    _sheetDismissController.removeListener(_handleSheetDismissTick);
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _composerFocusNode.dispose();
    _scrimController.dispose();
    _sheetDismissController.dispose();
    for (final image in _images) {
      image.progressTimer?.cancel();
    }
    super.dispose();
  }

  void _handleTextChanged() {
    setState(() {});
  }

  void _handleSheetDismissTick() {
    if (!mounted || !_closing) return;
    setState(() {});
  }

  void _trackVisibleKeyboard(double measuredInset) {
    if (measuredInset <= 0) return;
    _keyboardWasVisible = true;
    _ignoreKeyboardDismissAfterPicker = false;
    _keyboardHideDismissQueued = false;
  }

  void _queueDismissForHiddenKeyboard() {
    if (_keyboardHideDismissQueued) return;
    _keyboardHideDismissQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardHideDismissQueued = false;
      if (!mounted || !_shouldDismissForHiddenKeyboard) return;
      unawaited(_dismiss());
    });
  }

  bool get _shouldDismissForHiddenKeyboard {
    return _keyboardWasVisible &&
        !_ignoreKeyboardDismissAfterPicker &&
        !_pickerOpen &&
        _images.isEmpty &&
        !_closing &&
        !_submitting;
  }

  void _startPickerReturnScrimGuardTimer() {
    _pickerReturnScrimGuardTimer?.cancel();
    _pickerReturnScrimGuardTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _ignoreScrimDismissAfterPicker = false);
    });
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() => _submitting = true);
    try {
      await Future.wait(_images.map((image) => image.uploadFuture));
      final imageUrls = _images
          .map((image) => image.url?.trim() ?? '')
          .where((url) => url.isNotEmpty)
          .toList(growable: false);
      await widget.onSubmit(
        normalizeGenesisUgcTextForSubmission(_controller.text),
        imageUrls,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showGenesisToast(context, 'Post failed', brightness: Brightness.dark);
    }
  }

  Future<void> _pickAndUploadImages() async {
    if (_submitting || _images.length >= discussPostMaxImages) return;
    final available = discussPostMaxImages - _images.length;
    List<DiscussPickedImage>? picked;
    Object? pickError;
    var rejectedUnsupportedGif = false;
    setState(() {
      _pickerOpen = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      final pickImageResult = widget.pickImageResult;
      if (pickImageResult != null) {
        final result = await pickImageResult(available);
        picked = result.images;
        rejectedUnsupportedGif = result.rejectedUnsupportedGif;
      } else {
        picked = await widget.pickImages(available);
      }
    } catch (error, stackTrace) {
      pickError = error;
      debugPrint('Discuss image selection failed: $error\n$stackTrace');
    } finally {
      if (mounted) {
        setState(() {
          _pickerOpen = false;
          _ignoreScrimDismissAfterPicker = true;
          _ignoreKeyboardDismissAfterPicker = true;
        });
        _startPickerReturnScrimGuardTimer();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _closing) return;
          _composerFocusNode.requestFocus();
          unawaited(
            SystemChannels.textInput.invokeMethod<void>('TextInput.show'),
          );
        });
      }
    }
    if (!mounted) return;
    if (pickError != null) {
      showGenesisToast(
        context,
        _imagePickErrorText(pickError),
        brightness: Brightness.dark,
      );
      return;
    }
    if (rejectedUnsupportedGif) {
      showGenesisToast(
        context,
        unsupportedGifImageMessage,
        brightness: Brightness.dark,
      );
    }
    if (picked == null || picked.isEmpty) return;

    final selected = picked.take(available).toList(growable: false);
    final added = <_DiscussImageAttachment>[];
    for (final image in selected) {
      final attachment = _DiscussImageAttachment(
        id: _nextImageId++,
        image: image,
      );
      attachment.uploadFuture = _uploadAttachmentAfterThumbnailFrame(
        attachment,
      );
      added.add(attachment);
    }
    setState(() => _images.addAll(added));
  }

  Future<void> _uploadAttachmentAfterThumbnailFrame(
    _DiscussImageAttachment attachment,
  ) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_images.contains(attachment)) return;
    await _uploadAttachment(attachment);
  }

  Future<void> _uploadAttachment(_DiscussImageAttachment attachment) async {
    try {
      _startAttachmentCompressionProgressTimer(
        attachment,
        byteCount: attachment.image.bytes.length,
      );
      final processingRequest = <String, Object>{
        'bytes': attachment.image.bytes,
        'filename': attachment.image.filename,
        'content_type': attachment.image.contentType,
        'max_width': _discussUploadMaxWidth,
      };
      final imageProcessor = debugDiscussImageProcessorOverride;
      final uploadImage = imageProcessor == null
          ? await compute(
              _prepareDiscussImageForUpload,
              processingRequest,
              debugLabel: 'discuss-image-upload-processing',
            )
          : await imageProcessor(processingRequest);
      attachment.progressTimer?.cancel();
      attachment.progressTimer = null;
      if (!mounted || !_images.contains(attachment)) return;
      setState(() {
        attachment.progress = _discussCompressionProgress;
      });
      final uploadBytes = uploadImage['bytes']! as Uint8List;
      final uploadFilename = uploadImage['filename']! as String;
      final uploadContentType = uploadImage['content_type']! as String;
      final pickedImage = DiscussPickedImage(
        bytes: uploadBytes,
        filename: uploadFilename,
        contentType: uploadContentType,
      );
      final progressUploader = widget.uploadImageWithProgress;
      final String url;
      if (progressUploader == null) {
        _startAttachmentUploadProgressTimer(
          attachment,
          byteCount: uploadBytes.length,
        );
        url = await widget.uploadImage(pickedImage);
      } else {
        url = await progressUploader(
          pickedImage,
          onSendProgress: (sentBytes, totalBytes) {
            if (!mounted || !_images.contains(attachment)) return;
            final isProcessing = totalBytes > 0 && sentBytes >= totalBytes;
            setState(() {
              attachment.processing = isProcessing;
              attachment.progress = _actualDiscussUploadProgress(
                sentBytes: sentBytes,
                totalBytes: totalBytes,
              );
            });
          },
        );
      }
      if (!mounted || !_images.contains(attachment)) return;
      attachment.progressTimer?.cancel();
      setState(() {
        attachment.progress = 1;
        attachment.url = url;
        attachment.processing = false;
        attachment.uploading = false;
      });
    } catch (_) {
      if (!mounted || !_images.contains(attachment)) return;
      attachment.progressTimer?.cancel();
      setState(() {
        attachment.failed = true;
        attachment.processing = false;
        attachment.uploading = false;
      });
      showGenesisToast(
        context,
        'Image upload failed',
        brightness: Brightness.dark,
      );
      rethrow;
    }
  }

  void _removeImage(_DiscussImageAttachment image) {
    if (_submitting) return;
    image.progressTimer?.cancel();
    setState(() => _images.remove(image));
  }

  void _startAttachmentCompressionProgressTimer(
    _DiscussImageAttachment attachment, {
    required int byteCount,
  }) {
    attachment.progressTimer?.cancel();
    final stopwatch = Stopwatch()..start();
    attachment.progressTimer = Timer.periodic(_discussUploadProgressTick, (_) {
      if (!mounted || !_images.contains(attachment) || !attachment.uploading) {
        attachment.progressTimer?.cancel();
        return;
      }
      setState(() {
        attachment.progress = estimateDiscussCompressionProgressForTesting(
          byteCount: byteCount,
          elapsed: stopwatch.elapsed,
        );
      });
    });
  }

  void _startAttachmentUploadProgressTimer(
    _DiscussImageAttachment attachment, {
    required int byteCount,
  }) {
    attachment.progressTimer?.cancel();
    final stopwatch = Stopwatch()..start();
    attachment.progressTimer = Timer.periodic(_discussUploadProgressTick, (_) {
      if (!mounted || !_images.contains(attachment) || !attachment.uploading) {
        attachment.progressTimer?.cancel();
        return;
      }
      setState(() {
        attachment.progress = _estimatedDiscussUploadProgress(
          byteCount: byteCount,
          elapsed: stopwatch.elapsed,
        );
      });
    });
  }

  double _estimatedDiscussUploadProgress({
    required int byteCount,
    required Duration elapsed,
  }) {
    final estimatedBytes = byteCount <= 0 ? 1 : byteCount;
    final estimatedDurationMs =
        estimatedBytes / _discussUploadProgressBytesPerSecond * 1000;
    if (estimatedDurationMs <= 0) return _discussEstimatedUploadProgressCap;
    final uploadProgress =
        elapsed.inMilliseconds /
        estimatedDurationMs *
        (_discussEstimatedUploadProgressCap - _discussCompressionProgress);
    return (_discussCompressionProgress + uploadProgress)
        .clamp(_discussCompressionProgress, _discussEstimatedUploadProgressCap)
        .toDouble();
  }

  double _actualDiscussUploadProgress({
    required int sentBytes,
    required int totalBytes,
  }) {
    final total = totalBytes <= 0 ? 1 : totalBytes;
    final raw = (sentBytes / total).clamp(0.0, 1.0).toDouble();
    return (_discussCompressionProgress +
            raw * (1 - _discussCompressionProgress))
        .clamp(_discussCompressionProgress, 1.0)
        .toDouble();
  }

  void _handleScrimTap() {
    if (_pickerOpen) return;
    if (_ignoreScrimDismissAfterPicker) {
      _pickerReturnScrimGuardTimer?.cancel();
      _pickerReturnScrimGuardTimer = null;
      setState(() => _ignoreScrimDismissAfterPicker = false);
      return;
    }
    unawaited(_dismiss());
  }

  Future<void> _dismiss() async {
    if (_submitting || _closing) return;
    setState(() {
      _closing = true;
    });
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    await Future.wait([
      _sheetDismissController.forward(),
      _scrimController.reverse(),
    ]);
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    _trackVisibleKeyboard(keyboardInset);
    if (keyboardInset <= 0 && _shouldDismissForHiddenKeyboard) {
      _queueDismissForHiddenKeyboard();
    }
    final closingSlideProgress = _closing
        ? Curves.easeInCubic.transform(_sheetDismissController.value)
        : 0.0;
    final hasImages = _images.isNotEmpty;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_dismiss());
      },
      child: GenesisEdgeSwipeBack(
        onBack: () => unawaited(_dismiss()),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: FadeTransition(
                  opacity: _scrimController,
                  child: GestureDetector(
                    key: const ValueKey('discuss-composer-scrim-dismiss'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleScrimTap,
                    child: const ColoredBox(
                      color: kGenesisSubtleModalBarrierColor,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionalTranslation(
                  translation: Offset(0, closingSlideProgress),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: _DiscussComposerPanel(
                      title: widget.title,
                      placeholder: widget.placeholder,
                      controller: _controller,
                      focusNode: _composerFocusNode,
                      hasImages: hasImages,
                      images: _images,
                      submitting: _submitting,
                      canSend: _canSend,
                      showImagePickerButton: widget.showImagePickerButton,
                      onPickImages: _pickAndUploadImages,
                      onRemoveImage: _removeImage,
                      onSend: _send,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

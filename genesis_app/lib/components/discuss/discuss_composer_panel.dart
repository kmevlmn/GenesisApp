part of 'discuss_post_library.dart';

class _DiscussComposerPanel extends StatelessWidget {
  const _DiscussComposerPanel({
    required this.title,
    required this.placeholder,
    required this.controller,
    required this.focusNode,
    required this.hasImages,
    required this.images,
    required this.submitting,
    required this.canSend,
    required this.showImagePickerButton,
    required this.onPickImages,
    required this.onRemoveImage,
    required this.onSend,
  });

  final String title;
  final String placeholder;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasImages;
  final List<_DiscussImageAttachment> images;
  final bool submitting;
  final bool canSend;
  final bool showImagePickerButton;
  final VoidCallback onPickImages;
  final ValueChanged<_DiscussImageAttachment> onRemoveImage;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('discuss-composer-sheet'),
      color: _discussComposerSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: GenesisBottomSheetPanel.borderRadius,
        side: BorderSide(color: _discussComposerBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GenesisBottomSheetPanel.titleStyle.copyWith(
                  color: _discussComposerPrimary,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                focusNode: focusNode,
                cursorColor: _discussComposerPrimary,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: _discussComposerMinTextLines,
                maxLines: _discussComposerMaxTextLines,
                style: const TextStyle(
                  fontSize: _discussComposerFontSize,
                  height: _discussComposerLineHeight,
                  fontWeight: FontWeight.w400,
                  color: _discussComposerPrimary,
                ),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle: const TextStyle(
                    fontSize: _discussComposerFontSize,
                    height: _discussComposerLineHeight,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                    color: GenesisColors.darkInputPlaceholder,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 14),
              if (hasImages) ...[
                _DiscussImageStrip(
                  images: images,
                  showAddButton: images.length < discussPostMaxImages,
                  submitting: submitting,
                  onAdd: onPickImages,
                  onRemove: onRemoveImage,
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  if (showImagePickerButton)
                    IconButton(
                      key: const ValueKey('discuss-image-picker-button'),
                      onPressed: submitting ? null : onPickImages,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      icon: const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 30,
                        color: GenesisColors.brand,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: canSend ? onSend : null,
                    style: TextButton.styleFrom(
                      foregroundColor: GenesisColors.brand,
                      disabledForegroundColor: _discussComposerMuted,
                      textStyle: const TextStyle(
                        fontFamily: GenesisTypography.fontFamily,
                        fontFamilyFallback:
                            GenesisTypography.fontFamilyFallback,
                        fontSize: 16,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: GenesisColors.brand,
                            ),
                          )
                        : const Text('Send'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscussImageAttachment {
  _DiscussImageAttachment({required this.id, required this.image})
    : uploadFuture = Future<void>.value();

  final int id;
  final DiscussPickedImage image;
  late Future<void> uploadFuture;
  Timer? progressTimer;
  String? url;
  double progress = 0;
  bool uploading = true;
  bool processing = false;
  bool failed = false;
}

Future<Map<String, Object>> _prepareDiscussImageForUpload(
  Map<String, Object> request,
) async {
  final result = await resizeImageToMaxWidth(
    bytes: request['bytes']! as Uint8List,
    filename: request['filename']! as String,
    contentType: request['content_type']! as String,
    maxWidth: request['max_width']! as int,
  );
  return <String, Object>{
    'bytes': result.bytes,
    'filename': result.filename,
    'content_type': result.contentType,
  };
}

@visibleForTesting
double estimateDiscussCompressionProgressForTesting({
  required int byteCount,
  required Duration elapsed,
}) {
  final estimatedDurationMs = _estimatedDiscussCompressionDurationMs(byteCount);
  if (estimatedDurationMs <= 0) return _discussCompressionProgress * 0.95;
  final progress =
      elapsed.inMilliseconds /
      estimatedDurationMs *
      _discussCompressionProgress;
  return progress.clamp(0.0, _discussCompressionProgress * 0.95).toDouble();
}

int _estimatedDiscussCompressionDurationMs(int byteCount) {
  final estimatedBytes = byteCount <= 0 ? 1 : byteCount;
  final estimatedMs =
      estimatedBytes / _discussCompressionProgressBytesPerSecond * 1000;
  return estimatedMs
      .round()
      .clamp(
        _discussCompressionProgressMinDuration.inMilliseconds,
        _discussCompressionProgressMaxDuration.inMilliseconds,
      )
      .toInt();
}

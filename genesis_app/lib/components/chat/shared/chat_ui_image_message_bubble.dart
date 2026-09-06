part of 'chat_ui_library.dart';

class ChatImageMessage extends StatelessWidget {
  const ChatImageMessage({
    super.key,
    required this.message,
    required this.style,
    this.imageViewerMessages = const <ChatMessageVm>[],
    this.onLongPressStart,
  });

  final ChatMessageVm message;
  final ChatUiStyleConfig style;
  final List<ChatMessageVm> imageViewerMessages;
  final GestureLongPressStartCallback? onLongPressStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: style.avatarSideSpacerWidth,
        right: style.systemMessageMargin.right,
        bottom: style.rowBottomPadding,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            return ChatThumbnailImage(
              key: ValueKey<String>('chat-image-message-${message.localId}'),
              imageUrl: _rawImageUrl(message),
              maxWidth: maxWidth,
              placeholderColor: chatNarratorMessageBackgroundColor(style),
              borderRadius: BorderRadius.circular(8),
              onTap: _rawImageUrl(message).isEmpty
                  ? null
                  : (previewImageProvider) =>
                        _showImageViewer(context, previewImageProvider),
              onLongPressStart: onLongPressStart,
            );
          },
        ),
      ),
    );
  }

  void _showImageViewer(
    BuildContext context,
    ImageProvider<Object>? previewImageProvider,
  ) {
    final sourceMessages = imageViewerMessages.isEmpty
        ? <ChatMessageVm>[message]
        : imageViewerMessages;
    final indexedMessages =
        <({int index, ChatMessageVm message})>[
          for (var index = 0; index < sourceMessages.length; index += 1)
            if (sourceMessages[index].isImage &&
                _rawImageUrl(sourceMessages[index]).isNotEmpty)
              (index: index, message: sourceMessages[index]),
        ]..sort((left, right) {
          final byTime = left.message.createdAt.compareTo(
            right.message.createdAt,
          );
          return byTime != 0 ? byTime : left.index.compareTo(right.index);
        });
    if (indexedMessages.isEmpty) return;

    final initialIndex = indexedMessages.indexWhere(
      (entry) => entry.message.localId == message.localId,
    );
    final viewerInitialIndex = initialIndex < 0 ? 0 : initialIndex;
    showGenesisImageViewer(
      context,
      imageUrls: [
        for (final entry in indexedMessages) _rawImageUrl(entry.message),
      ],
      previewImageProviders: [
        for (var index = 0; index < indexedMessages.length; index += 1)
          index == viewerInitialIndex ? previewImageProvider : null,
      ],
      initialIndex: viewerInitialIndex,
    );
  }
}

part of 'chat_ui_library.dart';

class ChatSelfMessageBubble extends StatelessWidget {
  const ChatSelfMessageBubble({
    super.key,
    required this.message,
    required this.style,
    this.maxWidthCap,
    this.onLongPressStart,
    this.onFailedMessageTap,
  });

  final ChatMessageVm message;
  final ChatUiStyleConfig style;
  final double? maxWidthCap;
  final GestureLongPressStartCallback? onLongPressStart;
  final ChatMessageTap? onFailedMessageTap;

  @override
  Widget build(BuildContext context) {
    final defaultMaxBubbleWidth = chatNormalBubbleMaxWidth(context, style);
    final maxBubbleWidth = maxWidthCap == null
        ? defaultMaxBubbleWidth
        : math.min(defaultMaxBubbleWidth, maxWidthCap!);
    final showFailedBadge = message.status == 'failed';
    final showSendingBadge = message.status == 'sending';
    final showStatusText =
        message.status != 'sent' && !showFailedBadge && !showSendingBadge;
    return Padding(
      padding: EdgeInsets.only(bottom: style.rowBottomPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChatAvatarSideSpacer(style: style),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (showFailedBadge) ...[
                      GestureDetector(
                        key: ValueKey('chat-message-retry-${message.localId}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onFailedMessageTap == null
                            ? null
                            : () => onFailedMessageTap!(message),
                        child: ChatFailedBadge(style: style),
                      ),
                      SizedBox(width: style.badgeBubbleGap),
                    ] else if (showSendingBadge) ...[
                      ChatSendingBadge(style: style),
                      SizedBox(width: style.badgeBubbleGap),
                    ],
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                        child: ChatMessageBubble(
                          message: message,
                          style: style,
                          onTap: showFailedBadge && onFailedMessageTap != null
                              ? () => onFailedMessageTap!(message)
                              : null,
                          onLongPressStart: onLongPressStart,
                        ),
                      ),
                    ),
                  ],
                ),
                if (showStatusText) ...[
                  SizedBox(height: style.statusTextTopGap),
                  Text(
                    genesisDisplaySafeText(message.status),
                    style: style.statusTextStyle,
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: style.avatarBubbleGap),
          ChatAvatar(
            label: chatInitials(message.senderName),
            imageUrl: message.avatarUrl,
            colors: style.selfAvatarColors,
            seed: message.senderName,
            style: style,
          ),
        ],
      ),
    );
  }
}

part of 'chat_ui_library.dart';

class ChatOtherMessageBubble extends StatelessWidget {
  const ChatOtherMessageBubble({
    super.key,
    required this.message,
    required this.style,
    this.maxWidthCap,
    this.onAvatarTap,
    this.onLongPressStart,
  });

  final ChatMessageVm message;
  final ChatUiStyleConfig style;
  final double? maxWidthCap;
  final VoidCallback? onAvatarTap;
  final GestureLongPressStartCallback? onLongPressStart;

  @override
  Widget build(BuildContext context) {
    final defaultMaxBubbleWidth = chatNormalBubbleMaxWidth(context, style);
    final maxBubbleWidth = maxWidthCap == null
        ? defaultMaxBubbleWidth
        : math.min(defaultMaxBubbleWidth, maxWidthCap!);
    final senderName = genesisDisplaySafeText(message.senderName);
    final currentTime = genesisDisplaySafeText(message.currentTime).trim();
    return Padding(
      padding: EdgeInsets.only(bottom: style.rowBottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAvatarTap,
                child: _isNpcSender(message.senderId)
                    ? ChatNpcAvatar(style: style)
                    : ChatAvatar(
                        label: chatInitials(message.senderName),
                        imageUrl: message.avatarUrl,
                        colors: style.otherAvatarColors,
                        seed: message.senderName,
                        borderColor: message.isPlayerControlledRole
                            ? (style.useScenePlateBubbleGeometry
                                  ? kChatScenePlatePlayerRoleBorderColor
                                  : GenesisColors.brand)
                            : null,
                        style: style,
                      ),
              ),
            ],
          ),
          SizedBox(width: style.avatarBubbleGap),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (style.showSenderNameAboveOtherBubble) ...[
                  SizedBox(
                    width: maxBubbleWidth,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            key: ValueKey<String>(
                              'chat-sender-name-${message.localId}',
                            ),
                            senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                message.isPlayerControlledRole &&
                                    !style.useScenePlateBubbleGeometry
                                ? style.senderNameTextStyle.copyWith(
                                    color: GenesisColors.brand,
                                  )
                                : style.senderNameTextStyle,
                          ),
                        ),
                        if (currentTime.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            key: ValueKey<String>(
                              'chat-sender-time-${message.localId}',
                            ),
                            currentTime,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.useScenePlateBubbleGeometry
                                ? GenesisTypography.withFallback(
                                    style.senderNameTextStyle,
                                  ).copyWith(
                                    color: GenesisColors.darkTextTertiary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w400,
                                    height: 1,
                                  )
                                : style.senderNameTextStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: style.senderNameBottomGap),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: ChatMessageBubble(
                    message: message,
                    style: style,
                    onLongPressStart: onLongPressStart,
                  ),
                ),
              ],
            ),
          ),
          _ChatAvatarSideSpacer(style: style),
        ],
      ),
    );
  }
}

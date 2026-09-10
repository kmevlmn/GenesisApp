part of 'chat_ui_library.dart';

/// Subtle outline shared by Opening and inline narrator editing.
final Border chatNarratorEditorBorder = Border.all(
  color: GenesisColors.darkFaintFill.withValues(alpha: 0.06),
);

Color chatNarratorMessageBackgroundColor(ChatUiStyleConfig style) {
  if (!style.useScenePlateBubbleGeometry ||
      style.useConfiguredScenePlateSystemStyle) {
    return style.systemMessageBackgroundColor;
  }
  return const Color(0x80151517);
}

TextStyle chatNarratorMessageTextStyle(ChatUiStyleConfig style) {
  if (style.useScenePlateBubbleGeometry &&
      !style.useConfiguredScenePlateSystemStyle) {
    return const TextStyle(
      color: Color.fromRGBO(255, 255, 255, 0.73),
      fontSize: 14,
      height: 1.3,
      fontWeight: FontWeight.w400,
    );
  }
  return style.systemMessageTextStyle.copyWith(fontSize: 14);
}

Color? chatNarratorMessageIconColor(ChatUiStyleConfig style) {
  if (!style.useScenePlateBubbleGeometry) return null;
  return style.useConfiguredScenePlateSystemStyle
      ? chatNarratorMessageTextStyle(style).color
      : Colors.white.withValues(alpha: 0.60);
}

class ChatNarratorMessageBubble extends StatelessWidget {
  const ChatNarratorMessageBubble({
    super.key,
    required this.message,
    required this.style,
    this.onLongPressStart,
  });

  final ChatMessageVm message;
  final ChatUiStyleConfig style;
  final GestureLongPressStartCallback? onLongPressStart;

  @override
  Widget build(BuildContext context) {
    final usesScenePlate = style.useScenePlateBubbleGeometry;
    final narratorTextStyle = chatNarratorMessageTextStyle(style);
    final editor = ChatMessageEditorScope.controllerOf(
      context,
      message.localId,
    );
    return ChatSystemMessage(
      content: editor == null
          ? null
          : _ChatMessageTextEditor(
              messageId: message.localId,
              controller: editor,
              style: usesScenePlate
                  ? genesisSoftItalicStyle(
                      narratorTextStyle,
                      platform: Theme.of(context).platform,
                    )
                  : narratorTextStyle,
            ),
      text: message.text,
      fullWidth: true,
      textAlign: TextAlign.left,
      leadingIconAsset: paragraphIconAsset,
      backgroundColor: chatNarratorMessageBackgroundColor(style),
      border: editor == null ? null : chatNarratorEditorBorder,
      textStyle: narratorTextStyle,
      leadingIconColor: chatNarratorMessageIconColor(style),
      softItalic: usesScenePlate,
      markdownEmphasisColor: narratorTextStyle.color ?? Colors.white,
      style: style,
      onLongPressStart: onLongPressStart,
    );
  }
}

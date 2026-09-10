part of 'chat_ui_library.dart';

class ChatStoryEventsMessageBubble extends StatelessWidget {
  const ChatStoryEventsMessageBubble({
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
    final payload = message.timelinePayload;
    if (payload is! ChatStoryEventsPayloadVm || payload.paragraphs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: style.systemMessageMargin,
      child: GestureDetector(
        onLongPressStart: onLongPressStart,
        child: Container(
          key: ValueKey<String>('chat-story-events-message-${message.localId}'),
          width: double.infinity,
          padding: style.systemMessagePadding,
          decoration: BoxDecoration(
            color: style.systemMessageBackgroundColor,
            borderRadius: BorderRadius.circular(
              style.systemMessageBorderRadius,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < payload.paragraphs.length; index += 1)
                _ChatStoryEventParagraph(
                  messageLocalId: message.localId,
                  index: index,
                  paragraph: payload.paragraphs[index],
                  style: style,
                  addTopSpacing: index > 0,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatStoryEventParagraph extends StatelessWidget {
  const _ChatStoryEventParagraph({
    required this.messageLocalId,
    required this.index,
    required this.paragraph,
    required this.style,
    required this.addTopSpacing,
    this.scenePlate = false,
  });

  final String messageLocalId;
  final int index;
  final ChatStoryEventParagraphVm paragraph;
  final ChatUiStyleConfig style;
  final bool addTopSpacing;
  final bool scenePlate;

  @override
  Widget build(BuildContext context) {
    if (scenePlate) {
      return ChatTickStoryEventParagraph(
        messageLocalId: messageLocalId,
        index: index,
        paragraph: paragraph,
        addTopSpacing: addTopSpacing,
      );
    }
    final textColor = style.systemMessageTextStyle.color ?? Colors.white;
    final metadataStyle = style.systemMessageTextStyle.copyWith(
      color: textColor.withValues(alpha: 0.72),
      fontSize: 11,
      fontWeight: FontWeight.w400,
      height: 1.3,
    );
    final isPublic = paragraph.visibilityLabel.trim().toLowerCase() == 'public';
    final hasTimestamp = paragraph.timestamp.trim().isNotEmpty;
    final hasVisibility =
        !isPublic && paragraph.visibilityLabel.trim().isNotEmpty;
    return Container(
      key: ValueKey<String>(
        'chat-story-event-paragraph-$messageLocalId-$index',
      ),
      width: double.infinity,
      margin: EdgeInsets.only(top: addTopSpacing ? 10 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SvgPicture.asset(
                eventsIconAsset,
                key: ValueKey<String>(
                  'chat-story-event-icon-$messageLocalId-$index',
                ),
                width: 13,
                height: 13,
                colorFilter: ColorFilter.mode(
                  textColor.withValues(alpha: 0.60),
                  BlendMode.srcIn,
                ),
              ),
              if (hasTimestamp) ...[
                const SizedBox(width: 8),
                Text(
                  genesisDisplaySafeText(paragraph.timestamp),
                  key: ValueKey<String>(
                    'chat-story-event-timestamp-$messageLocalId-$index',
                  ),
                  style: metadataStyle,
                ),
              ],
              if (hasVisibility) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _ChatStoryEventVisibility(
                    key: ValueKey<String>(
                      'chat-story-event-visibility-$messageLocalId-$index',
                    ),
                    label: paragraph.visibilityLabel,
                    visibleRoles: paragraph.visibleRoles,
                    style: style,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          _InlineMarkdownText(
            text: paragraph.text,
            textAlign: TextAlign.left,
            style: style.systemMessageTextStyle.copyWith(
              fontSize: 13,
              height: 1.3,
            ),
          ),
          if (paragraph.clue.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Row(
              key: ValueKey<String>(
                'chat-story-event-clue-$messageLocalId-$index',
              ),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SvgPicture.asset(
                    clueIconAsset,
                    width: 14,
                    height: 14,
                    colorFilter: ColorFilter.mode(textColor, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: _InlineMarkdownText(
                    text: paragraph.clue,
                    textAlign: TextAlign.left,
                    style: style.systemMessageTextStyle.copyWith(
                      color: textColor.withValues(alpha: 0.72),
                      fontSize: 13,
                      height: 1.3,
                    ),
                    softItalic: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class ChatTickStoryEventParagraph extends StatelessWidget {
  const ChatTickStoryEventParagraph({
    super.key,
    required this.messageLocalId,
    required this.index,
    required this.paragraph,
    required this.addTopSpacing,
  });

  final String messageLocalId;
  final int index;
  final ChatStoryEventParagraphVm paragraph;
  final bool addTopSpacing;

  @override
  Widget build(BuildContext context) {
    final hasTimestamp = paragraph.timestamp.trim().isNotEmpty;
    final hasVisibleRoles = paragraph.visibleRoles.isNotEmpty;
    final visibilityLabel = paragraph.visibilityLabel.trim();
    final showFallbackVisibility =
        !hasVisibleRoles &&
        visibilityLabel.isNotEmpty &&
        visibilityLabel.toLowerCase() != 'public';
    return Container(
      key: ValueKey<String>(
        'chat-story-event-paragraph-$messageLocalId-$index',
      ),
      width: double.infinity,
      margin: EdgeInsets.only(top: addTopSpacing ? 12 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: const Offset(0, -1),
            child: SvgPicture.asset(
              eventsIconAsset,
              key: ValueKey<String>(
                'chat-story-event-icon-$messageLocalId-$index',
              ),
              width: 13,
              height: 13,
              colorFilter: ColorFilter.mode(
                _tickMessageHeaderColor.withValues(alpha: 0.60),
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasTimestamp)
                  Text(
                    genesisDisplaySafeText(paragraph.timestamp),
                    key: ValueKey<String>(
                      'chat-story-event-timestamp-$messageLocalId-$index',
                    ),
                    style: TextStyle(
                      color: GenesisColors.darkTextTertiary,
                      fontSize: 11,
                      height: 1,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                if (hasVisibleRoles || showFallbackVisibility) ...[
                  if (hasTimestamp) const SizedBox(height: 8),
                  KeyedSubtree(
                    key: ValueKey<String>(
                      'chat-story-event-visibility-$messageLocalId-$index',
                    ),
                    child: hasVisibleRoles
                        ? _ChatTickSceneVisibleRoles(
                            roles: paragraph.visibleRoles,
                          )
                        : Text(
                            genesisDisplaySafeText(visibilityLabel),
                            style: TextStyle(
                              color: GenesisColors.darkTextSecondary,
                              fontSize: 13,
                              height: 1,
                            ),
                          ),
                  ),
                ],
                const SizedBox(height: 7),
                _InlineMarkdownText(
                  text: paragraph.text,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: GenesisColors.darkTextSecondary,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (paragraph.clue.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    key: ValueKey<String>(
                      'chat-story-event-clue-$messageLocalId-$index',
                    ),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: SvgPicture.asset(
                          clueIconAsset,
                          key: ValueKey<String>(
                            'chat-story-event-key-icon-$messageLocalId-$index',
                          ),
                          width: 13,
                          height: 13,
                          colorFilter: const ColorFilter.mode(
                            GenesisColors.redSecondary,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InlineMarkdownText(
                          text: paragraph.clue,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            color: GenesisColors.redSecondary,
                            fontSize: 13,
                            height: 1.3,
                            fontWeight: FontWeight.w400,
                          ),
                          softItalic: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTickSceneVisibleRoles extends StatelessWidget {
  const _ChatTickSceneVisibleRoles({required this.roles});

  final List<ChatStoryEventVisibleRoleVm> roles;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final role in roles) _ChatTickSceneVisibleRole(role: role),
      ],
    );
  }
}

class _ChatTickSceneVisibleRole extends StatelessWidget {
  const _ChatTickSceneVisibleRole({required this.role});

  final ChatStoryEventVisibleRoleVm role;

  @override
  Widget build(BuildContext context) {
    final isPlayerRole = !role.isAi;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: ValueKey<String>('chat-tick-visible-role-avatar-${role.roleId}'),
          width: 18,
          height: 18,
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: isPlayerRole
                ? Border.all(color: _tickMessageAccentColor, width: 1.5)
                : null,
          ),
          child: GenesisAvatar(
            name: role.name,
            url: role.avatarUrl,
            size: 18,
            borderRadius: 6,
            textStyle: const TextStyle(
              color: GenesisColors.darkTextPrimary,
              fontSize: 9.5,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            genesisDisplaySafeText(role.name),
            style: TextStyle(
              color: isPlayerRole
                  ? GenesisColors.darkTextPrimary
                  : GenesisColors.darkTextSecondary,
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatStoryEventVisibility extends StatelessWidget {
  const _ChatStoryEventVisibility({
    super.key,
    required this.label,
    required this.visibleRoles,
    required this.style,
  });

  final String label;
  final List<ChatStoryEventVisibleRoleVm> visibleRoles;
  final ChatUiStyleConfig style;

  @override
  Widget build(BuildContext context) {
    final textColor = style.systemMessageTextStyle.color ?? Colors.white;
    final badgeColor = textColor.withValues(alpha: 0.72);
    final aiNames = visibleRoles
        .where((role) => role.isAi)
        .map((role) => role.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final playerNames = visibleRoles
        .where((role) => !role.isAi)
        .map((role) => role.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final names = <String>[...aiNames, ...playerNames];
    if (names.isEmpty && label.trim().isNotEmpty) {
      names.add(label.trim());
    }
    if (names.isEmpty) return const SizedBox.shrink();
    return _ChatStoryEventVisibleRoleGroup(
      iconAsset: characterStatIconAsset,
      names: names,
      textColor: badgeColor,
    );
  }
}

class _ChatStoryEventVisibleRoleGroup extends StatelessWidget {
  const _ChatStoryEventVisibleRoleGroup({
    required this.iconAsset,
    required this.names,
    required this.textColor,
  });

  final String iconAsset;
  final List<String> names;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SvgPicture.asset(
            iconAsset,
            width: 12,
            height: 12,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            colorFilter: ColorFilter.mode(
              textColor.withValues(alpha: 1),
              BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            genesisDisplaySafeText(names.join(', ')),
            softWrap: true,
            style: TextStyle(color: textColor, fontSize: 13, height: 1.3),
          ),
        ),
      ],
    );
  }
}

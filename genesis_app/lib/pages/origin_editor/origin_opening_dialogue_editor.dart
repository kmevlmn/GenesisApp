part of 'origin_editor_pages.dart';

const Color _openingDialogueAddColor = GenesisColors.darkTextSecondary;

class _OpeningDialogueEditor extends StatelessWidget {
  const _OpeningDialogueEditor({
    required this.items,
    required this.characters,
    required this.onAddNarrator,
    required this.onAddCharacter,
    required this.onAddImage,
    required this.onDelete,
    required this.onChanged,
  });

  final List<_OpeningDialogueItem> items;
  final List<CharacterDraft> characters;
  final VoidCallback onAddNarrator;
  final ValueChanged<CharacterDraft> onAddCharacter;
  final VoidCallback onAddImage;
  final ValueChanged<_OpeningDialogueItem> onDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final style = kOpeningDialogueStyle;
    final namedCharacters = characters
        .where((character) => character.name.trim().isNotEmpty)
        .toList(growable: false);
    return SizedBox(
      key: const ValueKey<String>('opening-dialogue-editor'),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int index = 0; index < items.length; index++) ...[
            CreateKeyboardSafeFocusRegion(
              builder: (context, focusNode) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _OpeningDialogueContentEditor(
                    item: items[index],
                    style: style,
                    onDelete: () => onDelete(items[index]),
                    onChanged: onChanged,
                    focusNode: focusNode,
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ],
          Column(
            key: const ValueKey<String>('opening-dialogue-add-buttons'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (namedCharacters.isNotEmpty) ...[
                Wrap(
                  key: const ValueKey<String>(
                    'opening-dialogue-character-buttons',
                  ),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final character in namedCharacters)
                      _OpeningDialogueAddButton(
                        key: ValueKey<String>(
                          'opening-add-character-${character.charId.trim()}',
                        ),
                        label: character.name.trim(),
                        leading: SvgPicture.asset(
                          characterStatIconAsset,
                          width: 14,
                          height: 14,
                          colorFilter: const ColorFilter.mode(
                            _openingDialogueAddColor,
                            BlendMode.srcIn,
                          ),
                        ),
                        onTap: () => onAddCharacter(character),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                key: const ValueKey<String>('opening-dialogue-media-buttons'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  _OpeningDialogueAddButton(
                    key: const ValueKey<String>('opening-add-narrator'),
                    label: 'Narrator',
                    leading: SvgPicture.asset(
                      paragraphIconAsset,
                      width: 14,
                      height: 14,
                      colorFilter: const ColorFilter.mode(
                        _openingDialogueAddColor,
                        BlendMode.srcIn,
                      ),
                    ),
                    onTap: onAddNarrator,
                  ),
                  _OpeningDialogueAddButton(
                    key: const ValueKey<String>('opening-add-image'),
                    label: 'Image',
                    leading: const Icon(
                      Icons.image_outlined,
                      color: _openingDialogueAddColor,
                      size: 16,
                    ),
                    onTap: onAddImage,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OpeningBestRoleSelector extends StatelessWidget {
  const _OpeningBestRoleSelector({
    required this.characters,
    required this.onChanged,
  });

  final List<CharacterDraft> characters;
  final ValueChanged<CharacterDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        key: const ValueKey<String>('opening-best-role-selector'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Suggest a role for user',
            style: TextStyle(
              color: GenesisColors.darkTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: _fieldLabelInputGap),
          if (characters.isEmpty)
            const Text(
              'No characters available.',
              style: TextStyle(
                color: GenesisColors.darkTextTertiary,
                fontSize: 13,
                height: 1.2,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final character in characters)
                  _OpeningBestRoleOption(
                    character: character,
                    onTap: () => onChanged(character),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _OpeningBestRoleOption extends StatelessWidget {
  const _OpeningBestRoleOption({required this.character, required this.onTap});

  final CharacterDraft character;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final characterId = character.charId.trim();
    return Semantics(
      button: true,
      selected: character.isRecommended,
      label: '${character.name.trim()} suggested for the user',
      child: GestureDetector(
        key: ValueKey<String>('opening-best-role-$characterId'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          key: ValueKey<String>('opening-best-role-card-$characterId'),
          width: 104,
          height: 116,
          child: Column(
            children: [
              SizedBox(
                width: 82,
                height: 82,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GenesisCharacterAvatar(
                      key: ValueKey<String>(
                        'opening-best-role-avatar-$characterId',
                      ),
                      url: character.avatarUrl.trim(),
                      name: character.name.trim(),
                      size: 82,
                      borderRadius: GenesisAvatarRadii.character,
                      showFallbackWhileLoading: false,
                    ),
                    if (character.isRecommended)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: OriginRecommendedRoleMark(
                          badgeKey: ValueKey<String>(
                            'opening-best-role-mark-$characterId',
                          ),
                          showBackground: true,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(
                character.name.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: GenesisColors.darkTextPrimary,
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpeningDialogueContentEditor extends StatelessWidget {
  const _OpeningDialogueContentEditor({
    required this.item,
    required this.style,
    required this.onDelete,
    required this.onChanged,
    required this.focusNode,
  });

  final _OpeningDialogueItem item;
  final ChatUiStyleConfig style;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return switch (item.type) {
      _OpeningDialogueType.narrator => _OpeningNarratorEditor(
        item: item,
        style: style,
        onDelete: onDelete,
        onChanged: onChanged,
        focusNode: focusNode,
      ),
      _OpeningDialogueType.character => _OpeningCharacterEditor(
        item: item,
        style: style,
        onDelete: onDelete,
        onChanged: onChanged,
        focusNode: focusNode,
      ),
      _OpeningDialogueType.image => _OpeningImageEditor(
        item: item,
        style: style,
        onDelete: onDelete,
        onChanged: onChanged,
      ),
    };
  }
}

class _OpeningNarratorEditor extends StatelessWidget {
  const _OpeningNarratorEditor({
    required this.item,
    required this.style,
    required this.onDelete,
    required this.onChanged,
    required this.focusNode,
  });

  final _OpeningDialogueItem item;
  final ChatUiStyleConfig style;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final narratorTextStyle = chatNarratorMessageTextStyle(style);
    final iconColor =
        chatNarratorMessageIconColor(style) ?? narratorTextStyle.color!;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: style.systemMessageMargin.left,
            right: style.systemMessageMargin.right,
          ),
          child: Container(
            key: ValueKey<String>('${item.id}-narrator'),
            width: double.infinity,
            padding: style.systemMessagePadding,
            decoration: BoxDecoration(
              color: chatNarratorMessageBackgroundColor(style),
              border: Border.all(
                color: GenesisColors.darkFaintFill.withValues(alpha: 0.06),
              ),
              borderRadius: BorderRadius.circular(
                style.systemMessageBorderRadius,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: SvgPicture.asset(
                    paragraphIconAsset,
                    width: 13,
                    height: 13,
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _OpeningDialogueTextField(
                    key: ValueKey<String>(
                      '${item.id}-keyboard-safe-text-field',
                    ),
                    item: item,
                    hintText: 'Enter narrator dialogue',
                    style: narratorTextStyle,
                    softItalic: true,
                    insertTextColor: GenesisColors.darkTextSecondary,
                    insertBackgroundColor: GenesisColors.darkFaintFill,
                    onChanged: onChanged,
                    focusNode: focusNode,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: -8,
          child: GenesisDeleteButton(
            buttonKey: ValueKey<String>('${item.id}-delete'),
            decorationKey: ValueKey<String>('${item.id}-delete-container'),
            onPressed: onDelete,
          ),
        ),
      ],
    );
  }
}

class _OpeningCharacterEditor extends StatelessWidget {
  const _OpeningCharacterEditor({
    required this.item,
    required this.style,
    required this.onDelete,
    required this.onChanged,
    required this.focusNode,
  });

  final _OpeningDialogueItem item;
  final ChatUiStyleConfig style;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final character = item.character!;
    final name = character.name.trim();
    final bubbleWidthCaps =
        locationChatOrdinaryMessageBubbleMaxWidthCapsForMetrics(
          logicalWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
          bubbleFontSize: style.bubbleTextStyle.fontSize ?? 14,
          crowdedEffectiveWidthThreshold: locationChatBubbleLayoutSettings
              .value
              .crowdedEffectiveWidthThreshold,
          avatarSize: style.avatarSize,
          avatarBubbleGap: style.avatarBubbleGap,
          avatarSideSpacerWidth: style.avatarSideSpacerWidth,
          messageListHorizontalPadding: style.messageListPadding.horizontal,
        );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          key: ValueKey<String>('${item.id}-character'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChatAvatar(
              label: chatInitials(name),
              imageUrl: character.avatarUrl,
              colors: style.otherAvatarColors,
              seed: name,
              style: style,
            ),
            SizedBox(width: style.avatarBubbleGap),
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                key: ValueKey<String>('${item.id}-bubble-width-limit'),
                constraints: BoxConstraints(
                  maxWidth: bubbleWidthCaps.otherMessage,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      key: ValueKey<String>('${item.id}-name-row'),
                      height:
                          MediaQuery.textScalerOf(
                            context,
                          ).scale(style.senderNameTextStyle.fontSize ?? 11) *
                          (style.senderNameTextStyle.height ?? 1),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.senderNameTextStyle,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: style.senderNameBottomGap),
                    Container(
                      key: ValueKey<String>('${item.id}-bubble'),
                      width: double.infinity,
                      padding: style.bubblePadding,
                      decoration: BoxDecoration(
                        color: style.otherBubbleColor,
                        borderRadius: kChatScenePlateAiBubbleBorderRadius,
                      ),
                      child: _OpeningDialogueTextField(
                        key: ValueKey<String>(
                          '${item.id}-keyboard-safe-text-field',
                        ),
                        item: item,
                        hintText: 'Enter $name dialogue',
                        style: style.bubbleTextStyle,
                        insertTextColor: GenesisColors.darkTextSecondary,
                        insertBackgroundColor: GenesisColors.darkFaintFill,
                        showAsteriskInsert: true,
                        onChanged: onChanged,
                        focusNode: focusNode,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: style.avatarSideSpacerWidth),
          ],
        ),
        Positioned(
          right: 0,
          top: -8,
          child: GenesisDeleteButton(
            buttonKey: ValueKey<String>('${item.id}-delete'),
            decorationKey: ValueKey<String>('${item.id}-delete-container'),
            onPressed: onDelete,
          ),
        ),
      ],
    );
  }
}

class _OpeningDialogueTextField extends StatelessWidget {
  const _OpeningDialogueTextField({
    super.key,
    required this.item,
    required this.hintText,
    required this.style,
    required this.insertTextColor,
    required this.insertBackgroundColor,
    this.showAsteriskInsert = false,
    this.softItalic = false,
    required this.onChanged,
    required this.focusNode,
  });

  final _OpeningDialogueItem item;
  final String hintText;
  final TextStyle style;
  final Color insertTextColor;
  final Color insertBackgroundColor;
  final bool showAsteriskInsert;
  final bool softItalic;
  final VoidCallback onChanged;
  final FocusNode focusNode;

  static const int _maxCharacterCount = 500;

  void _insertToken(String token) {
    final value = item.controller.value;
    final text = value.text;
    final selection = value.selection;

    int safeOffset(int offset) {
      if (offset < 0 || offset > text.length) return text.length;
      return offset;
    }

    final selectionStart = selection.isValid
        ? safeOffset(selection.start)
        : text.length;
    final selectionEnd = selection.isValid
        ? safeOffset(selection.end)
        : text.length;
    final replaceStart = selectionStart < selectionEnd
        ? selectionStart
        : selectionEnd;
    final replaceEnd = selectionStart < selectionEnd
        ? selectionEnd
        : selectionStart;
    final updatedText = text.replaceRange(replaceStart, replaceEnd, token);
    if (updatedText.characters.length > _maxCharacterCount) {
      focusNode.requestFocus();
      return;
    }
    item.controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: replaceStart + token.length),
    );
    focusNode.requestFocus();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final textStyle = softItalic
        ? genesisSoftItalicStyle(style, platform: platform)
        : style;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[focusNode, item.controller]),
      builder: (context, child) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          genesisSoftItalicForPlatform(
            platform: platform,
            useIosSkew: softItalic && GenesisTypography.useIosSoftItalicSkew,
            child: TextField(
              key: ValueKey<String>('${item.id}-field'),
              controller: item.controller,
              focusNode: focusNode,
              cursorColor: GenesisColors.darkTextPrimary,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              scrollPadding: const EdgeInsets.fromLTRB(
                20,
                20,
                20,
                kMinInteractiveDimension,
              ),
              minLines: 3,
              maxLines: null,
              maxLength: _maxCharacterCount,
              style: textStyle,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.zero,
                hintText: hintText,
                hintStyle: textStyle.copyWith(
                  color: GenesisColors.darkInputPlaceholder,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      key: ValueKey<String>('${item.id}-insert-actions'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _OpeningDialogueInsertButton(
                          buttonKey: ValueKey<String>('${item.id}-insert-user'),
                          label: '{{user}}',
                          textColor: insertTextColor,
                          backgroundColor: insertBackgroundColor,
                          onTap: () => _insertToken('{{user}}'),
                        ),
                        if (showAsteriskInsert) ...[
                          const SizedBox(width: 10),
                          _OpeningDialogueInsertButton(
                            buttonKey: ValueKey<String>(
                              '${item.id}-insert-asterisk',
                            ),
                            label: '*',
                            textColor: insertTextColor,
                            backgroundColor: insertBackgroundColor,
                            square: true,
                            onTap: () => _insertToken('*'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item.controller.text.characters.length}/'
                '$_maxCharacterCount',
                key: ValueKey<String>('${item.id}-character-count'),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: GenesisColors.darkTextTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OpeningDialogueInsertButton extends StatelessWidget {
  const _OpeningDialogueInsertButton({
    required this.buttonKey,
    required this.label,
    required this.textColor,
    required this.backgroundColor,
    required this.onTap,
    this.square = false,
  });

  final Key buttonKey;
  final String label;
  final Color textColor;
  final Color backgroundColor;
  final VoidCallback onTap;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: textColor,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1,
    );
    return Semantics(
      button: true,
      label: 'Insert $label',
      child: GestureDetector(
        key: buttonKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: square
              ? SizedBox.square(
                  dimension: 26,
                  child: Center(
                    child: label == '*'
                        ? GenesisAsteriskIcon(color: textColor)
                        : Text(
                            label,
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.center,
                            style: labelStyle,
                          ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.center,
                    style: labelStyle,
                  ),
                ),
        ),
      ),
    );
  }
}

class _OpeningImageEditor extends StatelessWidget {
  const _OpeningImageEditor({
    required this.item,
    required this.style,
    required this.onDelete,
    required this.onChanged,
  });

  final _OpeningDialogueItem item;
  final ChatUiStyleConfig style;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: style.systemMessageMargin.left,
        right: style.systemMessageMargin.right,
      ),
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Align(
                alignment: Alignment.centerLeft,
                child: CreateUploadBox(
                  key: ValueKey<String>('${item.id}-image'),
                  controller: item.controller,
                  label: 'UPLOAD IMAGE',
                  emptyBackgroundColor: GenesisColors.darkFaintFill,
                  emptyBorderColor: GenesisColors.darkTextTertiary,
                  emptyIconColor: GenesisColors.createAdd,
                  emptyLabelColor: GenesisColors.darkTextSecondary,
                  borderRadius: 8,
                  width: width,
                  height: width,
                  uploadOriginalImage: true,
                  preserveImageAspectRatio: true,
                  useMessageImageSizing: true,
                  previewAlignment: Alignment.center,
                  showRemoveLinkWhenFilled: false,
                  onChanged: onChanged,
                ),
              );
            },
          ),
          Positioned(
            right: 4,
            top: 4,
            child: GenesisDeleteButton(
              buttonKey: ValueKey<String>('${item.id}-delete'),
              decorationKey: ValueKey<String>('${item.id}-delete-container'),
              onPressed: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpeningDialogueAddButton extends StatelessWidget {
  const _OpeningDialogueAddButton({
    super.key,
    required this.label,
    required this.leading,
    required this.onTap,
  });

  final String label;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GenesisColors.darkFaintFill,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, color: _openingDialogueAddColor, size: 17),
              const SizedBox(width: 4),
              leading,
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: _openingDialogueAddColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

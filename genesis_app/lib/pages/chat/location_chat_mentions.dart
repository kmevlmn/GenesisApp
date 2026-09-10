part of 'location_chat_page.dart';

const String _locationChatMentionPlaceholder = '\uFFFC';
const Color _locationChatMentionPrimaryForeground =
    GenesisColors.darkTextPrimary;

ChatMentionCatalog mergeLocationChatMentionCatalogs(
  ChatMentionCatalog primary,
  ChatMentionCatalog? fallback,
) {
  if (fallback == null || fallback.isEmpty) return primary;
  if (primary.isEmpty) return fallback;
  final charactersById = <String, ChatMentionEntry>{
    for (final entry in primary.characters) entry.id.trim(): entry,
  }..remove('');
  final locationsById = <String, ChatMentionEntry>{
    for (final entry in primary.locations) entry.id.trim(): entry,
  }..remove('');
  for (final entry in fallback.characters) {
    final id = entry.id.trim();
    if (id.isNotEmpty) charactersById.putIfAbsent(id, () => entry);
  }
  for (final entry in fallback.locations) {
    final id = entry.id.trim();
    if (id.isNotEmpty) locationsById.putIfAbsent(id, () => entry);
  }
  return ChatMentionCatalog(
    characters: charactersById.values,
    currentLocationCharacters: primary.currentLocationCharacters,
    locations: locationsById.values,
  );
}

@visibleForTesting
ChatMentionCatalog locationChatMentionCatalogForState(
  WorldChatroomState state, {
  Iterable<String> currentUserIds = const <String>[],
  Iterable<String> currentSenderIds = const <String>[],
  Iterable<String> currentLocationIds = const <String>[],
}) {
  final world = state.world;
  if (world == null) return ChatMentionCatalog.empty;
  final currentIdentityKeys = <String>{
    ...currentUserIds.map(_chatroomIdentityKey),
    ...currentSenderIds.map(_chatroomIdentityKey),
  }..remove('');

  final characterIds = <String>{};
  final characters = <ChatMentionEntry>[];
  final characterEntriesByIdentity = <String, ChatMentionEntry>{};
  for (final character in world.characters) {
    final id = _firstMapString(character, const [
      'char_id',
      'character_id',
      'id',
    ]).trim();
    if (id.isEmpty || characterIds.contains(id)) continue;
    final playerIdentityKeys = <String>{
      for (final key in const ['player_uid', 'user_id', 'uid'])
        _chatroomIdentityKey(_mapString(character, key)),
    }..remove('');
    final isPlayerControlled = playerIdentityKeys.isNotEmpty;
    final characterIdentityKeys = <String>{
      _chatroomIdentityKey(id),
      ...playerIdentityKeys,
    }..remove('');
    if (isPlayerControlled &&
        characterIdentityKeys.any(currentIdentityKeys.contains)) {
      continue;
    }
    final name = _firstMapString(character, const [
      'name',
      'role_nickname',
      'role_name',
      'character_name',
    ]).trim();
    if (name.isEmpty) continue;
    characterIds.add(id);
    final entry = ChatMentionEntry(
      id: id,
      name: normalizeGenesisUgcTextForDisplay(name),
      type: ChatMentionType.character,
      imageUrl: _firstMapImageUrl(character, const ['avatar', 'avatar_url']),
      isPlayerControlled: isPlayerControlled,
      isNew: asBool(character['is_new']),
    );
    characters.add(entry);
    for (final identityKey in characterIdentityKeys) {
      characterEntriesByIdentity.putIfAbsent(identityKey, () => entry);
    }
  }

  final resolvedCurrentLocationIds = <String>{
    ...currentLocationIds.map((id) => id.trim()),
  }..remove('');
  if (resolvedCurrentLocationIds.isEmpty) {
    final joinedLocationId = state.joinedLocationId.trim();
    if (joinedLocationId.isNotEmpty) {
      resolvedCurrentLocationIds.add(joinedLocationId);
    }
  }
  final currentLocationCharactersById = <String, ChatMentionEntry>{};

  void addCurrentLocationCharacterForIdentities(Iterable<String> identities) {
    for (final identity in identities) {
      final entry = characterEntriesByIdentity[_chatroomIdentityKey(identity)];
      if (entry == null) continue;
      currentLocationCharactersById.putIfAbsent(entry.id, () => entry);
      return;
    }
  }

  for (final locationId in resolvedCurrentLocationIds) {
    for (final entity
        in state.entitiesByLocation[locationId] ??
            const <WorldChatroomEntity>[]) {
      addCurrentLocationCharacterForIdentities(<String>[entity.id]);
    }
  }
  for (final position in world.characterPositions) {
    final locationId = _firstMapString(position, const [
      'location_id',
      'current_location_id',
    ]);
    if (!resolvedCurrentLocationIds.contains(locationId)) continue;
    final rawCharacter = position['character'];
    final character = rawCharacter is Map
        ? _stringKeyMap(rawCharacter)
        : position;
    addCurrentLocationCharacterForIdentities(<String>[
      for (final key in const [
        'character_id',
        'char_id',
        'id',
        'player_uid',
        'user_id',
        'uid',
      ])
        _mapString(character, key),
    ]);
  }

  final locationTree = world.processedLocationTree;
  final locationNodes = locationTree.flattened.where(
    (node) => node.children.isEmpty,
  );
  final locationIds = <String>{};
  final locations = <ChatMentionEntry>[];
  for (final node in locationNodes) {
    final id = firstNonEmpty([
      node.id,
      _firstMapString(node.value, const ['location_id', 'id']),
    ]);
    if (id.isEmpty || locationIds.contains(id)) continue;
    final name = _firstMapString(node.value, const [
      'location_name',
      'name',
    ]).trim();
    if (name.isEmpty) continue;
    final parent = locationTree.nodeById(node.parentId);
    final parentName = parent == null
        ? ''
        : _firstMapString(parent.value, const ['location_name', 'name']).trim();
    final declaredLevel = asInt(node.value['level']);
    final isLevel3 = (declaredLevel > 0 ? declaredLevel : node.depth) == 3;
    locationIds.add(id);
    locations.add(
      ChatMentionEntry(
        id: id,
        name: normalizeGenesisUgcTextForDisplay(name),
        type: ChatMentionType.location,
        subtitle: normalizeGenesisUgcTextForDisplay(parentName),
        isNew: isLevel3 && asBool(node.value['is_new']),
        isCurrentLocation: resolvedCurrentLocationIds.contains(id),
      ),
    );
  }

  return ChatMentionCatalog(
    characters: characters,
    currentLocationCharacters: currentLocationCharactersById.values,
    locations: locations,
  );
}

class LocationChatMentionEditingController extends TextEditingController {
  LocationChatMentionEditingController({ChatMentionCatalog? catalog})
    : _catalog = catalog ?? ChatMentionCatalog.empty;

  ChatMentionCatalog _catalog;
  final List<_LocationChatComposerMention> _mentions =
      <_LocationChatComposerMention>[];
  int? _insertedAtOffset;
  bool _applyingValue = false;

  ChatMentionCatalog get catalog => _catalog;

  ChatMentionCatalog get composedMentionCatalog {
    final characters = <String, ChatMentionEntry>{};
    final locations = <String, ChatMentionEntry>{};
    for (final mention in _mentions) {
      final entry = mention.entry;
      final id = entry.id.trim();
      if (id.isEmpty) continue;
      final target = entry.type == ChatMentionType.character
          ? characters
          : locations;
      target.putIfAbsent(id, () => entry);
    }
    return ChatMentionCatalog(
      characters: characters.values,
      locations: locations.values,
    );
  }

  String get serializedText {
    final buffer = StringBuffer();
    var mentionIndex = 0;
    for (var index = 0; index < text.length; index += 1) {
      if (text[index] != _locationChatMentionPlaceholder) {
        buffer.write(text[index]);
        continue;
      }
      if (mentionIndex < _mentions.length) {
        buffer.write(_mentions[mentionIndex].serializedText);
      }
      mentionIndex += 1;
    }
    return buffer.toString();
  }

  int? takeInsertedAtOffset() {
    final result = _insertedAtOffset;
    _insertedAtOffset = null;
    return result;
  }

  void insertShortcut(String shortcut) {
    final value = this.value;
    final selection = value.selection;
    final textLength = value.text.length;
    final hasUsableSelection =
        selection.isValid &&
        selection.start <= textLength &&
        selection.end <= textLength;
    final start = hasUsableSelection ? selection.start : textLength;
    final end = hasUsableSelection ? selection.end : textLength;
    this.value = TextEditingValue(
      text: value.text.replaceRange(start, end, shortcut),
      selection: TextSelection.collapsed(offset: start + shortcut.length),
    );
  }

  bool updateCatalog(ChatMentionCatalog nextCatalog) {
    final effectiveCatalog = mergeLocationChatMentionCatalogs(
      nextCatalog,
      composedMentionCatalog,
    );
    if (_catalogSignature(_catalog) == _catalogSignature(effectiveCatalog)) {
      return false;
    }
    final rawText = serializedText;
    final serializedBase = _internalOffsetToSerialized(selection.baseOffset);
    final serializedExtent = _internalOffsetToSerialized(
      selection.extentOffset,
    );
    _catalog = effectiveCatalog;
    _setSerializedValue(
      rawText,
      serializedSelection: TextSelection(
        baseOffset: serializedBase,
        extentOffset: serializedExtent,
      ),
    );
    return true;
  }

  void setSerializedText(String rawText) {
    _setSerializedValue(
      rawText,
      serializedSelection: TextSelection.collapsed(offset: rawText.length),
    );
  }

  void insertMention(
    ChatMentionEntry entry, {
    required int replaceStart,
    required int replaceEnd,
  }) {
    final safeStart = replaceStart.clamp(0, text.length);
    final safeEnd = replaceEnd.clamp(safeStart, text.length);
    final mentionIndex = _placeholderCount(text.substring(0, safeStart));
    final removedCount = _placeholderCount(text.substring(safeStart, safeEnd));
    if (removedCount > 0) {
      _mentions.removeRange(mentionIndex, mentionIndex + removedCount);
    }
    _mentions.insert(
      mentionIndex,
      _LocationChatComposerMention(
        id: entry.id,
        name: entry.name,
        entry: entry,
        ownsTrailingSpace: true,
      ),
    );
    final replacedText = text.replaceRange(
      safeStart,
      safeEnd,
      _locationChatMentionPlaceholder,
    );
    final mentionEnd = safeStart + 1;
    final hasTrailingSpace =
        mentionEnd < replacedText.length && replacedText[mentionEnd] == ' ';
    final nextText = hasTrailingSpace
        ? replacedText.replaceRange(mentionEnd, mentionEnd + 1, '')
        : replacedText;
    _setInternalValue(
      TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: mentionEnd),
      ),
    );
  }

  @override
  set value(TextEditingValue newValue) {
    if (_applyingValue) {
      super.value = newValue;
      return;
    }
    final oldValue = super.value;
    if (oldValue.text == newValue.text) {
      super.value = newValue;
      return;
    }

    final difference = _singleTextDifference(oldValue.text, newValue.text);
    final mentionIndex = _placeholderCount(
      oldValue.text.substring(0, difference.oldStart),
    );
    final removedMentions = _placeholderCount(
      oldValue.text.substring(difference.oldStart, difference.oldEnd),
    );
    if (removedMentions > 0) {
      _mentions.removeRange(mentionIndex, mentionIndex + removedMentions);
    }

    final inserted = newValue.text.substring(
      difference.newStart,
      difference.newEnd,
    );
    final sanitizedInserted = inserted.replaceAll(
      _locationChatMentionPlaceholder,
      '',
    );
    final sanitizedText = newValue.text.replaceRange(
      difference.newStart,
      difference.newEnd,
      sanitizedInserted,
    );
    final strippedPlaceholders = inserted.length - sanitizedInserted.length;
    final nextSelection = _shiftSelectionAfterRemovedCharacters(
      newValue.selection,
      difference.newStart,
      strippedPlaceholders,
      sanitizedText.length,
    );
    final nextComposing = strippedPlaceholders == 0
        ? newValue.composing
        : TextRange.empty;

    final caret = nextSelection.extentOffset;
    final insertedStart = difference.newStart;
    final insertedEnd = insertedStart + sanitizedInserted.length;
    int? atOffset;
    for (var index = insertedEnd - 1; index >= insertedStart; index -= 1) {
      if (sanitizedText[index] == '@' && index < caret) {
        atOffset = index;
        break;
      }
    }
    _insertedAtOffset = atOffset;
    super.value = TextEditingValue(
      text: sanitizedText,
      selection: nextSelection,
      composing: nextComposing,
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <InlineSpan>[];
    final composing = withComposing && value.composing.isValid
        ? value.composing
        : TextRange.empty;
    var mentionIndex = 0;
    var index = 0;
    while (index < text.length) {
      if (text[index] == _locationChatMentionPlaceholder) {
        if (mentionIndex < _mentions.length) {
          final mention = _mentions[mentionIndex];
          spans.add(
            chatMentionWidgetSpan(
              ChatMentionToken(
                start: index,
                end: index + 1,
                name: mention.name,
                id: mention.id,
                entry: mention.entry,
              ),
              style: style,
              includeTrailingSpace: mention.ownsTrailingSpace,
            ),
          );
        }
        mentionIndex += 1;
        index += 1;
        continue;
      }

      final composingText =
          composing.isValid &&
          index >= composing.start &&
          index < composing.end;
      final start = index;
      while (index < text.length &&
          text[index] != _locationChatMentionPlaceholder &&
          (composing.isValid &&
                  index >= composing.start &&
                  index < composing.end) ==
              composingText) {
        index += 1;
      }
      spans.add(
        TextSpan(
          text: text.substring(start, index),
          style: composingText
              ? const TextStyle(decoration: TextDecoration.underline)
              : null,
        ),
      );
    }
    return TextSpan(style: style, children: spans);
  }

  void _setSerializedValue(
    String rawText, {
    required TextSelection serializedSelection,
  }) {
    final tokens = parseKnownChatMentions(rawText, _catalog);
    final buffer = StringBuffer();
    final mentions = <_LocationChatComposerMention>[];
    var offset = 0;
    for (final token in tokens) {
      buffer.write(rawText.substring(offset, token.start));
      buffer.write(_locationChatMentionPlaceholder);
      final ownsTrailingSpace = _mentionTokenHasTrailingSpace(rawText, token);
      mentions.add(
        _LocationChatComposerMention(
          id: token.id,
          name: token.name,
          entry: token.entry,
          ownsTrailingSpace: ownsTrailingSpace,
        ),
      );
      offset = token.end + (ownsTrailingSpace ? 1 : 0);
    }
    buffer.write(rawText.substring(offset));
    final internalText = buffer.toString();
    _mentions
      ..clear()
      ..addAll(mentions);
    _insertedAtOffset = null;
    _setInternalValue(
      TextEditingValue(
        text: internalText,
        selection: TextSelection(
          baseOffset: _serializedOffsetToInternal(
            rawText,
            tokens,
            serializedSelection.baseOffset,
          ),
          extentOffset: _serializedOffsetToInternal(
            rawText,
            tokens,
            serializedSelection.extentOffset,
          ),
        ),
      ),
    );
  }

  void _setInternalValue(TextEditingValue nextValue) {
    _applyingValue = true;
    try {
      super.value = nextValue;
    } finally {
      _applyingValue = false;
    }
  }

  int _internalOffsetToSerialized(int internalOffset) {
    final safeOffset = internalOffset.clamp(0, text.length);
    var serializedOffset = 0;
    var mentionIndex = 0;
    for (var index = 0; index < safeOffset; index += 1) {
      if (text[index] == _locationChatMentionPlaceholder &&
          mentionIndex < _mentions.length) {
        serializedOffset += _mentions[mentionIndex].serializedText.length;
        mentionIndex += 1;
      } else {
        serializedOffset += 1;
      }
    }
    return serializedOffset;
  }
}

class _LocationChatComposerMention {
  const _LocationChatComposerMention({
    required this.id,
    required this.name,
    required this.entry,
    required this.ownsTrailingSpace,
  });

  final String id;
  final String name;
  final ChatMentionEntry entry;
  final bool ownsTrailingSpace;

  String get serializedText => '@$name<$id>${ownsTrailingSpace ? ' ' : ''}';
}

bool _mentionTokenHasTrailingSpace(String text, ChatMentionToken token) {
  return token.end < text.length && text[token.end] == ' ';
}

({int oldStart, int oldEnd, int newStart, int newEnd}) _singleTextDifference(
  String oldText,
  String newText,
) {
  var prefix = 0;
  final shortestLength = math.min(oldText.length, newText.length);
  while (prefix < shortestLength && oldText[prefix] == newText[prefix]) {
    prefix += 1;
  }
  var suffix = 0;
  while (suffix < oldText.length - prefix &&
      suffix < newText.length - prefix &&
      oldText[oldText.length - 1 - suffix] ==
          newText[newText.length - 1 - suffix]) {
    suffix += 1;
  }
  return (
    oldStart: prefix,
    oldEnd: oldText.length - suffix,
    newStart: prefix,
    newEnd: newText.length - suffix,
  );
}

int _placeholderCount(String text) {
  return _locationChatMentionPlaceholder.allMatches(text).length;
}

TextSelection _shiftSelectionAfterRemovedCharacters(
  TextSelection selection,
  int removalStart,
  int removedCount,
  int textLength,
) {
  if (!selection.isValid || removedCount == 0) {
    return selection.isValid
        ? TextSelection(
            baseOffset: selection.baseOffset.clamp(0, textLength),
            extentOffset: selection.extentOffset.clamp(0, textLength),
          )
        : TextSelection.collapsed(offset: textLength);
  }
  int shift(int offset) {
    if (offset <= removalStart) return offset.clamp(0, textLength);
    return (offset - removedCount).clamp(0, textLength);
  }

  return TextSelection(
    baseOffset: shift(selection.baseOffset),
    extentOffset: shift(selection.extentOffset),
    affinity: selection.affinity,
    isDirectional: selection.isDirectional,
  );
}

int _serializedOffsetToInternal(
  String rawText,
  List<ChatMentionToken> tokens,
  int serializedOffset,
) {
  final target = serializedOffset.clamp(0, rawText.length);
  var sourceOffset = 0;
  var internalOffset = 0;
  for (final token in tokens) {
    final sourceEnd =
        token.end + (_mentionTokenHasTrailingSpace(rawText, token) ? 1 : 0);
    if (target <= token.start) {
      return internalOffset + target - sourceOffset;
    }
    internalOffset += token.start - sourceOffset;
    if (target <= sourceEnd) return internalOffset + 1;
    internalOffset += 1;
    sourceOffset = sourceEnd;
  }
  return internalOffset + target - sourceOffset;
}

int _catalogSignature(ChatMentionCatalog catalog) {
  return Object.hashAll(<Object?>[
    for (final entry in <ChatMentionEntry>[
      ...catalog.characters,
      ...catalog.locations,
    ]) ...[
      entry.id,
      entry.name,
      entry.type,
      entry.subtitle,
      entry.imageUrl,
      entry.isPlayerControlled,
      entry.isNew,
      entry.isCurrentLocation,
    ],
    'current-location-characters',
    ...catalog.currentLocationCharacters.map((entry) => entry.id),
    'new-locations',
    ...catalog.newLocations.map((entry) => entry.id),
  ]);
}

extension _LocationChatMentionActions on _LocationChatPanelState {
  ChatMentionCatalog _mentionCatalogForState(WorldChatroomState state) {
    final currentCatalog = locationChatMentionCatalogForState(
      state,
      currentUserIds: _myUserIdKeys,
      currentSenderIds: _mySenderIdKeys,
      currentLocationIds: _currentLocationIds(),
    );
    return mergeLocationChatMentionCatalogs(
      currentCatalog,
      _initialMessageSendPending ? widget.initialMentionCatalog : null,
    );
  }

  void _scheduleMentionSheet(int triggerOffset) {
    if (_mentionSheetOpen || _mentionSheetSchedulePending || !widget.active) {
      return;
    }
    _mentionSheetSchedulePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mentionSheetSchedulePending = false;
      if (!mounted || _mentionSheetOpen || !widget.active) return;
      unawaited(_showMentionSheet(triggerOffset));
    });
  }

  Future<void> _showMentionSheet(int triggerOffset) async {
    if (_mentionSheetOpen ||
        triggerOffset < 0 ||
        triggerOffset >= _textController.text.length ||
        _textController.text[triggerOffset] != '@') {
      return;
    }
    final view = View.maybeOf(context);
    final keyboardInset = view == null || view.devicePixelRatio <= 0
        ? 0.0
        : view.viewInsets.bottom / view.devicePixelRatio;
    _setLocationChatState(() {
      _mentionSheetKeyboardInset = keyboardInset;
      _mentionSheetOpen = true;
      _mentionComposerPositionFrozen = true;
    });
    _composerFocusNode.unfocus();
    final selected = await showGenesisModalBottomSheet<ChatMentionEntry>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (sheetContext) =>
          LocationChatMentionSheet(catalog: _textController.catalog),
    );
    if (!mounted) return;
    _setLocationChatState(() {
      _mentionSheetOpen = false;
    });
    if (selected != null) {
      final triggerStillExists =
          triggerOffset < _textController.text.length &&
          _textController.text[triggerOffset] == '@';
      final selection = _textController.selection;
      final fallbackStart = selection.isValid
          ? selection.start
          : _textController.text.length;
      final fallbackEnd = selection.isValid ? selection.end : fallbackStart;
      _textController.insertMention(
        selected,
        replaceStart: triggerStillExists ? triggerOffset : fallbackStart,
        replaceEnd: triggerStillExists ? triggerOffset + 1 : fallbackEnd,
      );
    }
    _composerFocusNode.requestFocus();
    _releaseMentionComposerPositionIfKeyboardRestored();
  }

  void _releaseMentionComposerPositionIfKeyboardRestored() {
    if (!_mentionComposerPositionFrozen || _mentionSheetOpen) return;
    final view = View.maybeOf(context);
    final keyboardInset = view == null || view.devicePixelRatio <= 0
        ? 0.0
        : view.viewInsets.bottom / view.devicePixelRatio;
    if (_mentionSheetKeyboardInset > 0 &&
        keyboardInset + 0.5 < _mentionSheetKeyboardInset) {
      return;
    }
    _handleMentionKeyboardInsetRestored();
  }

  void _handleMentionKeyboardInsetRestored() {
    if (!mounted || !_mentionComposerPositionFrozen || _mentionSheetOpen) {
      return;
    }
    _setLocationChatState(() {
      _mentionComposerPositionFrozen = false;
      _mentionSheetKeyboardInset = 0;
    });
  }
}

class LocationChatMentionSheet extends StatefulWidget {
  const LocationChatMentionSheet({super.key, required this.catalog});

  final ChatMentionCatalog catalog;

  @override
  State<LocationChatMentionSheet> createState() =>
      _LocationChatMentionSheetState();
}

class _LocationChatMentionSheetState extends State<LocationChatMentionSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.8;
    return Material(
      key: const ValueKey<String>('location-chat-mention-sheet'),
      color: GenesisColors.darkRaisedBackground,
      borderRadius: GenesisBottomSheetPanel.borderRadius,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              SizedBox(
                key: const ValueKey<String>('location-chat-mention-header'),
                height: 48,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 15,
                      child: SizedBox(
                        height: 28,
                        child: const Center(
                          child: Text(
                            'Mention',
                            style: TextStyle(
                              color: _locationChatMentionPrimaryForeground,
                              fontSize: 16,
                              height: 1.6,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      top: 17,
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: TextButton(
                          key: const ValueKey<String>(
                            'location-chat-mention-collapse',
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(24, 24),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: GenesisColors.darkFaintFill,
                            foregroundColor:
                                _locationChatMentionPrimaryForeground,
                            shape: const CircleBorder(),
                          ),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              GenesisTabBar(
                controller: _tabController,
                labels: const <String>['Characters', 'Locations'],
                horizontalPadding: 8,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                labelFontSize: 14,
                labelColor: _locationChatMentionPrimaryForeground,
                unselectedLabelColor: GenesisColors.darkTextSecondary,
                expanded: true,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GenesisBottomSheetDragDismissArea(
                  onDismiss: () => Navigator.of(context).pop(),
                  child: ScrollConfiguration(
                    key: const ValueKey<String>(
                      'location-chat-mention-tab-scroll-configuration',
                    ),
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(overscroll: false),
                    child: TabBarView(
                      key: const ValueKey<String>(
                        'location-chat-mention-tab-view',
                      ),
                      controller: _tabController,
                      physics: const ClampingScrollPhysics(),
                      children: [
                        _LocationChatMentionList(
                          key: const PageStorageKey<String>(
                            'location-chat-character-mentions',
                          ),
                          entries: widget.catalog.characters,
                          emptyLabel: 'No characters',
                          currentEntryIds: widget
                              .catalog
                              .currentLocationCharacters
                              .map((entry) => entry.id.trim())
                              .where((id) => id.isNotEmpty)
                              .toSet(),
                        ),
                        _LocationChatMentionList(
                          key: const PageStorageKey<String>(
                            'location-chat-location-mentions',
                          ),
                          entries: widget.catalog.locations,
                          emptyLabel: 'No locations',
                        ),
                      ],
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

class _LocationChatMentionList extends StatelessWidget {
  const _LocationChatMentionList({
    super.key,
    required this.entries,
    required this.emptyLabel,
    this.currentEntryIds = const <String>{},
  });

  final List<ChatMentionEntry> entries;
  final String emptyLabel;
  final Set<String> currentEntryIds;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          emptyLabel,
          style: const TextStyle(
            color: GenesisColors.darkTextSecondary,
            fontSize: 14,
          ),
        ),
      );
    }
    final sortedEntries = entries.toList(growable: false)
      ..sort(_compareLocationChatMentionEntries);
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
      child: ListView.builder(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: sortedEntries.length,
        itemBuilder: (context, index) {
          final entry = sortedEntries[index];
          return _LocationChatMentionListRow(
            entry: entry,
            isCurrentLocation: currentEntryIds.contains(entry.id.trim()),
          );
        },
      ),
    );
  }
}

class _LocationChatMentionListRow extends StatelessWidget {
  const _LocationChatMentionListRow({
    required this.entry,
    this.isCurrentLocation = false,
  });

  final ChatMentionEntry entry;
  final bool isCurrentLocation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        key: ValueKey<String>(
          'location-chat-mention-${entry.type.name}-${entry.id}',
        ),
        onTap: () => Navigator.of(context).pop(entry),
        child: SizedBox(
          height: 56,
          child: entry.type == ChatMentionType.character
              ? _LocationChatCharacterMentionRow(
                  entry: entry,
                  isCurrentLocation: isCurrentLocation,
                )
              : _LocationChatLocationMentionRow(entry: entry),
        ),
      ),
    );
  }
}

class _LocationChatCharacterMentionRow extends StatelessWidget {
  const _LocationChatCharacterMentionRow({
    required this.entry,
    required this.isCurrentLocation,
  });

  final ChatMentionEntry entry;
  final bool isCurrentLocation;

  @override
  Widget build(BuildContext context) {
    final showNewBadge = shouldMarkWorldContentAsNew(entry.isNew);
    return Row(
      children: [
        _LocationChatMentionThumbnail(entry: entry),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(child: _LocationChatMentionName(name: entry.name)),
              if (showNewBadge) ...[
                const SizedBox(width: 6),
                WorldNewBadge(
                  key: ValueKey<String>(
                    'location-chat-mention-character-new-badge-${entry.id}',
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isCurrentLocation) ...[
          const SizedBox(width: 12),
          const _LocationChatMentionHereLabel(),
        ],
      ],
    );
  }
}

class _LocationChatLocationMentionRow extends StatelessWidget {
  const _LocationChatLocationMentionRow({required this.entry});

  final ChatMentionEntry entry;

  @override
  Widget build(BuildContext context) {
    final subtitle = entry.subtitle.trim();
    final showNewBadge = shouldMarkWorldContentAsNew(entry.isNew);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (subtitle.isNotEmpty) ...[
          Text(
            '$subtitle >',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: GenesisColors.darkTextTertiary,
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(child: _LocationChatMentionName(name: entry.name)),
                  if (showNewBadge) ...[
                    const SizedBox(width: 6),
                    WorldNewBadge(
                      key: ValueKey<String>(
                        'location-chat-mention-location-new-badge-${entry.id}',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (entry.isCurrentLocation) ...[
              const SizedBox(width: 12),
              const _LocationChatMentionHereLabel(),
            ],
          ],
        ),
      ],
    );
  }
}

class _LocationChatMentionHereLabel extends StatelessWidget {
  const _LocationChatMentionHereLabel();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Here',
      style: TextStyle(
        color: GenesisColors.darkTextTertiary,
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _LocationChatMentionName extends StatelessWidget {
  const _LocationChatMentionName({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _locationChatMentionPrimaryForeground,
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

int _compareLocationChatMentionEntries(
  ChatMentionEntry left,
  ChatMentionEntry right,
) {
  final leftName = left.name.trim().toLowerCase();
  final rightName = right.name.trim().toLowerCase();
  final caseInsensitiveOrder = leftName.compareTo(rightName);
  if (caseInsensitiveOrder != 0) return caseInsensitiveOrder;
  return left.name.compareTo(right.name);
}

class _LocationChatMentionThumbnail extends StatelessWidget {
  const _LocationChatMentionThumbnail({required this.entry});

  final ChatMentionEntry entry;

  @override
  Widget build(BuildContext context) {
    final sourceUrl = entry.imageUrl.trim();
    final resizedUrl = resizeGenesisImageUrl(
      sourceUrl,
      logicalWidth: worldCharacterAvatarLogicalSize,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    final imageUrl = resizedUrl.isNotEmpty ? resizedUrl : sourceUrl;
    return GenesisCharacterAvatar(
      url: imageUrl,
      name: entry.name,
      size: _locationChatAvatarLogicalSize,
      borderRadius: 8,
      border: entry.isPlayerControlled
          ? Border.all(color: GenesisColors.redPrimary, width: 2)
          : null,
    );
  }
}

part of 'origin_world_page.dart';

ChatUiStyleConfig get _originDetailSheetChatComposerStyle =>
    kLocationChatStyle.copyWith(
      composerBackgroundColor: originWorldDetailSheetBackgroundColor.withValues(
        alpha: 0.9,
      ),
    );

const double _originLocationChatRolePillAvatarSize = 22;
const double _originLocationChatDockRoleOffsetY = -2;

class _OriginLocationChatEmptyState extends StatelessWidget {
  const _OriginLocationChatEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'This location comes to life after launch.',
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xF2FFFFFF),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
              SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Launch this Worldo to explore and interact here.',
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xB8FFFFFF),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
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

String _originLaunchChatLocationId(OriginDetail origin) {
  final previewLocationId =
      _originFirstInitialDialoguePreview(origin)?.locationId.trim() ?? '';
  if (previewLocationId.isNotEmpty) return previewLocationId;

  final initLocationId = origin.initLocationGroup?.locationId.trim() ?? '';
  if (initLocationId.isNotEmpty) return initLocationId;

  for (final character in origin.characters) {
    final initialLocationId = character.initialLocationBusinessId.trim();
    if (initialLocationId.isNotEmpty) return initialLocationId;
  }
  for (final location in origin.allLocations) {
    final locationId = location.locationId.trim();
    if (locationId.isNotEmpty && location.locations.isEmpty) {
      return locationId;
    }
  }
  for (final location in origin.allLocations) {
    final locationId = location.locationId.trim();
    if (locationId.isNotEmpty) return locationId;
  }
  return '';
}

ChatMentionCatalog _originLocationChatMentionCatalog(
  OriginDetail origin, {
  required String selectedRoleId,
}) {
  final normalizedSelectedRoleId = selectedRoleId.trim();
  final characters = <ChatMentionEntry>[
    for (final character in origin.characters)
      if (_characterStableId(character).isNotEmpty &&
          _characterStableId(character) != normalizedSelectedRoleId &&
          character.name.trim().isNotEmpty)
        ChatMentionEntry(
          id: _characterStableId(character),
          name: character.name.trim(),
          type: ChatMentionType.character,
          imageUrl: character.avatar,
        ),
  ];
  final locationTree = origin.processedLocationTree;
  final locations = <ChatMentionEntry>[
    for (final node in locationTree.flattened)
      if (node.children.isEmpty &&
          node.id != originSyntheticRootLocationId &&
          node.id.trim().isNotEmpty &&
          node.value.name.trim().isNotEmpty)
        ChatMentionEntry(
          id: node.id.trim(),
          name: node.value.name.trim(),
          type: ChatMentionType.location,
          subtitle:
              locationTree.nodeById(node.parentId)?.value.name.trim() ?? '',
        ),
  ];
  return ChatMentionCatalog(characters: characters, locations: locations);
}

extension _OriginWorldPageLocationChat on _OriginWorldPageState {
  void _handleCurrentTilemapLocationsChanged(
    String _,
    Set<String> locationIds,
  ) {
    _currentTilemapLocationIds = Set<String>.unmodifiable(locationIds);
    _preloadCurrentTilemapLocationBackgrounds(_origin);
  }

  void _preloadCurrentTilemapLocationBackgrounds(OriginDetail? origin) {
    if (origin == null || _currentTilemapLocationIds.isEmpty) return;
    _locationChatBackgroundPreloader.preload(
      _currentTilemapLocationIds.map((locationId) {
        final location = origin.processedLocationTree
            .nodeById(locationId)
            ?.value;
        if (location == null) return '';
        final xlUrl = location.imageResource.xlUrl.trim();
        return _resolveAssetUrl(xlUrl.isNotEmpty ? xlUrl : location.icon);
      }),
    );
  }

  Widget _buildLocationChatOverlay() {
    final descriptor = _activeChatLocation;
    return Positioned.fill(
      child: LocationChatOverlayTransition(
        active: descriptor != null,
        child: descriptor == null
            ? null
            : GenesisEdgeSwipeBack(
                onBack: _closeLocationChat,
                child: LocationChatPanel(
                  key: ValueKey(
                    'origin-location-chat-${descriptor.locationId}',
                  ),
                  worldId: descriptor.originId,
                  modelWorldId: null,
                  locationId: descriptor.locationId,
                  locationName: descriptor.locationName,
                  backgroundImageUrl: descriptor.backgroundImageUrl,
                  backgroundPreviewImageUrl:
                      descriptor.backgroundPreviewImageUrl,
                  openingPreviewMessages: descriptor.openingPreviewMessages,
                  openingPreviewEntities: descriptor.openingPreviewEntities,
                  emptyState: descriptor.openingPreviewMessages.isEmpty
                      ? const _OriginLocationChatEmptyState()
                      : null,
                  isLeafLocation: descriptor.isLeafLocation,
                  active: false,
                  leaveOnInactive: false,
                  showMoreButton: false,
                  onBack: _closeLocationChat,
                  showComposer: false,
                ),
              ),
      ),
    );
  }

  String _effectiveLocationChatRoleId(OriginDetail origin) {
    final selectedId = _selectedLocationChatRoleId;
    if (selectedId == _OriginWorldPageState._profileLocationChatRoleId) {
      if (_openingProfileRole != null) return selectedId;
    } else {
      for (final character in origin.characters) {
        if (_characterStableId(character) == selectedId) return selectedId;
      }
    }

    for (final character in originCharactersRecommendedFirst(
      origin.characters,
    )) {
      final characterId = _characterStableId(character);
      if (characterId.isNotEmpty) return characterId;
    }
    if (_openingProfileRole != null) {
      return _OriginWorldPageState._profileLocationChatRoleId;
    }
    return '';
  }

  _OriginLocationChatRoleOption _locationChatRoleOption(OriginDetail origin) {
    final selectedId = _effectiveLocationChatRoleId(origin);
    if (selectedId != _OriginWorldPageState._profileLocationChatRoleId) {
      for (final character in origin.characters) {
        if (_characterStableId(character) == selectedId) {
          return _OriginLocationChatRoleOption(
            id: selectedId,
            name: character.name.trim().isEmpty
                ? selectedId
                : character.name.trim(),
            subtitle: character.identity.trim(),
            avatarSnapshotSourceKey: _resolveAssetUrl(character.avatar).trim(),
          );
        }
      }
    }
    final profileRole = _openingProfileRole;
    if (profileRole == null) {
      return const _OriginLocationChatRoleOption(
        id: '',
        name: 'Select a role',
        subtitle: '',
        avatarSnapshotSourceKey: '',
      );
    }
    final profileName = profileRole.name.trim();
    return _OriginLocationChatRoleOption(
      id: _OriginWorldPageState._profileLocationChatRoleId,
      name: profileName.isEmpty ? 'Your Profile' : profileName,
      subtitle: profileRole.identity.trim(),
      avatarSnapshotSourceKey: _resolveAssetUrl(profileRole.avatarUrl).trim(),
    );
  }

  void _selectLocationChatRole(String roleId) {
    if (_launching || roleId == _selectedLocationChatRoleId) return;
    _setLocationChatRoleId(roleId);
  }

  Future<_OriginLocationChatSendResult> _launchLocationChatMessage(
    OriginDetail origin, {
    required String locationId,
    required String message,
    required ChatMentionCatalog mentionCatalog,
  }) async {
    if (_launching || message.trim().isEmpty) {
      return _OriginLocationChatSendResult.notLaunched;
    }
    // Keep the visible role when signing in adds a profile role to the list.
    final selectedRoleId = _effectiveLocationChatRoleId(origin);
    _setLocationChatRoleId(selectedRoleId);
    if (!await ensureGenesisLogin(context)) {
      if (!mounted) return _OriginLocationChatSendResult.notLaunched;
      return await hasGenesisLoginSession(context)
          ? _OriginLocationChatSendResult.loginCompleted
          : _OriginLocationChatSendResult.notLaunched;
    }
    if (!mounted) return _OriginLocationChatSendResult.notLaunched;

    OriginRoleLaunchSelection roleSelection;
    String telemetryRoleId;
    if (selectedRoleId == _OriginWorldPageState._profileLocationChatRoleId) {
      final profileRole = _openingProfileRole ?? await _customRoleFromProfile();
      if (!mounted || profileRole == null) {
        return _OriginLocationChatSendResult.notLaunched;
      }
      roleSelection = OriginRoleLaunchSelection.custom(profileRole);
      telemetryRoleId = 'current_user';
    } else {
      final character = origin.characters
          .where((character) => _characterStableId(character) == selectedRoleId)
          .firstOrNull;
      if (character == null) {
        showGenesisToast(context, 'This role is no longer available');
        _setLocationChatRoleId(
          _OriginWorldPageState._profileLocationChatRoleId,
        );
        return _OriginLocationChatSendResult.notLaunched;
      }
      final characterId = _characterStableId(character);
      roleSelection = OriginRoleLaunchSelection.preset(characterId);
      telemetryRoleId = characterId;
    }

    final worldId = await _launchOrigin(
      origin,
      roleSelection,
      telemetryRoleId: telemetryRoleId,
      launchSource: OriginLaunchSource.openingMessage,
      initialLocationId: locationId,
      initialMessageToSend: message,
      initialMentionCatalog: mentionCatalog,
    );
    return worldId == null
        ? _OriginLocationChatSendResult.notLaunched
        : _OriginLocationChatSendResult.launched;
  }
}

enum _OriginLocationChatSendResult { notLaunched, launched, loginCompleted }

class _OriginLocationChatDescriptor {
  const _OriginLocationChatDescriptor({
    required this.originId,
    required this.locationId,
    required this.locationName,
    required this.backgroundImageUrl,
    required this.backgroundPreviewImageUrl,
    required this.isLeafLocation,
    required this.openingPreviewMessages,
    required this.openingPreviewEntities,
  });

  final String originId;
  final String locationId;
  final String locationName;
  final String backgroundImageUrl;
  final String backgroundPreviewImageUrl;
  final bool isLeafLocation;
  final List<WorldChatroomMessage> openingPreviewMessages;
  final List<WorldChatroomEntity> openingPreviewEntities;
}

class _OriginLocationChatLaunchComposer extends StatefulWidget {
  const _OriginLocationChatLaunchComposer({
    super.key,
    required this.launching,
    required this.sending,
    required this.role,
    required this.roleAvatarSnapshots,
    required this.mentionCatalog,
    required this.onSelectRole,
    required this.onSend,
    this.style,
    this.roleForegroundColor = const Color(0xFFF4F3F6),
    this.roleMutedColor = const Color(0x99FFFFFF),
    this.roleBackgroundColor = const Color(0xCC151517),
    this.showShortcuts = true,
    this.enableMentionSheet = true,
    this.roleBorderRadius = 999,
    this.bottomSafeAreaInset,
    this.onInputDockHeightChanged,
    this.onFocusChanged,
    this.onSendCompleted,
  });

  final bool launching;
  final bool sending;
  final _OriginLocationChatRoleOption role;
  final OriginRoleAvatarSnapshotStore roleAvatarSnapshots;
  final ChatMentionCatalog mentionCatalog;
  final VoidCallback onSelectRole;
  final Future<_OriginLocationChatSendResult> Function(
    String message,
    ChatMentionCatalog mentionCatalog,
  )
  onSend;
  final ChatUiStyleConfig? style;
  final Color roleForegroundColor;
  final Color roleMutedColor;
  final Color roleBackgroundColor;
  final bool showShortcuts;
  final bool enableMentionSheet;
  final double roleBorderRadius;
  final double? bottomSafeAreaInset;
  final ValueChanged<double>? onInputDockHeightChanged;
  final ValueChanged<bool>? onFocusChanged;
  final ValueChanged<bool>? onSendCompleted;

  @override
  State<_OriginLocationChatLaunchComposer> createState() =>
      _OriginLocationChatLaunchComposerState();
}

class _OriginLocationChatLaunchComposerState
    extends State<_OriginLocationChatLaunchComposer> {
  late final LocationChatMentionEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;
  bool _mentionSheetOpen = false;
  bool _mentionSheetSchedulePending = false;

  @override
  void initState() {
    super.initState();
    _controller = LocationChatMentionEditingController(
      catalog: widget.mentionCatalog,
    );
    _controller.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _OriginLocationChatLaunchComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.updateCatalog(widget.mentionCatalog);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    widget.onFocusChanged?.call(_focusNode.hasFocus);
  }

  void _handleTextChanged() {
    final hasText = _controller.serializedText.trim().isNotEmpty;
    final triggerOffset = _controller.takeInsertedAtOffset();
    if (widget.enableMentionSheet && triggerOffset != null) {
      _scheduleMentionSheet(triggerOffset);
    }
    if (_hasText == hasText) return;
    setState(() => _hasText = hasText);
  }

  void _scheduleMentionSheet(int triggerOffset) {
    if (_mentionSheetOpen || _mentionSheetSchedulePending) return;
    _mentionSheetSchedulePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mentionSheetSchedulePending = false;
      if (!mounted || _mentionSheetOpen) return;
      unawaited(_showMentionSheet(triggerOffset));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _showMentionSheet(int triggerOffset) async {
    if (_mentionSheetOpen ||
        triggerOffset < 0 ||
        triggerOffset >= _controller.text.length ||
        _controller.text[triggerOffset] != '@') {
      return;
    }
    setState(() => _mentionSheetOpen = true);
    _focusNode.unfocus();
    final selected = await showGenesisModalBottomSheet<ChatMentionEntry>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (_) => LocationChatMentionSheet(catalog: _controller.catalog),
    );
    if (!mounted) return;
    setState(() => _mentionSheetOpen = false);
    if (selected != null) {
      final triggerStillExists =
          triggerOffset < _controller.text.length &&
          _controller.text[triggerOffset] == '@';
      final selection = _controller.selection;
      final fallbackStart = selection.isValid
          ? selection.start
          : _controller.text.length;
      final fallbackEnd = selection.isValid ? selection.end : fallbackStart;
      _controller.insertMention(
        selected,
        replaceStart: triggerStillExists ? triggerOffset : fallbackStart,
        replaceEnd: triggerStillExists ? triggerOffset + 1 : fallbackEnd,
      );
    }
    _focusNode.requestFocus();
  }

  Future<void> _send() async {
    final message = _controller.serializedText;
    if (widget.launching || message.trim().isEmpty) return;
    final mentionCatalog = _controller.composedMentionCatalog;
    final result = await widget.onSend(message, mentionCatalog);
    if (!mounted) return;
    if (result == _OriginLocationChatSendResult.loginCompleted) {
      // Restore the draft input after login without running the failed-send
      // cleanup that would close it again.
      _focusNode.requestFocus();
      return;
    }
    _focusNode.unfocus();
    widget.onSendCompleted?.call(
      result == _OriginLocationChatSendResult.launched,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? kLocationChatStyle;
    final sendEnabled = !widget.launching && _hasText;
    final composer = LocationChatComposerInput(
      controller: _controller,
      focusNode: _focusNode,
      hintText: 'Text...',
      inputEnabled: !widget.launching,
      sendEnabled: sendEnabled,
      sending: widget.sending,
      onSend: _send,
      onHeightChanged: widget.onInputDockHeightChanged,
      composerHeader: null,
      style: style,
      showShortcuts: widget.showShortcuts,
      bottomSafeAreaInset: widget.bottomSafeAreaInset,
    );
    final roleRegion = _OriginLocationChatRoleRegion(
      role: widget.role,
      roleAvatarSnapshots: widget.roleAvatarSnapshots,
      enabled: !widget.launching,
      onTap: widget.onSelectRole,
      style: style,
      foregroundColor: widget.roleForegroundColor,
      mutedColor: widget.roleMutedColor,
      backgroundColor: widget.roleBackgroundColor,
      borderRadius: widget.roleBorderRadius,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [roleRegion, composer],
    );
  }
}

class _OriginLocationChatRoleRegion extends StatelessWidget {
  const _OriginLocationChatRoleRegion({
    required this.role,
    required this.roleAvatarSnapshots,
    required this.enabled,
    required this.onTap,
    required this.style,
    required this.foregroundColor,
    required this.mutedColor,
    required this.backgroundColor,
    this.borderRadius = 999,
  });

  final _OriginLocationChatRoleOption role;
  final OriginRoleAvatarSnapshotStore roleAvatarSnapshots;
  final bool enabled;
  final VoidCallback onTap;
  final ChatUiStyleConfig style;
  final Color foregroundColor;
  final Color mutedColor;
  final Color backgroundColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final roleSelector = _OriginLocationChatRoleSelector(
      role: role,
      roleAvatarSnapshots: roleAvatarSnapshots,
      enabled: enabled,
      onTap: onTap,
      foregroundColor: foregroundColor,
      mutedColor: mutedColor,
      backgroundColor: backgroundColor,
      backdropBlurSigma: style.inputBackdropBlurSigma,
      borderRadius: borderRadius,
    );
    return ColoredBox(
      key: const ValueKey<String>('origin-location-chat-role-region'),
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(
          left: style.composerPadding.left,
          top: style.composerPadding.top,
          right: style.composerPadding.right,
        ),
        child: Transform.translate(
          key: const ValueKey<String>(
            'origin-location-chat-dock-role-translation',
          ),
          offset: const Offset(0, _originLocationChatDockRoleOffsetY),
          child: roleSelector,
        ),
      ),
    );
  }
}

@immutable
class _OriginLocationChatRoleOption {
  const _OriginLocationChatRoleOption({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.avatarSnapshotSourceKey,
  });

  final String id;
  final String name;
  final String subtitle;
  final String avatarSnapshotSourceKey;
}

class _OriginLocationChatRoleSelector extends StatelessWidget {
  const _OriginLocationChatRoleSelector({
    required this.role,
    required this.roleAvatarSnapshots,
    required this.enabled,
    required this.onTap,
    required this.foregroundColor,
    required this.mutedColor,
    required this.backgroundColor,
    required this.backdropBlurSigma,
    required this.borderRadius,
  });

  final _OriginLocationChatRoleOption role;
  final OriginRoleAvatarSnapshotStore roleAvatarSnapshots;
  final bool enabled;
  final VoidCallback onTap;
  final Color foregroundColor;
  final Color mutedColor;
  final Color backgroundColor;
  final double backdropBlurSigma;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final pill = Material(
      key: const ValueKey<String>('origin-location-chat-role-pill'),
      color: backgroundColor,
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey<String>('origin-location-chat-role-selector'),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: roleAvatarSnapshots,
                builder: (context, _) {
                  final snapshot = roleAvatarSnapshots.imageFor(
                    role.avatarSnapshotSourceKey,
                  );
                  return ClipRRect(
                    key: ValueKey<String>(
                      'origin-location-chat-role-avatar-${role.id}',
                    ),
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox.square(
                      dimension: _originLocationChatRolePillAvatarSize,
                      child: snapshot == null
                          ? null
                          : RawImage(
                              key: ValueKey<String>(
                                'origin-location-chat-role-snapshot-${role.id}',
                              ),
                              image: snapshot,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                            ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  role.name,
                  key: const ValueKey<String>(
                    'origin-location-chat-role-label',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.swap_horiz_rounded,
                key: const ValueKey<String>(
                  'origin-location-chat-role-switch-icon',
                ),
                size: 17,
                color: mutedColor,
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: 'Select Your Role',
      child: backdropBlurSigma <= 0
          ? pill
          : ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: BackdropFilter(
                key: const ValueKey<String>(
                  'origin-location-chat-role-pill-backdrop',
                ),
                filterConfig: ImageFilterConfig.blur(
                  sigmaX: backdropBlurSigma,
                  sigmaY: backdropBlurSigma,
                  bounded: false,
                ),
                child: pill,
              ),
            ),
    );
  }
}

class _OriginInitialDialoguePreview {
  const _OriginInitialDialoguePreview({
    required this.locationId,
    required this.locationName,
    required this.messages,
  });

  final String locationId;
  final String locationName;
  final List<ChatMessageVm> messages;
}

_OriginInitialDialoguePreview? _originFirstInitialDialoguePreview(
  OriginDetail origin,
) {
  final locationIds = <String>{
    for (final location in origin.allLocations)
      if (location.locationId.trim().isNotEmpty) location.locationId.trim(),
  };
  if (locationIds.isEmpty) return null;

  final sourceMessages = _originLocationOpeningPreviewMessages(
    origin,
    locationIds,
  );
  if (!sourceMessages.any((message) => message.senderType != 'tick')) {
    return null;
  }

  final locationId = sourceMessages
      .map((message) => message.locationId.trim())
      .firstWhere((id) => id.isNotEmpty, orElse: () => '');
  final location = origin.allLocations
      .where((item) => item.locationId.trim() == locationId)
      .firstOrNull;
  final entities = _originLocationOpeningPreviewEntities(
    origin.characters,
    sourceMessages,
    locationId,
  );
  final entitiesById = <String, WorldChatroomEntity>{
    for (final entity in entities) entity.id.trim().toLowerCase(): entity,
  };
  final messages = sourceMessages.indexed
      .map((entry) {
        final index = entry.$1;
        final source = entry.$2;
        final rawSenderType = source.senderType.trim().toLowerCase();
        final senderType = switch (rawSenderType) {
          'ai' => 'character',
          '' => 'user',
          _ => rawSenderType,
        };
        final entity = entitiesById[source.senderId.trim().toLowerCase()];
        final senderName = entity?.name.trim().isNotEmpty == true
            ? entity!.name.trim()
            : source.senderName.trim();
        final currentTime =
            senderType == 'user' ||
                senderType == 'tick' ||
                senderType == 'system'
            ? ''
            : source.currentTime.trim();
        return ChatMessageVm(
          localId: 'origin-initial-dialogue-${source.tickNo}-$index',
          globalMessageId: source.globalMessageId,
          messageId: source.messageId,
          locationMessageId: source.locationMessageId,
          roundId: source.conversationRoundId,
          tickNo: source.tickNo,
          senderId: source.senderId,
          senderName: senderName,
          avatarUrl: entity?.avatarUrl ?? '',
          imageUrl: senderType == 'image' ? source.content : '',
          text: source.content,
          currentTime: currentTime,
          isMe: false,
          status: 'sent',
          senderType: senderType,
          createdAt: source.createdAt,
        );
      })
      .toList(growable: false);

  return _OriginInitialDialoguePreview(
    locationId: locationId,
    locationName: location?.name.trim().isNotEmpty == true
        ? location!.name.trim()
        : locationId,
    messages: messages,
  );
}

Map<String, Map<String, dynamic>> _originLocationsById(
  List<OriginLocation> locations,
) {
  final out = <String, Map<String, dynamic>>{};
  for (final location in locations) {
    final locationId = location.locationId.trim();
    if (locationId.isEmpty) continue;
    out[locationId] = <String, dynamic>{
      'location_name': location.name,
      'name': location.name,
    };
  }
  return out;
}

List<WorldChatroomMessage> _originLocationOpeningPreviewMessages(
  OriginDetail origin,
  Iterable<String> locationIds,
) {
  final initLocationGroup = origin.initLocationGroup;
  if (initLocationGroup != null) {
    final messages = originInitialLocationGroupPreviewMessagesForTesting(
      initLocationGroup,
      locationIds,
      createdAt: origin.createdAt,
    );
    if (messages.isNotEmpty) return messages;
  }
  return originLocationOpeningPreviewMessagesForTesting(
    origin.ticks,
    locationIds,
  );
}

@visibleForTesting
List<WorldChatroomMessage> originOpeningPreviewMessagesForTesting(
  OriginDetail origin,
  Iterable<String> locationIds,
) {
  return _originLocationOpeningPreviewMessages(origin, locationIds);
}

@visibleForTesting
List<WorldChatroomMessage> originInitialLocationGroupPreviewMessagesForTesting(
  OriginInitLocationGroup group,
  Iterable<String> locationIds, {
  DateTime? createdAt,
}) {
  return originLocationOpeningPreviewMessagesForTesting(<Map<String, dynamic>>[
    <String, dynamic>{
      'tick_no': 0,
      'created_at': createdAt,
      'tick_result': <String, dynamic>{
        'location_groups': <Map<String, dynamic>>[
          <String, dynamic>{
            'location_id': group.locationId,
            'initial_dialogue': <Map<String, dynamic>>[
              for (final line in group.initialDialogue)
                <String, dynamic>{
                  'char_id': line.charId,
                  'char_name': line.charName,
                  'content': line.content,
                },
            ],
          },
        ],
      },
    },
  ], locationIds);
}

@visibleForTesting
List<WorldChatroomMessage> originLocationOpeningPreviewMessagesForTesting(
  List<Map<String, dynamic>> ticks,
  Iterable<String> locationIds,
) {
  final locationIdSet = locationIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  if (locationIdSet.isEmpty) return const <WorldChatroomMessage>[];

  final orderedTicks = ticks.toList(growable: false);
  orderedTicks.sort((left, right) {
    final leftTickNo = _mapInt(left, const ['tick_no']);
    final rightTickNo = _mapInt(right, const ['tick_no']);
    if (leftTickNo == 1 && rightTickNo != 1) return -1;
    if (rightTickNo == 1 && leftTickNo != 1) return 1;
    if (leftTickNo != 0 && rightTickNo != 0 && leftTickNo != rightTickNo) {
      return leftTickNo.compareTo(rightTickNo);
    }
    return 0;
  });

  for (final tick in orderedTicks) {
    final tickNo = _mapInt(tick, const ['tick_no']);
    final createdAt = asDateTime(tick['created_at']);
    final result = tick['tick_result'] is Map
        ? (tick['tick_result'] as Map).cast<String, dynamic>()
        : tick;
    final resultCurrentTime = _mapString(result, const [
      'current_time',
      'time',
    ]);
    final currentTime = resultCurrentTime.isNotEmpty
        ? resultCurrentTime
        : _mapString(tick, const ['current_time', 'time']);
    final groupsRaw = result['location_groups'] ?? tick['location_groups'];
    if (groupsRaw is! List) continue;
    for (final rawGroup in groupsRaw.whereType<Map>()) {
      final group = rawGroup.cast<String, dynamic>();
      final groupLocationId = _mapString(group, const [
        'location_id',
        'loc_id',
        'id',
      ]);
      if (!locationIdSet.contains(groupLocationId)) continue;
      final dialogueRaw =
          group['initial_dialogue'] ??
          group['initialDialogue'] ??
          group['dialogue'];
      if (dialogueRaw is! List) continue;
      final messages = <WorldChatroomMessage>[];
      if (tickNo > 0 || currentTime.isNotEmpty) {
        messages.add(
          WorldChatroomMessage(
            messageId: 0,
            conversationRoundId:
                'opening-preview-tick-${tickNo == 0 ? 1 : tickNo}',
            roundOrder: 0,
            tickNo: tickNo == 0 ? 1 : tickNo,
            locationId: groupLocationId,
            senderType: 'tick',
            senderId: 'tick',
            senderName: 'Time',
            content: currentTime,
            createdAt: createdAt,
          ),
        );
      }
      messages.addAll(
        dialogueRaw
            .whereType<Map>()
            .indexed
            .map((entry) {
              final index = entry.$1;
              final line = entry.$2.cast<String, dynamic>();
              final content = _mapString(line, const ['content', 'text']);
              if (content.isEmpty) return null;
              final charId = _mapString(line, const [
                'char_id',
                'character_id',
                'sender_id',
              ]);
              final charName = _mapString(line, const [
                'char_name',
                'name',
                'sender_name',
              ]);
              final senderId = charId.isEmpty
                  ? 'opening-preview-$index'
                  : charId;
              final senderName = charName.isEmpty ? senderId : charName;
              final normalizedCharId = charId.trim().toLowerCase();
              final isNarrator = normalizedCharId == 'nar';
              final isImage =
                  normalizedCharId == 'nar_pic' || normalizedCharId == 'image';
              return WorldChatroomMessage(
                messageId: 0,
                conversationRoundId: 'opening-preview-$index',
                roundOrder: index,
                tickNo: tickNo == 0 ? 1 : tickNo,
                locationId: groupLocationId,
                senderType: isImage
                    ? 'image'
                    : isNarrator
                    ? 'narrator'
                    : 'character',
                senderId: senderId,
                senderName: senderName,
                currentTime: currentTime,
                content: content,
                createdAt:
                    createdAt ?? DateTime.fromMillisecondsSinceEpoch(index),
              );
            })
            .whereType<WorldChatroomMessage>()
            .toList(growable: false),
      );
      return messages;
    }
  }
  return const <WorldChatroomMessage>[];
}

List<WorldChatroomEntity> _originLocationOpeningPreviewEntities(
  List<OriginCharacter> characters,
  List<WorldChatroomMessage> messages,
  String locationId,
) {
  return originLocationOpeningPreviewEntitiesForTesting(
    characters,
    messages,
    locationId,
  );
}

@visibleForTesting
List<WorldChatroomEntity> originLocationOpeningPreviewEntitiesForTesting(
  List<OriginCharacter> characters,
  List<WorldChatroomMessage> messages,
  String locationId,
) {
  final charactersByKey = <String, OriginCharacter>{};
  for (final character in characters) {
    void addKey(String value) {
      final key = value.trim().toLowerCase();
      if (key.isEmpty) return;
      charactersByKey.putIfAbsent(key, () => character);
    }

    addKey(character.characterId);
    if (character.id > 0) addKey('${character.id}');
    addKey(character.name);
  }

  final entities = <WorldChatroomEntity>[];
  final seen = <String>{};
  for (final message in messages) {
    final senderId = message.senderId.trim();
    if (senderId.isEmpty || !seen.add(senderId.toLowerCase())) continue;
    final character =
        charactersByKey[senderId.toLowerCase()] ??
        charactersByKey[message.senderName.trim().toLowerCase()];
    if (character == null) continue;
    entities.add(
      WorldChatroomEntity(
        id: senderId,
        name: message.senderName.trim().isNotEmpty
            ? message.senderName.trim()
            : character.name,
        avatarUrl: _resolveAssetUrl(character.avatar),
        type: WorldChatroomEntityType.character,
        locationId: locationId,
        isAi: true,
      ),
    );
  }
  return entities;
}

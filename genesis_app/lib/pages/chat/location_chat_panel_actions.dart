part of 'location_chat_page.dart';

extension _LocationChatPanelActions on _LocationChatPanelState {
  void _clearUnseenIncomingCount() {
    if (_unseenIncomingCount == 0 || !mounted) return;
    _setLocationChatState(_unseenIncomingMessageLocalIds.clear);
  }

  void _openUnseenIncomingMessages() {
    _clearUnseenIncomingCount();
    _scrollCoordinator.requestBottom(
      reason: LocationChatBottomReason.unseenMessageNotice,
      behavior: LocationChatBottomBehavior.jump,
    );
  }

  void _showMessageActionMenu(
    BuildContext menuContext,
    ChatMessageVm message,
    LongPressStartDetails details,
  ) {
    final items = <GenesisActionMenuItem>[
      GenesisActionMenuItem(
        label: 'Copy',
        iconData: Icons.copy_outlined,
        onSelected: () => _copyMessageText(message),
      ),
      if (locationChatMessageCanReportForTesting(message))
        GenesisActionMenuItem(
          label: 'Report',
          iconAsset: genesisReportIconAsset,
          onSelected: () {
            showGenesisReportDialog(
              context: context,
              targetType: 'message',
              targetId: _messageReportTargetId(message),
            );
          },
        ),
    ];
    showGenesisActionMenuAt(
      context: menuContext,
      globalPosition: details.globalPosition,
      items: items,
      appearance: GenesisActionMenuAppearance.message,
    );
  }

  Future<void> _copyMessageText(ChatMessageVm message) async {
    final text = message.isTick
        ? chatTickMessageCopyText(message)
        : message.text;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showGenesisToast(context, 'Copied', brightness: Brightness.dark);
  }

  String _messageReportTargetId(ChatMessageVm message) {
    return locationChatMessageReportTargetIdForTesting(message);
  }

  /// Everyone standing in the room, including AI characters. Self is inserted
  /// first, then the server order is preserved while duplicate identities are
  /// removed.
  List<WorldChatroomEntity> _roomOccupantsForCurrentLocation(
    WorldChatroomState state,
  ) {
    final locationIds = _currentLocationIds();
    final occupants = <WorldChatroomEntity>[];
    final seen = <String>{};

    void add(WorldChatroomEntity entity) {
      final key = _realUserDedupKey(entity);
      if (key.isEmpty || !seen.add(key)) return;
      occupants.add(entity);
    }

    final selfId = firstNonEmpty([_myUserId, _mySenderId]);
    final selfName = _localSelfDisplayName();
    if ((state.joinedLocationId == widget.locationId ||
            _optimisticSelfOccupancy) &&
        (selfId.isNotEmpty || selfName.isNotEmpty)) {
      add(
        WorldChatroomEntity(
          id: selfId.isEmpty ? selfName : selfId,
          name: selfName,
          avatarUrl: _localSelfAvatarUrl(),
          type: WorldChatroomEntityType.player,
          locationId: widget.locationId,
          isAi: false,
        ),
      );
    }

    for (final locationId in locationIds) {
      for (final entity
          in state.entitiesByLocation[locationId] ??
              const <WorldChatroomEntity>[]) {
        add(entity);
      }
    }

    return occupants;
  }

  List<String> _currentLocationIds() {
    final seen = <String>{};
    final ids = <String>[];
    void add(String? value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty || !seen.add(trimmed)) return;
      ids.add(trimmed);
    }

    add(widget.locationId);
    for (final locationId in widget.localMessageLocationIds) {
      add(locationId);
    }
    return ids;
  }

  String _realUserDedupKey(WorldChatroomEntity entity) {
    final idKey = _chatroomIdentityKey(entity.id);
    if (idKey.isNotEmpty) return 'id:$idKey';
    final nameKey = entity.name.trim().toLowerCase();
    return nameKey.isEmpty ? '' : 'name:$nameKey';
  }
}

@visibleForTesting
bool locationChatMessageCanReportForTesting(ChatMessageVm message) {
  return !message.isMe && message.globalMessageId > 0;
}

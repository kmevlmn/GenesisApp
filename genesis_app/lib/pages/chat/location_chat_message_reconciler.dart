part of 'location_chat_page.dart';

extension _LocationChatMessageReconciler on _LocationChatPanelState {
  bool _reconcileMessages(
    List<WorldChatroomMessage> source, {
    WorldChatroomState? identityState,
  }) {
    final resolvedIdentityState = identityState ?? _chatroomState;
    final renderWindow = _visibleLocationChatMessages(
      source,
      renderedLocationMessageIds: _renderedLocationMessageIds(),
      releasedGapKeys: _releasedMessageGapKeys,
      locationId: widget.locationId,
    );
    _requestVisibleMessageGapFillIfNeeded(renderWindow.gaps, source);
    final timelineIdentityIndex = _LocationChatTimelineIdentityIndex.fromState(
      resolvedIdentityState,
      currentUserIds: _myUserIdKeys,
      currentSenderIds: _mySenderIdKeys,
    );
    final baseParseContext = LocationChatMessageParseContext(
      currentLocationId: widget.locationId,
      isMine: (message) =>
          _isMineMessage(message, identityState: resolvedIdentityState),
      senderName: (message) => _messageSenderDisplayName(
        message,
        identityState: resolvedIdentityState,
      ),
      avatarUrl: (message) =>
          _messageAvatarUrl(message, identityState: resolvedIdentityState),
      isPlayerControlledRole: (message) => _messageSenderIsPlayerControlledRole(
        message,
        identityState: resolvedIdentityState,
      ),
      characterName: timelineIdentityIndex.characterName,
      locationName: timelineIdentityIndex.locationName,
      roleName: timelineIdentityIndex.roleName,
      roleIsAi: timelineIdentityIndex.roleIsAi,
      roleAvatarUrl: (roleId) => _resizedLocationChatAvatarUrl(
        timelineIdentityIndex.roleAvatarUrl(roleId),
      ),
    );
    final retainedTimelineCacheKeys = <String>{};
    final visibleSource = <LocationChatParsedMessage>[];
    for (final message in renderWindow.messages) {
      final isTimelineMessage = isChatroomTimelinePayloadSenderType(
        message.senderType,
      );
      final timelineCacheKey = locationChatMessageLocalId(message);
      var parseContext = baseParseContext;
      _LocationChatTimelineVmCacheEntry? cachedTimelineEntry;
      if (isTimelineMessage) {
        retainedTimelineCacheKeys.add(timelineCacheKey);
        final cached = _timelineVmCache[timelineCacheKey];
        if (cached != null &&
            identical(cached.payload, message.timelinePayload) &&
            cached.identityRevision == timelineIdentityIndex.revision) {
          cachedTimelineEntry = cached;
          parseContext = baseParseContext.withTimelineCache(
            hasCachedTimelinePayload: true,
            cachedTimelinePayload: cached.viewModel,
          );
        }
      }
      final parser = _parserForMessage(message);
      if (parser == null) continue;
      final parsed = parser.parse(message, parseContext);
      if (isTimelineMessage && cachedTimelineEntry == null) {
        _timelineVmCache[timelineCacheKey] = _LocationChatTimelineVmCacheEntry(
          payload: message.timelinePayload,
          identityRevision: timelineIdentityIndex.revision,
          viewModel: parsed?.timelinePayload,
        );
      }
      if (parsed == null) continue;
      visibleSource.add(parsed);
    }
    _timelineVmCache.removeWhere(
      (key, _) => !retainedTimelineCacheKeys.contains(key),
    );
    final previous = _messages.where((message) => !message.isSystem).toList();
    final existingByKey = {
      for (final message in previous) message.localId: message,
    };
    final existingByMessageId = <int, ChatMessageVm>{
      for (final message in previous)
        if ((message.messageId ?? 0) > 0) message.messageId!: message,
    };
    final existingByClientMsgId = <String, ChatMessageVm>{
      for (final message in previous)
        if (message.clientMsgId.trim().isNotEmpty)
          message.clientMsgId.trim(): message,
    };
    final next = <ChatMessageVm>[];
    final usedLocalIds = <String>{};
    var changed = false;
    for (final parsed in visibleSource) {
      final message = parsed.source;
      final clientMsgId = parsed.clientMsgId.trim();
      final existing =
          (clientMsgId.isEmpty ? null : existingByClientMsgId[clientMsgId]) ??
          existingByKey[parsed.localId] ??
          (parsed.messageId > 0
              ? existingByMessageId[parsed.messageId]
              : null) ??
          _matchingPendingSelfMessage(
            previous,
            message,
            usedLocalIds: usedLocalIds,
          );
      if (existing != null) {
        if (usedLocalIds.contains(existing.localId)) {
          changed = true;
          continue;
        }
        usedLocalIds.add(existing.localId);
        if (existing.globalMessageId != parsed.globalMessageId ||
            existing.messageId != parsed.messageId ||
            existing.locationMessageId != parsed.locationMessageId ||
            existing.roundId != parsed.roundId ||
            existing.tickNo != parsed.tickNo ||
            existing.subTickNo != parsed.subTickNo ||
            existing.senderName != parsed.senderName ||
            existing.isMe != parsed.isMe ||
            existing.isPlayerControlledRole != parsed.isPlayerControlledRole ||
            existing.avatarUrl != parsed.avatarUrl ||
            existing.imageUrl != parsed.imageUrl ||
            existing.timelinePayload != parsed.timelinePayload ||
            existing.text != parsed.text ||
            existing.currentTime != parsed.currentTime ||
            existing.status != parsed.status ||
            existing.localId != parsed.localId) {
          changed = true;
        }
        existing.globalMessageId = parsed.globalMessageId;
        existing.messageId = parsed.messageId;
        existing.locationMessageId = parsed.locationMessageId;
        existing.roundId = parsed.roundId;
        existing.tickNo = parsed.tickNo;
        existing.subTickNo = parsed.subTickNo;
        existing.senderName = parsed.senderName;
        existing.isMe = parsed.isMe;
        existing.isPlayerControlledRole = parsed.isPlayerControlledRole;
        existing.avatarUrl = parsed.avatarUrl;
        existing.imageUrl = parsed.imageUrl;
        existing.timelinePayload = parsed.timelinePayload;
        existing.text = parsed.text;
        existing.currentTime = parsed.currentTime;
        existing.status = parsed.status;
        existing.error = null;
        next.add(existing);
      } else {
        changed = true;
        final nextMessage = ChatMessageVm(
          localId: parsed.localId,
          clientMsgId: parsed.clientMsgId,
          globalMessageId: parsed.globalMessageId,
          messageId: parsed.messageId,
          locationMessageId: parsed.locationMessageId,
          roundId: parsed.roundId,
          tickNo: parsed.tickNo,
          subTickNo: parsed.subTickNo,
          senderId: parsed.senderId,
          senderName: parsed.senderName,
          isPlayerControlledRole: parsed.isPlayerControlledRole,
          avatarUrl: parsed.avatarUrl,
          imageUrl: parsed.imageUrl,
          timelinePayload: parsed.timelinePayload,
          text: parsed.text,
          currentTime: parsed.currentTime,
          isMe: parsed.isMe,
          status: parsed.status,
          senderType: parsed.senderType,
          createdAt: parsed.createdAt,
        );
        usedLocalIds.add(nextMessage.localId);
        next.add(nextMessage);
      }
    }
    preserveUnmatchedLocationChatLocalMessages(
      previous: previous,
      reconciled: next,
      usedLocalIds: usedLocalIds,
    );
    if (next.length != previous.length) {
      changed = true;
    }
    for (var i = 0; i < next.length && i < previous.length; i += 1) {
      if (next[i].localId != previous[i].localId) {
        changed = true;
        break;
      }
    }
    if (changed) {
      _messages
        ..clear()
        ..addAll(next);
    }
    return changed;
  }

  Set<int> _renderedLocationMessageIds() {
    return _messages
        .where((message) => !message.isSystem && message.locationMessageId > 0)
        .map((message) => message.locationMessageId)
        .toSet();
  }

  void _requestVisibleMessageGapFillIfNeeded(
    List<_LocationChatMessageGap> gaps,
    List<WorldChatroomMessage> source,
  ) {
    final service = _service;
    if (service == null || source.isEmpty || gaps.isEmpty) return;
    if (_loadingOlderMessages) {
      _deferredVisibleMessageGapFill = true;
      return;
    }
    for (final gap in gaps) {
      final key = _locationChatMessageGapKey(widget.locationId, gap);
      if (_releasedMessageGapKeys.contains(key)) continue;
      if (!_messageGapFillBeforeLocationMessageIds.add(
        gap.upperLocationMessageId,
      )) {
        continue;
      }
      if (!_messageGapFillKeys.add(key)) {
        _messageGapFillBeforeLocationMessageIds.remove(
          gap.upperLocationMessageId,
        );
        continue;
      }
      _logPanelMetric(
        'message gap fill requested location=${widget.locationId} '
        'lower=${gap.lowerLocationMessageId} '
        'upper=${gap.upperLocationMessageId}',
      );
      _recordPanelDebug(
        action: 'gapFillRequested',
        sourceMessages: source,
        details: {
          'lowerLocationMessageId': gap.lowerLocationMessageId,
          'upperLocationMessageId': gap.upperLocationMessageId,
          'missingCount': gap.missingCount,
        },
      );
      unawaited(_fillVisibleMessageGap(service: service, key: key, gap: gap));
    }
  }

  void _runDeferredVisibleMessageGapFillIfNeeded() {
    if (!_deferredVisibleMessageGapFill || _loadingOlderMessages) return;
    _deferredVisibleMessageGapFill = false;
    final source =
        _chatroomState.messagesByLocation[widget.locationId] ??
        const <WorldChatroomMessage>[];
    final renderWindow = _visibleLocationChatMessages(
      source,
      renderedLocationMessageIds: _renderedLocationMessageIds(),
      releasedGapKeys: _releasedMessageGapKeys,
      locationId: widget.locationId,
    );
    _requestVisibleMessageGapFillIfNeeded(renderWindow.gaps, source);
  }

  Future<void> _fillVisibleMessageGap({
    required WorldChatroomService service,
    required String key,
    required _LocationChatMessageGap gap,
  }) async {
    final location = widget.locationId;
    final generation = service.state.historyGenerationByLocation[location] ?? 0;
    bool current() =>
        mounted &&
        identical(service, _service) &&
        widget.locationId == location &&
        generation ==
            (service.state.historyGenerationByLocation[location] ?? 0);
    try {
      for (
        var attempt = 1;
        attempt <= _locationChatMessageGapMaxAttempts;
        attempt += 1
      ) {
        if (!current()) return;
        _messageGapFillAttempts[key] = attempt;
        try {
          if (_isLocationChatMessageGapFilled(
            service.state.messagesByLocation[widget.locationId] ??
                const <WorldChatroomMessage>[],
            gap,
          )) {
            _messageGapFillKeys.remove(key);
            _messageGapFillAttempts.remove(key);
            return;
          }
          await service.loadOlderMessages(
            locationId: widget.locationId,
            beforeMessageId: gap.upperLocationMessageId,
            limit: math.min(100, gap.missingCount + 1),
          );
          if (!current()) return;
          if (_isLocationChatMessageGapFilled(
            service.state.messagesByLocation[widget.locationId] ??
                const <WorldChatroomMessage>[],
            gap,
          )) {
            _messageGapFillKeys.remove(key);
            _messageGapFillAttempts.remove(key);
            return;
          }
        } catch (error) {
          _logPanelMetric(
            'message gap fill failed location=${widget.locationId} '
            'lower=${gap.lowerLocationMessageId} '
            'upper=${gap.upperLocationMessageId} '
            'attempt=$attempt error=$error',
          );
          _recordPanelDebug(
            action: 'gapFillFailed',
            details: {
              'lowerLocationMessageId': gap.lowerLocationMessageId,
              'upperLocationMessageId': gap.upperLocationMessageId,
              'attempt': attempt,
              'error': '$error',
            },
          );
        }
      }
    } finally {
      if (current()) {
        _messageGapFillBeforeLocationMessageIds.remove(
          gap.upperLocationMessageId,
        );
      }
    }
    if (!current()) return;
    _releasedMessageGapKeys.add(key);
    _messageGapFillKeys.remove(key);
    _messageGapFillAttempts.remove(key);
    _recordPanelDebug(
      action: 'gapFillReleased',
      details: {
        'lowerLocationMessageId': gap.lowerLocationMessageId,
        'upperLocationMessageId': gap.upperLocationMessageId,
        'attempts': _locationChatMessageGapMaxAttempts,
      },
    );
    if (!mounted) return;
    final changed = _reconcileMessages(
      _chatroomState.messagesByLocation[widget.locationId] ??
          const <WorldChatroomMessage>[],
    );
    if (changed && mounted) {
      _setLocationChatState(() {});
    }
  }

  ChatMessageVm? _matchingPendingSelfMessage(
    List<ChatMessageVm> previous,
    WorldChatroomMessage message, {
    required Set<String> usedLocalIds,
  }) {
    final content = _locationChatMessageDisplayText(message).trim();
    if (content.isEmpty) return null;
    final now = DateTime.now();
    for (final candidate in previous.reversed) {
      if (usedLocalIds.contains(candidate.localId)) continue;
      if (!candidate.isMe) continue;
      if (candidate.status != 'sending' && candidate.status != 'sent') {
        continue;
      }
      final candidateMessageId = candidate.messageId ?? 0;
      if (candidateMessageId > 0 &&
          message.messageId > 0 &&
          candidateMessageId != message.messageId) {
        continue;
      }
      final age = now.difference(candidate.createdAt).abs();
      if (candidateMessageId <= 0 &&
          candidate.status != 'sending' &&
          age > const Duration(minutes: 1)) {
        continue;
      }
      if (candidate.text.trim() != content) continue;
      return candidate;
    }
    return null;
  }

  LocationChatMessageParser? _parserForMessage(WorldChatroomMessage message) {
    return locationChatMessageParserForTesting(message);
  }

  void _syncSenderIdentity(WorldChatroomService service) {
    final identity = service.identity;
    if (identity == null) return;
    final userId = identity.userId.trim();
    final senderId = identity.senderId.trim();
    final senderName = identity.senderName.trim();
    _rememberMyUserId(userId);
    _rememberMySenderId(senderId);
    if (senderName.isNotEmpty) _mySenderName = senderName;
  }

  Future<void> _syncLocalIdentity(AppServices services) async {
    final uid = (await services.sessionStore.readUid())?.trim() ?? '';
    final userInfo = await services.sessionStore.readUserInfo();
    final cachedUid = _mapString(userInfo, 'uid');
    final avatarUrl = _resolvedProfileAvatar(
      userInfo ?? const <String, dynamic>{},
      '',
    );
    final avatarChanged = avatarUrl != _myAvatarUrl;
    _myAvatarUrl = avatarUrl;
    final changed =
        _rememberMyUserId(uid) | _rememberMyUserId(cachedUid) | avatarChanged;
    if (!changed || !mounted) return;
    final mentionCatalogChanged = _textController.updateCatalog(
      _mentionCatalogForState(_chatroomState),
    );
    final changedMessages = _reconcileMessages(
      _chatroomState.messagesByLocation[widget.locationId] ??
          const <WorldChatroomMessage>[],
    );
    if ((changedMessages || mentionCatalogChanged) && mounted) {
      _setLocationChatState(() {});
    }
  }

  bool _rememberMyUserId(String? userId) {
    final trimmed = userId?.trim() ?? '';
    final key = _chatroomIdentityKey(trimmed);
    if (key.isEmpty) return false;
    if (_myUserId.isEmpty) _myUserId = trimmed;
    return _myUserIdKeys.add(key);
  }

  bool _rememberMySenderId(String? senderId) {
    final trimmed = senderId?.trim() ?? '';
    final key = _chatroomIdentityKey(trimmed);
    if (key.isEmpty) return false;
    if (_mySenderId.isEmpty) _mySenderId = trimmed;
    return _mySenderIdKeys.add(key);
  }

  bool _isMineMessage(
    WorldChatroomMessage message, {
    WorldChatroomState? identityState,
  }) {
    final world = (identityState ?? _chatroomState).world;
    return _locationChatMessageBelongsToCurrentRole(
      messageBusinessType:
          message.hasExplicitBusinessType || message.isLlmStreamMessage
          ? locationChatBusinessType(message)
          : '',
      messageUserId: message.userId,
      messageSenderId: message.senderId,
      currentUserIds: _myUserIdKeys,
      currentSenderIds: _mySenderIdKeys,
      characters: world?.characters ?? const <Map<String, dynamic>>[],
      characterPositions:
          world?.characterPositions ?? const <Map<String, dynamic>>[],
    );
  }

  void _handleFailure(ChatroomFailureEvent failure) {
    if (!isChatroomUnauthorizedFailure(failure)) return;
    unawaited(_handleUnauthorizedFailure());
  }

  Future<void> _handleUnauthorizedFailure() async {
    if (_handlingUnauthorizedFailure || !mounted) return;
    _handlingUnauthorizedFailure = true;
    try {
      final services = AppServicesScope.read(context);
      final previousService = _service;
      final ownedPreviousService = _ownsService;
      await _closeChatroom();
      if (!ownedPreviousService && previousService != null) {
        try {
          await previousService.disconnect();
        } catch (_) {}
      }
      await services.sessionStore.clearUid();
      services.notifySessionChanged();
      try {
        await services.identityAuth.signOutIdentity();
      } catch (error) {
        debugPrint(
          '[Auth][ChatroomUnauthorized] identity sign out failed: $error',
        );
      }
      if (!mounted) return;
      final loggedIn = await ensureGenesisLogin(context);
      if (!mounted) return;
      if (!loggedIn) {
        final onBack = widget.onBack;
        if (onBack != null) {
          onBack();
        } else {
          await Navigator.of(context).maybePop();
        }
        return;
      }
      if (!ownedPreviousService && previousService != null) {
        _service = previousService;
        _ownsService = false;
        _attachService(previousService);
        await _connectFallbackAndJoin(previousService, services);
      } else {
        _prepareConnection();
      }
    } finally {
      _handlingUnauthorizedFailure = false;
    }
  }
}

@visibleForTesting
LocationChatMessageParser? locationChatMessageParserForTesting(
  WorldChatroomMessage message,
) {
  if (!locationChatMessageHasSupportedExplicitV2Envelope(message)) {
    return null;
  }
  final businessType = locationChatBusinessType(message);
  final normalizedMessageType = normalizeChatroomMessageType(
    message.messageType,
  );
  switch (businessType) {
    case 'tick':
      return const TickMessageParser();
    case chatroomUserEnterLocationSenderType:
      return const UserEnterLocationMessageParser();
    case chatroomStoryEventsSenderType:
      return const StoryEventsMessageParser();
    case chatroomCharactersMovedSenderType:
      return const CharactersMovedMessageParser();
    case 'narrator':
      return switch (normalizedMessageType) {
        chatroomTextMessageType => const NarratorMessageParser(),
        chatroomImageMessageType => const ImageMessageParser(),
        _ => null,
      };
    case 'user':
    case 'character':
    case 'system':
      if (normalizedMessageType != chatroomTextMessageType) return null;
      return TextMessageParser(senderType: businessType);
  }
  if (message.hasExplicitBusinessType) return null;
  final renderKind = resolveChatroomMessageRenderKind(
    messageType: message.messageType,
    senderId: message.senderId,
  );
  if (renderKind == ChatroomMessageRenderKind.hidden) return null;
  if (renderKind == ChatroomMessageRenderKind.image) {
    return const ImageMessageParser();
  }
  return switch (locationChatResolvedSenderType(message)) {
    'narrator' => const NarratorMessageParser(),
    _ => const TextMessageParser(),
  };
}

class _LocationChatTimelineVmCacheEntry {
  const _LocationChatTimelineVmCacheEntry({
    required this.payload,
    required this.identityRevision,
    required this.viewModel,
  });

  final ChatroomTimelinePayload? payload;
  final int identityRevision;
  final ChatTimelinePayloadVm? viewModel;
}

class _LocationChatTimelineIdentityIndex {
  _LocationChatTimelineIdentityIndex._({
    required this.characterNamesById,
    required this.locationNamesById,
    required this.roleNamesById,
    required this.roleIsAiById,
    required this.roleAvatarsById,
    required this.revision,
  });

  factory _LocationChatTimelineIdentityIndex.fromState(
    WorldChatroomState state, {
    required Iterable<String> currentUserIds,
    required Iterable<String> currentSenderIds,
  }) {
    final world = state.world;
    final characters = world?.characters ?? const <Map<String, dynamic>>[];
    final characterPositions =
        world?.characterPositions ?? const <Map<String, dynamic>>[];
    final characterNamesById = <String, String>{};
    for (final candidate in <Map<String, dynamic>>[
      ...characters,
      ...characterPositions,
    ]) {
      final rawCharacter = candidate['character'];
      final character = rawCharacter is Map
          ? _stringKeyMap(rawCharacter)
          : candidate;
      final characterId = _firstMapString(character, const [
        'char_id',
        'character_id',
        'id',
      ]).trim();
      final key = _chatroomIdentityKey(characterId);
      if (key.isEmpty || characterNamesById.containsKey(key)) continue;
      final name = _firstMapString(character, const [
        'name',
        'role_nickname',
        'role_name',
        'character_name',
      ]).trim();
      if (name.isNotEmpty) {
        characterNamesById[key] = normalizeGenesisUgcTextForDisplay(name);
      }
    }
    for (final entry in state.entitiesById.entries) {
      final keys = <String>{
        _chatroomIdentityKey(entry.key),
        _chatroomIdentityKey(entry.value.id),
      }..remove('');
      final name = entry.value.name.trim();
      if (name.isEmpty) continue;
      for (final key in keys) {
        characterNamesById.putIfAbsent(
          key,
          () => normalizeGenesisUgcTextForDisplay(name),
        );
      }
    }

    final locationNamesById = <String, String>{};
    final locations = <Map<String, dynamic>>[
      ...?world?.locations,
      ...?world?.processedLocationTree.flattened.map((node) => node.value),
    ];
    for (final location in locations) {
      final locationId = _firstMapString(location, const [
        'location_id',
        'id',
      ]).trim();
      final key = _chatroomIdentityKey(locationId);
      if (key.isEmpty || locationNamesById.containsKey(key)) continue;
      final name = _firstMapString(location, const [
        'location_name',
        'name',
      ]).trim();
      if (name.isNotEmpty) {
        locationNamesById[key] = normalizeGenesisUgcTextForDisplay(name);
      }
    }
    final roleNamesById = _locationChatRoleNamesById(
      currentUserIds: currentUserIds,
      currentSenderIds: currentSenderIds,
      characters: characters,
      characterPositions: characterPositions,
    );
    final roleIsAiById = _locationChatRoleIsAiById(
      characters: characters,
      characterPositions: characterPositions,
      entitiesById: state.entitiesById,
    );
    final roleAvatarsById = _locationChatRoleAvatarsById(
      characters: characters,
      characterPositions: characterPositions,
      entitiesById: state.entitiesById,
    );
    final revision = Object.hashAll(<Object?>[
      ...characterNamesById.entries.expand((entry) => [entry.key, entry.value]),
      ...locationNamesById.entries.expand((entry) => [entry.key, entry.value]),
      ...roleNamesById.entries.expand((entry) => [entry.key, entry.value]),
      ...roleIsAiById.entries.expand((entry) => [entry.key, entry.value]),
      ...roleAvatarsById.entries.expand((entry) => [entry.key, entry.value]),
    ]);
    return _LocationChatTimelineIdentityIndex._(
      characterNamesById: characterNamesById,
      locationNamesById: locationNamesById,
      roleNamesById: roleNamesById,
      roleIsAiById: roleIsAiById,
      roleAvatarsById: roleAvatarsById,
      revision: revision,
    );
  }

  final Map<String, String> characterNamesById;
  final Map<String, String> locationNamesById;
  final Map<String, String> roleNamesById;
  final Map<String, bool> roleIsAiById;
  final Map<String, String> roleAvatarsById;
  final int revision;

  String characterName(String characterId) {
    final resolvedId = characterId.trim();
    return characterNamesById[_chatroomIdentityKey(resolvedId)] ?? resolvedId;
  }

  String locationName(String locationId) {
    final resolvedId = locationId.trim();
    return locationNamesById[_chatroomIdentityKey(resolvedId)] ?? resolvedId;
  }

  String roleName(String roleId) {
    return roleNamesById[_chatroomIdentityKey(roleId)] ?? '';
  }

  bool? roleIsAi(String roleId) {
    return roleIsAiById[_chatroomIdentityKey(roleId)];
  }

  String roleAvatarUrl(String roleId) {
    return roleAvatarsById[_chatroomIdentityKey(roleId)] ?? '';
  }
}

String _resolveTimelineCharacterName(
  String characterId, {
  required Iterable<Map<String, dynamic>> characters,
  required Iterable<Map<String, dynamic>> characterPositions,
  required Map<String, WorldChatroomEntity> entitiesById,
}) {
  final resolvedId = characterId.trim();
  final identityKey = _chatroomIdentityKey(resolvedId);
  for (final candidate in <Map<String, dynamic>>[
    ...characters,
    ...characterPositions,
  ]) {
    final rawCharacter = candidate['character'];
    final character = rawCharacter is Map
        ? _stringKeyMap(rawCharacter)
        : candidate;
    final candidateId = _firstMapString(character, const [
      'char_id',
      'character_id',
      'id',
    ]);
    if (_chatroomIdentityKey(candidateId) != identityKey) continue;
    final name = _firstMapString(character, const [
      'name',
      'role_nickname',
      'role_name',
      'character_name',
    ]).trim();
    if (name.isNotEmpty) return normalizeGenesisUgcTextForDisplay(name);
  }
  for (final entry in entitiesById.entries) {
    if (_chatroomIdentityKey(entry.key) != identityKey &&
        _chatroomIdentityKey(entry.value.id) != identityKey) {
      continue;
    }
    final name = entry.value.name.trim();
    if (name.isNotEmpty) return normalizeGenesisUgcTextForDisplay(name);
  }
  return resolvedId;
}

String _resolveTimelineLocationName(
  String locationId, {
  required Iterable<Map<String, dynamic>> locations,
  ProcessedLocationTree<Map<String, dynamic>>? processedLocationTree,
}) {
  final resolvedId = locationId.trim();
  final identityKey = _chatroomIdentityKey(resolvedId);
  for (final location in locations) {
    final candidateId = _firstMapString(location, const ['location_id', 'id']);
    if (_chatroomIdentityKey(candidateId) != identityKey) continue;
    final name = _firstMapString(location, const [
      'location_name',
      'name',
    ]).trim();
    if (name.isNotEmpty) return normalizeGenesisUgcTextForDisplay(name);
  }
  final node = processedLocationTree?.nodeById(resolvedId);
  if (node != null) {
    final name = _firstMapString(node.value, const [
      'location_name',
      'name',
    ]).trim();
    if (name.isNotEmpty) return normalizeGenesisUgcTextForDisplay(name);
  }
  return resolvedId;
}

Map<String, String> _locationChatRoleNamesById({
  required Iterable<String> currentUserIds,
  required Iterable<String> currentSenderIds,
  required Iterable<Map<String, dynamic>> characters,
  required Iterable<Map<String, dynamic>> characterPositions,
}) {
  final candidates = <Map<String, dynamic>>[];
  for (final candidate in <Map<String, dynamic>>[
    ...characters,
    ...characterPositions,
  ]) {
    final rawCharacter = candidate['character'];
    candidates.add(
      rawCharacter is Map ? _stringKeyMap(rawCharacter) : candidate,
    );
  }
  final result = <String, String>{};
  for (final character in candidates) {
    final characterId = _firstMapString(character, const [
      'character_id',
      'char_id',
      'id',
    ]).trim();
    final characterKey = _chatroomIdentityKey(characterId);
    if (characterKey.isEmpty) continue;
    final name = _firstMapString(character, const [
      'name',
      'role_nickname',
      'role_name',
      'character_name',
    ]).trim();
    final resolvedName = normalizeGenesisUgcTextForDisplay(
      name.isEmpty ? characterId : name,
    );
    final existingName = result[characterKey];
    if (existingName == null ||
        existingName == characterId ||
        name.isNotEmpty) {
      result[characterKey] = resolvedName;
    }
  }
  return result;
}

Map<String, bool> _locationChatRoleIsAiById({
  required Iterable<Map<String, dynamic>> characters,
  required Iterable<Map<String, dynamic>> characterPositions,
  required Map<String, WorldChatroomEntity> entitiesById,
}) {
  final result = <String, bool>{};
  for (final candidate in <Map<String, dynamic>>[
    ...characters,
    ...characterPositions,
  ]) {
    final rawCharacter = candidate['character'];
    final character = rawCharacter is Map
        ? _stringKeyMap(rawCharacter)
        : candidate;
    final characterId = _firstMapString(character, const [
      'character_id',
      'char_id',
      'id',
    ]).trim();
    final key = _chatroomIdentityKey(characterId);
    if (key.isEmpty) continue;
    if (!character.containsKey('player_uid') && result.containsKey(key)) {
      continue;
    }
    result[key] = _firstMapString(character, const ['player_uid']).isEmpty;
  }
  for (final entry in entitiesById.entries) {
    final keys = <String>{
      _chatroomIdentityKey(entry.key),
      _chatroomIdentityKey(entry.value.id),
    }..remove('');
    for (final key in keys) {
      result.putIfAbsent(key, () => entry.value.isAi);
    }
  }
  return result;
}

Map<String, String> _locationChatRoleAvatarsById({
  required Iterable<Map<String, dynamic>> characters,
  required Iterable<Map<String, dynamic>> characterPositions,
  required Map<String, WorldChatroomEntity> entitiesById,
}) {
  final result = <String, String>{};
  for (final candidate in <Map<String, dynamic>>[
    ...characters,
    ...characterPositions,
  ]) {
    final rawCharacter = candidate['character'];
    final character = rawCharacter is Map
        ? _stringKeyMap(rawCharacter)
        : candidate;
    final characterId = _firstMapString(character, const [
      'character_id',
      'char_id',
      'id',
    ]).trim();
    final key = _chatroomIdentityKey(characterId);
    if (key.isEmpty) continue;
    final avatarUrl = _firstMapImageUrl(character, const [
      'avatar',
      'avatar_url',
    ]);
    if (avatarUrl.isNotEmpty) result.putIfAbsent(key, () => avatarUrl);
  }
  for (final entry in entitiesById.entries) {
    final avatarUrl = entry.value.avatarUrl.trim();
    if (avatarUrl.isEmpty) continue;
    final keys = <String>{
      _chatroomIdentityKey(entry.key),
      _chatroomIdentityKey(entry.value.id),
    }..remove('');
    for (final key in keys) {
      result.putIfAbsent(key, () => avatarUrl);
    }
  }
  return result;
}

@visibleForTesting
Map<String, String> locationChatCurrentRoleNamesByIdForTesting({
  required Iterable<String> currentUserIds,
  required Iterable<String> currentSenderIds,
  required Iterable<Map<String, dynamic>> characters,
  required Iterable<Map<String, dynamic>> characterPositions,
}) {
  return _locationChatRoleNamesById(
    currentUserIds: currentUserIds,
    currentSenderIds: currentSenderIds,
    characters: characters,
    characterPositions: characterPositions,
  );
}

@visibleForTesting
Map<String, bool> locationChatRoleIsAiByIdForTesting({
  required Iterable<Map<String, dynamic>> characters,
  Iterable<Map<String, dynamic>> characterPositions =
      const <Map<String, dynamic>>[],
  Map<String, WorldChatroomEntity> entitiesById =
      const <String, WorldChatroomEntity>{},
}) {
  return _locationChatRoleIsAiById(
    characters: characters,
    characterPositions: characterPositions,
    entitiesById: entitiesById,
  );
}

@visibleForTesting
ChatStoryEventParagraphVm? locationChatStoryEventParagraphVmForTesting(
  ChatroomStoryEventParagraph paragraph, {
  required Map<String, String> roleNamesById,
  Map<String, bool> roleIsAiById = const <String, bool>{},
}) {
  return parseLocationChatStoryEventParagraph(
    paragraph,
    roleName: (id) => roleNamesById[_chatroomIdentityKey(id)] ?? '',
    roleIsAi: (id) => roleIsAiById[_chatroomIdentityKey(id)],
  );
}

@visibleForTesting
String resolveLocationChatTimelineCharacterNameForTesting({
  required String characterId,
  Iterable<Map<String, dynamic>> characters = const <Map<String, dynamic>>[],
  Iterable<Map<String, dynamic>> characterPositions =
      const <Map<String, dynamic>>[],
  Map<String, WorldChatroomEntity> entitiesById =
      const <String, WorldChatroomEntity>{},
}) {
  return _resolveTimelineCharacterName(
    characterId,
    characters: characters,
    characterPositions: characterPositions,
    entitiesById: entitiesById,
  );
}

@visibleForTesting
String resolveLocationChatTimelineLocationNameForTesting({
  required String locationId,
  Iterable<Map<String, dynamic>> locations = const <Map<String, dynamic>>[],
}) {
  return _resolveTimelineLocationName(locationId, locations: locations);
}

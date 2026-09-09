part of 'world_chatroom_service.dart';

extension _WorldChatroomMessageReducer on WorldChatroomService {
  Future<void> _handleIncomingMessage(WorldChatroomMessage message) async {
    _upsertMessage(message, socketCurrentTime: message.currentTime);
  }

  Future<void> _handleCharactersMovedMessage(
    WorldChatroomMessage message, {
    bool persist = true,
  }) async {
    final locationId = message.locationId.trim();
    final locationIds = locationId.isNotEmpty
        ? <String>[locationId]
        : _tickAdvanceLocationIds('');
    _upsertMessages(
      locationIds.isEmpty
          ? <WorldChatroomMessage>[message]
          : locationIds
                .map((targetId) => message.copyWith(locationId: targetId))
                .toList(growable: false),
      persist: persist,
      socketCurrentTime: message.currentTime,
    );
  }

  Future<void> _handleTickAdvanceMessage(WorldChatroomMessage message) async {
    if (message.isV2LocationTick) {
      _upsertMessage(
        message,
        socketCurrentTime: message.currentTime,
        socketTickNo: message.tickNo,
        socketSubTickNo: message.subTickNo,
      );
      return;
    }
    final messages = _tickAdvanceLocationIds(message.locationId)
        .map((locationId) => message.copyWith(locationId: locationId))
        .toList(growable: false);
    _upsertMessages(
      messages.isEmpty ? [message] : messages,
      socketCurrentTime: message.currentTime,
      socketTickNo: message.tickNo,
      socketSubTickNo: message.subTickNo,
    );
  }

  Future<List<WorldChatroomMessage>> _fetchLatestLocationMessages({
    required String locationId,
    required int limit,
    bool emitLatestFetched = true,
  }) async {
    if (_worldId.isEmpty) return const <WorldChatroomMessage>[];
    _requireHistoryAvailable(locationId);
    final ticket = _historyTicket(locationId);
    final response = await _api.chatroomHttp.getMessages(
      worldId: _worldId,
      locationId: locationId,
      since: 0,
      limit: limit,
    );
    final messages = await _mergeFetchedMessages(
      locationId,
      response.messages,
      ticket: ticket,
    );
    if (emitLatestFetched &&
        messages.isNotEmpty &&
        !_latestFetchedMessages.isClosed) {
      _latestFetchedMessages.add(messages);
    }
    _recordServiceQueueDebug(
      action: 'refreshLocationLatestDone',
      locationId: locationId,
      details: {
        'limit': limit,
        'loaded': messages.length,
        'hasMore': response.hasMore,
        'emitLatestFetched': emitLatestFetched,
      },
    );
    return messages;
  }

  Future<List<WorldChatroomMessage>> _fetchLatestLocationMessagesWithFailure({
    required String locationId,
    required int limit,
    bool emitLatestFetched = true,
  }) async {
    try {
      return await _fetchLatestLocationMessages(
        locationId: locationId,
        limit: limit,
        emitLatestFetched: emitLatestFetched,
      );
    } catch (e) {
      _logChatroomSocketEvent(
        'latest location messages fetch failed world=$_worldId '
        'location=$locationId limit=$limit error=$e',
      );
      _recordFailure(
        ChatroomFailureEvent(
          code: 'message_history_load_failed',
          message: 'Something went wrong',
          sourceType: 'message_history',
          requestType: 'get_messages',
          cause: e,
        ),
      );
      return const <WorldChatroomMessage>[];
    }
  }

  Future<List<WorldChatroomMessage>> _fetchLatestWorldMessages({
    required int limit,
    bool emitLatestFetched = true,
  }) async {
    final stopwatch = _chatroomHydrateMetricsEnabled
        ? (Stopwatch()..start())
        : null;
    if (_worldId.isEmpty) return const <WorldChatroomMessage>[];
    _logChatroomHydrateMetric(
      'world history fetch start world=$_worldId limit=$limit '
      'locationCount=${_state.messagesByLocation.length}',
    );
    final locationIds = _leafLocationIdsForCurrentWorld();
    final messages = <WorldChatroomMessage>[];
    await _runLimited<String>(
      locationIds,
      _defaultLocationQueueInitConcurrency,
      (locationId) async {
        final fetched = await _fetchLatestLocationMessagesWithFailure(
          locationId: locationId,
          limit: limit,
          emitLatestFetched: false,
        );
        messages.addAll(fetched);
      },
    );
    if (emitLatestFetched &&
        messages.isNotEmpty &&
        !_latestFetchedMessages.isClosed) {
      _latestFetchedMessages.add(messages);
    }
    _logChatroomHydrateMetric(
      'world history fetch done world=$_worldId '
      'locations=${locationIds.length} loaded=${messages.length} '
      'elapsed=${stopwatch?.elapsedMilliseconds}ms',
    );
    _recordServiceQueueDebug(
      action: 'refreshWorldLatestDone',
      locationId: '',
      details: {
        'limit': limit,
        'locations': locationIds.length,
        'loaded': messages.length,
        'emitLatestFetched': emitLatestFetched,
        'elapsedMs': stopwatch?.elapsedMilliseconds,
      },
    );
    return messages;
  }

  Future<List<WorldChatroomMessage>> _fetchLatestWorldMessagesWithFailure({
    required int limit,
    bool emitLatestFetched = true,
  }) async {
    try {
      return await _fetchLatestWorldMessages(
        limit: limit,
        emitLatestFetched: emitLatestFetched,
      );
    } catch (e) {
      _logChatroomSocketEvent(
        'latest world messages fetch failed world=$_worldId limit=$limit error=$e',
      );
      _recordFailure(
        ChatroomFailureEvent(
          code: 'message_history_load_failed',
          message: 'Something went wrong',
          sourceType: 'message_history',
          requestType: 'get_messages',
          cause: e,
        ),
      );
      return const <WorldChatroomMessage>[];
    }
  }

  Future<void> _scheduleLatestMessagesRefresh() {
    if (_disposed || _worldId.trim().isEmpty) return Future<void>.value();
    _latestWorldMessagesRefreshPending = true;
    final activeDrain = _latestWorldMessagesRefreshDrain;
    if (activeDrain != null) return activeDrain;
    final drain = _drainLatestMessagesRefreshes();
    _latestWorldMessagesRefreshDrain = drain;
    unawaited(
      drain.whenComplete(() {
        if (!identical(_latestWorldMessagesRefreshDrain, drain)) return;
        _latestWorldMessagesRefreshDrain = null;
        if (_latestWorldMessagesRefreshPending && !_disposed) {
          unawaited(_scheduleLatestMessagesRefresh());
        }
      }),
    );
    return drain;
  }

  Future<void> _drainLatestMessagesRefreshes() async {
    while (_latestWorldMessagesRefreshPending && !_disposed) {
      _latestWorldMessagesRefreshPending = false;
      try {
        await _fetchLatestWorldMessagesWithFailure(limit: 20);
      } catch (error) {
        if (_disposed) return;
        _recordFailure(
          ChatroomFailureEvent(
            code: 'message_history_load_failed',
            message: 'Something went wrong',
            sourceType: 'world_message_refresh',
            requestType: 'get_messages',
            cause: error,
          ),
        );
      }
    }
  }

  List<String> _leafLocationIdsForCurrentWorld() {
    return _leafLocationIdsForWorld(_state.world);
  }

  List<String> _leafLocationIdsForWorld(WorldDetail? world) {
    final ids = <String>{};
    if (world != null) {
      for (final node in world.processedLocationTree.flattened) {
        if (node.children.isNotEmpty) continue;
        final id = node.id.trim();
        if (id.isNotEmpty) ids.add(id);
      }
      if (ids.isEmpty) {
        final parentIds = world.locations
            .map((location) => asString(location['location_pid']).trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        for (final location in world.locations) {
          final id = asString(
            location['location_id'],
            fallback: asString(location['id']),
          ).trim();
          if (id.isEmpty || parentIds.contains(id)) continue;
          ids.add(id);
        }
      }
    }
    return ids.toList(growable: false);
  }

  List<String> _tickAdvanceLocationIds(String fallbackLocationId) {
    final ids = <String>{..._leafLocationIdsForCurrentWorld()};
    if (ids.isEmpty) {
      ids.addAll(
        _state.messagesByLocation.keys
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty),
      );
      final joinedLocationId = _state.joinedLocationId.trim();
      if (joinedLocationId.isNotEmpty) ids.add(joinedLocationId);
      final fallback = fallbackLocationId.trim();
      if (fallback.isNotEmpty) ids.add(fallback);
    }
    return ids.toList(growable: false);
  }

  Future<List<WorldChatroomMessage>> _mergeFetchedMessages(
    String locationId,
    List<ChatroomHttpMessage> messages, {
    required _HistoryTicket ticket,
  }) async {
    if (!_historyIsCurrent(locationId, ticket)) {
      return const <WorldChatroomMessage>[];
    }
    final worldMessages = messages
        .map(
          (message) => _worldMessageFromHttpMessage(
            message,
            fallbackLocationId: locationId,
          ),
        )
        .toList(growable: false);
    await _withLocationWrite(locationId, () async {
      if (!_historyIsCurrent(locationId, ticket)) return;
      if (ticket.owner.isNotEmpty && ticket.world.isNotEmpty) {
        await _messageStorage.mergeMessages(
          ownerUid: ticket.owner,
          worldId: ticket.world,
          locationId: locationId,
          messages: messages
              .map(
                (m) => _storageJsonFromHttpMessage(
                  m,
                  fallbackLocationId: locationId,
                ),
              )
              .toList(),
          maxMessagesPerLocation: _maxMessagesPerLocation,
        );
      }
      if (_historyIsCurrent(locationId, ticket)) {
        _upsertMessages(worldMessages, persist: false);
      }
    });
    if (!_historyIsCurrent(locationId, ticket)) {
      return const <WorldChatroomMessage>[];
    }
    await _loadReplyCardsForHistory(locationId, worldMessages, ticket);
    if (!_historyIsCurrent(locationId, ticket)) {
      return const <WorldChatroomMessage>[];
    }
    if (LocationChatDebugSlice.enabled) {
      LocationChatDebugSlice.recordEvent(
        source: 'service',
        action: 'mergeFetched',
        worldId: _worldId,
        locationId: locationId,
        details: {
          'incoming': messages.length,
          'messages': LocationChatDebugSlice.debugWorldMessageQueue(
            worldMessages,
          ),
        },
      );
    }
    return worldMessages;
  }

  void _startStream(ChatroomAiStreamStart event) {
    final key = _streamKey(
      event.locationId,
      event.conversationRoundId,
      event.senderId,
    );
    if (key.isEmpty) return;
    final message = WorldChatroomMessage.fromAiStreamStart(event);
    final existing = _streamAccumulators[key];
    if (existing == null) {
      _streamAccumulators[key] = _ChatroomStreamAccumulator(message: message);
      _upsertMessage(
        message,
        persist: false,
        socketCurrentTime: event.currentTime,
      );
      return;
    }
    existing.message = message.copyWith(content: existing.message.content);
    _upsertMessage(
      existing.message,
      persist: false,
      socketCurrentTime: event.currentTime,
    );
  }

  void _appendStreamChunk(ChatroomAiStreamChunk event) {
    final key = _streamKey(
      event.locationId,
      event.conversationRoundId,
      event.senderId,
    );
    if (key.isEmpty) return;
    var accumulator = _streamAccumulators[key];
    var createdAccumulator = false;
    if (accumulator == null) {
      final entity = _state.entitiesById[event.senderId];
      final synthetic = WorldChatroomMessage(
        globalMessageId: event.globalMessageId,
        messageId: event.messageId,
        locationMessageId: event.locationMessageId,
        conversationRoundId: event.conversationRoundId,
        roundOrder: 0,
        locationId: event.locationId,
        businessType: event.businessType.isEmpty
            ? 'character'
            : event.businessType,
        streamType: event.streamType,
        senderType: 'character',
        senderId: event.senderId,
        senderName: entity?.name ?? event.senderId,
        content: '',
        currentTime: event.currentTime,
        createdAt: null,
        streaming: true,
        isLlmStreamMessage: true,
        minAppVersion: event.minAppVersion ?? 0,
        rawPayload: event.rawPayload,
      );
      accumulator = _ChatroomStreamAccumulator(
        message: synthetic,
        firstSequence: event.seq == 0 ? 0 : 1,
      );
      _streamAccumulators[key] = accumulator;
      createdAccumulator = true;
    }
    final changed = accumulator.addChunk(event.seq, event.chunk);
    _recordServiceQueueDebug(
      action: changed ? 'streamChunkApplied' : 'streamChunkBuffered',
      locationId: event.locationId,
      details: {
        'streamKey': key,
        'seq': event.seq,
        'nextSeq': accumulator.nextSequence,
        'bufferedSeqs': accumulator.chunks.keys.toList(growable: false),
      },
    );
    if (!changed) {
      if (createdAccumulator) {
        _upsertMessage(
          accumulator.message,
          persist: false,
          socketCurrentTime: event.currentTime,
        );
      }
      return;
    }
    accumulator.message = accumulator.message.copyWith(
      currentTime: event.currentTime.trim().isEmpty
          ? accumulator.message.currentTime
          : event.currentTime,
    );
    _upsertMessage(
      accumulator.message,
      persist: false,
      socketCurrentTime: event.currentTime,
    );
  }

  void _finishStream(ChatroomAiStreamEnd event) {
    final key = _streamKey(
      event.locationId,
      event.conversationRoundId,
      event.senderId,
    );
    if (key.isEmpty) return;
    final accumulator = _streamAccumulators.remove(key);
    final existing =
        accumulator?.message ??
        _state.streamMessagesByKey[key] ??
        WorldChatroomMessage(
          messageId: event.messageId,
          locationMessageId: event.locationMessageId,
          conversationRoundId: event.conversationRoundId,
          roundOrder: 0,
          locationId: event.locationId,
          businessType: event.businessType.isEmpty
              ? 'character'
              : event.businessType,
          streamType: event.streamType,
          senderType: 'character',
          senderId: event.senderId,
          senderName:
              _state.entitiesById[event.senderId]?.name ?? event.senderId,
          content: '',
          createdAt: event.createdAt,
          isLlmStreamMessage: true,
          minAppVersion: event.minAppVersion ?? 0,
          rawPayload: event.rawPayload,
        );
    _recordServiceQueueDebug(
      action: 'streamEnd',
      locationId: event.locationId,
      details: {
        'streamKey': key,
        'finalMessageId': event.messageId,
        'finalLocationMessageId': event.locationMessageId,
        'usedAuthoritativeContent': event.content.trim().isNotEmpty,
      },
    );
    _removeProvisionalStreamMessages(
      key: key,
      locationId: event.locationId,
      conversationRoundId: event.conversationRoundId,
      senderId: event.senderId,
    );
    _upsertMessage(
      existing.copyWith(
        globalMessageId: event.globalMessageId > 0
            ? event.globalMessageId
            : existing.globalMessageId,
        messageId: event.messageId > 0 ? event.messageId : existing.messageId,
        locationMessageId: event.locationMessageId > 0
            ? event.locationMessageId
            : existing.locationMessageId,
        content: event.content.trim().isEmpty
            ? existing.content
            : event.content,
        currentTime: event.currentTime.trim().isEmpty
            ? existing.currentTime
            : event.currentTime,
        createdAt: event.createdAt ?? existing.createdAt,
        streamType: event.streamType,
        minAppVersion: event.minAppVersion ?? existing.minAppVersion,
        rawPayload: event.rawPayload.isEmpty
            ? existing.rawPayload
            : event.rawPayload,
        streaming: false,
      ),
      socketCurrentTime: event.currentTime,
    );
  }

  void _removeProvisionalStreamMessages({
    String key = '',
    String locationId = '',
    String conversationRoundId = '',
    String senderId = '',
    bool removeAll = false,
  }) {
    bool matches(WorldChatroomMessage message) {
      if (!message.streaming) return false;
      if (removeAll) return true;
      return message.locationId.trim() == locationId.trim() &&
          message.conversationRoundId.trim() == conversationRoundId.trim() &&
          message.senderId.trim() == senderId.trim();
    }

    final worldMessages = _state.worldMessages
        .where((message) => !matches(message))
        .toList(growable: false);
    final messagesByLocation = <String, List<WorldChatroomMessage>>{
      for (final entry in _state.messagesByLocation.entries)
        entry.key: List<WorldChatroomMessage>.unmodifiable(
          entry.value.where((message) => !matches(message)),
        ),
    };
    final streamMessagesByKey =
        <String, WorldChatroomMessage>{..._state.streamMessagesByKey}
          ..removeWhere(
            (streamKey, message) =>
                (key.isNotEmpty && streamKey == key) || matches(message),
          );
    final changed =
        worldMessages.length != _state.worldMessages.length ||
        streamMessagesByKey.length != _state.streamMessagesByKey.length ||
        _state.messagesByLocation.entries.any(
          (entry) =>
              messagesByLocation[entry.key]?.length != entry.value.length,
        );
    if (!changed) return;
    _setState(
      _state.copyWith(
        worldMessages: List<WorldChatroomMessage>.unmodifiable(worldMessages),
        messagesByLocation:
            Map<String, List<WorldChatroomMessage>>.unmodifiable(
              messagesByLocation,
            ),
        streamMessagesByKey: Map<String, WorldChatroomMessage>.unmodifiable(
          streamMessagesByKey,
        ),
      ),
    );
  }

  void _clearProvisionalStreamMessages() {
    _removeProvisionalStreamMessages(removeAll: true);
  }

  WorldChatroomState _stateWithSocketWorldProgress(
    WorldChatroomState state, {
    String socketCurrentTime = '',
    int socketTickNo = 0,
    int socketSubTickNo = 0,
  }) {
    final resolvedSocketCurrentTime = socketCurrentTime.trim();
    final resolvedSocketTickNo = socketTickNo > 0 ? socketTickNo : 0;
    final resolvedSocketSubTickNo = socketSubTickNo > 0 ? socketSubTickNo : 0;
    final hasSocketWorldProgress =
        resolvedSocketCurrentTime.isNotEmpty ||
        resolvedSocketTickNo > 0 ||
        resolvedSocketSubTickNo > 0;
    if (!hasSocketWorldProgress) return state;
    return state.copyWith(
      world: _worldWithSocketProgress(
        state.world,
        currentTime: resolvedSocketCurrentTime,
        tickNo: resolvedSocketTickNo,
        subTickNo: resolvedSocketSubTickNo,
      ),
      latestSocketCurrentTime: resolvedSocketCurrentTime,
      latestSocketTickNo: resolvedSocketTickNo,
      latestSocketSubTickNo: resolvedSocketSubTickNo,
      latestSocketCurrentTimeRevision:
          state.latestSocketCurrentTimeRevision + 1,
    );
  }

  WorldDetail? _worldWithSocketProgress(
    WorldDetail? world, {
    required String currentTime,
    required int tickNo,
    int subTickNo = 0,
  }) {
    if (world == null) return null;
    final resolvedCurrentTime = currentTime.trim();
    final resolvedTickNo = tickNo > 0 ? tickNo : 0;
    final resolvedSubTickNo = subTickNo > 0 ? subTickNo : 0;
    if (resolvedCurrentTime.isEmpty &&
        resolvedTickNo <= 0 &&
        resolvedSubTickNo <= 0) {
      return world;
    }
    return world.copyWith(
      currentTime: resolvedCurrentTime.isEmpty ? null : resolvedCurrentTime,
      tickCount: resolvedTickNo > 0 ? resolvedTickNo : null,
      subTickNo: resolvedSubTickNo > 0 ? resolvedSubTickNo : null,
    );
  }

  void _upsertMessage(
    WorldChatroomMessage message, {
    bool persist = true,
    String socketCurrentTime = '',
    int socketTickNo = 0,
    int socketSubTickNo = 0,
  }) {
    _upsertMessages(
      [message],
      persist: persist,
      socketCurrentTime: socketCurrentTime,
      socketTickNo: socketTickNo,
      socketSubTickNo: socketSubTickNo,
    );
  }

  void _upsertMessages(
    List<WorldChatroomMessage> messages, {
    bool persist = true,
    String socketCurrentTime = '',
    int socketTickNo = 0,
    int socketSubTickNo = 0,
  }) {
    if (messages.isEmpty) return;
    final resolvedSocketCurrentTime = socketCurrentTime.trim();
    final resolvedSocketTickNo = socketTickNo > 0 ? socketTickNo : 0;
    final resolvedSocketSubTickNo = socketSubTickNo > 0 ? socketSubTickNo : 0;
    var worldMessages = _state.worldMessages;
    final byLocation = _leafLocationMessageQueues(
      _state.world,
      _state.messagesByLocation,
    );
    final streamKeys = <String, WorldChatroomMessage>{
      ..._state.streamMessagesByKey,
    };
    final resolvedMessages = <WorldChatroomMessage>[];
    var lastMessageId = _state.lastMessageId;
    for (final incoming in messages) {
      if (_deletedMessageIds[incoming.locationId]?.contains(
            incoming.globalMessageId,
          ) ==
          true) {
        continue;
      }
      _completeCanonicalEcho(incoming);
      _bindCanonicalConversationRound(incoming);
      final message = _mergeWithExistingMessage(worldMessages, incoming);
      resolvedMessages.add(message);
      if (persist && !message.streaming && message.globalMessageId > 0) {
        _historyRefreshes[message.locationId]?.liveMessages[message
                .globalMessageId] =
            message;
      }
      worldMessages = _upsertIntoList(worldMessages, message);
      if (_shouldStoreMessageInLocationQueue(message)) {
        byLocation[message.locationId] = _trimMessageList(
          _upsertIntoList(
            byLocation[message.locationId] ?? const <WorldChatroomMessage>[],
            message,
          ),
          _maxMessagesPerLocation,
        );
      }
      final key = _streamKey(
        message.locationId,
        message.conversationRoundId,
        message.senderId,
      );
      if (message.streaming && key.isNotEmpty) {
        streamKeys[key] = message;
      } else {
        streamKeys.remove(key);
      }
      if (!_isTransientCharactersMovedMessage(message) &&
          message.messageId > lastMessageId) {
        lastMessageId = message.messageId;
      }
      _completeLegacyCharacterRound(message);
    }
    _setState(
      _stateWithSocketWorldProgress(
        _state.copyWith(
          worldMessages: worldMessages,
          messagesByLocation: byLocation,
          streamMessagesByKey: streamKeys,
          lastMessageId: lastMessageId,
        ),
        socketCurrentTime: resolvedSocketCurrentTime,
        socketTickNo: resolvedSocketTickNo,
        socketSubTickNo: resolvedSocketSubTickNo,
      ),
    );
    final changedLocationIds = resolvedMessages
        .map((message) => message.locationId.trim())
        .where((locationId) => locationId.isNotEmpty)
        .toSet();
    for (final locationId in changedLocationIds) {
      _recordServiceQueueDebug(
        action: persist ? 'upsertPersist' : 'upsertState',
        locationId: locationId,
        details: {'incoming': resolvedMessages.length, 'persist': persist},
      );
    }
    if (persist) {
      for (final message in resolvedMessages) {
        unawaited(
          _persistMessage(message).catchError((Object error) {
            _recordFailure(
              ChatroomFailureEvent(
                code: 'message_cache_failed',
                message: 'Something went wrong',
                sourceType: 'message_cache',
                cause: error,
              ),
            );
          }),
        );
      }
    }
    if (persist) {
      for (final locationId in changedLocationIds) {
        _restartPendingHistory(locationId);
      }
    }
  }

  void _completeCanonicalEcho(WorldChatroomMessage message) {
    final clientMsgId = message.clientMsgId.trim();
    if (clientMsgId.isEmpty || !message.isCanonicalUserMessage) return;
    final completer = _canonicalEchoCompleters.remove(clientMsgId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(message);
    }
  }

  List<WorldChatroomMessage> _upsertIntoList(
    List<WorldChatroomMessage> messages,
    WorldChatroomMessage message,
  ) {
    final next = <WorldChatroomMessage>[];
    var replaced = false;
    for (final item in messages) {
      if (_sameMessage(item, message)) {
        if (!replaced) {
          next.add(_mergeSameMessage(item, message));
          replaced = true;
        }
      } else {
        next.add(item);
      }
    }
    if (!replaced) next.add(message);
    next.sort(_compareMessages);
    return List<WorldChatroomMessage>.unmodifiable(next);
  }

  WorldChatroomMessage _mergeWithExistingMessage(
    List<WorldChatroomMessage> messages,
    WorldChatroomMessage incoming,
  ) {
    for (final existing in messages) {
      if (_sameMessage(existing, incoming)) {
        return _mergeSameMessage(existing, incoming);
      }
    }
    return incoming;
  }

  WorldChatroomMessage _mergeSameMessage(
    WorldChatroomMessage existing,
    WorldChatroomMessage incoming,
  ) {
    if (existing.rawPayload['status'] == 20 && incoming.isLlmStreamMessage) {
      return existing;
    }
    final existingIsAuthoritativeStreamEnd =
        existing.isLlmStreamMessage && !existing.streaming;
    final incomingIsCanonicalFinal =
        !incoming.isLlmStreamMessage && !incoming.streaming;
    if (!existingIsAuthoritativeStreamEnd ||
        !incomingIsCanonicalFinal ||
        !_sameStreamIdentity(existing, incoming)) {
      return incoming;
    }
    return incoming.copyWith(
      globalMessageId: existing.globalMessageId > 0
          ? existing.globalMessageId
          : incoming.globalMessageId,
      messageId: existing.messageId > 0
          ? existing.messageId
          : incoming.messageId,
      locationMessageId: existing.locationMessageId > 0
          ? existing.locationMessageId
          : incoming.locationMessageId,
      conversationRoundId: existing.conversationRoundId,
      content: existing.content,
      currentTime: existing.currentTime.trim().isNotEmpty
          ? existing.currentTime
          : incoming.currentTime,
      createdAt: existing.createdAt ?? incoming.createdAt,
      streamType: existing.streamType,
      isLlmStreamMessage: true,
      minAppVersion: existing.minAppVersion > 0
          ? existing.minAppVersion
          : incoming.minAppVersion,
      rawPayload: existing.rawPayload.isNotEmpty
          ? existing.rawPayload
          : incoming.rawPayload,
    );
  }

  bool _sameStreamIdentity(
    WorldChatroomMessage left,
    WorldChatroomMessage right,
  ) {
    final locationId = left.locationId.trim();
    final roundId = left.conversationRoundId.trim();
    final senderId = left.senderId.trim();
    return locationId.isNotEmpty &&
        roundId.isNotEmpty &&
        senderId.isNotEmpty &&
        locationId == right.locationId.trim() &&
        roundId == right.conversationRoundId.trim() &&
        senderId == right.senderId.trim();
  }

  List<WorldChatroomMessage> _trimMessageList(
    List<WorldChatroomMessage> messages,
    int maxMessages,
  ) {
    if (maxMessages <= 0 || messages.length <= maxMessages) return messages;
    return List<WorldChatroomMessage>.unmodifiable(
      messages.skip(messages.length - maxMessages),
    );
  }

  bool _sameMessage(WorldChatroomMessage a, WorldChatroomMessage b) {
    if (a.locationId == b.locationId &&
        a.globalMessageId > 0 &&
        b.globalMessageId > 0) {
      return a.globalMessageId == b.globalMessageId ||
          (a.locationMessageId > 0 &&
              a.locationMessageId == b.locationMessageId);
    }
    final aClientMsgId = a.clientMsgId.trim();
    final bClientMsgId = b.clientMsgId.trim();
    if (aClientMsgId.isNotEmpty && bClientMsgId.isNotEmpty) {
      return aClientMsgId == bClientMsgId;
    }
    if (_sameCanonicalAndTransientCharactersMovedMessage(a, b)) return true;
    if ((a.isLlmStreamMessage || b.isLlmStreamMessage) &&
        _sameStreamIdentity(a, b)) {
      return true;
    }
    if (a.locationId == b.locationId &&
        (isChatroomMessageIdOrderedSupplemental(
              a.senderType,
              locationMessageId: a.locationMessageId,
            ) ||
            isChatroomMessageIdOrderedSupplemental(
              b.senderType,
              locationMessageId: b.locationMessageId,
            )) &&
        a.messageId > 0 &&
        b.messageId > 0) {
      return a.messageId == b.messageId;
    }
    if (a.locationId == b.locationId &&
        a.locationMessageId > 0 &&
        b.locationMessageId > 0) {
      return a.locationMessageId == b.locationMessageId;
    }
    if (a.locationId == b.locationId &&
        a.messageId > 0 &&
        b.messageId > 0 &&
        (a.locationMessageId <= 0 || b.locationMessageId <= 0)) {
      return a.messageId == b.messageId;
    }
    if (a.locationId == b.locationId) {
      return a.conversationRoundId == b.conversationRoundId &&
          a.userId == b.userId &&
          a.senderId == b.senderId &&
          a.streaming == b.streaming;
    }
    if (a.messageId > 0 && b.messageId > 0) {
      return a.messageId == b.messageId;
    }
    return a.locationId == b.locationId &&
        a.conversationRoundId == b.conversationRoundId &&
        a.userId == b.userId &&
        a.senderId == b.senderId &&
        a.streaming == b.streaming;
  }

  bool _sameCanonicalAndTransientCharactersMovedMessage(
    WorldChatroomMessage a,
    WorldChatroomMessage b,
  ) {
    if (a.senderType.trim().toLowerCase() !=
            chatroomCharactersMovedSenderType ||
        b.senderType.trim().toLowerCase() !=
            chatroomCharactersMovedSenderType) {
      return false;
    }
    final aTransient = _isTransientCharactersMovedMessage(a);
    final bTransient = _isTransientCharactersMovedMessage(b);
    if (aTransient == bTransient) return false;
    final aCreatedAt = a.createdAt;
    final bCreatedAt = b.createdAt;
    if (aCreatedAt != null &&
        bCreatedAt != null &&
        aCreatedAt.difference(bCreatedAt).inSeconds.abs() > 300) {
      return false;
    }
    final aPayload = a.timelinePayload;
    final bPayload = b.timelinePayload;
    if (aPayload is! ChatroomCharactersMovedPayload ||
        bPayload is! ChatroomCharactersMovedPayload) {
      return false;
    }
    return encodeChatroomTimelinePayload(aPayload) ==
        encodeChatroomTimelinePayload(bPayload);
  }

  bool _isTransientCharactersMovedMessage(WorldChatroomMessage message) {
    return message.senderType.trim().toLowerCase() ==
            chatroomCharactersMovedSenderType &&
        message.conversationRoundId.startsWith(
          _transientCharactersMovedRoundPrefix,
        );
  }

  int _compareMessages(WorldChatroomMessage a, WorldChatroomMessage b) {
    if (a.locationId == b.locationId) {
      final aIsCursorlessStream = _isCursorlessStreamMessage(a);
      final bIsCursorlessStream = _isCursorlessStreamMessage(b);
      if (aIsCursorlessStream != bIsCursorlessStream) {
        return aIsCursorlessStream ? 1 : -1;
      }
      final aIsCursorlessNonOrdered = _isCursorlessNonOrderedMessage(a);
      final bIsCursorlessNonOrdered = _isCursorlessNonOrderedMessage(b);
      if (aIsCursorlessNonOrdered != bIsCursorlessNonOrdered) {
        return aIsCursorlessNonOrdered ? -1 : 1;
      }
      final aIsMessageIdOrdered = isChatroomMessageIdOrderedSupplemental(
        a.senderType,
        locationMessageId: a.locationMessageId,
      );
      final bIsMessageIdOrdered = isChatroomMessageIdOrderedSupplemental(
        b.senderType,
        locationMessageId: b.locationMessageId,
      );
      if (aIsMessageIdOrdered || bIsMessageIdOrdered) {
        final byMessageId = a.messageId.compareTo(b.messageId);
        if (byMessageId != 0) return byMessageId;
        final byLocationMessage = a.locationMessageId.compareTo(
          b.locationMessageId,
        );
        if (byLocationMessage != 0) return byLocationMessage;
      } else {
        final aHasLocationMessageId = a.locationMessageId > 0;
        final bHasLocationMessageId = b.locationMessageId > 0;
        if (aHasLocationMessageId && bHasLocationMessageId) {
          return a.locationMessageId.compareTo(b.locationMessageId);
        }
        if (aHasLocationMessageId != bHasLocationMessageId) {
          return aHasLocationMessageId ? 1 : -1;
        }
      }
    }
    if (a.locationId == b.locationId) {
      final round = a.conversationRoundNumber.compareTo(
        b.conversationRoundNumber,
      );
      if (round != 0) return round;
      final order = a.roundOrder.compareTo(b.roundOrder);
      if (order != 0) return order;
      return a.messageId.compareTo(b.messageId);
    }
    if (a.messageId > 0 && b.messageId > 0) {
      return a.messageId.compareTo(b.messageId);
    }
    final round = a.conversationRoundNumber.compareTo(
      b.conversationRoundNumber,
    );
    if (round != 0) return round;
    final order = a.roundOrder.compareTo(b.roundOrder);
    if (order != 0) return order;
    return a.messageId.compareTo(b.messageId);
  }

  bool _isCursorlessStreamMessage(WorldChatroomMessage message) {
    return message.locationMessageId <= 0 &&
        message.isLlmStreamMessage &&
        message.streaming;
  }

  bool _isCursorlessNonOrderedMessage(WorldChatroomMessage message) {
    return message.locationMessageId <= 0 &&
        !isChatroomMessageIdOrderedSupplemental(
          message.senderType,
          locationMessageId: message.locationMessageId,
        );
  }

  Map<String, List<WorldChatroomMessage>> _leafLocationMessageQueues(
    WorldDetail? world,
    Map<String, List<WorldChatroomMessage>> current,
  ) {
    if (world == null) {
      return Map<String, List<WorldChatroomMessage>>.from(current);
    }
    final leafIds = _leafLocationIdsForWorld(world);
    if (leafIds.isEmpty) {
      return Map<String, List<WorldChatroomMessage>>.from(current);
    }
    return <String, List<WorldChatroomMessage>>{
      for (final locationId in leafIds)
        locationId: List<WorldChatroomMessage>.unmodifiable(
          (current[locationId] ?? const <WorldChatroomMessage>[]).where(
            _isLocationQueueMessage,
          ),
        ),
    };
  }

  bool _shouldStoreMessageInLocationQueue(WorldChatroomMessage message) {
    return _shouldStoreMessageForLocation(message.locationId) &&
        _isLocationQueueMessage(message);
  }

  bool _shouldStoreMessageForLocation(String locationId) {
    final resolvedLocationId = locationId.trim();
    if (resolvedLocationId.isEmpty) return false;
    final world = _state.world;
    if (world == null) return true;
    final leafIds = _leafLocationIdsForWorld(world);
    return leafIds.isEmpty || leafIds.contains(resolvedLocationId);
  }

  bool _isLocationQueueMessage(WorldChatroomMessage message) {
    return _isTickAdvanceWorldMessage(message) ||
        message.locationMessageId > 0 ||
        message.messageId > 0 ||
        (message.isLlmStreamMessage &&
            message.conversationRoundId.trim().isNotEmpty &&
            message.senderId.trim().isNotEmpty);
  }

  bool _messageIsAtOrBeforeLocationCursor(
    WorldChatroomMessage message,
    int maxLocationMessageId, {
    int maxWorldMessageId = 0,
  }) {
    if (maxLocationMessageId <= 0) return false;
    if (isChatroomMessageIdOrderedSupplemental(
      message.senderType,
      locationMessageId: message.locationMessageId,
    )) {
      return maxWorldMessageId > 0 &&
          message.messageId > 0 &&
          message.messageId <= maxWorldMessageId;
    }
    // Cursorless non-tick legacy timeline records are display-only
    // compatibility items and cannot be assigned to a location gap boundary.
    if (message.locationMessageId <= 0) return false;
    return message.locationMessageId <= maxLocationMessageId;
  }
}

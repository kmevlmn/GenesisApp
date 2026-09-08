part of 'world_chatroom_service.dart';

extension _WorldChatroomEventProjection on WorldChatroomService {
  Future<void> _handleEvent(ChatroomEvent event) async {
    switch (event) {
      case ChatroomLlmCardStream():
      case ChatroomLlmCardGenerationEnd():
        // Candidate protocol events are exposed by the session only.
        break;
      case ChatroomLlmMessageUpdated e:
        await _handleLlmMessageUpdated(e);
      case ChatroomConversationRangeUpdated e:
        if (e.errNo == 0 && e.worldId == _worldId && e.locationId.isNotEmpty) {
          _backgroundHistoryRefresh(
            _requestHistoryReplacement(
              locationId: e.locationId,
              start: e.startConversationRoundId,
              end: e.endConversationRoundId,
            ),
          );
        }
      case ChatroomWorldNotification e:
        await _handleWorldNotification(e);
      case ChatroomNewUserJoinEvent e:
        _handleNewUserJoin(e);
      case ChatroomStoryEventsMessage e:
        await _handleIncomingMessage(
          WorldChatroomMessage.fromStoryEventsMessage(e),
        );
      case ChatroomCharactersMovedMessage e:
        await _handleCharactersMovedMessage(
          WorldChatroomMessage.fromCharactersMovedMessage(e),
        );
      case ChatroomUserEnterLocationMessage e:
        await _handleIncomingMessage(
          WorldChatroomMessage.fromUserEnterLocationMessage(e),
        );
        unawaited(
          _scheduleUserLocationsRefresh(socketCurrentTime: e.currentTime),
        );
      case ChatroomUserMessage e:
        await _handleIncomingMessage(WorldChatroomMessage.fromUserMessage(e));
      case ChatroomNarratorMessage e:
        await _handleIncomingMessage(
          WorldChatroomMessage.fromNarratorMessage(e),
        );
      case ChatroomTickAdvanceMessage e:
        await _handleTickAdvanceMessage(
          WorldChatroomMessage.fromTickAdvanceMessage(e),
        );
      case ChatroomAiStreamStart e:
        _startStream(e);
      case ChatroomAiStreamChunk e:
        _appendStreamChunk(e);
      case ChatroomAiStreamEnd e:
        _finishStream(e);
      case ChatroomErrorEvent e:
        _recordFailure(ChatroomFailureEvent.fromError(e));
      case ChatroomFailureEvent e:
        _recordFailure(e);
      case ChatroomBalanceLow e:
        _emitBalanceAlert(
          GemBalanceAlert(
            kind: GemBalanceAlertKind.low,
            balanceCent: e.balanceCent,
            message: e.message,
          ),
        );
      case ChatroomWaitingConversationRound e:
        _handleWaitingConversationRound(e);
      case ChatroomEndConversationRound e:
        _handleEndConversationRound(e);
      case ChatroomJoined():
      case ChatroomDisconnected():
        break;
      case ChatroomAck e:
        if (e.code == 3001) {
          _emitBalanceAlert(
            GemBalanceAlert(
              kind: GemBalanceAlertKind.insufficient,
              message: e.errorDetail.isNotEmpty ? e.errorDetail : e.codeMsg,
            ),
          );
        }
    }
  }

  void _handleWaitingConversationRound(ChatroomWaitingConversationRound event) {
    if (!event.ok) return;
    _bindWaitingConversationRound(
      locationId: event.locationId,
      conversationRoundId: event.conversationRoundId,
    );
  }

  void _handleEndConversationRound(ChatroomEndConversationRound event) {
    if (!event.ok) return;
    _completeConversationRound(
      locationId: event.locationId,
      conversationRoundId: event.conversationRoundId,
    );
  }

  void _handleNewUserJoin(ChatroomNewUserJoinEvent event) {
    _setState(
      _stateWithSocketWorldProgress(
        _state.copyWith(
          latestNewUserJoin: event,
          latestNewUserJoinRevision: _state.latestNewUserJoinRevision + 1,
        ),
        socketCurrentTime: event.currentTime,
      ),
    );
  }

  Future<void> _handleWorldNotification(ChatroomWorldNotification event) async {
    _logChatroomSocketEvent(
      'world notification event=${event.eventType} '
      'location=${event.locationId} world=$_worldId',
    );
    switch (event.eventType) {
      case 'world_change':
        await _consumeQueuedWorldRefresh(
          event,
          socketCurrentTime: event.currentTime,
        );
      case 'user_location_change':
        unawaited(
          _scheduleUserLocationsRefresh(socketCurrentTime: event.currentTime),
        );
      case 'user_enter_location':
        unawaited(
          _scheduleUserLocationsRefresh(socketCurrentTime: event.currentTime),
        );
      case 'map_updated':
        _setState(
          _stateWithSocketWorldProgress(
            _state.copyWith(mapUpdatedRevision: _state.mapUpdatedRevision + 1),
            socketCurrentTime: event.currentTime,
          ),
        );
        await _consumeQueuedWorldRefresh(
          event,
          socketCurrentTime: event.currentTime,
          detectMapContent: true,
        );
      case 'character_updated':
        await _consumeQueuedWorldRefresh(
          event,
          socketCurrentTime: event.currentTime,
          detectCharacterContent: true,
        );
      case 'characters_moved':
        final timelinePayload = event.timelinePayload;
        if (timelinePayload is ChatroomCharactersMovedPayload) {
          final sequence = ++_transientCharactersMovedSequence;
          final eventIdentity = event.eventId.trim().isNotEmpty
              ? event.eventId.trim()
              : '${event.ts?.microsecondsSinceEpoch ?? 0}:$sequence';
          await _handleCharactersMovedMessage(
            WorldChatroomMessage(
              globalMessageId: 0,
              messageId: _transientCharactersMovedMessageIdBase + sequence,
              locationMessageId: 0,
              conversationRoundId:
                  '$_transientCharactersMovedRoundPrefix$eventIdentity',
              roundOrder: 0,
              locationId: event.locationId,
              senderType: chatroomCharactersMovedSenderType,
              senderId: 'sub_tick',
              senderName: 'sub_tick',
              content: encodeChatroomTimelinePayload(timelinePayload),
              currentTime: event.currentTime,
              createdAt: event.ts,
              timelinePayload: timelinePayload,
            ),
            persist: false,
          );
        }
        final movedLocationId = event.locationId.trim();
        if (movedLocationId.isNotEmpty) {
          unawaited(
            _refreshEventLocationMessages(
              locationId: movedLocationId,
              sourceType: event.eventType,
            ),
          );
        } else {
          unawaited(_scheduleLatestMessagesRefresh());
        }
      case 'world_new_message':
        _logChatroomSocketEvent(
          'world_new_message fetch start location=${event.locationId} '
          'world=$_worldId',
        );
        final notificationLocationId = event.locationId.trim();
        if (notificationLocationId.isNotEmpty) {
          unawaited(
            _refreshEventLocationMessages(
              locationId: notificationLocationId,
              sourceType: event.eventType,
            ),
          );
        } else {
          unawaited(_scheduleLatestMessagesRefresh());
        }
        _logChatroomSocketEvent(
          'world_new_message fetch scheduled location=${event.locationId} '
          'world=$_worldId',
        );
      case 'tick_start':
        _setState(
          _stateWithSocketWorldProgress(
            _state.copyWith(inputBlocked: true),
            socketCurrentTime: event.currentTime,
          ),
        );
        break;
      case 'tick_done':
        _setState(
          _stateWithSocketWorldProgress(
            _state.copyWith(inputBlocked: false),
            socketCurrentTime: event.currentTime,
          ),
        );
        await _consumeQueuedWorldRefresh(
          event,
          socketCurrentTime: event.currentTime,
        );
        break;
      default:
        break;
    }
  }

  Future<void> _refreshEventLocationMessages({
    required String locationId,
    required String sourceType,
  }) async {
    if (_disposed || _worldId.trim().isEmpty) return;
    try {
      await refreshLatestMessages(
        locationId: locationId,
        limit: 20,
        emitLatestFetched: false,
      );
    } catch (error) {
      if (_disposed) return;
      _recordFailure(
        ChatroomFailureEvent(
          code: 'message_history_load_failed',
          message: 'Something went wrong',
          sourceType: sourceType,
          requestType: 'get_messages',
          cause: error,
        ),
      );
    }
  }

  Future<WorldDetail> _refreshWorld({String socketCurrentTime = ''}) async {
    final world = await _api.getWorld(_worldId);
    final updatedWorld =
        _worldWithSocketProgress(
          world,
          currentTime: socketCurrentTime,
          tickNo: 0,
        ) ??
        world;
    if (_disposed) return updatedWorld;
    final entities = _entitiesFromWorld(updatedWorld);
    _setState(
      _stateWithSocketWorldProgress(
        _state.copyWith(
          world: updatedWorld,
          locationTree: updatedWorld.locationTree,
          processedLocationTree: updatedWorld.processedLocationTree,
          entitiesById: entities,
          entitiesByLocation: _entitiesByLocation(entities),
          messagesByLocation: _leafLocationMessageQueues(
            updatedWorld,
            _state.messagesByLocation,
          ),
        ),
        socketCurrentTime: socketCurrentTime,
      ),
    );
    return updatedWorld;
  }

  Future<WorldDetail?> _scheduleWorldRefresh({
    String socketCurrentTime = '',
    bool detectMapContent = false,
    bool detectCharacterContent = false,
  }) {
    if (_disposed || _worldId.trim().isEmpty) {
      return Future<WorldDetail?>.value(_state.world);
    }
    _worldRefreshPending = true;
    _pendingMapContentDetection |= detectMapContent;
    _pendingCharacterContentDetection |= detectCharacterContent;
    final resolvedCurrentTime = socketCurrentTime.trim();
    if (resolvedCurrentTime.isNotEmpty) {
      _pendingWorldRefreshSocketCurrentTime = resolvedCurrentTime;
    }
    return _startWorldRefreshDrain();
  }

  void _prepareWorldRefreshForQueuedEvent(ChatroomEvent event) {
    if (event is! ChatroomWorldNotification) return;
    final eventType = event.eventType;
    if (eventType != 'world_change' &&
        eventType != 'tick_done' &&
        eventType != 'map_updated' &&
        eventType != 'character_updated') {
      return;
    }
    _queuedNotificationWorldRefreshes[event] = _scheduleWorldRefresh(
      socketCurrentTime: event.currentTime,
      detectMapContent: eventType == 'map_updated',
      detectCharacterContent: eventType == 'character_updated',
    );
  }

  Future<WorldDetail?> _consumeQueuedWorldRefresh(
    ChatroomWorldNotification event, {
    required String socketCurrentTime,
    bool detectMapContent = false,
    bool detectCharacterContent = false,
  }) {
    return _queuedNotificationWorldRefreshes.remove(event) ??
        _scheduleWorldRefresh(
          socketCurrentTime: socketCurrentTime,
          detectMapContent: detectMapContent,
          detectCharacterContent: detectCharacterContent,
        );
  }

  Future<WorldDetail?> _startWorldRefreshDrain() {
    final activeDrain = _worldRefreshDrain;
    if (activeDrain != null) return activeDrain;
    final drain = Future<WorldDetail?>.delayed(
      Duration.zero,
      _drainWorldRefreshes,
    );
    _worldRefreshDrain = drain;
    unawaited(
      drain.then((_) {
        if (!identical(_worldRefreshDrain, drain)) return;
        _worldRefreshDrain = null;
        if (_worldRefreshPending && !_disposed) {
          unawaited(_startWorldRefreshDrain());
        }
      }),
    );
    return drain;
  }

  Future<WorldDetail?> _drainWorldRefreshes() async {
    final baselineWorld = _state.world;
    var latestWorld = baselineWorld;
    var detectMapContent = false;
    var detectCharacterContent = false;

    while (_worldRefreshPending && !_disposed) {
      _worldRefreshPending = false;
      detectMapContent |= _pendingMapContentDetection;
      detectCharacterContent |= _pendingCharacterContentDetection;
      _pendingMapContentDetection = false;
      _pendingCharacterContentDetection = false;
      final socketCurrentTime = _pendingWorldRefreshSocketCurrentTime;
      _pendingWorldRefreshSocketCurrentTime = '';
      try {
        latestWorld = await _refreshWorld(socketCurrentTime: socketCurrentTime);
      } catch (error) {
        if (!_disposed) {
          _recordFailure(
            ChatroomFailureEvent(
              code: 'world_snapshot_refresh_failed',
              message: 'Something went wrong',
              sourceType: 'world_notification',
              requestType: 'world_detail',
              cause: error,
            ),
          );
        }
        return latestWorld;
      }
    }

    if (!_disposed && !_userDisconnected && latestWorld != null) {
      _publishContentUpdateNotices(
        previousWorld: baselineWorld,
        updatedWorld: latestWorld,
        includeLocations: detectMapContent,
        includeCharacters: detectCharacterContent,
      );
    }
    return latestWorld;
  }

  void _publishContentUpdateNotices({
    required WorldDetail? previousWorld,
    required WorldDetail updatedWorld,
    required bool includeLocations,
    required bool includeCharacters,
  }) {
    if (!includeLocations && !includeCharacters) return;
    final notices = <WorldContentUpdateNotice>[];
    if (includeLocations) {
      final previousIds = _worldContentIds(
        previousWorld?.locations ?? const <Map<String, dynamic>>[],
        const ['location_id', 'id'],
      );
      for (final location in updatedWorld.locations) {
        final id = _firstString(location, const ['location_id', 'id']);
        if (id.isEmpty ||
            _worldLocationLevel(updatedWorld, location, id) != 3 ||
            !asBool(location['is_new']) ||
            previousIds.contains(id)) {
          continue;
        }
        final notice = WorldContentUpdateNotice(
          kind: WorldContentUpdateKind.location,
          entityId: id,
          name: _firstString(location, const ['location_name', 'name']),
          targetLocationId: id,
          avatarUrl: _firstImageUrl(location, const ['image', 'image_url']),
          tickCount: updatedWorld.tickCount,
          contextLabel: _locationParentName(updatedWorld, location),
        );
        if (_publishedContentUpdateOccurrences.add(notice.occurrenceKey)) {
          notices.add(notice);
        }
      }
    }
    if (includeCharacters) {
      final previousIds = _worldContentIds(
        previousWorld?.characters ?? const <Map<String, dynamic>>[],
        const ['char_id', 'character_id', 'id'],
      );
      for (final character in updatedWorld.characters) {
        final id = _firstString(character, const [
          'char_id',
          'character_id',
          'id',
        ]);
        if (id.isEmpty ||
            !asBool(character['is_new']) ||
            previousIds.contains(id)) {
          continue;
        }
        final notice = WorldContentUpdateNotice(
          kind: WorldContentUpdateKind.character,
          entityId: id,
          name: _firstString(character, const [
            'name',
            'character_name',
            'role_name',
          ]),
          targetLocationId: _characterLocationId(updatedWorld, character, id),
          avatarUrl: _firstImageUrl(character, const ['avatar', 'avatar_url']),
          tickCount: updatedWorld.tickCount,
          contextLabel: _firstString(character, const ['identity']),
        );
        if (_publishedContentUpdateOccurrences.add(notice.occurrenceKey)) {
          notices.add(notice);
        }
      }
    }
    if (notices.isEmpty) return;
    _setState(
      _state.copyWith(
        latestContentUpdateNotices: List<WorldContentUpdateNotice>.unmodifiable(
          notices,
        ),
        contentUpdateNoticeRevision: _state.contentUpdateNoticeRevision + 1,
      ),
    );
  }

  int _worldLocationLevel(
    WorldDetail world,
    Map<String, dynamic> location,
    String locationId,
  ) {
    final declaredLevel = asInt(location['level']);
    if (declaredLevel > 0) return declaredLevel;
    return world.processedLocationTree.nodeById(locationId)?.depth ?? 0;
  }

  Set<String> _worldContentIds(
    List<Map<String, dynamic>> items,
    List<String> keys,
  ) {
    return <String>{
      for (final item in items)
        if (_firstString(item, keys).isNotEmpty) _firstString(item, keys),
    };
  }

  String _characterLocationId(
    WorldDetail world,
    Map<String, dynamic> character,
    String characterId,
  ) {
    final directLocationId = _firstString(character, const [
      'location_id',
      'current_location_id',
      'initial_location_id',
    ]);
    if (directLocationId.isNotEmpty) return directLocationId;
    for (final position in world.characterPositions) {
      final rawCharacter = position['character'];
      final positionedCharacter = rawCharacter is Map
          ? asJsonMap(rawCharacter)
          : position;
      final positionedId = _firstString(positionedCharacter, const [
        'char_id',
        'character_id',
        'id',
      ]);
      if (positionedId == characterId) return _locationIdFromMap(position);
    }
    return '';
  }

  String _locationParentName(WorldDetail world, Map<String, dynamic> location) {
    final parentId = _firstString(location, const ['location_pid']);
    if (parentId.isEmpty) return '';
    final parent = world.processedLocationTree.nodeById(parentId)?.value;
    if (parent == null) return '';
    return _firstString(parent, const ['location_name', 'name']);
  }

  Future<void> _scheduleUserLocationsRefresh({String socketCurrentTime = ''}) {
    if (_disposed || _worldId.trim().isEmpty) return Future<void>.value();
    _pendingUserLocationsSocketCurrentTime = socketCurrentTime;
    _userLocationsRefreshPending = true;
    _userLocationsRefreshGeneration += 1;
    return _startUserLocationsRefreshDrain();
  }

  Future<void> _startUserLocationsRefreshDrain() {
    final activeDrain = _userLocationsRefreshDrain;
    if (activeDrain != null) return activeDrain;
    final drain = _drainUserLocationsRefreshes();
    _userLocationsRefreshDrain = drain;
    unawaited(
      drain.whenComplete(() {
        if (!identical(_userLocationsRefreshDrain, drain)) return;
        _userLocationsRefreshDrain = null;
        if (_userLocationsRefreshPending && !_disposed) {
          unawaited(_startUserLocationsRefreshDrain());
        }
      }),
    );
    return drain;
  }

  Future<void> _drainUserLocationsRefreshes() async {
    while (_userLocationsRefreshPending && !_disposed) {
      _userLocationsRefreshPending = false;
      final refreshGeneration = _userLocationsRefreshGeneration;
      final socketCurrentTime = _pendingUserLocationsSocketCurrentTime;
      try {
        await _runUserLocationsRefresh(
          refreshGeneration: refreshGeneration,
          socketCurrentTime: socketCurrentTime,
        );
      } catch (error) {
        if (_disposed || refreshGeneration != _userLocationsRefreshGeneration) {
          continue;
        }
        _recordFailure(
          ChatroomFailureEvent(
            code: 'user_locations_refresh_failed',
            message: 'Something went wrong',
            sourceType: 'user_locations_refresh',
            requestType: 'get_user_locations',
            cause: error,
          ),
        );
      }
    }
  }

  Future<void> _runUserLocationsRefresh({
    required int refreshGeneration,
    String socketCurrentTime = '',
  }) async {
    late final ChatroomUserLocationsResponse response;
    try {
      response = await _api.chatroomHttp.getUserLocations(worldId: _worldId);
    } catch (_) {
      if (_disposed || refreshGeneration != _userLocationsRefreshGeneration) {
        return;
      }
      rethrow;
    }
    if (_disposed || refreshGeneration != _userLocationsRefreshGeneration) {
      return;
    }
    final responseWorldId = response.worldId.trim();
    if (responseWorldId.isNotEmpty && responseWorldId != _worldId) {
      throw ChatroomProtocolException(
        'User locations world_id mismatch: $responseWorldId',
      );
    }
    final entities = <String, WorldChatroomEntity>{
      for (final entry in _state.entitiesById.entries)
        entry.key: entry.value.type == WorldChatroomEntityType.player
            ? _entityWithoutLocation(entry.value)
            : entry.value,
    };
    for (final group in response.locations) {
      for (final user in group.users) {
        final id = user.userId.trim();
        if (id.isEmpty) continue;
        final existing = _state.entitiesById[id];
        final locationId = group.locationId.trim();
        entities[id] = WorldChatroomEntity(
          id: id,
          name: _firstNonEmpty([existing?.name, user.userName, id]),
          avatarUrl: _firstNonEmpty([existing?.avatarUrl, user.avatar]),
          type: WorldChatroomEntityType.player,
          locationId: locationId,
          isAi: false,
        );
      }
    }
    final locatedEntities = entities.values
        .where((entity) => entity.locationId.trim().isNotEmpty)
        .length;
    final realUsers = entities.values
        .where((entity) => entity.locationId.trim().isNotEmpty && !entity.isAi)
        .length;
    _logChatroomSocketEvent(
      'user locations refreshed groups=${response.locations.length} '
      'located=$locatedEntities realUsers=$realUsers world=$_worldId',
    );
    final world = _state.world;
    final worldWithEntityLocations = world == null
        ? null
        : _worldWithEntityLocations(world, entities);
    final updatedWorld = world == null
        ? null
        : _worldWithSocketProgress(
                worldWithEntityLocations,
                currentTime: socketCurrentTime,
                tickNo: 0,
              ) ??
              worldWithEntityLocations;
    _setState(
      _stateWithSocketWorldProgress(
        _state.copyWith(
          world: updatedWorld,
          entitiesById: entities,
          entitiesByLocation: _entitiesByLocation(entities),
        ),
        socketCurrentTime: socketCurrentTime,
      ),
    );
  }

  WorldDetail _worldWithEntityLocations(
    WorldDetail world,
    Map<String, WorldChatroomEntity> entities,
  ) {
    final characters = world.characters
        .map((character) {
          final copy = Map<String, dynamic>.from(character);
          final playerUid = _firstString(copy, const ['player_uid', 'user_id']);
          final charId = _firstString(copy, const [
            'char_id',
            'character_id',
            'id',
          ]);
          final entity = _firstEntity(entities, [
            if (playerUid.isNotEmpty) playerUid,
            if (charId.isNotEmpty) charId,
          ]);
          if (entity == null || entity.locationId.trim().isEmpty) {
            copy.remove('location_id');
            copy.remove('current_location_id');
            return copy;
          }
          copy['location_id'] = entity.locationId;
          return copy;
        })
        .toList(growable: false);
    return world.copyWith(
      characters: characters,
      locations: _locationsWithCharacters(world.locations, characters),
      characterPositions: characters
          .map(_characterPositionFromWorldCharacter)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false),
      userPositions: characters
          .map(_userPositionFromWorldCharacter)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false),
    );
  }

  WorldChatroomEntity? _firstEntity(
    Map<String, WorldChatroomEntity> entities,
    Iterable<String> ids,
  ) {
    for (final id in ids) {
      final entity = entities[id.trim()];
      if (entity != null) return entity;
    }
    return null;
  }

  WorldChatroomEntity _entityWithoutLocation(WorldChatroomEntity entity) {
    if (entity.locationId.trim().isEmpty) return entity;
    return WorldChatroomEntity(
      id: entity.id,
      name: entity.name,
      avatarUrl: entity.avatarUrl,
      type: entity.type,
      locationId: '',
      isAi: entity.isAi,
    );
  }

  List<Map<String, dynamic>> _locationsWithCharacters(
    List<Map<String, dynamic>> locations,
    List<Map<String, dynamic>> characters,
  ) {
    return locations
        .map((location) {
          final copy = Map<String, dynamic>.from(location);
          final locationId = _locationIdFromMap(copy);
          copy['characters'] = characters
              .where((character) => _locationIdFromMap(character) == locationId)
              .map((character) => Map<String, dynamic>.from(character))
              .toList(growable: false);
          return copy;
        })
        .toList(growable: false);
  }

  Map<String, dynamic>? _characterPositionFromWorldCharacter(
    Map<String, dynamic> character,
  ) {
    final locationId = _locationIdFromMap(character);
    if (locationId.isEmpty) return null;
    return {
      'location_id': locationId,
      'character': {
        'id': _firstString(character, const ['char_id', 'character_id', 'id']),
        'name': _firstString(character, const ['name']),
        'type': _firstString(character, const ['type']),
        'player_uid': _firstString(character, const ['player_uid', 'user_id']),
        'player_username': _firstString(character, const [
          'player_username',
          'user_name',
          'username',
        ]),
        'player_deleted': character['player_deleted'],
        'identity': _firstString(character, const ['identity']),
        'tagline': _firstString(character, const ['brief', 'tagline']),
        'description': _firstString(character, const ['description']),
        'avatar': _firstImageUrl(character, const ['avatar', 'avatar_url']),
        'is_new': asBool(character['is_new']),
      },
    };
  }

  Map<String, dynamic>? _userPositionFromWorldCharacter(
    Map<String, dynamic> character,
  ) {
    final playerUid = _firstString(character, const ['player_uid', 'user_id']);
    final locationId = _locationIdFromMap(character);
    if (playerUid.isEmpty || locationId.isEmpty) return null;
    return {'uid': playerUid, 'location_id': locationId};
  }

  Future<void> _hydrateLocalMessagesForLocation(
    String locationId, {
    String? worldId,
    String? ownerUid,
    String? stateLocationId,
  }) async {
    final resolvedLocationId = locationId.trim();
    if (resolvedLocationId.isEmpty) return;
    final resolvedStateLocationId = stateLocationId?.trim().isNotEmpty == true
        ? stateLocationId!.trim()
        : resolvedLocationId;
    final resolvedOwnerUid = ownerUid?.trim().isNotEmpty == true
        ? ownerUid!.trim()
        : _storageOwnerUid;
    final resolvedWorldId = worldId?.trim().isNotEmpty == true
        ? worldId!.trim()
        : _worldId;
    if (resolvedOwnerUid.isEmpty || resolvedWorldId.isEmpty) return;
    final hydrationKey = _messageHydrationKey(
      ownerUid: resolvedOwnerUid,
      worldId: resolvedWorldId,
      locationId: resolvedLocationId,
      stateLocationId: resolvedStateLocationId,
    );
    if (_localHydratedMessageKeys.contains(hydrationKey)) {
      _logChatroomHydrateMetric(
        'alias skip hydrated storage=$resolvedLocationId '
        'state=$resolvedStateLocationId',
      );
      return;
    }
    final existingHydration = _localHydratingMessageFutures[hydrationKey];
    if (existingHydration != null) {
      final stopwatch = _chatroomHydrateMetricsEnabled
          ? (Stopwatch()..start())
          : null;
      _logChatroomHydrateMetric(
        'alias wait inFlight storage=$resolvedLocationId '
        'state=$resolvedStateLocationId',
      );
      await existingHydration;
      _logChatroomHydrateMetric(
        'alias waited inFlight storage=$resolvedLocationId '
        'state=$resolvedStateLocationId '
        'elapsed=${stopwatch?.elapsedMilliseconds}ms',
      );
      return;
    }
    final hydration = _loadLocalMessagesForLocation(
      ownerUid: resolvedOwnerUid,
      worldId: resolvedWorldId,
      storageLocationId: resolvedLocationId,
      stateLocationId: resolvedStateLocationId,
      hydrationKey: hydrationKey,
      cacheGeneration: _localMessageCacheGeneration,
    );
    _localHydratingMessageFutures[hydrationKey] = hydration;
    try {
      await hydration;
    } finally {
      if (identical(_localHydratingMessageFutures[hydrationKey], hydration)) {
        _localHydratingMessageFutures.remove(hydrationKey);
      }
    }
  }

  Future<void> _loadLocalMessagesForLocation({
    required String ownerUid,
    required String worldId,
    required String storageLocationId,
    required String stateLocationId,
    required String hydrationKey,
    required int cacheGeneration,
  }) async {
    final stopwatch = _chatroomHydrateMetricsEnabled
        ? (Stopwatch()..start())
        : null;
    final historyTicket = _historyTicket(stateLocationId);
    if (_historyRefreshes.containsKey(stateLocationId)) return;
    final beforeStateCount =
        _state.messagesByLocation[stateLocationId]?.length ?? 0;
    _logChatroomHydrateMetric(
      'db load start storage=$storageLocationId state=$stateLocationId '
      'world=$worldId beforeStateCount=$beforeStateCount',
    );
    try {
      final localMessages = await _messageStorage.loadLatestMessages(
        ownerUid: ownerUid,
        worldId: worldId,
        locationId: storageLocationId,
        limit: 20,
      );
      if (cacheGeneration != _localMessageCacheGeneration ||
          !_historyIsCurrent(stateLocationId, historyTicket)) {
        _logChatroomHydrateMetric(
          'db load skipped stale generation storage=$storageLocationId '
          'state=$stateLocationId',
        );
        return;
      }
      final hydratedMessages = localMessages
          .map((json) {
            final message = WorldChatroomMessage.fromStorageJson(json);
            return message.locationId == stateLocationId
                ? message
                : message.copyWith(locationId: stateLocationId);
          })
          .toList(growable: false);
      _upsertMessages(hydratedMessages, persist: false);
      _localHydratedMessageKeys.add(hydrationKey);
      final afterStateCount =
          _state.messagesByLocation[stateLocationId]?.length ?? 0;
      final firstMessageId = localMessages.isEmpty
          ? 0
          : WorldChatroomMessage.fromStorageJson(localMessages.first).messageId;
      _logChatroomHydrateMetric(
        'db load done storage=$storageLocationId state=$stateLocationId '
        'loaded=${localMessages.length} firstMsg=$firstMessageId '
        'beforeStateCount=$beforeStateCount afterStateCount=$afterStateCount '
        'elapsed=${stopwatch?.elapsedMilliseconds}ms',
      );
      _recordServiceQueueDebug(
        action: 'dbHydrateDone',
        locationId: stateLocationId,
        details: {
          'storageLocationId': storageLocationId,
          'loaded': localMessages.length,
          'firstMsg': firstMessageId,
          'beforeStateCount': beforeStateCount,
          'afterStateCount': afterStateCount,
          'elapsedMs': stopwatch?.elapsedMilliseconds,
        },
      );
    } catch (e) {
      _logChatroomHydrateMetric(
        'db load failed storage=$storageLocationId state=$stateLocationId '
        'elapsed=${stopwatch?.elapsedMilliseconds}ms error=$e',
      );
      LocationChatDebugSlice.recordEvent(
        source: 'service',
        action: 'dbHydrateFailed',
        worldId: worldId,
        locationId: stateLocationId,
        details: {
          'storageLocationId': storageLocationId,
          'elapsedMs': stopwatch?.elapsedMilliseconds,
          'error': '$e',
        },
      );
      _recordFailure(
        ChatroomFailureEvent(
          code: 'message_cache_load_failed',
          message: 'Something went wrong',
          sourceType: 'message_cache',
          cause: e,
        ),
      );
    }
  }

  String _messageHydrationKey({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required String stateLocationId,
  }) => '$ownerUid\u001F$worldId\u001F$locationId\u001F$stateLocationId';

  List<String> _orderedNonEmpty(Iterable<String?> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty || !seen.add(trimmed)) continue;
      result.add(trimmed);
    }
    return result;
  }
}

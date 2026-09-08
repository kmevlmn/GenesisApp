part of 'world_chatroom_service.dart';

extension _WorldChatroomWorldProjection on WorldChatroomService {
  Map<String, WorldChatroomEntity> _entitiesFromWorld(WorldDetail world) {
    final entities = <String, WorldChatroomEntity>{};
    for (final character in world.characters) {
      final entity = _entityFromCharacter(character, '');
      if (entity != null) entities[entity.id] = entity;
    }
    for (final position in world.characterPositions) {
      final locationId = _locationIdFromMap(position);
      final raw = position['character'];
      final character = raw is Map ? asJsonMap(raw) : position;
      final entity = _entityFromCharacter(character, locationId);
      if (entity != null) entities[entity.id] = entity;
    }
    for (final position in world.userPositions) {
      final entity = _entityFromUserPosition(position);
      if (entity == null) continue;
      final existing = entities[entity.id];
      entities[entity.id] = WorldChatroomEntity(
        id: entity.id,
        name: _firstNonEmpty([existing?.name, entity.name]),
        avatarUrl: _firstNonEmpty([entity.avatarUrl, existing?.avatarUrl]),
        type: WorldChatroomEntityType.player,
        locationId: entity.locationId,
        isAi: false,
      );
    }
    return entities;
  }

  WorldChatroomEntity? _entityFromCharacter(
    Map<String, dynamic> character,
    String locationId,
  ) {
    final type = _firstString(character, const ['type', 'sender_type']);
    final normalizedType = type.trim().toLowerCase();
    final playerUid = _firstString(character, const [
      'player_uid',
      'user_id',
      'uid',
    ]);
    final characterId = _firstString(character, const [
      'character_id',
      'char_id',
      'id',
    ]);
    final isPlayer = normalizedType == 'player' || playerUid.isNotEmpty;
    final id = isPlayer
        ? _firstNonEmpty([playerUid, characterId])
        : characterId;
    if (id.isEmpty) return null;
    final name = isPlayer
        ? _firstNonEmpty([
            _firstString(character, const [
              'name',
              'role_nickname',
              'role_name',
              'character_name',
            ]),
            _firstString(character, const [
              'player_username',
              'user_name',
              'username',
              'sender_name',
            ]),
            id,
          ])
        : _firstString(character, const [
            'name',
            'role_nickname',
            'role_name',
            'character_name',
            'sender_name',
          ]);
    return WorldChatroomEntity(
      id: id,
      name: name,
      avatarUrl: _firstImageUrl(character, const ['avatar', 'avatar_url']),
      type: isPlayer
          ? WorldChatroomEntityType.player
          : WorldChatroomEntityType.character,
      locationId: locationId,
      isAi: !isPlayer,
    );
  }

  WorldChatroomEntity? _entityFromUserPosition(Map<String, dynamic> position) {
    final rawUser = position['user'];
    final user = rawUser is Map ? asJsonMap(rawUser) : position;
    final id = _firstString(user, const ['user_id', 'uid', 'id']);
    if (id.isEmpty) return null;
    return WorldChatroomEntity(
      id: id,
      name: _firstString(user, const [
        'role_nickname',
        'role_name',
        'character_name',
        'name',
        'user_name',
        'sender_name',
      ]),
      avatarUrl: _firstImageUrl(user, const ['avatar', 'avatar_url']),
      type: WorldChatroomEntityType.player,
      locationId: _locationIdFromMap(position),
    );
  }

  Map<String, List<WorldChatroomEntity>> _entitiesByLocation(
    Map<String, WorldChatroomEntity> entities,
  ) {
    final byLocation = <String, List<WorldChatroomEntity>>{};
    for (final entity in entities.values) {
      final locationId = entity.locationId.trim();
      if (locationId.isEmpty) continue;
      byLocation
          .putIfAbsent(locationId, () => <WorldChatroomEntity>[])
          .add(entity);
    }
    return {
      for (final entry in byLocation.entries)
        entry.key: List<WorldChatroomEntity>.unmodifiable(entry.value),
    };
  }

  String _locationIdFromMap(Map<String, dynamic> map) {
    return _firstString(map, const ['location_id', 'current_location_id']);
  }

  String _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = asString(map[key]).trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _firstImageUrl(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (!map.containsKey(key)) continue;
      final value = map[key];
      final resolved = asResolvedImageUrl(value, resolveAssetUrl);
      if (resolved.isNotEmpty) return resolved;
    }
    return '';
  }

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  String _streamKey(
    String locationId,
    String conversationRoundId,
    String senderId,
  ) {
    final location = locationId.trim();
    final round = conversationRoundId.trim();
    final sender = senderId.trim();
    if (_worldId.trim().isEmpty ||
        location.isEmpty ||
        round.isEmpty ||
        sender.isEmpty) {
      return '';
    }
    return '$_worldId|$location|$round|$sender';
  }

  void _recordFailure(
    ChatroomFailureEvent failure, {
    String socketCurrentTime = '',
    int socketTickNo = 0,
  }) {
    if (_disposed) return;
    if (!_failures.isClosed) _failures.add(failure);
    _setState(
      _stateWithSocketWorldProgress(
        _state.copyWith(lastFailure: failure),
        socketCurrentTime: socketCurrentTime,
        socketTickNo: socketTickNo,
      ),
    );
  }

  void _emitBalanceAlert(GemBalanceAlert alert) {
    if (!_balanceAlerts.isClosed) _balanceAlerts.add(alert);
  }

  Future<void> _persistMessage(WorldChatroomMessage message) async {
    final ownerUid = _storageOwnerUid;
    final locationId = message.locationId.trim();
    if (ownerUid.isEmpty ||
        _worldId.isEmpty ||
        locationId.isEmpty ||
        message.streaming ||
        message.messageId <= 0) {
      return;
    }
    final ticket = _historyTicket(locationId);
    await _withLocationWrite(locationId, () async {
      if (!_historyIsCurrent(locationId, ticket) ||
          _deletedMessageIds[locationId]?.contains(message.globalMessageId) ==
              true) {
        return;
      }
      await _messageStorage.upsertMessage(
        ownerUid: ownerUid,
        worldId: ticket.world,
        locationId: locationId,
        message: _storageJsonFromWorldMessage(message),
        maxMessagesPerLocation: _maxMessagesPerLocation,
      );
    });
    if (LocationChatDebugSlice.enabled) {
      LocationChatDebugSlice.recordEvent(
        source: 'service',
        action: 'persistMessage',
        worldId: _worldId,
        locationId: locationId,
        details: {
          'ownerUid': ownerUid,
          'message': LocationChatDebugSlice.debugWorldMessage(message),
        },
      );
    }
  }

  void _recordServiceQueueDebug({
    required String action,
    required String locationId,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    LocationChatDebugSlice.recordServiceQueue(
      action: action,
      worldId: _worldId,
      locationId: locationId,
      state: _state,
      details: details,
    );
  }

  String get _storageOwnerUid {
    final identity = _identity;
    if (identity == null) return '';
    final userId = identity.userId.trim();
    if (userId.isNotEmpty) return userId;
    return identity.senderId.trim();
  }

  Map<String, dynamic> _storageJsonFromWorldMessage(
    WorldChatroomMessage message,
  ) {
    return {
      if (message.hasExplicitBusinessType) 'type': message.businessType,
      'stream_type': message.streamType,
      'world_id': _worldId,
      'global_message_id': message.globalMessageId,
      'message_id': message.messageId,
      'location_message_id': message.locationMessageId,
      'global_msg_id': message.globalMessageId,
      'msg_id': message.messageId,
      'location_msg_id': message.locationMessageId,
      'location_id': message.locationId,
      'conversation_round_id': message.conversationRoundNumber,
      'round_order': message.roundOrder,
      'tick_no': message.tickNo,
      'sub_tick_no': message.subTickNo,
      'sender_type': message.senderType,
      'sender_id': message.senderId,
      'sender_name': message.senderName,
      'user_id': message.userId,
      'client_msg_id': message.clientMsgId,
      'content': message.content,
      'message_type': message.messageType,
      'current_time': message.currentTime,
      'min_app_version': message.minAppVersion,
      'payload': message.rawPayload.isNotEmpty
          ? message.rawPayload
          : message.v2TickPayload?.toJson(),
      // WorldChatroomMessage only contains successfully decoded messages, so
      // the V2 business status is necessarily successful by this boundary.
      'err_no': 0,
      'err_msg': '',
      'is_llm_stream': message.isLlmStreamMessage,
      'created_at': message.createdAt?.toIso8601String(),
      'ts': message.createdAt?.millisecondsSinceEpoch,
    };
  }

  Map<String, dynamic> _storageJsonFromHttpMessage(
    ChatroomHttpMessage message, {
    String fallbackLocationId = '',
  }) {
    return {
      if (message.businessType.trim().isNotEmpty) 'type': message.businessType,
      'stream_type': message.streamType,
      'world_id': message.worldId,
      'session_id': message.sessionId,
      'global_message_id': message.globalMessageId,
      'message_id': message.messageId,
      'location_message_id': message.locationMessageId,
      'global_msg_id': message.globalMessageId,
      'msg_id': message.messageId,
      'location_msg_id': message.locationMessageId,
      'location_id': message.locationId.trim().isEmpty
          ? fallbackLocationId
          : message.locationId,
      'conversation_round_id': message.conversationRoundId,
      'round_order': 0,
      'tick_no': message.tickNo,
      'sub_tick_no': message.subTickNo,
      'sender_type': message.senderType,
      'sender_id': message.senderId,
      'sender_name': message.senderName,
      'user_id': message.userId,
      'client_msg_id': message.clientMsgId,
      'content': message.content,
      'message_type': message.messageType,
      'current_time': message.currentTime,
      'min_app_version': message.minAppVersion,
      'payload': message.payload,
      'err_no': message.errNo,
      'err_msg': message.errMsg,
      'created_at': asString(
        message.rawJson['created_at'],
        fallback: message.createdAt?.toIso8601String() ?? '',
      ),
      'ts': message.ts ?? message.createdAt?.millisecondsSinceEpoch,
    };
  }

  WorldChatroomMessage _worldMessageFromHttpMessage(
    ChatroomHttpMessage message, {
    required String fallbackLocationId,
  }) {
    final worldMessage = WorldChatroomMessage.fromHttpMessage(message);
    if (worldMessage.locationId.trim().isNotEmpty) return worldMessage;
    return worldMessage.copyWith(locationId: fallbackLocationId);
  }

  void _setState(WorldChatroomState state) {
    if (_disposed) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw const ChatroomProtocolException('WorldChatroomService is disposed');
    }
  }
}

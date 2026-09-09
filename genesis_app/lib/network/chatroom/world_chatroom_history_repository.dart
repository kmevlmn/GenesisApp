part of 'world_chatroom_service.dart';

extension _WorldChatroomHistoryRepository on WorldChatroomService {
  Future<void> _loadReplyCardsForHistory(
    String locationId,
    Iterable<WorldChatroomMessage> messages,
    _HistoryTicket ticket,
  ) async {
    bool current() => _historyIsCurrent(locationId, ticket);
    if (!current()) return;
    final rounds = messages
        .map((message) => message.conversationRoundNumber)
        .where((round) => round > 0)
        .toSet();
    if (rounds.isEmpty) return;
    try {
      await replyActions?.loadHistoryCards(
        locationId,
        roundIds: rounds,
        isCurrent: current,
      );
    } catch (error) {
      if (!current()) return;
      _recordFailure(
        ChatroomFailureEvent(
          code: 'card_history_failed',
          message: 'Failed to refresh reply cards',
          sourceType: 'history',
          cause: error,
        ),
      );
    }
  }

  Future<void> _initializeLeafLocationQueue({
    required String locationId,
    required int latestLimit,
  }) async {
    final resolvedLocationId = locationId.trim();
    if (resolvedLocationId.isEmpty || _worldId.isEmpty) return;
    try {
      _requireHistoryAvailable(resolvedLocationId);
      final ticket = _historyTicket(resolvedLocationId);
      _recordServiceQueueDebug(
        action: 'leafQueueInitLocationStart',
        locationId: resolvedLocationId,
        details: {'limit': latestLimit},
      );
      final response = await _api.chatroomHttp.getMessages(
        worldId: _worldId,
        locationId: resolvedLocationId,
        since: 0,
        limit: latestLimit,
      );
      await _mergeFetchedMessages(
        resolvedLocationId,
        response.messages,
        ticket: ticket,
      );
      if (!_historyIsCurrent(resolvedLocationId, ticket)) return;
      await _repairLocationMessageGaps(resolvedLocationId);
      _recordServiceQueueDebug(
        action: 'leafQueueInitLocationDone',
        locationId: resolvedLocationId,
        details: {
          'loaded': response.messages.length,
          'hasMore': response.hasMore,
        },
      );
    } catch (error) {
      _recordServiceQueueDebug(
        action: 'leafQueueInitLocationFailed',
        locationId: resolvedLocationId,
        details: {'error': '$error'},
      );
    }
  }

  Future<void> _repairLocationMessageGaps(String locationId) async {
    final ticket = _historyTicket(locationId);
    final unresolvedGapKeys = <String>{};
    for (var pass = 0; pass < _maxMessagesPerLocation; pass += 1) {
      if (!_historyIsCurrent(locationId, ticket) ||
          _historyRefreshes.containsKey(locationId)) {
        return;
      }
      final gap = _firstLocationMessageGap(
        _state.messagesByLocation[locationId] ?? const <WorldChatroomMessage>[],
        ignoredKeys: unresolvedGapKeys,
      );
      if (gap == null) return;
      final gapKey = _locationMessageGapKey('', gap);
      if (gap.missingCount > _maxRecoverableLocationMessageGap) {
        await _discardLocationMessagesAtOrBefore(
          locationId: locationId,
          maxLocationMessageId: gap.lower,
          reason: 'largeGap',
        );
        continue;
      }
      final filled = await _fillLocationMessageGap(
        locationId: locationId,
        gap: gap,
      );
      if (!filled) {
        unresolvedGapKeys.add(gapKey);
        return;
      }
    }
  }

  Future<bool> _fillLocationMessageGap({
    required String locationId,
    required _LocationMessageGap gap,
  }) async {
    if (_historyRefreshes.containsKey(locationId)) return false;
    final ticket = _historyTicket(locationId);
    final limit = math.min(100, gap.missingCount + 1);
    for (
      var attempt = 1;
      attempt <= _maxLocationMessageGapFillAttempts;
      attempt += 1
    ) {
      try {
        if (!_historyIsCurrent(locationId, ticket)) return false;
        _recordServiceQueueDebug(
          action: 'gapFillStart',
          locationId: locationId,
          details: {
            'lower': gap.lower,
            'upper': gap.upper,
            'missingCount': gap.missingCount,
            'attempt': attempt,
            'limit': limit,
          },
        );
        final response = await _api.chatroomHttp.getMessages(
          worldId: _worldId,
          locationId: locationId,
          since: gap.upper,
          limit: limit,
        );
        await _mergeFetchedMessages(
          locationId,
          response.messages,
          ticket: ticket,
        );
        if (!_historyIsCurrent(locationId, ticket)) return false;
        if (_isLocationMessageGapFilled(
          _state.messagesByLocation[locationId] ??
              const <WorldChatroomMessage>[],
          gap,
        )) {
          _recordServiceQueueDebug(
            action: 'gapFillDone',
            locationId: locationId,
            details: {
              'lower': gap.lower,
              'upper': gap.upper,
              'attempt': attempt,
              'loaded': response.messages.length,
            },
          );
          return true;
        }
      } catch (error) {
        _recordServiceQueueDebug(
          action: 'gapFillFailed',
          locationId: locationId,
          details: {
            'lower': gap.lower,
            'upper': gap.upper,
            'attempt': attempt,
            'error': '$error',
          },
        );
      }
    }
    _recordServiceQueueDebug(
      action: 'gapFillReleased',
      locationId: locationId,
      details: {
        'lower': gap.lower,
        'upper': gap.upper,
        'attempts': _maxLocationMessageGapFillAttempts,
      },
    );
    return false;
  }

  Future<void> _discardLocationMessagesAtOrBefore({
    required String locationId,
    required int maxLocationMessageId,
    required String reason,
  }) async {
    if (maxLocationMessageId <= 0) return;
    final maxWorldMessageId = _worldMessageBoundaryForLocationCursor(
      _state.messagesByLocation[locationId] ?? const <WorldChatroomMessage>[],
      maxLocationMessageId,
    );
    final ticket = _historyTicket(locationId);
    if (_historyRefreshes.containsKey(locationId)) return;
    final ownerUid = _storageOwnerUid;
    if (ownerUid.isNotEmpty && _worldId.isNotEmpty) {
      await _withLocationWrite(locationId, () async {
        if (!_historyIsCurrent(locationId, ticket)) return;
        await _messageStorage.deleteMessagesAtOrBefore(
          ownerUid: ownerUid,
          worldId: _worldId,
          locationId: locationId,
          maxLocationMessageId: maxLocationMessageId,
          maxWorldMessageId: maxWorldMessageId,
        );
      });
    }
    if (!_historyIsCurrent(locationId, ticket)) return;
    final byLocation = Map<String, List<WorldChatroomMessage>>.from(
      _state.messagesByLocation,
    );
    byLocation[locationId] = List<WorldChatroomMessage>.unmodifiable(
      (byLocation[locationId] ?? const <WorldChatroomMessage>[]).where(
        (message) => !_messageIsAtOrBeforeLocationCursor(
          message,
          maxLocationMessageId,
          maxWorldMessageId: maxWorldMessageId,
        ),
      ),
    );
    final streamMessagesByKey = <String, WorldChatroomMessage>{
      ..._state.streamMessagesByKey,
    };
    streamMessagesByKey.removeWhere((_, message) {
      return message.locationId == locationId &&
          _messageIsAtOrBeforeLocationCursor(
            message,
            maxLocationMessageId,
            maxWorldMessageId: maxWorldMessageId,
          );
    });
    _setState(
      _state.copyWith(
        worldMessages: _state.worldMessages
            .where(
              (message) =>
                  message.locationId != locationId ||
                  !_messageIsAtOrBeforeLocationCursor(
                    message,
                    maxLocationMessageId,
                    maxWorldMessageId: maxWorldMessageId,
                  ),
            )
            .toList(growable: false),
        messagesByLocation: byLocation,
        streamMessagesByKey: streamMessagesByKey,
      ),
    );
    _recordServiceQueueDebug(
      action: 'discardLocationMessages',
      locationId: locationId,
      details: {
        'maxLocationMessageId': maxLocationMessageId,
        'maxWorldMessageId': maxWorldMessageId,
        'reason': reason,
      },
    );
  }

  int _worldMessageBoundaryForLocationCursor(
    List<WorldChatroomMessage> messages,
    int maxLocationMessageId,
  ) {
    var boundary = 0;
    for (final message in messages) {
      if (message.locationMessageId <= 0 ||
          message.locationMessageId > maxLocationMessageId ||
          message.messageId <= 0) {
        continue;
      }
      if (message.messageId > boundary) boundary = message.messageId;
    }
    return boundary;
  }

  _LocationMessageGap? _firstLocationMessageGap(
    List<WorldChatroomMessage> messages, {
    Set<String> ignoredKeys = const <String>{},
  }) {
    final ids =
        messages
            .where((message) => message.locationMessageId > 0)
            .map((message) => message.locationMessageId)
            .toSet()
            .toList(growable: false)
          ..sort();
    for (var index = 1; index < ids.length; index += 1) {
      final lower = ids[index - 1];
      final upper = ids[index];
      if (upper <= lower + 1) continue;
      final gap = _LocationMessageGap(lower: lower, upper: upper);
      if (ignoredKeys.contains(_locationMessageGapKey('', gap))) continue;
      return gap;
    }
    return null;
  }

  bool _isTickAdvanceWorldMessage(WorldChatroomMessage message) {
    return message.senderType.trim().toLowerCase() == 'tick' &&
        message.locationMessageId <= 0 &&
        !message.isV2LocationTick;
  }

  bool _isLocationMessageGapFilled(
    List<WorldChatroomMessage> messages,
    _LocationMessageGap gap,
  ) {
    final ids = messages
        .where((message) => message.locationMessageId > 0)
        .map((message) => message.locationMessageId)
        .toSet();
    for (var id = gap.lower + 1; id < gap.upper; id += 1) {
      if (!ids.contains(id)) return false;
    }
    return true;
  }

  String _locationMessageGapKey(String locationId, _LocationMessageGap gap) {
    return '${locationId.trim()}\u001F${gap.lower}\u001F${gap.upper}';
  }

  Future<void> _runLimited<T>(
    List<T> items,
    int concurrency,
    Future<void> Function(T item) run,
  ) async {
    var nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < items.length) {
        final index = nextIndex;
        nextIndex += 1;
        await run(items[index]);
      }
    }

    final workerCount = math.min(concurrency, items.length);
    await Future.wait<void>([
      for (var i = 0; i < workerCount; i += 1) worker(),
    ]);
  }
}

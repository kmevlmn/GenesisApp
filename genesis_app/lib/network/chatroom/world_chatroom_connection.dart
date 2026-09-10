part of 'world_chatroom_service.dart';

extension _WorldChatroomConnection on WorldChatroomService {
  Future<void> _connectOnce() async {
    if (_userDisconnected || _disposed) return;
    if (_session != null && _state.connected) return;
    final current = _connectCompleter;
    if (current != null) {
      await current.future;
      return;
    }
    final identity = _identity;
    if (identity == null) {
      throw const ChatroomProtocolException('chatroom identity is required');
    }
    final completer = Completer<void>();
    _connectCompleter = completer;
    unawaited(completer.future.catchError((Object _) {}));
    _setState(
      _state.copyWith(connected: false, reconnecting: _state.world != null),
    );
    try {
      await _detachSession(disconnect: true);
      final session = await _client.connect(
        worldId: _worldId,
        userId: identity.userId,
        senderId: identity.senderId,
        senderName: identity.senderName,
        autoHeartbeat: false,
      );
      if (_userDisconnected || _disposed) {
        await session.disconnect();
        return;
      }
      _session = session;
      _attachSession(session);
      _setState(_state.copyWith(connected: true));
      if (_refreshInitialSnapshotOnConnect) {
        await _refreshInitialSnapshot();
      }
      final desiredLocationId = _desiredLocationId;
      if (desiredLocationId.isNotEmpty && _joinCompleter == null) {
        await _joinSession(session, desiredLocationId);
      }
      _startHeartbeat();
      _setState(_state.copyWith(connected: true, reconnecting: false));
      completer.complete();
    } catch (e) {
      final failure = e is ChatroomFailureEvent
          ? e
          : ChatroomFailureEvent(
              code: 'connect_failed',
              message: 'Failed to connect to chatroom',
              sourceType: 'connect',
              requestType: 'connect',
              cause: e,
            );
      _recordFailure(failure);
      _scheduleReconnect();
      completer.completeError(failure);
      rethrow;
    } finally {
      if (identical(_connectCompleter, completer)) {
        _connectCompleter = null;
      }
    }
  }

  Future<void> _refreshInitialSnapshot() async {
    try {
      await _refreshWorld();
      await _scheduleUserLocationsRefresh();
    } catch (e) {
      _recordFailure(
        ChatroomFailureEvent(
          code: 'snapshot_failed',
          message: 'Something went wrong',
          sourceType: 'snapshot',
          cause: e,
        ),
      );
    }
  }

  Future<void> _joinDesiredLocation(Completer<ChatroomJoined> completer) async {
    try {
      await _connectOnce();
      final session = _session;
      final locationId = _desiredLocationId;
      if (session == null || locationId.isEmpty) {
        throw const ChatroomProtocolException('chatroom is not connected');
      }
      _sendPendingUserEnterLocationCommand(session, locationId);
      final joined = await _joinSession(session, locationId);
      if (!completer.isCompleted) completer.complete(joined);
    } catch (e) {
      final failure = e is ChatroomFailureEvent
          ? e
          : ChatroomFailureEvent(
              code: 'join_failed',
              message: 'Something went wrong',
              sourceType: 'join',
              requestType: 'join',
              cause: e,
            );
      _recordFailure(failure);
      if (!completer.isCompleted) completer.completeError(failure);
    } finally {
      if (identical(_joinCompleter, completer)) {
        _joinCompleter = null;
      }
    }
  }

  void _sendPendingUserEnterLocationCommand(
    ChatroomSession session,
    String locationId,
  ) {
    if (_pendingUserEnterLocationCommandId != locationId) return;
    _pendingUserEnterLocationCommandId = '';
    unawaited(
      Future<void>.sync(
        () => session.sendUserEnterLocation(locationId: locationId),
      ).catchError((Object error) {
        _logChatroomSocketEvent(
          'user_enter_location send ignored world=$_worldId '
          'location=$locationId error=$error',
        );
        _recordServiceQueueDebug(
          action: 'userEnterLocationSendIgnored',
          locationId: locationId,
          details: {'error': '$error'},
        );
      }),
    );
  }

  Future<ChatroomJoined> _joinSession(
    ChatroomSession session,
    String locationId,
  ) async {
    _setState(_state.copyWith(joining: true));
    try {
      final joined = await session.join(locationId: locationId);
      if (_desiredLocationId == locationId) {
        final joinedLocationId = joined.locationId.isEmpty
            ? locationId
            : joined.locationId;
        _setState(
          _state.copyWith(
            connected: true,
            joining: false,
            joinedLocationId: joinedLocationId,
          ),
        );
        _backgroundHistoryRefresh(
          refreshLocationHistory(locationId: joinedLocationId).then((_) async {
            if (_disposed ||
                _session != session ||
                _desiredLocationId != joinedLocationId ||
                _state.joinedLocationId != joinedLocationId) {
              return;
            }
            await replyActions?.restoreLocationCards(
              joinedLocationId,
              reloadCards: false,
            );
          }),
        );
      }
      return joined;
    } catch (_) {
      _setState(_state.copyWith(joining: false, joinedLocationId: ''));
      rethrow;
    }
  }

  void _attachSession(ChatroomSession session) {
    _eventSubscription = session.events.listen(
      _enqueueEvent,
      onDone: () => _handleConnectionLost(),
    );
    _failureSubscription = session.failures.listen(_recordFailure);
    _errorSubscription = session.errors.listen((error) {
      _recordFailure(ChatroomFailureEvent.fromError(error));
    });
  }

  void _enqueueEvent(ChatroomEvent event) {
    _logChatroomSocketEvent(
      'event received type=${chatroomEventType(event)} '
      'world=$_worldId joined=${_state.joinedLocationId}',
    );
    _replyActionsController?.receiveEvent(event);
    if (event is ChatroomWaitingConversationRound &&
        event.worldId == _worldId) {
      final round = int.tryParse(event.conversationRoundId);
      if (round != null && round > 0) {
        _inspirations?.observe(
          event.locationId,
          roundId: round,
          tailMessageId: 0,
        );
      }
    }
    _prepareWorldRefreshForQueuedEvent(event);
    _eventQueue = _eventQueue.then((_) => _handleEvent(event)).catchError((
      Object error,
    ) {
      _recordFailure(
        ChatroomFailureEvent(
          code: 'event_handle_failed',
          message: 'Something went wrong',
          sourceType: chatroomEventType(event),
          cause: error,
        ),
      );
    });
    unawaited(_eventQueue);
  }

  Future<void> _detachSession({required bool disconnect}) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final session = _session;
    _session = null;
    await _eventSubscription?.cancel();
    await _failureSubscription?.cancel();
    await _errorSubscription?.cancel();
    _eventSubscription = null;
    _failureSubscription = null;
    _errorSubscription = null;
    try {
      await _eventQueue;
    } catch (_) {}
    _streamAccumulators.clear();
    _clearProvisionalStreamMessages();
    if (disconnect && session != null) {
      try {
        await session.disconnect();
      } catch (_) {}
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      unawaited(_sendHeartbeat());
    });
  }

  Future<void> _sendHeartbeat() async {
    final session = _session;
    if (session == null ||
        _userDisconnected ||
        _disposed ||
        _heartbeatInFlight) {
      return;
    }
    _heartbeatInFlight = true;
    try {
      await session.heartbeat();
    } catch (_) {
      await _handleConnectionLost();
    } finally {
      _heartbeatInFlight = false;
    }
  }

  Future<void> _handleConnectionLost() async {
    if (_userDisconnected || _disposed) return;
    _suspendInspirations();
    _replyActionsController?.invalidateCardsOnDisconnect();
    await _detachSession(disconnect: true);
    _setState(_state.copyWith(connected: false, joinedLocationId: ''));
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_userDisconnected || _disposed) return;
    _setState(_state.copyWith(reconnecting: true));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectInterval, () {
      _reconnectTimer = null;
      unawaited(_connectOnce().catchError((Object _) {}));
    });
  }
}

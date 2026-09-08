import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../app/debug/location_chat_debug_slice.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../api_client.dart';
import '../app_request_headers.dart';
import '../gateway_auth.dart';
import '../../platform/device/device_id_service.dart';
import '../../platform/session/user_session_store.dart';
import '../../utils/genesis_ugc_text.dart';
import 'chatroom_models.dart';
import 'chatroom_socket_transport.dart';
import 'chatroom_timeline_payload.dart';

class ChatroomClient {
  ChatroomClient({
    required String wsBaseUrl,
    required UserSessionStore sessionStore,
    DeviceIdService? deviceIdService,
    ChatroomSocketTransport? transport,
    Duration heartbeatInterval = const Duration(seconds: 2),
    Duration ackTimeout = const Duration(seconds: 12),
    bool autoHeartbeat = true,
    RequestHeaderProvider? requestHeaderProvider,
    GatewayHandshakeHeaderSigner? handshakeHeaderSigner,
  }) : _wsBaseUri = Uri.parse(wsBaseUrl),
       _sessionStore = sessionStore,
       _transport = transport ?? IoChatroomSocketTransport(),
       _heartbeatInterval = heartbeatInterval,
       _ackTimeout = ackTimeout,
       _autoHeartbeat = autoHeartbeat,
       _requestHeaderProvider = requestHeaderProvider,
       _handshakeHeaderSigner = handshakeHeaderSigner;

  final Uri _wsBaseUri;
  final UserSessionStore _sessionStore;
  final ChatroomSocketTransport _transport;
  final Duration _heartbeatInterval;
  final Duration _ackTimeout;
  final bool _autoHeartbeat;
  final RequestHeaderProvider? _requestHeaderProvider;
  final GatewayHandshakeHeaderSigner? _handshakeHeaderSigner;

  Future<ChatroomSession> connect({
    required String worldId,
    String? locationId,
    String? userId,
    String? senderId,
    String? senderName,
    bool? autoHeartbeat,
  }) async {
    final resolvedWorldId = worldId.trim();
    if (resolvedWorldId.isEmpty) {
      throw const ChatroomProtocolException('worldId is required');
    }
    final localSession = await _sessionStore.readCompleteSession();
    if (localSession == null) {
      throw const ChatroomProtocolException('authToken is required');
    }
    final resolvedUserId = (userId ?? localSession.uid).trim();
    if (resolvedUserId.isEmpty) {
      throw const ChatroomProtocolException('userId is required');
    }

    final authToken = localSession.authToken;
    final resolvedSenderId = senderId?.trim().isNotEmpty == true
        ? senderId!.trim()
        : resolvedUserId;
    final resolvedSenderName = senderName?.trim().isNotEmpty == true
        ? senderName!.trim()
        : resolvedSenderId;
    final uri = _resolveUri(worldId: resolvedWorldId);
    var headers = <String, String>{
      ...await _resolveRequestHeaders(),
      'Authorization': authToken.toLowerCase().startsWith('bearer ')
          ? authToken
          : 'Bearer $authToken',
    };
    final signer = _handshakeHeaderSigner;
    if (signer != null) {
      headers = await signer(uri, headers);
    }
    final protocolVersion = resolveChatroomProtocolVersion(
      _caseInsensitiveHeaderValue(headers, 'x-app-version'),
    );
    final connectStopwatch = Stopwatch()..start();
    final ChatroomSocket socket;
    try {
      socket = await _transport.connect(
        uri,
        headers: headers.isEmpty ? null : headers,
      );
      connectStopwatch.stop();
      _chatroomTelemetry(
        'chatroom.ws_connect',
        data: <String, Object?>{
          'path': uri.path,
          'duration_ms': connectStopwatch.elapsedMilliseconds,
          'outcome': 'success',
        },
      );
    } catch (error) {
      connectStopwatch.stop();
      _chatroomTelemetry(
        'chatroom.ws_connect',
        data: <String, Object?>{
          'path': uri.path,
          'duration_ms': connectStopwatch.elapsedMilliseconds,
          'outcome': 'failure',
          'error_type': error.runtimeType.toString(),
        },
        level: GenesisTelemetryLevel.warning,
      );
      rethrow;
    }
    final session = ChatroomSession._(
      socket: socket,
      worldId: resolvedWorldId,
      locationId: locationId?.trim() ?? '',
      userId: resolvedUserId,
      senderId: resolvedSenderId,
      senderName: resolvedSenderName,
      protocolVersion: protocolVersion,
      heartbeatInterval: _heartbeatInterval,
      ackTimeout: _ackTimeout,
      autoHeartbeat: autoHeartbeat ?? _autoHeartbeat,
    );
    return session;
  }

  Future<Map<String, String>> _resolveRequestHeaders() async {
    final provider = _requestHeaderProvider;
    if (provider == null) return const <String, String>{};
    try {
      final headers = await provider();
      return stripLegacyAppPublicHeaders({
        for (final entry in headers.entries)
          if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
            entry.key: entry.value,
      });
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<ChatroomSession> connectAndJoin({
    required String worldId,
    String? locationId,
    String? userId,
    String? senderId,
    String? senderName,
    bool? autoHeartbeat,
  }) async {
    final session = await connect(
      worldId: worldId,
      locationId: locationId,
      userId: userId,
      senderId: senderId,
      senderName: senderName,
      autoHeartbeat: autoHeartbeat,
    );
    try {
      await session.join();
    } catch (_) {
      await session.disconnect();
      rethrow;
    }
    return session;
  }

  Uri _resolveUri({required String worldId}) {
    final base = _withDefaultWebSocketPort(_wsBaseUri);
    final basePath = base.path.trim();
    final path = basePath.isEmpty ? '/' : basePath;
    return base.replace(
      path: path,
      queryParameters: <String, String>{
        ...base.queryParameters,
        'world_id': worldId,
      },
    );
  }

  Uri _withDefaultWebSocketPort(Uri uri) {
    if (uri.hasPort) return uri;
    return switch (uri.scheme.toLowerCase()) {
      'ws' => uri.replace(port: 80),
      'wss' => uri.replace(port: 443),
      _ => uri,
    };
  }
}

class ChatroomSession {
  ChatroomSession._({
    required ChatroomSocket socket,
    required this.worldId,
    required this.locationId,
    required this.userId,
    required this.senderId,
    required this.senderName,
    required this.protocolVersion,
    required Duration heartbeatInterval,
    required Duration ackTimeout,
    required bool autoHeartbeat,
  }) : _socket = socket,
       _heartbeatInterval = heartbeatInterval,
       _ackTimeout = ackTimeout,
       _autoHeartbeat = autoHeartbeat {
    _subscription = _socket.messages.listen(
      _handleMessage,
      onError: _handleSocketError,
      onDone: () => _handleSocketDone(),
      cancelOnError: false,
    );
    if (_autoHeartbeat) _startHeartbeat();
  }

  final ChatroomSocket _socket;
  final Duration _heartbeatInterval;
  final Duration _ackTimeout;
  final String worldId;
  final String locationId;
  final String userId;
  final String senderId;
  final String senderName;
  final ChatroomProtocolVersion protocolVersion;
  final bool _autoHeartbeat;
  final _events = StreamController<ChatroomEvent>.broadcast();
  final _errors = StreamController<ChatroomErrorEvent>.broadcast();
  final _failures = StreamController<ChatroomFailureEvent>.broadcast();
  final _streams = StreamController<ChatroomAiMessageStream>.broadcast();
  final _pendingAcks = <String, _PendingAck>{};
  final _activeStreams = <String, ChatroomAiMessageStream>{};
  var _streamOrdinal = 0;
  late final StreamSubscription<String> _subscription;
  Timer? _heartbeatTimer;
  bool _heartbeatInFlight = false;
  bool _closed = false;
  bool _disposed = false;
  ChatroomJoined? _joined;

  Stream<ChatroomEvent> get events => _events.stream;

  Stream<ChatroomErrorEvent> get errors => _errors.stream;

  Stream<ChatroomFailureEvent> get failures => _failures.stream;

  Stream<ChatroomAiMessageStream> get streams => _streams.stream;

  ChatroomJoined? get joined => _joined;

  StreamSubscription<ChatroomEvent> listenMessages(
    ChatroomMessageHandlers handlers, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return events.listen(
      handlers.handle,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  Future<ChatroomJoined> join({String? locationId}) async {
    _throwIfClosed();
    final stopwatch = Stopwatch()..start();
    try {
      final requestedLocationId = locationId?.trim();
      final resolvedLocationId =
          requestedLocationId != null && requestedLocationId.isNotEmpty
          ? requestedLocationId
          : this.locationId.trim();
      if (resolvedLocationId.isEmpty) {
        throw const ChatroomProtocolException('locationId is required');
      }
      final joined = _joined;
      if (joined != null && joined.locationId == resolvedLocationId) {
        return joined;
      }
      final ack = await _sendAckedClientMessage('join', <String, Object?>{
        'world_id': worldId,
        'location_id': resolvedLocationId,
      }, requestType: 'join');
      final nextJoined = ChatroomJoined(
        sessionId: ack.sessionId,
        worldId: ack.worldId.isEmpty ? worldId : ack.worldId,
        locationId: ack.locationId.isEmpty
            ? resolvedLocationId
            : ack.locationId,
        userId: ack.userId.isEmpty ? userId : ack.userId,
        code: ack.code,
        codeMsg: ack.codeMsg,
        ts: ack.ts,
        onlineUsers: const <ChatroomOnlineUser>[],
      );
      _joined = nextJoined;
      stopwatch.stop();
      _chatroomTelemetry(
        'chatroom.join',
        data: <String, Object?>{
          'duration_ms': stopwatch.elapsedMilliseconds,
          'outcome': 'success',
        },
      );
      return nextJoined;
    } catch (e) {
      stopwatch.stop();
      _chatroomTelemetry(
        'chatroom.join',
        data: <String, Object?>{
          'duration_ms': stopwatch.elapsedMilliseconds,
          'outcome': 'failure',
          'error_type': e.runtimeType.toString(),
        },
        level: GenesisTelemetryLevel.warning,
      );
      if (e is ChatroomFailureEvent) {
        rethrow;
      }
      final failure = ChatroomFailureEvent(
        code: 'join_send_failed',
        message: 'Something went wrong',
        sourceType: 'join',
        requestType: 'join',
        cause: e,
      );
      _emitFailure(failure);
      throw failure;
    }
  }

  Future<void> heartbeat() async {
    _throwIfClosed();
    try {
      await _sendClientMessage('heartbeat', const <String, Object?>{});
    } catch (e) {
      if (e is ChatroomFailureEvent) {
        rethrow;
      }
      final failure = ChatroomFailureEvent(
        code: 'heartbeat_failed',
        message: 'Something went wrong',
        sourceType: 'heartbeat',
        requestType: 'heartbeat',
        cause: e,
      );
      _emitFailure(failure);
      throw failure;
    }
  }

  Future<void> sendUserEnterLocation({required String locationId}) {
    _throwIfClosed();
    final resolvedLocationId = locationId.trim();
    if (resolvedLocationId.isEmpty) {
      throw const ChatroomProtocolException('locationId is required');
    }
    if (protocolVersion == ChatroomProtocolVersion.v2) {
      return _sendClientMessage('user_enter_location', <String, Object?>{
        'client_msg_id': _newClientMessageId(),
        'world_id': worldId,
        'location_id': resolvedLocationId,
      });
    }
    return _sendClientJson(<String, Object?>{
      'type': 'user_enter_location',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'world_id': worldId,
      'payload': <String, Object?>{'loc_id': resolvedLocationId},
      'err_no': '',
      'err_msg': '',
      'broadcast': false,
    });
  }

  Future<ChatroomAck> sendMessage(String text, {String? clientMsgId}) async {
    _throwIfClosed();
    final content = normalizeGenesisUgcTextForSubmission(text);
    if (isGenesisUgcTextBlank(content)) {
      throw const ChatroomProtocolException('Message text is required');
    }
    return _sendAckedClientMessage(
      'send_message',
      <String, Object?>{'content': content},
      clientMsgId: clientMsgId,
      requestType: 'send_message',
    );
  }

  /// Request a private candidate over V2. The caller supplies an idempotency ID;
  /// no request, polling, stream replay or formal-history mutation is automatic.
  Future<ChatroomCardRegeneration> regenerateLlmCard({
    required String locationId,
    required int conversationRoundId,
    required String clientMsgId,
  }) async {
    _validateCardCommand(locationId, conversationRoundId, clientMsgId);
    if (_joined?.locationId != locationId.trim()) {
      throw const ChatroomProtocolException(
        'Regeneration requires the joined location',
      );
    }
    final ack = await _sendAckedClientMessage(
      'regenerate_llm_card',
      {
        'conversation_round_id': conversationRoundId,
        'payload': {'location_id': locationId.trim()},
      },
      clientMsgId: clientMsgId,
      maxAttempts: 1,
    );
    _validateCardAck(ack, locationId, conversationRoundId);
    final result = ack.regeneration;
    if (result == null || result.conversationRoundId != conversationRoundId) {
      throw const ChatroomProtocolException(
        'Missing or mismatched regeneration receipt',
      );
    }
    return result;
  }

  /// Final selection may target a previously joined location. Only return its
  /// receipt; business code decides when to confirm and when to refresh.
  Future<ChatroomCardSelection> selectLlmCard({
    required String locationId,
    required int conversationRoundId,
    required int cardId,
    required String clientMsgId,
  }) async {
    _validateCardCommand(
      locationId,
      conversationRoundId,
      clientMsgId,
      cardId: cardId,
    );
    final ack = await _sendAckedClientMessage(
      'select_llm_card',
      {
        'conversation_round_id': conversationRoundId,
        'payload': {'location_id': locationId.trim(), 'card_id': cardId},
      },
      clientMsgId: clientMsgId,
      maxAttempts: 1,
    );
    _validateCardAck(ack, locationId, conversationRoundId);
    final result = ack.selection;
    if (result == null ||
        result.conversationRoundId != conversationRoundId ||
        result.selectedCardId != cardId) {
      throw const ChatroomProtocolException(
        'Missing or mismatched selection receipt',
      );
    }
    return result;
  }

  void _validateCardCommand(
    String location,
    int round,
    String requestId, {
    int? cardId,
  }) {
    _throwIfClosed();
    if (protocolVersion != ChatroomProtocolVersion.v2) {
      throw const ChatroomProtocolException('Cards require a V2 connection');
    }
    if (location.trim().isEmpty) throw ArgumentError('locationId is required');
    validateLlmCardRequest(
      conversationRoundId: round,
      cardId: cardId,
      clientMsgId: requestId,
    );
    if (_pendingAcks.containsKey(requestId)) {
      throw StateError('clientMsgId is already in flight');
    }
  }

  void _validateCardAck(ChatroomAck ack, String location, int round) {
    if (ack.worldId != worldId ||
        ack.locationId != location.trim() ||
        ack.cardConversationRoundId != round) {
      throw const ChatroomProtocolException('Card receipt identity mismatch');
    }
  }

  Future<ChatroomAck> _sendAckedClientMessage(
    String type,
    Map<String, Object?> fields, {
    String? clientMsgId,
    String? requestType,
    int maxAttempts = 3,
  }) {
    _throwIfClosed();
    final resolvedClientMsgId = clientMsgId ?? _newClientMessageId();
    final resolvedRequestType = requestType ?? type;
    final completer = Completer<ChatroomAck>();
    late final _PendingAck pending;
    var attempt = 0;

    void fail(ChatroomFailureEvent failure) {
      final pending = _pendingAcks.remove(resolvedClientMsgId);
      pending?.completeError(failure);
      _emitFailure(failure);
    }

    Future<void> sendAttempt() async {
      if (_closed || completer.isCompleted) return;
      attempt += 1;
      pending.cancel();
      try {
        await _sendClientMessage(type, <String, Object?>{
          'client_msg_id': resolvedClientMsgId,
          ...fields,
        });
      } catch (e) {
        fail(
          ChatroomFailureEvent(
            code: '${resolvedRequestType}_send_failed',
            message: 'Failed to send chatroom $resolvedRequestType',
            sourceType: type,
            requestType: resolvedRequestType,
            cause: e,
          ),
        );
        return;
      }

      pending.timer = Timer(_ackTimeout, () {
        if (completer.isCompleted) return;
        if (attempt >= maxAttempts) {
          fail(
            ChatroomFailureEvent(
              code: 'ack_timeout',
              message: 'Timed out waiting for $resolvedRequestType ack',
              sourceType: 'ack',
              requestType: resolvedRequestType,
              cause: resolvedClientMsgId,
            ),
          );
          return;
        }
        unawaited(sendAttempt());
      });
    }

    pending = _PendingAck(completer, requestType: resolvedRequestType);
    _pendingAcks[resolvedClientMsgId] = pending;
    unawaited(sendAttempt());
    return completer.future;
  }

  ChatroomAiMessageStream? streamForMessage(int messageId) {
    final matches = _activeStreams.values
        .where((stream) => stream.start.messageId == messageId)
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  Future<void> close() async {
    if (_closed) return;
    if (_joined != null) {
      try {
        await leave();
      } catch (_) {
        // close() preserves the old best-effort shutdown behavior.
      }
    }
    await disconnect();
  }

  Future<void> leave() async {
    _throwIfClosed();
    try {
      await _sendClientMessage('leave', <String, Object?>{
        'client_msg_id': _newClientMessageId(),
      });
      _joined = null;
    } catch (e) {
      final failure = ChatroomFailureEvent(
        code: 'leave_failed',
        message: 'Something went wrong',
        sourceType: 'leave',
        requestType: 'leave',
        cause: e,
      );
      _emitFailure(failure);
      throw failure;
    }
  }

  Future<void> disconnect() async {
    if (_closed) return;
    _chatroomTelemetry(
      'chatroom.disconnect',
      data: const <String, Object?>{'outcome': 'requested'},
    );
    final reason = ChatroomFailureEvent(
      code: 'closed',
      message: 'Something went wrong',
      sourceType: 'disconnect',
      requestType: 'disconnect',
    );
    await _disposeState(reason);
    await _socket.close(1000, 'client_disconnect');
  }

  Future<void> _sendClientMessage(String type, Map<String, Object?> fields) {
    _throwIfClosed();
    if (protocolVersion == ChatroomProtocolVersion.v2) {
      if (type == 'regenerate_llm_card' || type == 'select_llm_card') {
        return _sendClientJson({
          'type': type,
          'world_id': worldId,
          'conversation_round_id': fields['conversation_round_id'],
          'client_msg_id': fields['client_msg_id'],
          'payload': fields['payload'],
        });
      }
      final requestedClientMsgId = '${fields['client_msg_id'] ?? ''}'.trim();
      final clientMsgId = requestedClientMsgId.isEmpty
          ? _newClientMessageId()
          : requestedClientMsgId;
      final payload = switch (type) {
        'join' || 'user_enter_location' => <String, Object?>{
          'location_id': fields['location_id'],
        },
        'send_message' => <String, Object?>{'content': fields['content']},
        _ => const <String, Object?>{},
      };
      return _sendClientJson(
        ChatroomV2Message(
          type: type,
          ts: DateTime.now().millisecondsSinceEpoch,
          worldId:
              type == 'join' ||
                  type == 'send_message' ||
                  type == 'user_enter_location'
              ? worldId
              : '',
          clientMsgId: clientMsgId,
          payload: Map<String, dynamic>.from(payload),
        ).toJson(),
      );
    }
    final json = <String, Object?>{'type': type};
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      json[entry.key] = value;
    }
    return _sendClientJson(json);
  }

  Future<void> _sendClientJson(Map<String, Object?> json) {
    _throwIfClosed();
    final type = '${json['type'] ?? ''}';
    final raw = jsonEncode(json);
    _recordWebSocketDebug(
      action: 'send',
      details: {'direction': 'out', 'type': type, 'raw': raw, 'payload': json},
    );
    return _socket.send(raw);
  }

  void _handleMessage(String raw) {
    final oversized = isChatroomFrameOversized(raw);
    try {
      if (oversized) {
        throw const ChatroomProtocolException(
          'Envelope exceeds the maximum frame size',
        );
      }
      late final ChatroomEvent event;
      late final String incomingType;
      late final String incomingLocationId;
      late final Object debugPayload;
      int? schemaVersion;
      var eventId = '';
      if (protocolVersion == ChatroomProtocolVersion.v2) {
        final message = ChatroomV2Message.decode(raw);
        event = chatroomEventFromV2Message(message);
        incomingType = message.type;
        incomingLocationId = message.locationId;
        debugPayload = message.toJson();
      } else {
        final envelope = ChatroomEnvelope.decode(raw);
        event = chatroomLegacyEventFromEnvelope(envelope);
        incomingType = envelope.type;
        incomingLocationId = envelope.locationId;
        debugPayload = envelope.mergedPayload;
        schemaVersion = envelope.schemaVersion;
        eventId = envelope.eventId;
      }
      _recordWebSocketDebug(
        action: 'receive',
        locationId: incomingLocationId,
        details: {
          'direction': 'in',
          'type': incomingType,
          'eventType': chatroomEventType(event),
          'protocolVersion': protocolVersion.name,
          'schemaVersion': schemaVersion,
          'eventId': eventId,
          'raw': raw,
          'payload': debugPayload,
        },
      );
      _dispatchEvent(event);
    } catch (e) {
      _recordWebSocketDebug(
        action: 'decodeFailed',
        details: {
          'direction': 'in',
          if (!oversized) 'raw': raw,
          if (oversized) ...{'rawOmitted': true, 'rawCodeUnits': raw.length},
          'error': e.toString(),
        },
      );
      _emitFailure(
        ChatroomFailureEvent(
          code: 'protocol_error',
          message: 'Something went wrong',
          sourceType: 'protocol_error',
          cause: e,
        ),
      );
    }
  }

  void _recordWebSocketDebug({
    required String action,
    String? locationId,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    if (!LocationChatDebugSlice.enabled) return;
    final resolvedLocationId = _resolveDebugLocationId(locationId);
    LocationChatDebugSlice.recordEvent(
      source: 'websocket',
      action: action,
      worldId: worldId,
      locationId: resolvedLocationId,
      details: <String, Object?>{
        'protocolVersion': protocolVersion.name,
        ...details,
        'sessionLocationId': this.locationId,
        'joinedLocationId': _joined?.locationId,
        'pendingAckCount': _pendingAcks.length,
        'activeStreamCount': _activeStreams.length,
      },
      snapshotKey: '$worldId|$resolvedLocationId',
      snapshot: <String, Object?>{
        'worldId': worldId,
        'locationId': resolvedLocationId,
        'lastAction': action,
        'protocolVersion': protocolVersion.name,
        'sessionLocationId': this.locationId,
        'joinedLocationId': _joined?.locationId,
        'pendingAckCount': _pendingAcks.length,
        'activeStreamCount': _activeStreams.length,
        'lastFrame': details,
      },
    );
  }

  String _resolveDebugLocationId(String? candidate) {
    final resolvedCandidate = candidate?.trim();
    if (resolvedCandidate != null && resolvedCandidate.isNotEmpty) {
      return resolvedCandidate;
    }
    final joinedLocationId = _joined?.locationId.trim() ?? '';
    if (joinedLocationId.isNotEmpty) return joinedLocationId;
    return locationId.trim();
  }

  void _dispatchEvent(ChatroomEvent event) {
    if (event is ChatroomLlmCardStream &&
        (event.worldId != worldId || event.userId != userId)) {
      return;
    }
    if (event is ChatroomLlmCardGenerationEnd &&
        (event.worldId != worldId || event.userId != userId)) {
      return;
    }
    if (event is ChatroomJoined) {
      if (event.ok) {
        _joined = event;
      } else {
        final failure = ChatroomFailureEvent.fromPayloadEvent(
          event,
          requestType: 'join',
        );
        _emitFailure(failure);
      }
    } else if (event is ChatroomAck) {
      final pendingEntry = _removePendingAckFor(event);
      final pending = pendingEntry?.value;
      if (event.ok) {
        pending?.complete(event);
      } else {
        final failure = ChatroomFailureEvent.fromPayloadEvent(
          event,
          requestType: pending?.requestType ?? 'send_message',
          clientMsgId: pendingEntry?.key ?? '',
        );
        pending?.completeError(failure);
        _emitFailure(failure);
      }
    } else if (event is ChatroomUserMessage &&
        protocolVersion == ChatroomProtocolVersion.legacy) {
      // Legacy servers may use the canonical user echo in place of an ACK.
      // V2 send futures complete only from the receipt-only `type=ack` frame;
      // canonical echo reconciliation belongs to the world service.
      final pending = event.clientMsgId.isEmpty
          ? null
          : _pendingAcks.remove(event.clientMsgId);
      pending?.complete(
        ChatroomAck(
          sessionId: event.sessionId,
          worldId: event.worldId,
          locationId: event.locationId,
          userId: event.userId,
          code: event.code,
          codeMsg: event.codeMsg,
          ts: event.ts,
          globalMessageId: event.globalMessageId,
          messageId: event.messageId,
          locationMessageId: event.locationMessageId,
          conversationRoundId: event.conversationRoundId,
          clientMsgId: event.clientMsgId,
        ),
      );
    } else if (event is ChatroomAiStreamStart) {
      final stream = ChatroomAiMessageStream._(event);
      final baseKey = event.identity.stableKey ?? 'cursorless';
      _streamOrdinal += 1;
      _activeStreams['$baseKey#$_streamOrdinal'] = stream;
      _streams.add(stream);
    } else if (event is ChatroomAiStreamChunk) {
      _streamForAiEvent(
        event.identity,
        sourceType: event.streamType,
      )?.addChunk(event);
    } else if (event is ChatroomAiStreamEnd) {
      final stream = _removeStreamForAiEvent(
        event.identity,
        sourceType: event.streamType,
      );
      stream?.complete(event);
    } else if (event is ChatroomErrorEvent) {
      _emitError(event);
      _emitFailure(ChatroomFailureEvent.fromError(event));
      _failMatchingStream(event);
    } else if (event is ChatroomPayloadEvent && !event.ok) {
      _emitFailure(ChatroomFailureEvent.fromPayloadEvent(event));
    }

    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  MapEntry<String, _PendingAck>? _removePendingAckFor(ChatroomAck event) {
    final clientMsgId = _pendingAcks.containsKey(event.clientMsgId)
        ? event.clientMsgId
        : event.clientMsgId.trim();
    if (clientMsgId.isNotEmpty) {
      final pending = _pendingAcks.remove(clientMsgId);
      return pending == null ? null : MapEntry(clientMsgId, pending);
    }
    if (protocolVersion == ChatroomProtocolVersion.v2 ||
        (event.code != 3001 && event.code != 10001)) {
      return null;
    }
    final sendMessageEntries = _pendingAcks.entries
        .where((entry) => entry.value.requestType == 'send_message')
        .toList(growable: false);
    if (sendMessageEntries.length != 1) return null;
    final entry = sendMessageEntries.single;
    _pendingAcks.remove(entry.key);
    return MapEntry(entry.key, entry.value);
  }

  void _handleSocketError(Object error) {
    _chatroomTelemetry(
      'chatroom.failure',
      data: <String, Object?>{
        'source': 'socket_error',
        'error_type': error.runtimeType.toString(),
      },
      level: GenesisTelemetryLevel.warning,
    );
    final event = ChatroomErrorEvent(
      code: 'socket_error',
      message: 'Something went wrong',
      cause: error,
    );
    _emitError(event);
    _emitFailure(ChatroomFailureEvent.fromError(event, requestType: 'socket'));
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _handleSocketDone() {
    _chatroomTelemetry(
      'chatroom.disconnect',
      data: const <String, Object?>{'outcome': 'socket_closed'},
      level: GenesisTelemetryLevel.warning,
    );
    final reason = ChatroomFailureEvent(
      code: 'socket_closed',
      message: 'Something went wrong',
      sourceType: 'socket_closed',
    );
    _emitFailure(reason);
    unawaited(_disposeState(reason));
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_heartbeatInFlight) return;
      _heartbeatInFlight = true;
      unawaited(
        heartbeat()
            .catchError((Object error) {})
            .whenComplete(() => _heartbeatInFlight = false),
      );
    });
  }

  Future<void> _disposeState(ChatroomFailureEvent reason) async {
    if (_disposed) return;
    _disposed = true;
    _closed = true;
    _stopHeartbeat();

    for (final pending in _pendingAcks.values) {
      pending.completeError(reason);
    }
    _pendingAcks.clear();

    for (final stream in _activeStreams.values) {
      stream.fail(reason);
    }
    _activeStreams.clear();

    await _subscription.cancel();
    await _events.close();
    await _errors.close();
    await _failures.close();
    await _streams.close();
  }

  void _emitError(ChatroomErrorEvent error) {
    if (!_errors.isClosed) {
      _errors.add(error);
    }
  }

  void _emitFailure(ChatroomFailureEvent failure) {
    if (!_failures.isClosed) {
      _failures.add(failure);
    }
    if (!_events.isClosed) {
      _events.add(failure);
    }
  }

  void _failMatchingStream(ChatroomErrorEvent error) {
    if (error.conversationRoundId.isEmpty && error.senderId.isEmpty) return;
    final matches = _matchingStreams(
      ChatroomStreamIdentity(
        conversationRoundId: error.conversationRoundId,
        senderId: error.senderId,
      ),
    );
    if (matches.length == 1) {
      final match = matches.single;
      _activeStreams.remove(match.key);
      match.value.fail(error);
    } else if (matches.length > 1) {
      _emitStreamAmbiguity(
        sourceType: error.sourceType,
        identity: ChatroomStreamIdentity(
          conversationRoundId: error.conversationRoundId,
          senderId: error.senderId,
        ),
        candidateCount: matches.length,
      );
    }
  }

  ChatroomAiMessageStream? _streamForAiEvent(
    ChatroomStreamIdentity identity, {
    required String sourceType,
  }) {
    final matches = _matchingStreams(identity);
    if (matches.length == 1) return matches.single.value;
    if (matches.length > 1) {
      _emitStreamAmbiguity(
        sourceType: sourceType,
        identity: identity,
        candidateCount: matches.length,
      );
    }
    return null;
  }

  ChatroomAiMessageStream? _removeStreamForAiEvent(
    ChatroomStreamIdentity identity, {
    required String sourceType,
  }) {
    final matches = _matchingStreams(identity);
    if (matches.length == 1) {
      return _activeStreams.remove(matches.single.key);
    }
    if (matches.length > 1) {
      _emitStreamAmbiguity(
        sourceType: sourceType,
        identity: identity,
        candidateCount: matches.length,
      );
    }
    return null;
  }

  List<MapEntry<String, ChatroomAiMessageStream>> _matchingStreams(
    ChatroomStreamIdentity incoming,
  ) {
    final scored = <(MapEntry<String, ChatroomAiMessageStream>, int)>[];
    for (final entry in _activeStreams.entries) {
      final candidate = entry.value.start.identity;
      if (_streamIdentityConflicts(incoming, candidate)) continue;
      scored.add((entry, _streamIdentityScore(incoming, candidate)));
    }
    if (scored.isEmpty) {
      return const <MapEntry<String, ChatroomAiMessageStream>>[];
    }
    final highestScore = scored
        .map((item) => item.$2)
        .reduce((left, right) => left > right ? left : right);
    return scored
        .where((item) => item.$2 == highestScore)
        .map((item) => item.$1)
        .toList(growable: false);
  }

  void _emitStreamAmbiguity({
    required String sourceType,
    required ChatroomStreamIdentity identity,
    required int candidateCount,
  }) {
    _emitFailure(
      ChatroomFailureEvent(
        code: 'stream_ambiguous',
        message: 'Ambiguous chatroom stream frame',
        detail:
            'world=${identity.worldId} location=${identity.locationId} '
            'round=${identity.conversationRoundId} message=${identity.messageId} '
            'sender=${identity.senderId} candidates=$candidateCount',
        sourceType: sourceType,
      ),
    );
  }

  void _throwIfClosed() {
    if (_closed) {
      throw const ChatroomProtocolException('Chatroom session is closed');
    }
  }

  String _newClientMessageId() {
    final random = Random().nextInt(1 << 32).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch}-$random';
  }
}

void _chatroomTelemetry(
  String name, {
  Map<String, Object?> data = const <String, Object?>{},
  GenesisTelemetryLevel level = GenesisTelemetryLevel.info,
}) {
  GenesisTelemetry.event(
    name,
    category: 'network.websocket',
    data: data,
    level: level,
  );
}

String _caseInsensitiveHeaderValue(Map<String, String> headers, String name) {
  final normalizedName = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == normalizedName) return entry.value;
  }
  return '';
}

bool _streamIdentityConflicts(
  ChatroomStreamIdentity incoming,
  ChatroomStreamIdentity candidate,
) {
  bool stringConflict(String left, String right) =>
      left.isNotEmpty && right.isNotEmpty && left != right;
  final sameConversationRound =
      incoming.conversationRoundId.isNotEmpty &&
      incoming.conversationRoundId == candidate.conversationRoundId;
  return stringConflict(incoming.worldId, candidate.worldId) ||
      stringConflict(incoming.locationId, candidate.locationId) ||
      stringConflict(incoming.sessionId, candidate.sessionId) ||
      stringConflict(
        incoming.conversationRoundId,
        candidate.conversationRoundId,
      ) ||
      stringConflict(incoming.senderId, candidate.senderId) ||
      (!sameConversationRound &&
          incoming.messageId > 0 &&
          candidate.messageId > 0 &&
          incoming.messageId != candidate.messageId);
}

int _streamIdentityScore(
  ChatroomStreamIdentity incoming,
  ChatroomStreamIdentity candidate,
) {
  var score = 0;
  if (incoming.conversationRoundId.isNotEmpty &&
      incoming.conversationRoundId == candidate.conversationRoundId) {
    score += 64;
  }
  if (incoming.senderId.isNotEmpty && incoming.senderId == candidate.senderId) {
    score += 32;
  }
  if (incoming.worldId.isNotEmpty && incoming.worldId == candidate.worldId) {
    score += 16;
  }
  if (incoming.locationId.isNotEmpty &&
      incoming.locationId == candidate.locationId) {
    score += 16;
  }
  if (incoming.sessionId.isNotEmpty &&
      incoming.sessionId == candidate.sessionId) {
    score += 8;
  }
  if (incoming.messageId > 0 && incoming.messageId == candidate.messageId) {
    // message_id is useful corroboration, but round+sender remain the primary
    // V2 stream identity because message ids may be absent on stream frames.
    score += 4;
  }
  return score;
}

class ChatroomAiMessageStream {
  ChatroomAiMessageStream._(this.start) {
    unawaited(_done.future.then<void>((_) {}, onError: (Object _) {}));
  }

  final ChatroomAiStreamStart start;
  final _chunks = StreamController<ChatroomAiStreamChunk>.broadcast();
  final _done = Completer<ChatroomAiStreamEnd>();
  final _pendingChunks = <int, ChatroomAiStreamChunk>{};
  var _nextSequence = 1;
  var _content = '';
  String? _completedContent;

  Stream<ChatroomAiStreamChunk> get chunks => _chunks.stream;

  Future<ChatroomAiStreamEnd> get done => _done.future;

  String get content => _completedContent ?? _content;

  bool get isCompleted => _done.isCompleted;

  void addChunk(ChatroomAiStreamChunk chunk) {
    if (_done.isCompleted) return;
    if (chunk.seq <= 0) {
      _emitChunk(chunk);
      return;
    }
    if (chunk.seq < _nextSequence || _pendingChunks.containsKey(chunk.seq)) {
      return;
    }
    _pendingChunks[chunk.seq] = chunk;
    while (true) {
      final next = _pendingChunks.remove(_nextSequence);
      if (next == null) break;
      _emitChunk(next);
      _nextSequence += 1;
    }
  }

  void complete(ChatroomAiStreamEnd end) {
    if (_done.isCompleted) return;
    _completedContent = end.content.isEmpty ? _content : end.content;
    _pendingChunks.clear();
    _done.complete(end);
    unawaited(_chunks.close());
  }

  void _emitChunk(ChatroomAiStreamChunk chunk) {
    _content = chunk.isDelta ? '$_content${chunk.chunk}' : chunk.chunk;
    _chunks.add(chunk);
  }

  void fail(Object error) {
    if (!_done.isCompleted) {
      _done.completeError(error);
    }
    if (!_chunks.isClosed) {
      _chunks.addError(error);
      unawaited(_chunks.close());
    }
  }
}

class _PendingAck {
  _PendingAck(this.completer, {required this.requestType});

  final Completer<ChatroomAck> completer;
  final String requestType;
  Timer? timer;

  void complete(ChatroomAck ack) {
    cancel();
    if (!completer.isCompleted) {
      completer.complete(ack);
    }
  }

  void completeError(Object error) {
    cancel();
    if (!completer.isCompleted) {
      completer.completeError(error);
    }
  }

  void cancel() {
    timer?.cancel();
    timer = null;
  }
}

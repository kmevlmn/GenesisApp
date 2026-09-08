import 'dart:convert';

import '../../utils/gem_amount.dart';
import '../json_utils.dart';
import 'chatroom_message_type.dart';
import 'chatroom_llm_cards.dart';
import 'chatroom_timeline_payload.dart';

export 'chatroom_llm_cards.dart';
part 'chatroom_card_events.dart';

class ChatroomProtocolException implements Exception {
  const ChatroomProtocolException(this.message, {this.error});

  final String message;
  final Object? error;

  @override
  String toString() => 'ChatroomProtocolException: $message';
}

enum ChatroomProtocolVersion { legacy, v2 }

/// Resolves the WebSocket wire contract selected by the gateway.
///
/// Missing or invalid versions intentionally stay on the legacy contract.
/// Pre-release/build suffixes do not affect the numeric comparison, so
/// `0.3.4-rc` is V2 while `0.3.3+9` is legacy.
ChatroomProtocolVersion resolveChatroomProtocolVersion(String appVersion) {
  final match = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)(?:[-+][0-9A-Za-z.-]+)?$',
  ).firstMatch(appVersion.trim());
  if (match == null) return ChatroomProtocolVersion.legacy;
  final parts = <int>[
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
  const boundary = <int>[0, 3, 3];
  for (var index = 0; index < parts.length; index += 1) {
    if (parts[index] > boundary[index]) return ChatroomProtocolVersion.v2;
    if (parts[index] < boundary[index]) {
      return ChatroomProtocolVersion.legacy;
    }
  }
  return ChatroomProtocolVersion.legacy;
}

const Set<String> chatroomV2StreamTypes = <String>{
  '',
  'llm_stream_start',
  'llm_chunk',
  'llm_stream_end',
};

/// Lossless V2 wire DTO shared by WebSocket and HTTP message decoders.
///
/// This class intentionally keeps `type` and `streamType` as separate axes.
/// It does not infer a canonical stored message from an ACK; callers must wait
/// for the later canonical user echo when they need message IDs or round data.
class ChatroomV2Message {
  const ChatroomV2Message({
    required this.type,
    this.streamType = '',
    this.ts,
    this.worldId = '',
    this.locationId = '',
    this.sessionId = '',
    this.globalMessageId,
    this.messageId,
    this.locationMessageId,
    this.conversationRoundId,
    this.tickNo,
    this.subTickNo,
    this.senderType = '',
    this.senderId = '',
    this.senderName = '',
    this.userId = '',
    this.clientMsgId = '',
    this.messageType = '',
    this.minAppVersion,
    this.createdAt = '',
    this.currentTime = '',
    this.payload = const <String, dynamic>{},
    this.errNo = 0,
    this.errMsg = '',
  });

  final String type;
  final String streamType;
  final int? ts;
  final String worldId;
  final String locationId;
  final String sessionId;
  final int? globalMessageId;
  final int? messageId;
  final int? locationMessageId;
  final int? conversationRoundId;
  final int? tickNo;
  final int? subTickNo;
  final String senderType;
  final String senderId;
  final String senderName;
  final String userId;
  final String clientMsgId;
  final String messageType;
  final int? minAppVersion;
  final String createdAt;
  final String currentTime;
  final Map<String, dynamic> payload;
  final int errNo;
  final String errMsg;

  bool get isLlmStream => streamType.isNotEmpty;

  factory ChatroomV2Message.fromJson(Map<String, dynamic> json) {
    final type = asString(json['type']).trim();
    if (type.isEmpty) {
      throw const ChatroomProtocolException('V2 message type is required');
    }
    final streamType = asString(json['stream_type']).trim().toLowerCase();
    if (!(type == 'llm_card_stream'
        ? const {'start', 'chunk', 'end'}.contains(streamType)
        : chatroomV2StreamTypes.contains(streamType))) {
      throw ChatroomProtocolException('Unsupported stream_type: $streamType');
    }
    if (type == 'llm_card_stream' ||
        type == 'llm_card_generation_end' ||
        (type == 'ack' &&
            json['payload'] is Map &&
            ((json['payload'] as Map).containsKey('regeneration') ||
                (json['payload'] as Map).containsKey('selection')))) {
      llmCardInt(json['conversation_round_id']);
    }
    if (type == 'llm_card_stream' || type == 'llm_card_generation_end') {
      for (final key in [
        'global_message_id',
        'message_id',
        'location_message_id',
      ]) {
        if (json[key] != null && (json[key] is! int || json[key] != 0)) {
          throw const FormatException(
            'Candidate event cannot have formal message IDs',
          );
        }
      }
    }
    if (type == 'llm_message_updated') {
      for (final key in [
        'global_message_id',
        'message_id',
        'location_message_id',
        'conversation_round_id',
      ]) {
        _mutationId(json[key]);
      }
    }
    return ChatroomV2Message(
      type: type,
      streamType: streamType,
      ts: json['ts'] == null ? null : asInt(json['ts']),
      worldId: asString(json['world_id']),
      locationId: asString(json['location_id']),
      sessionId: asString(json['session_id']),
      globalMessageId: json['global_message_id'] == null
          ? null
          : asInt(json['global_message_id']),
      messageId: json['message_id'] == null ? null : asInt(json['message_id']),
      locationMessageId: json['location_message_id'] == null
          ? null
          : asInt(json['location_message_id']),
      conversationRoundId: json['conversation_round_id'] == null
          ? null
          : asInt(json['conversation_round_id']),
      tickNo: json['tick_no'] == null ? null : asInt(json['tick_no']),
      subTickNo: json['sub_tick_no'] == null
          ? null
          : asInt(json['sub_tick_no']),
      senderType: asString(json['sender_type']),
      senderId: asString(json['sender_id']),
      senderName: asString(json['sender_name']),
      userId: asString(json['user_id']),
      clientMsgId: asString(json['client_msg_id']),
      messageType: asString(json['message_type']),
      minAppVersion: json['min_app_version'] == null
          ? null
          : asInt(json['min_app_version']),
      createdAt: asString(json['created_at']),
      currentTime: asString(json['current_time']),
      payload: _optionalJsonMap(json['payload']),
      errNo: asInt(json['err_no']),
      errMsg: asString(json['err_msg']),
    );
  }

  factory ChatroomV2Message.decode(String input) {
    try {
      if (isChatroomFrameOversized(input)) {
        throw const ChatroomProtocolException(
          'Envelope exceeds the maximum frame size',
        );
      }
      final decoded = jsonDecode(input);
      if (decoded is! Map) {
        throw const ChatroomProtocolException('Envelope is not a JSON object');
      }
      validateChatroomPayloadLimits(decoded, field: 'envelope');
      return ChatroomV2Message.fromJson(asJsonMap(decoded));
    } on ChatroomProtocolException {
      rethrow;
    } catch (error) {
      throw ChatroomProtocolException('Invalid V2 JSON envelope', error: error);
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type,
      'stream_type': streamType,
      if (ts != null) 'ts': ts,
      if (worldId.isNotEmpty) 'world_id': worldId,
      if (locationId.isNotEmpty) 'location_id': locationId,
      if (sessionId.isNotEmpty) 'session_id': sessionId,
      if (globalMessageId != null) 'global_message_id': globalMessageId,
      if (messageId != null) 'message_id': messageId,
      if (locationMessageId != null) 'location_message_id': locationMessageId,
      if (conversationRoundId != null)
        'conversation_round_id': conversationRoundId,
      if (tickNo != null) 'tick_no': tickNo,
      if (subTickNo != null) 'sub_tick_no': subTickNo,
      if (senderType.isNotEmpty) 'sender_type': senderType,
      if (senderId.isNotEmpty) 'sender_id': senderId,
      if (senderName.isNotEmpty) 'sender_name': senderName,
      if (userId.isNotEmpty) 'user_id': userId,
      if (clientMsgId.isNotEmpty) 'client_msg_id': clientMsgId,
      if (messageType.isNotEmpty) 'message_type': messageType,
      if (minAppVersion != null) 'min_app_version': minAppVersion,
      if (createdAt.isNotEmpty) 'created_at': createdAt,
      if (currentTime.isNotEmpty) 'current_time': currentTime,
      'payload': payload,
      'err_no': errNo,
      'err_msg': errMsg,
    };
  }

  String encode() => jsonEncode(toJson());
}

class ChatroomV2StoryEvent {
  const ChatroomV2StoryEvent({
    required this.locationId,
    required this.timestamp,
    required this.visibility,
    required this.visibleTo,
    required this.text,
    required this.clue,
  });

  final String locationId;
  final String timestamp;
  final String visibility;
  final List<String>? visibleTo;
  final String text;
  final String clue;

  factory ChatroomV2StoryEvent.fromJson(Map<String, dynamic> json) {
    final rawVisibleTo = json['visible_to'];
    return ChatroomV2StoryEvent(
      locationId: asString(json['location_id']),
      timestamp: asString(json['timestamp']),
      visibility: asString(json['visibility']),
      visibleTo: rawVisibleTo == null
          ? null
          : asJsonList(
              rawVisibleTo,
            ).map((value) => asString(value)).toList(growable: false),
      text: asString(json['text']),
      clue: asString(json['clue']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'location_id': locationId,
    'timestamp': timestamp,
    'visibility': visibility,
    'visible_to': visibleTo,
    'text': text,
    'clue': clue,
  };
}

class ChatroomV2CharacterMovement {
  const ChatroomV2CharacterMovement({
    required this.characterId,
    required this.oldLocationId,
    required this.toLocationId,
  });

  final String characterId;
  final String oldLocationId;
  final String toLocationId;

  factory ChatroomV2CharacterMovement.fromJson(Map<String, dynamic> json) {
    return ChatroomV2CharacterMovement(
      characterId: asString(json['char_id']),
      oldLocationId: asString(json['old_loc_id']),
      toLocationId: asString(json['to_loc_id']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'char_id': characterId,
    'old_loc_id': oldLocationId,
    'to_loc_id': toLocationId,
  };
}

class ChatroomV2TickPayload {
  const ChatroomV2TickPayload({
    required this.currentTime,
    required this.tickNo,
    required this.subTickNo,
    required this.globalText,
    required this.storyEvents,
    required this.charactersMoved,
    required this.fallbackContent,
  });

  final String currentTime;
  final int tickNo;
  final int subTickNo;
  final String globalText;
  final List<ChatroomV2StoryEvent> storyEvents;
  final List<ChatroomV2CharacterMovement> charactersMoved;
  final String fallbackContent;

  bool get isFallback =>
      fallbackContent.isNotEmpty &&
      globalText.isEmpty &&
      storyEvents.isEmpty &&
      charactersMoved.isEmpty;

  factory ChatroomV2TickPayload.fromJson(Map<String, dynamic> json) {
    final rawStoryEvents = json['story_events'];
    final rawCharactersMoved = json['characters_moved'];
    if (rawStoryEvents != null && rawStoryEvents is! List) {
      throw const ChatroomProtocolException(
        'tick payload story_events must be an array',
      );
    }
    if (rawCharactersMoved != null && rawCharactersMoved is! List) {
      throw const ChatroomProtocolException(
        'tick payload characters_moved must be an array',
      );
    }
    return ChatroomV2TickPayload(
      currentTime: asString(json['current_time']),
      tickNo: asInt(json['tick_no']),
      subTickNo: asInt(json['sub_tick_no']),
      globalText: asString(json['global']),
      storyEvents: (rawStoryEvents as List? ?? const <Object?>[])
          .map((value) => ChatroomV2StoryEvent.fromJson(asJsonMap(value)))
          .toList(growable: false),
      charactersMoved: (rawCharactersMoved as List? ?? const <Object?>[])
          .map(
            (value) => ChatroomV2CharacterMovement.fromJson(asJsonMap(value)),
          )
          .toList(growable: false),
      fallbackContent: asString(json['content']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'current_time': currentTime,
    'tick_no': tickNo,
    'sub_tick_no': subTickNo,
    'global': globalText,
    'story_events': storyEvents.map((event) => event.toJson()).toList(),
    'characters_moved': charactersMoved
        .map((movement) => movement.toJson())
        .toList(),
    if (fallbackContent.isNotEmpty) 'content': fallbackContent,
  };
}

class ChatroomEnvelope {
  const ChatroomEnvelope({
    required this.type,
    this.streamType = '',
    this.schemaVersion,
    this.eventId = '',
    this.ts,
    this.payload = const <String, dynamic>{},
    this.worldId = '',
    this.sessionId = '',
    this.locationId = '',
    this.userId = '',
    this.senderId = '',
    this.senderName = '',
    this.senderType = '',
    this.messageType = '',
    this.minAppVersion,
    this.createdAt = '',
    this.errNo = '',
    this.errMsg = '',
    this.currentTime = '',
    this.globalMsgId,
    this.msgId,
    this.locationMsgId,
    this.conversationRoundId,
    this.tickNo,
    this.subTickNo,
    this.clientMsgId = '',
    this.broadcast,
    this.wireProtocol = ChatroomProtocolVersion.legacy,
  });

  final String type;
  final String streamType;
  final int? schemaVersion;
  final String eventId;
  final int? ts;
  final Map<String, dynamic> payload;
  final String worldId;
  final String sessionId;
  final String locationId;
  final String userId;
  final String senderId;
  final String senderName;
  final String senderType;
  final String messageType;
  final int? minAppVersion;
  final String createdAt;
  final String errNo;
  final String errMsg;
  final String currentTime;
  final int? globalMsgId;
  final int? msgId;
  final int? locationMsgId;
  final int? conversationRoundId;
  final int? tickNo;
  final int? subTickNo;
  final String clientMsgId;
  final bool? broadcast;
  final ChatroomProtocolVersion wireProtocol;

  factory ChatroomEnvelope.fromJson(Map<String, dynamic> json) {
    return ChatroomEnvelope(
      type: asString(json['type']),
      streamType: asString(json['stream_type']),
      schemaVersion: json['schema_version'] == null
          ? null
          : asInt(json['schema_version']),
      eventId: asString(json['event_id']),
      ts: json['ts'] == null ? null : asInt(json['ts']),
      payload: _optionalJsonMap(json['payload']),
      worldId: asString(json['world_id']),
      sessionId: asString(json['session_id']),
      locationId: asString(json['location_id']),
      userId: asString(json['user_id']),
      senderId: asString(json['sender_id']),
      senderName: asString(json['sender_name']),
      senderType: asString(json['sender_type']),
      messageType: asString(json['message_type']),
      minAppVersion: json['min_app_version'] == null
          ? null
          : asInt(json['min_app_version']),
      createdAt: asString(json['created_at']),
      errNo: asString(json['err_no']),
      errMsg: asString(json['err_msg']),
      currentTime: _currentTime(json),
      globalMsgId: _optionalIntAlias(
        json,
        legacyKey: 'global_msg_id',
        v2Key: 'global_message_id',
      ),
      msgId: _optionalIntAlias(json, legacyKey: 'msg_id', v2Key: 'message_id'),
      locationMsgId: _optionalIntAlias(
        json,
        legacyKey: 'location_msg_id',
        v2Key: 'location_message_id',
      ),
      conversationRoundId: json['conversation_round_id'] == null
          ? null
          : asInt(json['conversation_round_id']),
      tickNo: json['tick_no'] == null ? null : asInt(json['tick_no']),
      subTickNo: json['sub_tick_no'] == null
          ? null
          : asInt(json['sub_tick_no']),
      clientMsgId: asString(json['client_msg_id']),
      broadcast: json.containsKey('broadcast')
          ? asBool(json['broadcast'])
          : null,
      wireProtocol: _looksLikeV2Envelope(json)
          ? ChatroomProtocolVersion.v2
          : ChatroomProtocolVersion.legacy,
    );
  }

  factory ChatroomEnvelope.fromV2Message(ChatroomV2Message message) {
    return ChatroomEnvelope(
      type: message.type,
      streamType: message.streamType,
      ts: message.ts,
      payload: message.payload,
      worldId: message.worldId,
      sessionId: message.sessionId,
      locationId: message.locationId,
      userId: message.userId,
      senderId: message.senderId,
      senderName: message.senderName,
      senderType: message.senderType,
      messageType: message.messageType,
      minAppVersion: message.minAppVersion,
      createdAt: message.createdAt,
      errNo: message.errNo.toString(),
      errMsg: message.errMsg,
      currentTime: message.currentTime.trim().isNotEmpty
          ? message.currentTime
          : _currentTime(message.payload),
      globalMsgId: message.globalMessageId,
      msgId: message.messageId,
      locationMsgId: message.locationMessageId,
      conversationRoundId: message.conversationRoundId,
      tickNo:
          message.tickNo ??
          (message.payload.containsKey('tick_no')
              ? asInt(message.payload['tick_no'])
              : null),
      subTickNo:
          message.subTickNo ??
          (message.payload.containsKey('sub_tick_no')
              ? asInt(message.payload['sub_tick_no'])
              : null),
      clientMsgId: message.clientMsgId,
      broadcast: message.payload.containsKey('broadcast')
          ? asBool(message.payload['broadcast'])
          : null,
      wireProtocol: ChatroomProtocolVersion.v2,
    );
  }

  factory ChatroomEnvelope.decode(String input) {
    try {
      if (isChatroomFrameOversized(input)) {
        throw const ChatroomProtocolException(
          'Envelope exceeds the maximum frame size',
        );
      }
      final decoded = jsonDecode(input);
      if (decoded is! Map) {
        throw const ChatroomProtocolException('Envelope is not a JSON object');
      }
      validateChatroomPayloadLimits(decoded, field: 'envelope');
      return ChatroomEnvelope.fromJson(asJsonMap(decoded));
    } on ChatroomProtocolException {
      rethrow;
    } catch (e) {
      throw ChatroomProtocolException('Invalid JSON envelope', error: e);
    }
  }

  String encode() {
    if (wireProtocol == ChatroomProtocolVersion.v2) {
      return toV2Message().encode();
    }
    final json = <String, Object?>{
      'type': type,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (eventId.isNotEmpty) 'event_id': eventId,
      'ts': ts ?? DateTime.now().millisecondsSinceEpoch,
      if (worldId.isNotEmpty) 'world_id': worldId,
      if (locationId.isNotEmpty) 'location_id': locationId,
      if (tickNo != null) 'tick_no': tickNo,
      if (subTickNo != null) 'sub_tick_no': subTickNo,
      if (payload.isNotEmpty) 'payload': payload,
    };
    return jsonEncode(json);
  }

  ChatroomV2Message toV2Message() {
    return ChatroomV2Message(
      type: type,
      streamType: streamType,
      ts: ts,
      worldId: worldId,
      locationId: locationId,
      sessionId: sessionId,
      globalMessageId: globalMsgId,
      messageId: msgId,
      locationMessageId: locationMsgId,
      conversationRoundId: conversationRoundId,
      tickNo: tickNo,
      subTickNo: subTickNo,
      senderType: senderType,
      senderId: senderId,
      senderName: senderName,
      userId: userId,
      clientMsgId: clientMsgId,
      messageType: messageType,
      minAppVersion: minAppVersion,
      createdAt: createdAt,
      currentTime: currentTime,
      payload: payload,
      errNo: asInt(errNo),
      errMsg: errMsg,
    );
  }

  Map<String, dynamic> get mergedPayload {
    final merged = <String, dynamic>{...payload};

    if (schemaVersion != null) merged['schema_version'] = schemaVersion;
    if (eventId.isNotEmpty) merged['event_id'] = eventId;
    if (ts != null) merged['ts'] = ts;
    if (worldId.isNotEmpty) merged['world_id'] = worldId;
    if (sessionId.isNotEmpty) merged['session_id'] = sessionId;
    if (locationId.isNotEmpty) merged['location_id'] = locationId;
    if (userId.isNotEmpty) merged['user_id'] = userId;
    if (senderId.isNotEmpty) merged['sender_id'] = senderId;
    if (senderName.isNotEmpty) merged['sender_name'] = senderName;
    if (senderType.isNotEmpty) merged['sender_type'] = senderType;
    if (messageType.isNotEmpty) merged['message_type'] = messageType;
    if (minAppVersion != null) merged['min_app_version'] = minAppVersion;
    if (createdAt.isNotEmpty) merged['created_at'] = createdAt;
    if (errNo.isNotEmpty) merged['err_no'] = errNo;
    if (errMsg.isNotEmpty) merged['err_msg'] = errMsg;
    if (currentTime.isNotEmpty) merged['current_time'] = currentTime;
    if (globalMsgId != null) {
      merged['global_msg_id'] = globalMsgId;
      merged['global_message_id'] = globalMsgId;
    }
    if (msgId != null) {
      merged['msg_id'] = msgId;
      merged['message_id'] = msgId;
    }
    if (locationMsgId != null) {
      merged['location_msg_id'] = locationMsgId;
      merged['location_message_id'] = locationMsgId;
    }
    if (conversationRoundId != null) {
      merged['conversation_round_id'] = conversationRoundId;
    }
    if (tickNo != null) merged['tick_no'] = tickNo;
    if (subTickNo != null) merged['sub_tick_no'] = subTickNo;
    if (clientMsgId.isNotEmpty) merged['client_msg_id'] = clientMsgId;
    if (broadcast != null) merged['broadcast'] = broadcast;
    merged.putIfAbsent('err_no', () => '');
    merged.putIfAbsent('err_msg', () => '');
    return merged;
  }
}

sealed class ChatroomEvent {
  const ChatroomEvent();
}

sealed class ChatroomPayloadEvent extends ChatroomEvent {
  const ChatroomPayloadEvent({
    required this.sessionId,
    required this.worldId,
    required this.locationId,
    required this.userId,
    required this.code,
    required this.codeMsg,
    required this.ts,
  });

  final String sessionId;
  final String worldId;
  final String locationId;
  final String userId;
  final int code;
  final String codeMsg;
  final DateTime? ts;

  bool get ok => code == 0;
}

class ChatroomJoined extends ChatroomPayloadEvent {
  const ChatroomJoined({
    required super.sessionId,
    required super.worldId,
    required super.locationId,
    required super.userId,
    required super.code,
    required super.codeMsg,
    required super.ts,
    required this.onlineUsers,
  });

  final List<ChatroomOnlineUser> onlineUsers;
}

class ChatroomDisconnected extends ChatroomEvent {
  const ChatroomDisconnected();
}

class ChatroomFailureEvent extends ChatroomEvent implements Exception {
  const ChatroomFailureEvent({
    required this.code,
    required this.message,
    this.detail = '',
    this.clientMsgId = '',
    this.sourceType = '',
    this.requestType = '',
    this.cause,
  });

  final String code;
  final String message;
  final String detail;
  final String clientMsgId;
  final String sourceType;
  final String requestType;
  final Object? cause;

  factory ChatroomFailureEvent.fromError(
    ChatroomErrorEvent error, {
    String requestType = '',
  }) {
    return ChatroomFailureEvent(
      code: error.code,
      message: error.message,
      sourceType: error.sourceType,
      requestType: requestType,
      cause: error.cause ?? error,
    );
  }

  factory ChatroomFailureEvent.fromPayloadEvent(
    ChatroomPayloadEvent event, {
    String sourceType = '',
    String requestType = '',
    String clientMsgId = '',
    Object? cause,
  }) {
    final ack = event is ChatroomAck ? event : null;
    return ChatroomFailureEvent(
      code: event.code.toString(),
      message: event.codeMsg.isEmpty ? 'Something went wrong' : event.codeMsg,
      detail: ack?.errorDetail ?? '',
      clientMsgId: clientMsgId.isNotEmpty
          ? clientMsgId
          : (ack?.clientMsgId ?? ''),
      sourceType: sourceType.isEmpty ? chatroomEventType(event) : sourceType,
      requestType: requestType,
      cause: cause ?? event,
    );
  }

  ChatroomFailureEvent withRequestType(String value) {
    return ChatroomFailureEvent(
      code: code,
      message: message,
      detail: detail,
      clientMsgId: clientMsgId,
      sourceType: sourceType,
      requestType: value,
      cause: cause,
    );
  }

  @override
  String toString() {
    final prefix = requestType.isEmpty
        ? sourceType
        : '$requestType/$sourceType';
    return 'ChatroomFailureEvent($prefix $code): $message';
  }
}

class ChatroomOnlineUser {
  const ChatroomOnlineUser({
    required this.userId,
    required this.senderId,
    required this.senderName,
  });

  final String userId;
  final String senderId;
  final String senderName;

  factory ChatroomOnlineUser.fromPayload(Map<String, dynamic> payload) {
    return ChatroomOnlineUser(
      userId: asString(payload['user_id']),
      senderId: asString(payload['sender_id']),
      senderName: asString(payload['sender_name']),
    );
  }
}

class ChatroomAck extends ChatroomPayloadEvent {
  const ChatroomAck({
    required super.sessionId,
    required super.worldId,
    required super.locationId,
    required super.userId,
    required super.code,
    required super.codeMsg,
    required super.ts,
    this.globalMessageId = 0,
    this.messageId = 0,
    this.locationMessageId = 0,
    this.conversationRoundId = '',
    required this.clientMsgId,
    this.errorDetail = '',
    this.cardConversationRoundId,
    this.regeneration,
    this.selection,
  });

  final int globalMessageId;
  final int messageId;
  final int locationMessageId;
  final String conversationRoundId;
  final String clientMsgId;
  final String errorDetail;
  final int? cardConversationRoundId;
  final ChatroomCardRegeneration? regeneration;
  final ChatroomCardSelection? selection;

  /// V2 ACKs are receipts only and deliberately leave these fields empty.
  bool get hasCanonicalMessageMetadata =>
      globalMessageId > 0 ||
      messageId > 0 ||
      locationMessageId > 0 ||
      conversationRoundId.isNotEmpty;

  factory ChatroomAck.fromPayload(Map<String, dynamic> payload) {
    return ChatroomAck.fromLegacyPayload(payload);
  }

  /// Explicit adapter for the legacy ACK shape, whose receipt id lives in
  /// payload and which may also contain canonical message metadata.
  factory ChatroomAck.fromLegacyPayload(Map<String, dynamic> payload) {
    return ChatroomAck(
      sessionId: asString(payload['session_id']),
      worldId: _worldId(payload),
      locationId: asString(payload['location_id']),
      userId: asString(payload['user_id']),
      code: _wsCode(payload),
      codeMsg: asString(payload['err_msg']),
      ts: asDateTime(payload['ts']),
      globalMessageId: asInt(payload['global_msg_id']),
      messageId: asInt(payload['msg_id']),
      locationMessageId: asInt(payload['location_msg_id']),
      conversationRoundId: asString(payload['conversation_round_id']),
      clientMsgId: asString(payload['client_msg_id']),
      errorDetail: asString(payload['err_detail']),
    );
  }

  factory ChatroomAck.fromV2Message(ChatroomV2Message message) {
    final regeneration = message.payload['regeneration'] == null
        ? null
        : ChatroomCardRegeneration.fromJson(message.payload['regeneration']);
    final selection = message.payload['selection'] == null
        ? null
        : ChatroomCardSelection.fromJson(message.payload['selection']);
    if ((regeneration != null && selection != null) ||
        (regeneration != null &&
            regeneration.conversationRoundId != message.conversationRoundId) ||
        (selection != null &&
            selection.conversationRoundId != message.conversationRoundId)) {
      throw const FormatException('Mismatched card receipt');
    }
    return ChatroomAck(
      sessionId: message.sessionId,
      worldId: message.worldId,
      locationId: message.locationId,
      userId: message.userId,
      code: message.errNo,
      codeMsg: message.errMsg,
      ts: asDateTime(message.ts),
      clientMsgId: message.clientMsgId,
      errorDetail: asString(message.payload['err_detail']),
      cardConversationRoundId: message.conversationRoundId,
      regeneration: regeneration,
      selection: selection,
    );
  }
}

class ChatroomBalanceLow extends ChatroomEvent {
  const ChatroomBalanceLow({required this.balanceCent, required this.message});

  final int balanceCent;
  final String message;

  factory ChatroomBalanceLow.fromEnvelope(ChatroomEnvelope envelope) {
    final payload = envelope.mergedPayload;
    return ChatroomBalanceLow(
      balanceCent: requireGemCent(
        payload['balance_cent'],
        fieldName: 'balance_low.balance_cent',
      ),
      message: asString(payload['message']),
    );
  }
}

/// V2-only control event announcing that the server started a conversation
/// round on behalf of the user.
/// Control events: never materialized as message bubbles or stream chunks.
class ChatroomLlmMessageUpdated extends ChatroomEvent {
  const ChatroomLlmMessageUpdated({
    required this.worldId,
    required this.locationId,
    required this.globalMessageId,
    required this.messageId,
    required this.locationMessageId,
    required this.conversationRoundId,
    required this.content,
    this.status = 20,
    this.errNo = 0,
  });
  final String worldId;
  final String locationId;
  final int globalMessageId;
  final int messageId;
  final int locationMessageId;
  final int conversationRoundId;
  final String content;
  final int status;
  final int errNo;

  factory ChatroomLlmMessageUpdated.fromV2Message(ChatroomV2Message message) {
    _validateMutationLocation(message);
    final content = message.payload['content'];
    if (content is! String ||
        content.trim().isEmpty ||
        message.payload['status'] != 20) {
      throw const ChatroomProtocolException(
        'Invalid llm_message_updated payload',
      );
    }
    return ChatroomLlmMessageUpdated(
      worldId: message.worldId,
      locationId: message.locationId,
      globalMessageId: _mutationId(message.globalMessageId),
      messageId: _mutationId(message.messageId),
      locationMessageId: _mutationId(message.locationMessageId),
      conversationRoundId: _mutationId(message.conversationRoundId),
      content: content,
      errNo: message.errNo,
    );
  }
}

class ChatroomConversationRangeUpdated extends ChatroomEvent {
  const ChatroomConversationRangeUpdated({
    required this.worldId,
    required this.locationId,
    required this.startConversationRoundId,
    required this.endConversationRoundId,
    required this.newestMessageId,
    this.errNo = 0,
  });
  final String worldId;
  final String locationId;
  final int startConversationRoundId;
  final int endConversationRoundId;
  final int newestMessageId;
  final int errNo;

  factory ChatroomConversationRangeUpdated.fromV2Message(
    ChatroomV2Message message,
  ) {
    _validateMutationLocation(message);
    final start = _mutationId(message.payload['start_conversation_round_id']);
    final end = _mutationId(message.payload['end_conversation_round_id']);
    final newest = _mutationId(
      message.payload['newest_message_id'],
      allowZero: true,
    );
    if (end < start) {
      throw const ChatroomProtocolException('Reversed conversation range');
    }
    return ChatroomConversationRangeUpdated(
      worldId: message.worldId,
      locationId: message.locationId,
      startConversationRoundId: start,
      endConversationRoundId: end,
      newestMessageId: newest,
      errNo: message.errNo,
    );
  }
}

void _validateMutationLocation(ChatroomV2Message message) {
  if (message.worldId.trim().isEmpty ||
      message.locationId.trim().isEmpty ||
      message.streamType.isNotEmpty) {
    throw const ChatroomProtocolException(
      'Mutation event requires world/location and empty stream_type',
    );
  }
}

int _mutationId(Object? value, {bool allowZero = false}) {
  if (value is! int || value < (allowZero ? 0 : 1)) {
    throw const ChatroomProtocolException(
      'Mutation event requires integer IDs',
    );
  }
  return value;
}

class ChatroomWaitingConversationRound extends ChatroomPayloadEvent {
  const ChatroomWaitingConversationRound({
    required super.sessionId,
    required super.worldId,
    required super.locationId,
    required super.userId,
    required super.code,
    required super.codeMsg,
    required super.ts,
    required this.conversationRoundId,
  });

  final String conversationRoundId;

  factory ChatroomWaitingConversationRound.fromV2Message(
    ChatroomV2Message message,
  ) {
    final locationId = message.locationId.trim();
    final conversationRoundId = _stringId(message.conversationRoundId);
    if (locationId.isEmpty) {
      throw const ChatroomProtocolException(
        'waiting_conversation_round location_id is required',
      );
    }
    if (conversationRoundId.isEmpty) {
      throw const ChatroomProtocolException(
        'waiting_conversation_round conversation_round_id is required',
      );
    }
    return ChatroomWaitingConversationRound(
      sessionId: message.sessionId,
      worldId: message.worldId,
      locationId: locationId,
      userId: message.userId,
      code: message.errNo,
      codeMsg: message.errMsg,
      ts: asDateTime(message.ts),
      conversationRoundId: conversationRoundId,
    );
  }
}

/// V2-only control event announcing that a conversation round reached a
/// terminal state. Its routing fields intentionally mirror
/// [ChatroomWaitingConversationRound].
class ChatroomEndConversationRound extends ChatroomPayloadEvent {
  const ChatroomEndConversationRound({
    required super.sessionId,
    required super.worldId,
    required super.locationId,
    required super.userId,
    required super.code,
    required super.codeMsg,
    required super.ts,
    required this.conversationRoundId,
  });

  final String conversationRoundId;

  factory ChatroomEndConversationRound.fromV2Message(
    ChatroomV2Message message,
  ) {
    final locationId = message.locationId.trim();
    final conversationRoundId = _stringId(message.conversationRoundId);
    if (locationId.isEmpty) {
      throw const ChatroomProtocolException(
        'end_conversation_round location_id is required',
      );
    }
    if (conversationRoundId.isEmpty) {
      throw const ChatroomProtocolException(
        'end_conversation_round conversation_round_id is required',
      );
    }
    return ChatroomEndConversationRound(
      sessionId: message.sessionId,
      worldId: message.worldId,
      locationId: locationId,
      userId: message.userId,
      code: message.errNo,
      codeMsg: message.errMsg,
      ts: asDateTime(message.ts),
      conversationRoundId: conversationRoundId,
    );
  }
}

sealed class ChatroomMessageEvent extends ChatroomPayloadEvent {
  const ChatroomMessageEvent({
    required super.sessionId,
    required super.worldId,
    required super.locationId,
    required super.userId,
    required super.code,
    required super.codeMsg,
    required super.ts,
    this.globalMessageId = 0,
    required this.messageId,
    this.locationMessageId = 0,
    required this.conversationRoundId,
    required this.roundOrder,
    required this.senderType,
    required this.senderId,
    required this.senderName,
    required this.content,
    this.messageType = chatroomTextMessageType,
    required this.broadcast,
    this.businessType = '',
    this.streamType = '',
    this.minAppVersion,
    this.rawPayload = const <String, dynamic>{},
  });

  final int globalMessageId;
  final int messageId;
  final int locationMessageId;
  final String conversationRoundId;
  final int roundOrder;
  final String senderType;
  final String senderId;
  final String senderName;
  final String content;
  final String messageType;
  final bool broadcast;
  final String businessType;
  final String streamType;
  final int? minAppVersion;
  final Map<String, dynamic> rawPayload;
}

class ChatroomUserMessage extends ChatroomMessageEvent {
  const ChatroomUserMessage({
    required super.sessionId,
    required super.worldId,
    required super.locationId,
    required super.userId,
    required super.code,
    required super.codeMsg,
    required super.ts,
    super.globalMessageId,
    required super.messageId,
    super.locationMessageId,
    required super.conversationRoundId,
    required super.roundOrder,
    required super.senderType,
    required super.senderId,
    required super.senderName,
    required super.content,
    super.messageType,
    required super.broadcast,
    super.businessType,
    super.streamType,
    super.minAppVersion,
    super.rawPayload,
    required this.currentTime,
    required this.clientMsgId,
    required this.createdAt,
  });

  final String currentTime;
  final String clientMsgId;
  final DateTime? createdAt;

  factory ChatroomUserMessage.fromEnvelope(ChatroomEnvelope envelope) {
    final payload = envelope.mergedPayload;
    return ChatroomUserMessage(
      sessionId: asString(payload['session_id']),
      worldId: _worldId(payload),
      locationId: asString(payload['location_id']),
      userId: asString(payload['user_id']),
      code: _wsCode(payload),
      codeMsg: asString(payload['err_msg']),
      ts: asDateTime(payload['ts'] ?? envelope.ts),
      globalMessageId: asInt(payload['global_msg_id']),
      messageId: asInt(payload['msg_id']),
      locationMessageId: asInt(payload['location_msg_id']),
      conversationRoundId: asString(payload['conversation_round_id']),
      roundOrder: 0,
      senderType: asString(payload['sender_type'], fallback: 'user'),
      senderId: asString(payload['sender_id']),
      senderName: asString(payload['sender_name']),
      content: asString(payload['content']),
      currentTime: _currentTime(payload),
      broadcast: asBool(payload['broadcast']),
      clientMsgId: asString(payload['client_msg_id']),
      createdAt: asDateTime(payload['ts'] ?? envelope.ts),
    );
  }

  factory ChatroomUserMessage.fromV2Message(ChatroomV2Message message) {
    final senderId = message.senderId;
    return ChatroomUserMessage(
      sessionId: message.sessionId,
      worldId: message.worldId,
      locationId: message.locationId,
      userId: message.userId,
      code: message.errNo,
      codeMsg: message.errMsg,
      ts: asDateTime(message.ts),
      globalMessageId: message.globalMessageId ?? 0,
      messageId: message.messageId ?? 0,
      locationMessageId: message.locationMessageId ?? 0,
      conversationRoundId: _stringId(message.conversationRoundId),
      roundOrder: asInt(message.payload['round_order']),
      senderType: message.senderType.isEmpty
          ? message.type
          : message.senderType,
      senderId: senderId,
      senderName: message.senderName,
      content: asString(message.payload['content']),
      messageType: resolveIncomingChatroomMessageType(
        hasMessageTypeField: message.messageType.isNotEmpty,
        rawMessageType: message.messageType,
        senderId: senderId,
      ),
      broadcast: asBool(message.payload['broadcast']),
      businessType: message.type,
      streamType: message.streamType,
      minAppVersion: message.minAppVersion,
      rawPayload: message.payload,
      currentTime: _currentTime(message.payload),
      clientMsgId: message.clientMsgId,
      createdAt: asDateTime(
        message.createdAt.isEmpty ? message.ts : message.createdAt,
      ),
    );
  }
}

class ChatroomUserEnterLocationMessage extends ChatroomMessageEvent {
  const ChatroomUserEnterLocationMessage({
    required super.sessionId,
    required super.worldId,
    required super.locationId,
    required super.userId,
    required super.code,
    required super.codeMsg,
    required super.ts,
    super.globalMessageId,
    required super.messageId,
    super.locationMessageId,
    required super.conversationRoundId,
    required super.roundOrder,
    required super.senderType,
    required super.senderId,
    required super.senderName,
    required super.content,
    super.messageType,
    required super.broadcast,
    required this.currentTime,
    required this.createdAt,
  });

  final String currentTime;
  final DateTime? createdAt;

  factory ChatroomUserEnterLocationMessage.fromEnvelope(
    ChatroomEnvelope envelope,
  ) {
    final payload = envelope.mergedPayload;
    final messageId = envelope.msgId ?? 0;
    final locationMessageId = envelope.locationMsgId ?? 0;
    final locationId = envelope.locationId.trim();
    final senderId = envelope.senderId.trim();
    if (messageId <= 0) {
      throw const ChatroomProtocolException(
        'user_enter_location msg_id must be a positive integer',
      );
    }
    if (locationMessageId <= 0) {
      throw const ChatroomProtocolException(
        'user_enter_location location_msg_id must be a positive integer',
      );
    }
    if (locationId.isEmpty) {
      throw const ChatroomProtocolException(
        'user_enter_location location_id is required',
      );
    }
    if (senderId.isEmpty) {
      throw const ChatroomProtocolException(
        'user_enter_location sender_id is required',
      );
    }
    return ChatroomUserEnterLocationMessage(
      sessionId: envelope.sessionId,
      worldId: envelope.worldId,
      locationId: locationId,
      userId: envelope.userId,
      code: _wsCode(payload),
      codeMsg: envelope.errMsg,
      ts: asDateTime(envelope.ts),
      globalMessageId: envelope.globalMsgId ?? 0,
      messageId: messageId,
      locationMessageId: locationMessageId,
      conversationRoundId: asString(envelope.conversationRoundId),
      roundOrder: asInt(payload['round_order']),
      senderType: chatroomUserEnterLocationSenderType,
      senderId: senderId,
      senderName: envelope.senderName,
      content: asString(payload['content']),
      messageType: resolveIncomingChatroomMessageType(
        hasMessageTypeField: envelope.payload.containsKey('message_type'),
        rawMessageType: envelope.payload['message_type'],
        senderId: senderId,
      ),
      broadcast: envelope.broadcast ?? false,
      currentTime: envelope.currentTime,
      createdAt: asDateTime(envelope.ts),
    );
  }
}

class ChatroomNarratorMessage extends ChatroomMessageEvent {
  const ChatroomNarratorMessage({
    required super.sessionId,
    required super.worldId,
    required super.locationId,
    required super.userId,
    required super.code,
    required super.codeMsg,
    required super.ts,
    super.globalMessageId,
    required super.messageId,
    super.locationMessageId,
    required super.conversationRoundId,
    required super.roundOrder,
    required super.senderType,
    required super.senderId,
    required super.senderName,
    required super.content,
    super.messageType,
    required super.broadcast,
    super.businessType,
    super.streamType,
    super.minAppVersion,
    super.rawPayload,
    required this.currentTime,
    required this.createdAt,
  });

  final String currentTime;
  final DateTime? createdAt;

  factory ChatroomNarratorMessage.fromEnvelope(ChatroomEnvelope envelope) {
    final payload = envelope.mergedPayload;
    final senderId = asString(payload['sender_id']);
    return ChatroomNarratorMessage(
      sessionId: asString(payload['session_id']),
      worldId: _worldId(payload),
      locationId: asString(payload['location_id']),
      userId: asString(payload['user_id']),
      code: _wsCode(payload),
      codeMsg: asString(payload['err_msg']),
      ts: asDateTime(payload['ts'] ?? envelope.ts),
      globalMessageId: asInt(payload['global_msg_id']),
      messageId: asInt(payload['msg_id']),
      locationMessageId: asInt(payload['location_msg_id']),
      conversationRoundId: asString(payload['conversation_round_id']),
      roundOrder: 0,
      senderType: asString(payload['sender_type'], fallback: 'narrator'),
      senderId: senderId,
      senderName: asString(payload['sender_name'], fallback: 'Narrator'),
      content: asString(payload['content']),
      messageType: resolveIncomingChatroomMessageType(
        hasMessageTypeField: payload.containsKey('message_type'),
        rawMessageType: payload['message_type'],
        senderId: senderId,
      ),
      currentTime: _currentTime(payload),
      broadcast: asBool(payload['broadcast']),
      createdAt: asDateTime(payload['ts'] ?? envelope.ts),
    );
  }

  factory ChatroomNarratorMessage.fromV2Message(ChatroomV2Message message) {
    final senderId = message.senderId;
    final senderType = message.senderType.isEmpty
        ? message.type
        : message.senderType;
    return ChatroomNarratorMessage(
      sessionId: message.sessionId,
      worldId: message.worldId,
      locationId: message.locationId,
      userId: message.userId,
      code: message.errNo,
      codeMsg: message.errMsg,
      ts: asDateTime(message.ts),
      globalMessageId: message.globalMessageId ?? 0,
      messageId: message.messageId ?? 0,
      locationMessageId: message.locationMessageId ?? 0,
      conversationRoundId: _stringId(message.conversationRoundId),
      roundOrder: asInt(message.payload['round_order']),
      senderType: senderType,
      senderId: senderId,
      senderName: message.senderName.isEmpty ? 'AI' : message.senderName,
      content: asString(message.payload['content']),
      messageType: resolveIncomingChatroomMessageType(
        hasMessageTypeField: message.messageType.isNotEmpty,
        rawMessageType: message.messageType,
        senderId: senderId,
      ),
      currentTime: _currentTime(message.payload),
      broadcast: asBool(message.payload['broadcast']),
      businessType: message.type,
      streamType: message.streamType,
      minAppVersion: message.minAppVersion,
      rawPayload: message.payload,
      createdAt: asDateTime(
        message.createdAt.isEmpty ? message.ts : message.createdAt,
      ),
    );
  }
}

class ChatroomTickAdvanceMessage extends ChatroomMessageEvent {
  const ChatroomTickAdvanceMessage({
    required super.sessionId,
    required super.worldId,
    required super.locationId,
    required super.userId,
    required super.code,
    required super.codeMsg,
    required super.ts,
    super.globalMessageId,
    required super.messageId,
    super.locationMessageId,
    required super.conversationRoundId,
    required super.roundOrder,
    required super.senderType,
    required super.senderId,
    required super.senderName,
    required super.content,
    super.messageType,
    required super.broadcast,
    super.businessType,
    super.streamType,
    super.minAppVersion,
    super.rawPayload,
    required this.tickNo,
    required this.subTickNo,
    required this.currentTime,
    this.v2TickPayload,
  });

  final int tickNo;
  final int subTickNo;
  final String currentTime;
  final ChatroomV2TickPayload? v2TickPayload;

  bool get isV2LocationTick => v2TickPayload != null;

  factory ChatroomTickAdvanceMessage.fromEnvelope(ChatroomEnvelope envelope) {
    final payload = envelope.mergedPayload;
    final currentTime = _currentTime(payload);
    return ChatroomTickAdvanceMessage(
      sessionId: asString(payload['session_id']),
      worldId: _worldId(payload),
      locationId: asString(payload['location_id']),
      userId: asString(payload['user_id']),
      code: _wsCode(payload),
      codeMsg: asString(payload['err_msg']),
      ts: asDateTime(payload['ts'] ?? envelope.ts),
      globalMessageId: asInt(payload['global_msg_id']),
      messageId: asInt(payload['msg_id']),
      locationMessageId: asInt(payload['location_msg_id']),
      conversationRoundId: asString(payload['conversation_round_id']),
      roundOrder: 0,
      senderType: 'tick',
      senderId: 'tick',
      senderName: 'Time',
      content: asString(payload['content'], fallback: currentTime),
      broadcast: asBool(payload['broadcast']),
      tickNo: asInt(payload['tick_no']),
      subTickNo: asInt(payload['sub_tick_no']),
      currentTime: currentTime,
    );
  }

  factory ChatroomTickAdvanceMessage.fromV2Message(ChatroomV2Message message) {
    final tickPayload = ChatroomV2TickPayload.fromJson(message.payload);
    final content = tickPayload.fallbackContent.isNotEmpty
        ? tickPayload.fallbackContent
        : (tickPayload.globalText.isNotEmpty
              ? tickPayload.globalText
              : tickPayload.currentTime);
    return ChatroomTickAdvanceMessage(
      sessionId: message.sessionId,
      worldId: message.worldId,
      locationId: message.locationId,
      userId: message.userId,
      code: message.errNo,
      codeMsg: message.errMsg,
      ts: asDateTime(message.ts),
      globalMessageId: message.globalMessageId ?? 0,
      messageId: message.messageId ?? 0,
      locationMessageId: message.locationMessageId ?? 0,
      conversationRoundId: _stringId(message.conversationRoundId),
      roundOrder: asInt(message.payload['round_order']),
      senderType: message.senderType.isEmpty ? 'tick' : message.senderType,
      senderId: message.senderId.isEmpty ? 'tick' : message.senderId,
      senderName: message.senderName.isEmpty ? 'SubTick' : message.senderName,
      content: content,
      messageType: resolveIncomingChatroomMessageType(
        hasMessageTypeField: message.messageType.isNotEmpty,
        rawMessageType: message.messageType,
        senderId: message.senderId,
      ),
      broadcast: asBool(message.payload['broadcast']),
      businessType: message.type,
      streamType: message.streamType,
      minAppVersion: message.minAppVersion,
      rawPayload: message.payload,
      tickNo: tickPayload.tickNo,
      subTickNo: tickPayload.subTickNo,
      currentTime: tickPayload.currentTime,
      v2TickPayload: tickPayload,
    );
  }
}

class ChatroomStreamIdentity {
  const ChatroomStreamIdentity({
    this.worldId = '',
    this.locationId = '',
    this.sessionId = '',
    this.messageId = 0,
    this.conversationRoundId = '',
    this.senderId = '',
  });

  final String worldId;
  final String locationId;
  final String sessionId;
  final int messageId;
  final String conversationRoundId;
  final String senderId;

  bool get hasStableMessageId => messageId > 0;
  bool get hasStableRoundId => conversationRoundId.isNotEmpty;
  bool get hasStableDiscriminator => hasStableMessageId || hasStableRoundId;

  /// Returns a collision-resistant key when the server supplied a stable id.
  /// Cursorless stream frames must use unique-candidate matching instead.
  String? get stableKey {
    if (!hasStableDiscriminator) return null;
    final discriminator = hasStableRoundId
        ? 'round:$conversationRoundId'
        : 'message:$messageId';
    return '$worldId|$locationId|$sessionId|$senderId|$discriminator';
  }
}

class ChatroomAiStreamStart extends ChatroomEvent {
  const ChatroomAiStreamStart({
    this.worldId = '',
    required this.sessionId,
    required this.locationId,
    this.globalMessageId = 0,
    required this.messageId,
    this.locationMessageId = 0,
    required this.conversationRoundId,
    required this.roundOrder,
    required this.senderType,
    required this.senderId,
    required this.senderName,
    required this.currentTime,
    this.businessType = '',
    this.streamType = 'llm_stream_start',
    this.messageType = '',
    this.minAppVersion,
    this.rawPayload = const <String, dynamic>{},
  });

  final String worldId;
  final String sessionId;
  final String locationId;
  final int globalMessageId;
  final int messageId;
  final int locationMessageId;
  final String conversationRoundId;
  final int roundOrder;
  final String senderType;
  final String senderId;
  final String senderName;
  final String currentTime;
  final String businessType;
  final String streamType;
  final String messageType;
  final int? minAppVersion;
  final Map<String, dynamic> rawPayload;

  ChatroomStreamIdentity get identity => ChatroomStreamIdentity(
    worldId: worldId,
    locationId: locationId,
    sessionId: sessionId,
    messageId: messageId,
    conversationRoundId: conversationRoundId,
    senderId: senderId,
  );

  factory ChatroomAiStreamStart.fromEnvelope(ChatroomEnvelope envelope) {
    final payload = envelope.mergedPayload;
    final roundId = asString(payload['conversation_round_id']);
    return ChatroomAiStreamStart(
      sessionId: asString(payload['session_id']),
      locationId: asString(payload['location_id']),
      globalMessageId: asInt(payload['global_msg_id']),
      messageId: asInt(payload['msg_id']),
      locationMessageId: asInt(payload['location_msg_id']),
      conversationRoundId: roundId,
      roundOrder: 0,
      senderType: asString(payload['sender_type'], fallback: 'character'),
      senderId: asString(payload['sender_id']),
      senderName: asString(payload['sender_name'], fallback: 'AI'),
      currentTime: _currentTime(payload),
    );
  }

  factory ChatroomAiStreamStart.fromV2Message(ChatroomV2Message message) {
    return ChatroomAiStreamStart(
      worldId: message.worldId,
      sessionId: message.sessionId,
      locationId: message.locationId,
      globalMessageId: message.globalMessageId ?? 0,
      messageId: message.messageId ?? 0,
      locationMessageId: message.locationMessageId ?? 0,
      conversationRoundId: _stringId(message.conversationRoundId),
      roundOrder: asInt(message.payload['round_order']),
      senderType: message.senderType.isEmpty
          ? message.type
          : message.senderType,
      senderId: message.senderId,
      senderName: message.senderName.isEmpty ? 'AI' : message.senderName,
      currentTime: _currentTime(message.payload),
      businessType: message.type,
      streamType: message.streamType,
      messageType: message.messageType,
      minAppVersion: message.minAppVersion,
      rawPayload: message.payload,
    );
  }
}

class ChatroomAiStreamChunk extends ChatroomEvent {
  const ChatroomAiStreamChunk({
    this.worldId = '',
    required this.sessionId,
    required this.locationId,
    this.globalMessageId = 0,
    required this.messageId,
    this.locationMessageId = 0,
    required this.conversationRoundId,
    required this.senderId,
    required this.seq,
    required this.chunk,
    required this.isDelta,
    required this.currentTime,
    this.businessType = '',
    this.streamType = 'llm_chunk',
    this.messageType = '',
    this.minAppVersion,
    this.rawPayload = const <String, dynamic>{},
  });

  final String worldId;
  final String sessionId;
  final String locationId;
  final int globalMessageId;
  final int messageId;
  final int locationMessageId;
  final String conversationRoundId;
  final String senderId;
  final int seq;
  final String chunk;
  final bool isDelta;
  final String currentTime;
  final String businessType;
  final String streamType;
  final String messageType;
  final int? minAppVersion;
  final Map<String, dynamic> rawPayload;

  ChatroomStreamIdentity get identity => ChatroomStreamIdentity(
    worldId: worldId,
    locationId: locationId,
    sessionId: sessionId,
    messageId: messageId,
    conversationRoundId: conversationRoundId,
    senderId: senderId,
  );

  factory ChatroomAiStreamChunk.fromEnvelope(ChatroomEnvelope envelope) {
    final payload = envelope.mergedPayload;
    return ChatroomAiStreamChunk(
      sessionId: asString(payload['session_id']),
      locationId: asString(payload['location_id']),
      globalMessageId: asInt(payload['global_msg_id']),
      messageId: asInt(payload['msg_id']),
      locationMessageId: asInt(payload['location_msg_id']),
      conversationRoundId: asString(payload['conversation_round_id']),
      senderId: asString(payload['sender_id']),
      seq: asInt(payload['seq']),
      chunk: asString(payload['content']),
      isDelta: true,
      currentTime: _currentTime(payload),
    );
  }

  factory ChatroomAiStreamChunk.fromV2Message(ChatroomV2Message message) {
    return ChatroomAiStreamChunk(
      worldId: message.worldId,
      sessionId: message.sessionId,
      locationId: message.locationId,
      globalMessageId: message.globalMessageId ?? 0,
      messageId: message.messageId ?? 0,
      locationMessageId: message.locationMessageId ?? 0,
      conversationRoundId: _stringId(message.conversationRoundId),
      senderId: message.senderId,
      seq: asInt(message.payload['seq']),
      chunk: asString(message.payload['content']),
      isDelta:
          !message.payload.containsKey('is_delta') ||
          asBool(message.payload['is_delta']),
      currentTime: _currentTime(message.payload),
      businessType: message.type,
      streamType: message.streamType,
      messageType: message.messageType,
      minAppVersion: message.minAppVersion,
      rawPayload: message.payload,
    );
  }
}

class ChatroomAiStreamEnd extends ChatroomEvent {
  const ChatroomAiStreamEnd({
    this.worldId = '',
    required this.sessionId,
    required this.locationId,
    this.globalMessageId = 0,
    required this.messageId,
    this.locationMessageId = 0,
    required this.conversationRoundId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.currentTime,
    this.businessType = '',
    this.streamType = 'llm_stream_end',
    this.messageType = '',
    this.minAppVersion,
    this.rawPayload = const <String, dynamic>{},
  });

  final String worldId;
  final String sessionId;
  final String locationId;
  final int globalMessageId;
  final int messageId;
  final int locationMessageId;
  final String conversationRoundId;
  final String senderId;
  final String content;
  final DateTime? createdAt;
  final String currentTime;
  final String businessType;
  final String streamType;
  final String messageType;
  final int? minAppVersion;
  final Map<String, dynamic> rawPayload;

  ChatroomStreamIdentity get identity => ChatroomStreamIdentity(
    worldId: worldId,
    locationId: locationId,
    sessionId: sessionId,
    messageId: messageId,
    conversationRoundId: conversationRoundId,
    senderId: senderId,
  );

  factory ChatroomAiStreamEnd.fromEnvelope(ChatroomEnvelope envelope) {
    final payload = envelope.mergedPayload;
    return ChatroomAiStreamEnd(
      sessionId: asString(payload['session_id']),
      locationId: asString(payload['location_id']),
      globalMessageId: asInt(payload['global_msg_id']),
      messageId: asInt(payload['msg_id']),
      locationMessageId: asInt(payload['location_msg_id']),
      conversationRoundId: asString(payload['conversation_round_id']),
      senderId: asString(payload['sender_id']),
      content: asString(payload['content']),
      createdAt: asDateTime(payload['ts'] ?? envelope.ts),
      currentTime: _currentTime(payload),
    );
  }

  factory ChatroomAiStreamEnd.fromV2Message(ChatroomV2Message message) {
    return ChatroomAiStreamEnd(
      worldId: message.worldId,
      sessionId: message.sessionId,
      locationId: message.locationId,
      globalMessageId: message.globalMessageId ?? 0,
      messageId: message.messageId ?? 0,
      locationMessageId: message.locationMessageId ?? 0,
      conversationRoundId: _stringId(message.conversationRoundId),
      senderId: message.senderId,
      content: asString(message.payload['content']),
      createdAt: asDateTime(
        message.createdAt.isEmpty ? message.ts : message.createdAt,
      ),
      currentTime: _currentTime(message.payload),
      businessType: message.type,
      streamType: message.streamType,
      messageType: message.messageType,
      minAppVersion: message.minAppVersion,
      rawPayload: message.payload,
    );
  }
}

class ChatroomWorldNotification extends ChatroomEvent {
  const ChatroomWorldNotification({
    required this.worldId,
    required this.locationId,
    required this.eventType,
    this.schemaVersion,
    this.eventId = '',
    required this.title,
    required this.summary,
    required this.detailUrl,
    required this.ts,
    required this.broadcast,
    this.currentTime = '',
    this.timelinePayload,
  });

  final String worldId;
  final String locationId;
  final String eventType;
  final int? schemaVersion;
  final String eventId;
  final String title;
  final String summary;
  final String detailUrl;
  final DateTime? ts;
  final bool broadcast;
  final String currentTime;
  final ChatroomTimelinePayload? timelinePayload;

  factory ChatroomWorldNotification.fromEnvelope(ChatroomEnvelope envelope) {
    final payload = envelope.mergedPayload;
    ChatroomTimelinePayload? timelinePayload;
    if (isChatroomTimelinePayloadSenderType(envelope.type)) {
      try {
        timelinePayload = decodeChatroomTimelinePayload(
          senderType: envelope.type,
          rawPayload: envelope.payload,
        );
      } catch (error) {
        throw ChatroomProtocolException(
          'Invalid ${envelope.type} payload',
          error: error,
        );
      }
    }
    return ChatroomWorldNotification(
      worldId: asString(payload['world_id'], fallback: envelope.worldId),
      locationId: asString(payload['location_id']),
      eventType: asString(payload['event_type'], fallback: envelope.type),
      schemaVersion: envelope.schemaVersion,
      eventId: envelope.eventId,
      title: asString(payload['title']),
      summary: asString(payload['summary']),
      detailUrl: asString(payload['detail_url']),
      ts: asDateTime(payload['ts'] ?? envelope.ts),
      broadcast: asBool(payload['broadcast']),
      currentTime: _currentTime(payload),
      timelinePayload: timelinePayload,
    );
  }
}

class ChatroomStoryEventsMessage extends ChatroomMessageEvent {
  const ChatroomStoryEventsMessage({
    required super.sessionId,
    required super.worldId,
    required super.locationId,
    required super.userId,
    required super.code,
    required super.codeMsg,
    required super.ts,
    super.globalMessageId,
    required super.messageId,
    super.locationMessageId,
    required super.conversationRoundId,
    required super.roundOrder,
    required super.senderType,
    required super.senderId,
    required super.senderName,
    required super.content,
    super.messageType,
    required super.broadcast,
    required this.schemaVersion,
    required this.eventId,
    required this.tickNo,
    required this.subTickNo,
    required this.currentTime,
    required this.createdAt,
    required this.timelinePayload,
  });

  final int? schemaVersion;
  final String eventId;
  final int tickNo;
  final int subTickNo;
  final String currentTime;
  final DateTime? createdAt;
  final ChatroomStoryEventsPayload timelinePayload;

  factory ChatroomStoryEventsMessage.fromEnvelope(ChatroomEnvelope envelope) {
    final payload = envelope.mergedPayload;
    final messageId = asInt(payload['msg_id']);
    if (messageId <= 0) {
      throw const ChatroomProtocolException(
        'story_events msg_id must be a positive integer',
      );
    }
    late final ChatroomStoryEventsPayload timelinePayload;
    try {
      final decoded = decodeChatroomTimelinePayload(
        senderType: chatroomStoryEventsSenderType,
        rawPayload: envelope.payload,
      );
      if (decoded is! ChatroomStoryEventsPayload) {
        throw const FormatException('story_events payload type mismatch');
      }
      timelinePayload = decoded;
    } catch (error) {
      throw ChatroomProtocolException(
        'Invalid story_events payload',
        error: error,
      );
    }
    final senderId = asString(payload['sender_id'], fallback: 'sub_tick');
    return ChatroomStoryEventsMessage(
      sessionId: asString(payload['session_id']),
      worldId: _worldId(payload),
      locationId: timelinePayload.locationId,
      userId: asString(payload['user_id']),
      code: _wsCode(payload),
      codeMsg: asString(payload['err_msg']),
      ts: asDateTime(payload['ts'] ?? envelope.ts),
      globalMessageId: asInt(payload['global_msg_id']),
      messageId: messageId,
      locationMessageId: asInt(payload['location_msg_id']),
      conversationRoundId: asString(payload['conversation_round_id']),
      roundOrder: asInt(payload['round_order']),
      senderType: chatroomStoryEventsSenderType,
      senderId: senderId,
      senderName: asString(payload['sender_name'], fallback: senderId),
      content: encodeChatroomTimelinePayload(timelinePayload),
      broadcast: asBool(payload['broadcast']),
      schemaVersion: envelope.schemaVersion,
      eventId: envelope.eventId,
      tickNo: asInt(payload['tick_no']),
      subTickNo: asInt(payload['sub_tick_no']),
      currentTime: _currentTime(payload),
      createdAt: asDateTime(payload['ts'] ?? envelope.ts),
      timelinePayload: timelinePayload,
    );
  }
}

class ChatroomCharactersMovedMessage extends ChatroomMessageEvent {
  const ChatroomCharactersMovedMessage({
    required super.sessionId,
    required super.worldId,
    required super.locationId,
    required super.userId,
    required super.code,
    required super.codeMsg,
    required super.ts,
    super.globalMessageId,
    required super.messageId,
    super.locationMessageId,
    required super.conversationRoundId,
    required super.roundOrder,
    required super.senderType,
    required super.senderId,
    required super.senderName,
    required super.content,
    super.messageType,
    required super.broadcast,
    required this.schemaVersion,
    required this.eventId,
    required this.tickNo,
    required this.subTickNo,
    required this.currentTime,
    required this.createdAt,
    required this.timelinePayload,
  });

  final int? schemaVersion;
  final String eventId;
  final int tickNo;
  final int subTickNo;
  final String currentTime;
  final DateTime? createdAt;
  final ChatroomCharactersMovedPayload timelinePayload;

  factory ChatroomCharactersMovedMessage.fromEnvelope(
    ChatroomEnvelope envelope,
  ) {
    final payload = envelope.mergedPayload;
    final messageId = envelope.msgId ?? 0;
    if (messageId <= 0) {
      throw const ChatroomProtocolException(
        'characters_moved msg_id must be a positive integer',
      );
    }
    final locationId = envelope.locationId.trim();
    late final ChatroomCharactersMovedPayload timelinePayload;
    try {
      final decoded = decodeChatroomTimelinePayload(
        senderType: chatroomCharactersMovedSenderType,
        rawPayload: envelope.payload,
      );
      if (decoded is! ChatroomCharactersMovedPayload) {
        throw const FormatException('characters_moved payload type mismatch');
      }
      timelinePayload = decoded;
    } catch (error) {
      throw ChatroomProtocolException(
        'Invalid characters_moved payload',
        error: error,
      );
    }
    final senderId = envelope.senderId.trim().isEmpty
        ? 'sub_tick'
        : envelope.senderId;
    return ChatroomCharactersMovedMessage(
      sessionId: envelope.sessionId,
      worldId: envelope.worldId,
      locationId: locationId,
      userId: envelope.userId,
      code: _wsCode(payload),
      codeMsg: envelope.errMsg,
      ts: asDateTime(envelope.ts),
      globalMessageId: envelope.globalMsgId ?? 0,
      messageId: messageId,
      locationMessageId: envelope.locationMsgId ?? 0,
      conversationRoundId: asString(envelope.conversationRoundId),
      roundOrder: asInt(payload['round_order']),
      senderType: chatroomCharactersMovedSenderType,
      senderId: senderId,
      senderName: envelope.senderName.trim().isEmpty
          ? senderId
          : envelope.senderName,
      content: encodeChatroomTimelinePayload(timelinePayload),
      broadcast: envelope.broadcast ?? false,
      schemaVersion: envelope.schemaVersion,
      eventId: envelope.eventId,
      tickNo: envelope.tickNo ?? 0,
      subTickNo: envelope.subTickNo ?? 0,
      currentTime: envelope.currentTime,
      createdAt: asDateTime(envelope.ts),
      timelinePayload: timelinePayload,
    );
  }
}

class ChatroomNewUserJoinEvent extends ChatroomEvent {
  const ChatroomNewUserJoinEvent({
    required this.worldId,
    required this.characterId,
    required this.characterType,
    required this.characterName,
    required this.playerUid,
    required this.playerUsername,
    required this.ts,
    this.currentTime = '',
  });

  final String worldId;
  final String characterId;
  final String characterType;
  final String characterName;
  final String playerUid;
  final String playerUsername;
  final DateTime? ts;
  final String currentTime;

  factory ChatroomNewUserJoinEvent.fromEnvelope(ChatroomEnvelope envelope) {
    final payload = envelope.mergedPayload;
    return ChatroomNewUserJoinEvent(
      worldId: asString(payload['world_id'], fallback: envelope.worldId),
      characterId: asString(payload['char_id']),
      characterType: asString(payload['type']),
      characterName: asString(payload['name']),
      playerUid: asString(payload['player_uid']),
      playerUsername: asString(payload['player_username']),
      ts: asDateTime(payload['ts'] ?? envelope.ts),
      currentTime: _currentTime(payload),
    );
  }
}

class ChatroomErrorEvent extends ChatroomEvent implements Exception {
  const ChatroomErrorEvent({
    required this.code,
    required this.message,
    this.sessionId = '',
    this.conversationRoundId = '',
    this.senderId = '',
    this.sourceType = 'error',
    this.cause,
  });

  final String sessionId;
  final String conversationRoundId;
  final String senderId;
  final String sourceType;
  final String code;
  final String message;
  final Object? cause;

  factory ChatroomErrorEvent.fromPayload(
    Map<String, dynamic> payload, {
    String sourceType = 'error',
  }) {
    return ChatroomErrorEvent(
      sessionId: asString(payload['session_id']),
      conversationRoundId: asString(payload['conversation_round_id']),
      senderId: asString(payload['sender_id']),
      sourceType: sourceType,
      code: asString(payload['err_no'], fallback: 'error'),
      message: asString(payload['err_msg']),
    );
  }

  @override
  String toString() => 'ChatroomErrorEvent($code): $message';
}

class ChatroomMessageHandlers {
  const ChatroomMessageHandlers({
    this.onEvent,
    this.onJoined,
    this.onDisconnected,
    this.onAck,
    this.onError,
    this.onFailure,
    this.onBalanceLow,
    this.onWaitingConversationRound,
    this.onEndConversationRound,
    this.onLlmMessageUpdated,
    this.onLlmCardStream,
    this.onLlmCardGenerationEnd,
    this.onConversationRangeUpdated,
    this.onWorldNotification,
    this.onStoryEventsMessage,
    this.onCharactersMovedMessage,
    this.onUserEnterLocationMessage,
    this.onUserMessage,
    this.onNarratorMessage,
    this.onTickAdvanceMessage,
    this.onAiStreamStart,
    this.onAiStreamChunk,
    this.onAiStreamEnd,
  });

  final void Function(ChatroomLlmMessageUpdated event)? onLlmMessageUpdated;
  final void Function(ChatroomLlmCardStream event)? onLlmCardStream;
  final void Function(ChatroomLlmCardGenerationEnd event)?
  onLlmCardGenerationEnd;
  final void Function(ChatroomConversationRangeUpdated event)?
  onConversationRangeUpdated;
  final void Function(ChatroomEvent event)? onEvent;
  final void Function(ChatroomJoined event)? onJoined;
  final void Function(ChatroomDisconnected event)? onDisconnected;
  final void Function(ChatroomAck event)? onAck;
  final void Function(ChatroomErrorEvent event)? onError;
  final void Function(ChatroomFailureEvent event)? onFailure;
  final void Function(ChatroomBalanceLow event)? onBalanceLow;
  final void Function(ChatroomWaitingConversationRound event)?
  onWaitingConversationRound;
  final void Function(ChatroomEndConversationRound event)?
  onEndConversationRound;
  final void Function(ChatroomWorldNotification event)? onWorldNotification;
  final void Function(ChatroomStoryEventsMessage event)? onStoryEventsMessage;
  final void Function(ChatroomCharactersMovedMessage event)?
  onCharactersMovedMessage;
  final void Function(ChatroomUserEnterLocationMessage event)?
  onUserEnterLocationMessage;
  final void Function(ChatroomUserMessage event)? onUserMessage;
  final void Function(ChatroomNarratorMessage event)? onNarratorMessage;
  final void Function(ChatroomTickAdvanceMessage event)? onTickAdvanceMessage;
  final void Function(ChatroomAiStreamStart event)? onAiStreamStart;
  final void Function(ChatroomAiStreamChunk event)? onAiStreamChunk;
  final void Function(ChatroomAiStreamEnd event)? onAiStreamEnd;

  void handle(ChatroomEvent event) {
    onEvent?.call(event);
    switch (event) {
      case ChatroomLlmCardStream e:
        onLlmCardStream?.call(e);
      case ChatroomLlmCardGenerationEnd e:
        onLlmCardGenerationEnd?.call(e);
      case ChatroomLlmMessageUpdated e:
        onLlmMessageUpdated?.call(e);
      case ChatroomConversationRangeUpdated e:
        onConversationRangeUpdated?.call(e);
      case ChatroomJoined e:
        onJoined?.call(e);
      case ChatroomDisconnected e:
        onDisconnected?.call(e);
      case ChatroomAck e:
        onAck?.call(e);
      case ChatroomErrorEvent e:
        onError?.call(e);
      case ChatroomFailureEvent e:
        onFailure?.call(e);
      case ChatroomBalanceLow e:
        onBalanceLow?.call(e);
      case ChatroomWaitingConversationRound e:
        onWaitingConversationRound?.call(e);
      case ChatroomEndConversationRound e:
        onEndConversationRound?.call(e);
      case ChatroomWorldNotification e:
        onWorldNotification?.call(e);
      case ChatroomStoryEventsMessage e:
        onStoryEventsMessage?.call(e);
      case ChatroomCharactersMovedMessage e:
        onCharactersMovedMessage?.call(e);
      case ChatroomUserEnterLocationMessage e:
        onUserEnterLocationMessage?.call(e);
      case ChatroomNewUserJoinEvent():
        break;
      case ChatroomUserMessage e:
        onUserMessage?.call(e);
      case ChatroomNarratorMessage e:
        onNarratorMessage?.call(e);
      case ChatroomTickAdvanceMessage e:
        onTickAdvanceMessage?.call(e);
      case ChatroomAiStreamStart e:
        onAiStreamStart?.call(e);
      case ChatroomAiStreamChunk e:
        onAiStreamChunk?.call(e);
      case ChatroomAiStreamEnd e:
        onAiStreamEnd?.call(e);
    }
  }
}

/// Explicit entry point for adapting the pre-V2 wire contract.
ChatroomEvent chatroomLegacyEventFromEnvelope(ChatroomEnvelope envelope) {
  switch (envelope.type) {
    case 'ack':
      return ChatroomAck.fromPayload(envelope.mergedPayload);
    case 'balance_low':
      return ChatroomBalanceLow.fromEnvelope(envelope);
    case 'tick_start':
    case 'tick_done':
    case 'world_change':
    case 'user_location_change':
    case 'world_new_message':
    case 'map_updated':
    case 'character_updated':
      return ChatroomWorldNotification.fromEnvelope(envelope);
    case 'user_enter_location':
      return (envelope.msgId ?? 0) > 0 &&
              envelope.payload.containsKey('content')
          ? ChatroomUserEnterLocationMessage.fromEnvelope(envelope)
          : ChatroomWorldNotification.fromEnvelope(envelope);
    case 'story_events':
      return ChatroomStoryEventsMessage.fromEnvelope(envelope);
    case 'characters_moved':
      return (envelope.msgId ?? 0) > 0
          ? ChatroomCharactersMovedMessage.fromEnvelope(envelope)
          : ChatroomWorldNotification.fromEnvelope(envelope);
    case 'new_user_join':
      return ChatroomNewUserJoinEvent.fromEnvelope(envelope);
    case 'tick_advance':
      return ChatroomTickAdvanceMessage.fromEnvelope(envelope);
    case 'nar_new_message':
      return ChatroomNarratorMessage.fromEnvelope(envelope);
    case 'user_message':
      return ChatroomUserMessage.fromEnvelope(envelope);
    case 'llm_stream_start':
      return ChatroomAiStreamStart.fromEnvelope(envelope);
    case 'llm_chunk':
      return ChatroomAiStreamChunk.fromEnvelope(envelope);
    case 'llm_stream_end':
      return ChatroomAiStreamEnd.fromEnvelope(envelope);
    default:
      throw ChatroomProtocolException('Unsupported type: ${envelope.type}');
  }
}

/// Routes V2 on two independent axes: `stream_type` first, then business
/// `type`. This prevents character/narrator stream frames from being mistaken
/// for complete canonical messages.
ChatroomEvent chatroomEventFromV2Message(ChatroomV2Message message) {
  if (message.type == 'llm_card_stream') {
    return ChatroomLlmCardStream.fromV2Message(message);
  }
  if (message.type == 'llm_card_generation_end') {
    return ChatroomLlmCardGenerationEnd.fromV2Message(message);
  }
  if ((message.type == 'llm_message_updated' ||
          message.type == 'conversation_range_updated') &&
      message.streamType.isNotEmpty) {
    throw const ChatroomProtocolException('Mutation events cannot be streamed');
  }
  switch (message.streamType) {
    case 'llm_stream_start':
      return ChatroomAiStreamStart.fromV2Message(message);
    case 'llm_chunk':
      return ChatroomAiStreamChunk.fromV2Message(message);
    case 'llm_stream_end':
      return ChatroomAiStreamEnd.fromV2Message(message);
    case '':
      break;
    default:
      // `ChatroomV2Message.fromJson` rejects this earlier, but retain a guard
      // for manually constructed DTOs.
      throw ChatroomProtocolException(
        'Unsupported stream_type: ${message.streamType}',
      );
  }

  switch (message.type) {
    case 'llm_message_updated':
      return ChatroomLlmMessageUpdated.fromV2Message(message);
    case 'conversation_range_updated':
      return ChatroomConversationRangeUpdated.fromV2Message(message);
    case 'ack':
      return ChatroomAck.fromV2Message(message);
    case 'user':
      return ChatroomUserMessage.fromV2Message(message);
    case 'character':
    case 'narrator':
      return ChatroomNarratorMessage.fromV2Message(message);
    case 'tick':
      return ChatroomTickAdvanceMessage.fromV2Message(message);
    case 'waiting_conversation_round':
      return ChatroomWaitingConversationRound.fromV2Message(message);
    case 'end_conversation_round':
      return ChatroomEndConversationRound.fromV2Message(message);
    case 'balance_low':
    case 'tick_start':
    case 'tick_done':
    case 'world_change':
    case 'user_location_change':
    case 'world_new_message':
    case 'map_updated':
    case 'character_updated':
    case 'user_enter_location':
    case 'story_events':
    case 'characters_moved':
    case 'new_user_join':
      return chatroomLegacyEventFromEnvelope(
        ChatroomEnvelope.fromV2Message(message),
      );
    default:
      throw ChatroomProtocolException('Unsupported V2 type: ${message.type}');
  }
}

/// Compatibility router for callers that already decoded a generic envelope.
/// New WebSocket and HTTP code should prefer the explicit V2 DTO entry point.
ChatroomEvent chatroomEventFromEnvelope(
  ChatroomEnvelope envelope, {
  ChatroomProtocolVersion? protocolVersion,
}) {
  final resolvedVersion = protocolVersion ?? envelope.wireProtocol;
  if (resolvedVersion == ChatroomProtocolVersion.v2) {
    return chatroomEventFromV2Message(envelope.toV2Message());
  }
  return chatroomLegacyEventFromEnvelope(envelope);
}

String chatroomEventType(ChatroomEvent event) {
  switch (event) {
    case ChatroomLlmCardStream():
      return 'llm_card_stream';
    case ChatroomLlmCardGenerationEnd():
      return 'llm_card_generation_end';
    case ChatroomLlmMessageUpdated():
      return 'llm_message_updated';
    case ChatroomConversationRangeUpdated():
      return 'conversation_range_updated';
    case ChatroomJoined():
      return 'join';
    case ChatroomDisconnected():
      return 'unsupported';
    case ChatroomAck():
      return 'ack';
    case ChatroomErrorEvent e:
      return e.sourceType;
    case ChatroomFailureEvent e:
      return e.sourceType;
    case ChatroomBalanceLow():
      return 'balance_low';
    case ChatroomWaitingConversationRound():
      return 'waiting_conversation_round';
    case ChatroomEndConversationRound():
      return 'end_conversation_round';
    case ChatroomWorldNotification e:
      return e.eventType;
    case ChatroomStoryEventsMessage():
      return 'story_events';
    case ChatroomCharactersMovedMessage():
      return 'characters_moved';
    case ChatroomUserEnterLocationMessage():
      return 'user_enter_location';
    case ChatroomNewUserJoinEvent():
      return 'new_user_join';
    case ChatroomUserMessage():
      return 'user_message';
    case ChatroomNarratorMessage():
      return 'nar_new_message';
    case ChatroomTickAdvanceMessage():
      return 'tick_advance';
    case ChatroomAiStreamStart():
      return 'llm_stream_start';
    case ChatroomAiStreamChunk():
      return 'llm_chunk';
    case ChatroomAiStreamEnd():
      return 'llm_stream_end';
  }
}

Map<String, dynamic> _optionalJsonMap(Object? value) {
  if (value == null) return const <String, dynamic>{};
  return asJsonMap(value);
}

int? _optionalIntAlias(
  Map<String, dynamic> json, {
  required String legacyKey,
  required String v2Key,
}) {
  if (json.containsKey(legacyKey) && json[legacyKey] != null) {
    return asInt(json[legacyKey]);
  }
  if (json.containsKey(v2Key) && json[v2Key] != null) {
    return asInt(json[v2Key]);
  }
  return null;
}

bool _looksLikeV2Envelope(Map<String, dynamic> json) {
  return json.containsKey('stream_type') ||
      json.containsKey('global_message_id') ||
      json.containsKey('message_id') ||
      json.containsKey('location_message_id') ||
      json.containsKey('min_app_version') ||
      json.containsKey('created_at');
}

String _stringId(int? value) => value == null ? '' : value.toString();

String _worldId(Map<String, dynamic> payload) {
  return asString(payload['world_id']);
}

String _currentTime(Map<String, dynamic> payload) {
  return _findCurrentTime(payload);
}

String _findCurrentTime(Object? value) {
  if (value is Map) {
    final snakeCase = asString(value['current_time']);
    if (snakeCase.trim().isNotEmpty) return snakeCase;
    final camelCase = asString(value['currentTime']);
    if (camelCase.trim().isNotEmpty) return camelCase;
    for (final child in value.values) {
      final currentTime = _findCurrentTime(child);
      if (currentTime.trim().isNotEmpty) return currentTime;
    }
  } else if (value is Iterable) {
    for (final child in value) {
      final currentTime = _findCurrentTime(child);
      if (currentTime.trim().isNotEmpty) return currentTime;
    }
  }
  return '';
}

int _wsCode(Map<String, dynamic> payload) {
  final raw = payload['err_no'];
  if (raw == null || asString(raw).isEmpty) return 0;
  return asInt(raw);
}

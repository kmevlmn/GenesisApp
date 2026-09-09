export 'chatroom_llm_cards.dart';
export 'chatroom_message_batch.dart';

import '../json_utils.dart';
import 'chatroom_message_type.dart';
import 'chatroom_models.dart';
import 'chatroom_timeline_payload.dart';

class ChatroomHttpMessage {
  const ChatroomHttpMessage({
    this.rawJson = const <String, Object?>{},
    this.businessType = '',
    this.streamType = '',
    this.ts,
    this.worldId = '',
    this.sessionId = '',
    required this.globalMessageId,
    required this.messageId,
    required this.locationMessageId,
    required this.locationId,
    required this.conversationRoundId,
    this.tickNo = 0,
    this.subTickNo = 0,
    required this.senderType,
    required this.senderId,
    required this.senderName,
    required this.userId,
    required this.content,
    this.messageType = chatroomTextMessageType,
    this.currentTime = '',
    this.clientMsgId = '',
    this.minAppVersion = 0,
    this.payload = const <String, dynamic>{},
    this.v2TickPayload,
    this.errNo = 0,
    this.errMsg = '',
    required this.createdAt,
  });

  final Map<String, Object?> rawJson;
  final String businessType;
  final String streamType;
  final int? ts;
  final String worldId;
  final String sessionId;
  final int globalMessageId;
  final int messageId;
  final int locationMessageId;
  final String locationId;
  final int conversationRoundId;
  final int tickNo;
  final int subTickNo;
  final String senderType;
  final String senderId;
  final String senderName;
  final String userId;
  final String content;
  final String messageType;
  final String currentTime;
  final String clientMsgId;
  final int minAppVersion;
  final Map<String, dynamic> payload;
  final ChatroomV2TickPayload? v2TickPayload;
  final int errNo;
  final String errMsg;
  final DateTime? createdAt;

  Map<String, dynamic> get rawPayload => payload;

  bool get isLocationSupplementalMessage =>
      locationMessageId <= 0 &&
      isChatroomLocationSupplementalSenderType(senderType);

  ChatroomTimelinePayload? get timelinePayload {
    final decoded = tryDecodeChatroomTimelinePayload(
      senderType: senderType,
      rawPayload: content,
    );
    if (decoded != null) return decoded;
    if (senderType.trim().toLowerCase() !=
        chatroomUserEnterLocationSenderType) {
      return null;
    }
    final resolvedSenderId = senderId.trim();
    final resolvedLocationId = locationId.trim();
    if (resolvedSenderId.isEmpty ||
        resolvedLocationId.isEmpty ||
        content.trim().isEmpty) {
      return null;
    }
    return ChatroomUserEnterLocationPayload(
      charId: resolvedSenderId,
      toLocationId: resolvedLocationId,
      text: content,
    );
  }

  ChatroomTimelinePayload decodeTimelinePayload() {
    return decodeChatroomTimelinePayload(
      senderType: senderType,
      rawPayload: content,
    );
  }

  factory ChatroomHttpMessage.fromJson(Map<String, dynamic> json) {
    final messageId = asInt(json['message_id']);
    final senderId = asString(json['sender_id']);
    return ChatroomHttpMessage(
      rawJson: Map<String, Object?>.from(json),
      globalMessageId: asInt(json['global_message_id']),
      messageId: messageId,
      locationMessageId: asInt(
        json['location_msg_id'],
        fallback: asInt(json['location_message_id']),
      ),
      locationId: asString(json['location_id']),
      conversationRoundId: asInt(json['conversation_round_id']),
      tickNo: asInt(json['tick_no']),
      subTickNo: asInt(json['sub_tick_no']),
      senderType: asString(json['sender_type']),
      senderId: senderId,
      senderName: asString(json['sender_name']),
      userId: asString(json['user_id']),
      content: asString(json['content']),
      messageType: resolveIncomingChatroomMessageType(
        hasMessageTypeField: json.containsKey('message_type'),
        rawMessageType: json['message_type'],
        senderId: senderId,
      ),
      currentTime: asString(json['current_time']),
      createdAt: asDateTime(json['created_at']),
    );
  }

  factory ChatroomHttpMessage.fromV2Json(Map<String, dynamic> json) {
    return ChatroomHttpMessage.fromV2Message(
      ChatroomV2Message.fromJson(json),
      rawJson: Map<String, Object?>.from(json),
    );
  }

  factory ChatroomHttpMessage.fromV2Message(
    ChatroomV2Message message, {
    Map<String, Object?>? rawJson,
  }) {
    final payload = Map<String, dynamic>.from(message.payload);
    final tickPayload = _decodeV2TickPayload(message.type, payload);
    final senderId = message.senderId;
    final resolvedRawJson = rawJson ?? message.toJson();
    final topLevelCurrentTime = message.currentTime;
    final payloadCurrentTime =
        tickPayload?.currentTime.trim().isNotEmpty == true
        ? tickPayload!.currentTime
        : asString(payload['current_time']);
    final content = asString(
      payload['content'],
      fallback: tickPayload?.globalText ?? '',
    );
    return ChatroomHttpMessage(
      rawJson: resolvedRawJson,
      businessType: message.type,
      streamType: message.streamType,
      ts: message.ts,
      worldId: message.worldId,
      sessionId: message.sessionId,
      globalMessageId: message.globalMessageId ?? 0,
      messageId: message.messageId ?? 0,
      locationMessageId: message.locationMessageId ?? 0,
      locationId: message.locationId,
      conversationRoundId: message.conversationRoundId ?? 0,
      tickNo: message.tickNo ?? tickPayload?.tickNo ?? 0,
      subTickNo: message.subTickNo ?? tickPayload?.subTickNo ?? 0,
      senderType: message.senderType,
      senderId: senderId,
      senderName: message.senderName,
      userId: message.userId,
      content: content,
      messageType: resolveIncomingChatroomMessageType(
        hasMessageTypeField: resolvedRawJson.containsKey('message_type'),
        rawMessageType: message.messageType,
        senderId: senderId,
      ),
      currentTime: topLevelCurrentTime.trim().isNotEmpty
          ? topLevelCurrentTime
          : payloadCurrentTime,
      clientMsgId: message.clientMsgId,
      minAppVersion: message.minAppVersion ?? 0,
      payload: payload,
      v2TickPayload: tickPayload,
      errNo: message.errNo,
      errMsg: message.errMsg,
      createdAt: asDateTime(message.createdAt) ?? asDateTime(message.ts),
    );
  }
}

class ChatroomLocationUser {
  const ChatroomLocationUser({
    required this.userId,
    required this.userName,
    required this.avatar,
  });

  final String userId;
  final String userName;
  final String avatar;

  factory ChatroomLocationUser.fromJson(Map<String, dynamic> json) {
    return ChatroomLocationUser(
      userId: asString(json['user_id']),
      userName: asString(json['user_name']),
      avatar: asString(json['avatar']),
    );
  }
}

class ChatroomUserLocationGroup {
  const ChatroomUserLocationGroup({
    required this.locationId,
    required this.users,
  });

  final String locationId;
  final List<ChatroomLocationUser> users;

  factory ChatroomUserLocationGroup.fromJson(Map<String, dynamic> json) {
    final rawUsers = json['users'] is List
        ? asJsonList(json['users'])
        : const [];
    return ChatroomUserLocationGroup(
      locationId: asString(json['location_id']),
      users: rawUsers
          .map((item) => ChatroomLocationUser.fromJson(asJsonMap(item)))
          .toList(growable: false),
    );
  }
}

class ChatroomUserLocationsResponse {
  const ChatroomUserLocationsResponse({
    required this.worldId,
    required this.locations,
  });

  final String worldId;
  final List<ChatroomUserLocationGroup> locations;

  factory ChatroomUserLocationsResponse.fromJson(Map<String, dynamic> json) {
    final rawLocations = json['locations'] is List
        ? asJsonList(json['locations'])
        : const [];
    return ChatroomUserLocationsResponse(
      worldId: asString(json['world_id']),
      locations: rawLocations
          .map((item) => ChatroomUserLocationGroup.fromJson(asJsonMap(item)))
          .toList(growable: false),
    );
  }
}

class ChatroomLocationMessages {
  const ChatroomLocationMessages({
    required this.locationId,
    required this.messages,
  });

  final String locationId;
  final List<ChatroomHttpMessage> messages;

  factory ChatroomLocationMessages.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] is List
        ? asJsonList(json['messages'])
        : const [];
    return ChatroomLocationMessages(
      locationId: asString(json['location_id']),
      messages: rawMessages
          .map((item) => ChatroomHttpMessage.fromJson(asJsonMap(item)))
          .toList(growable: false),
    );
  }
}

class ChatroomWorldMessagesResponse {
  const ChatroomWorldMessagesResponse({required this.locations});

  final List<ChatroomLocationMessages> locations;

  factory ChatroomWorldMessagesResponse.fromJson(Map<String, dynamic> json) {
    final rawLocations = json['locations'] is List
        ? asJsonList(json['locations'])
        : const [];
    return ChatroomWorldMessagesResponse(
      locations: rawLocations
          .map((item) => ChatroomLocationMessages.fromJson(asJsonMap(item)))
          .toList(growable: false),
    );
  }
}

class ChatroomMessageListResponse {
  const ChatroomMessageListResponse({
    this.rawJson = const <String, Object?>{},
    required this.messages,
    required this.hasMore,
    required this.newestMessageId,
  });

  final Map<String, Object?> rawJson;
  final List<ChatroomHttpMessage> messages;
  final bool hasMore;
  final int newestMessageId;

  factory ChatroomMessageListResponse.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] is List
        ? asJsonList(json['messages'])
        : const [];
    final messages = rawMessages
        .map((item) => ChatroomHttpMessage.fromJson(asJsonMap(item)))
        .toList(growable: false);
    return ChatroomMessageListResponse(
      rawJson: Map<String, Object?>.from(json),
      messages: messages,
      hasMore: asBool(json['has_more']),
      newestMessageId: asInt(
        json['newest_message_id'],
        fallback: messages.fold<int>(
          0,
          (previous, message) =>
              message.messageId > previous ? message.messageId : previous,
        ),
      ),
    );
  }

  factory ChatroomMessageListResponse.fromV2Json(Map<String, dynamic> json) {
    final rawMessages = json['messages'] is List
        ? asJsonList(json['messages'])
        : const [];
    final messages = rawMessages
        .map((item) => ChatroomHttpMessage.fromV2Json(asJsonMap(item)))
        .toList(growable: false);
    return ChatroomMessageListResponse(
      rawJson: Map<String, Object?>.from(json),
      messages: messages,
      hasMore: asBool(json['has_more']),
      newestMessageId: asInt(
        json['newest_message_id'],
        fallback: messages.fold<int>(
          0,
          (previous, message) => message.locationMessageId > previous
              ? message.locationMessageId
              : previous,
        ),
      ),
    );
  }
}

ChatroomV2TickPayload? _decodeV2TickPayload(
  String businessType,
  Map<String, dynamic> payload,
) {
  if (businessType.trim().toLowerCase() != 'tick') return null;
  try {
    return ChatroomV2TickPayload.fromJson(payload);
  } catch (_) {
    return ChatroomV2TickPayload(
      currentTime: asString(payload['current_time']),
      tickNo: asInt(payload['tick_no']),
      subTickNo: asInt(payload['sub_tick_no']),
      globalText: '',
      storyEvents: const <ChatroomV2StoryEvent>[],
      charactersMoved: const <ChatroomV2CharacterMovement>[],
      fallbackContent: asString(payload['content']),
    );
  }
}

class ChatroomTickProgress {
  const ChatroomTickProgress({
    required this.progress,
    required this.pendingMessages,
    required this.activeLlmCalls,
  });

  final int progress;
  final int pendingMessages;
  final int activeLlmCalls;

  factory ChatroomTickProgress.fromJson(Map<String, dynamic> json) {
    return ChatroomTickProgress(
      progress: asInt(json['progress']),
      pendingMessages: asInt(json['pending_messages']),
      activeLlmCalls: asInt(json['active_llm_calls']),
    );
  }
}

class ChatroomTickLockStatus {
  const ChatroomTickLockStatus({required this.isLocked});

  final bool isLocked;

  factory ChatroomTickLockStatus.fromJson(Map<String, dynamic> json) {
    return ChatroomTickLockStatus(isLocked: asBool(json['is_locked']));
  }
}

class ChatroomNarratorLocationGroup {
  const ChatroomNarratorLocationGroup({
    required this.locationId,
    required this.locationName,
    required this.locationSummary,
    required this.characters,
    required this.initialDialogue,
  });

  final String locationId;
  final String locationName;
  final String locationSummary;
  final List<ChatroomNarratorCharacter> characters;
  final List<ChatroomNarratorDialogueLine> initialDialogue;

  Map<String, Object?> toJson() {
    return {
      'location_id': locationId,
      'location_name': locationName,
      'location_summary': locationSummary,
      'characters': characters
          .map((character) => character.toJson())
          .toList(growable: false),
      'initial_dialogue': initialDialogue
          .map((line) => line.toJson())
          .toList(growable: false),
    };
  }
}

class ChatroomNarratorCharacter {
  const ChatroomNarratorCharacter({required this.charId, required this.name});

  final String charId;
  final String name;

  Map<String, Object?> toJson() => {'char_id': charId, 'name': name};
}

class ChatroomNarratorDialogueLine {
  const ChatroomNarratorDialogueLine({
    required this.charId,
    required this.charName,
    required this.content,
  });

  final String charId;
  final String charName;
  final String content;

  Map<String, Object?> toJson() {
    return {'char_id': charId, 'char_name': charName, 'content': content};
  }
}

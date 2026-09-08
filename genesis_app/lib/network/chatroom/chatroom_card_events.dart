part of 'chatroom_models.dart';

/// Private candidate events never enter the formal message/LLM stream types.
class ChatroomLlmCardStream extends ChatroomEvent {
  ChatroomLlmCardStream.fromV2Message(ChatroomV2Message message)
    : worldId = message.worldId,
      locationId = message.locationId,
      userId = message.userId,
      conversationRoundId = llmCardInt(message.conversationRoundId),
      cardId = llmCardInt(message.payload['card_id']),
      cardMessageIndex = llmCardInt(message.payload['card_message_index']),
      streamType = message.streamType,
      seq = message.payload['seq'] == null
          ? null
          : llmCardInt(message.payload['seq']),
      content = message.payload['content'] is String
          ? message.payload['content'] as String
          : '',
      currentTime = asString(message.payload['current_time']),
      senderType = message.senderType,
      senderId = message.senderId,
      senderName = message.senderName,
      errNo = message.errNo,
      errMsg = message.errMsg,
      ts = message.ts {
    _validateCardEnvelope(message);
    if (!const {'start', 'chunk', 'end'}.contains(streamType) ||
        (streamType == 'chunk' && seq == null) ||
        (streamType != 'start' && message.payload['content'] is! String)) {
      throw const FormatException('Invalid candidate stream');
    }
  }
  final String worldId, locationId, userId, senderType, senderId, senderName;
  final int conversationRoundId, cardId, cardMessageIndex;
  final int? seq, ts;
  final String streamType, content, currentTime;
  final int errNo;
  final String errMsg;
}

class ChatroomLlmCardGenerationEnd extends ChatroomEvent {
  ChatroomLlmCardGenerationEnd.fromV2Message(ChatroomV2Message message)
    : worldId = message.worldId,
      locationId = message.locationId,
      userId = message.userId,
      conversationRoundId = llmCardInt(message.conversationRoundId),
      cardId = llmCardInt(message.payload['card_id']),
      generationState = llmCardGenerationState(
        message.payload['generation_state'],
      ),
      billing = ChatroomCardBilling.fromJson(message.payload['billing']),
      error = message.payload['error'],
      errNo = message.errNo,
      errMsg = message.errMsg,
      ts = message.ts {
    _validateCardEnvelope(message);
    if (message.streamType.isNotEmpty ||
        !const {
          ChatroomCardGenerationState.succeeded,
          ChatroomCardGenerationState.failed,
        }.contains(generationState)) {
      throw const FormatException('Invalid candidate terminal state');
    }
  }
  final String worldId, locationId, userId;
  final int conversationRoundId, cardId;
  final ChatroomCardGenerationState generationState;
  final ChatroomCardBilling billing;
  final Object? error;
  final int errNo;
  final String errMsg;
  final int? ts;
}

void _validateCardEnvelope(ChatroomV2Message message) {
  if (message.worldId.trim().isEmpty ||
      message.locationId.trim().isEmpty ||
      message.userId.trim().isEmpty) {
    throw const FormatException('Missing private candidate identity');
  }
  if ((message.globalMessageId ?? 0) != 0 ||
      (message.messageId ?? 0) != 0 ||
      (message.locationMessageId ?? 0) != 0) {
    throw const FormatException(
      'Candidate event cannot have formal message IDs',
    );
  }
}

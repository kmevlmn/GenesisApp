part of '../../../../network/chatroom/chatroom_client.dart';

/// Feature-owned wire protocol; exposed through ChatroomSession only.
extension ChatroomRegenerateProtocol on ChatroomSession {
  Future<ChatroomCardRegeneration> _executeRegenerateLlmCard({
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
}

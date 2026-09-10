part of '../../../../network/chatroom/chatroom_client.dart';

/// Feature-owned wire protocol; exposed through ChatroomSession only.
extension ChatroomGoOnProtocol on ChatroomSession {
  Future<ChatroomGoOnReceipt> _executeGoOn({
    required String locationId,
    required int sourceConversationRoundId,
    required String clientMsgId,
  }) async {
    _throwIfClosed();
    if (protocolVersion != ChatroomProtocolVersion.v2) {
      throw const ChatroomProtocolException('Go on requires a V2 connection');
    }
    final location = locationId.trim();
    if (location.isEmpty ||
        sourceConversationRoundId <= 0 ||
        clientMsgId.trim().isEmpty) {
      throw ArgumentError(
        'Go on requires location, positive source round and request ID',
      );
    }
    if (_joined?.locationId != location) {
      throw const ChatroomProtocolException(
        'Go on requires the joined location',
      );
    }
    if (_pendingAcks.containsKey(clientMsgId)) {
      throw StateError('clientMsgId is already in flight');
    }
    final ack = await _sendAckedClientMessage(
      'go_on',
      {
        'payload': {
          'location_id': location,
          'source_conversation_round_id': sourceConversationRoundId,
        },
      },
      clientMsgId: clientMsgId,
      maxAttempts: 1,
    );
    final round = ack.receiptConversationRoundId;
    if (ack.worldId != worldId ||
        ack.locationId != location ||
        round == null ||
        round <= 0 ||
        round == sourceConversationRoundId) {
      throw const ChatroomProtocolException(
        'Missing or mismatched Go on receipt',
      );
    }
    return ChatroomGoOnReceipt(
      worldId: worldId,
      locationId: location,
      sourceConversationRoundId: sourceConversationRoundId,
      conversationRoundId: round,
      clientMsgId: ack.clientMsgId,
      billing: ack.billing,
    );
  }
}

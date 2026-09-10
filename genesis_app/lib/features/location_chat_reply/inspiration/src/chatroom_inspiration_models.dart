import 'dart:convert';

class ChatroomInspirationSource {
  const ChatroomInspirationSource({
    required this.ownerUid,
    required this.worldId,
    required this.locationId,
    required this.roundId,
    required this.sourceCardId,
    this.cardId,
    this.tailMessageId = 0,
  });

  final String ownerUid, worldId, locationId;
  final int roundId, sourceCardId, tailMessageId;
  final int? cardId;
  String get key =>
      jsonEncode([ownerUid, worldId, locationId, roundId, sourceCardId]);
  bool sameOrigin(ChatroomInspirationSource? other) => other?.key == key;

  ChatroomInspirationSource resolved(int sourceCardId) =>
      ChatroomInspirationSource(
        ownerUid: ownerUid,
        worldId: worldId,
        locationId: locationId,
        roundId: roundId,
        sourceCardId: sourceCardId,
        cardId: cardId,
        tailMessageId: tailMessageId,
      );
}

class ChatroomInspirationResponse {
  const ChatroomInspirationResponse({
    required this.conversationRoundId,
    required this.cardId,
    required this.sourceCardId,
    required this.messages,
    required this.gatewayRequestId,
  });

  final int conversationRoundId, cardId, sourceCardId;
  final List<String> messages;
  final String gatewayRequestId;

  factory ChatroomInspirationResponse.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid inspiration response');
    }
    int id(String key, {bool positive = false}) {
      final n = value[key];
      if (n is! int || n < (positive ? 1 : 0)) {
        throw FormatException('Invalid inspiration $key');
      }
      return n;
    }

    final messages = value['messages'];
    final gateway = value['gateway_request_id'];
    if (messages is! List ||
        messages.isEmpty ||
        messages.any((v) => v is! String || v.trim().isEmpty) ||
        gateway is! String) {
      throw const FormatException('Invalid inspiration messages');
    }
    return ChatroomInspirationResponse(
      conversationRoundId: id('conversation_round_id', positive: true),
      cardId: id('card_id'),
      sourceCardId: id('source_card_id'),
      messages: List<String>.unmodifiable(messages.cast<String>()),
      gatewayRequestId: gateway,
    );
  }

  Map<String, Object?> toJson() => {
    'conversation_round_id': conversationRoundId,
    'card_id': cardId,
    'source_card_id': sourceCardId,
    'messages': messages,
    'gateway_request_id': gatewayRequestId,
  };
}

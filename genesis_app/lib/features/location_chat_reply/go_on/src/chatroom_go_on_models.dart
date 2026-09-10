part of '../../../../network/chatroom/chatroom_models.dart';

/// Ordinary round pricing is optional and has no candidate billing status.
class ChatroomRoundBilling {
  const ChatroomRoundBilling({this.price, this.priceCent, this.pricingVersion});

  final int? price;
  final int? priceCent;
  final String? pricingVersion;

  factory ChatroomRoundBilling.fromJson(Object? value) {
    final json = llmCardMap(value);
    final version = json['pricing_version'];
    if (version != null && version is! String) {
      throw const FormatException('Invalid round pricing version');
    }
    return ChatroomRoundBilling(
      price: json['price'] == null
          ? null
          : llmCardInt(json['price'], allowZero: true),
      priceCent: json['price_cent'] == null
          ? null
          : llmCardInt(json['price_cent'], allowZero: true),
      pricingVersion: version as String?,
    );
  }
}

/// Acceptance of a new round, not evidence that any message was persisted.
class ChatroomGoOnReceipt {
  const ChatroomGoOnReceipt({
    required this.worldId,
    required this.locationId,
    required this.sourceConversationRoundId,
    required this.conversationRoundId,
    required this.clientMsgId,
    this.billing,
  });

  final String worldId, locationId, clientMsgId;
  final int sourceConversationRoundId, conversationRoundId;
  final ChatroomRoundBilling? billing;
}

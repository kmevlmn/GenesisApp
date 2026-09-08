/// Contract-only models. Candidate snapshots are separate from formal messages.
enum ChatroomCardGenerationState {
  preparing,
  queued,
  generating,
  succeeded,
  failed,
}

enum ChatroomCardBillingStatus {
  notRequired,
  notStarted,
  reserved,
  committed,
  cancelled,
}

Map<String, dynamic> llmCardMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected card object');
  return Map<String, dynamic>.from(value);
}

int llmCardInt(Object? value, {bool allowZero = false}) {
  if (value is! int || value < (allowZero ? 0 : 1)) {
    throw const FormatException('Invalid card integer');
  }
  return value;
}

bool _cardBool(Object? value) {
  if (value is! bool) throw const FormatException('Invalid card boolean');
  return value;
}

ChatroomCardGenerationState llmCardGenerationState(Object? value) =>
    ChatroomCardGenerationState.values.firstWhere(
      (state) => state.name == value,
      orElse: () =>
          throw const FormatException('Invalid card generation state'),
    );

void validateLlmCardRequest({
  required int conversationRoundId,
  int? cardId,
  String? clientMsgId,
}) {
  if (conversationRoundId <= 0 || (cardId != null && cardId <= 0)) {
    throw ArgumentError('Card and round IDs must be positive');
  }
  if (clientMsgId != null &&
      (clientMsgId.trim().isEmpty || clientMsgId.runes.length > 128)) {
    throw ArgumentError('clientMsgId must contain 1–128 characters');
  }
}

class ChatroomCardBilling {
  const ChatroomCardBilling({
    required this.status,
    this.priceCent,
    this.pricingVersion,
  });
  final ChatroomCardBillingStatus status;
  final int? priceCent;
  final String? pricingVersion;

  factory ChatroomCardBilling.fromJson(Object? value) {
    final json = llmCardMap(value);
    final status = switch (json['status']) {
      'not_required' => ChatroomCardBillingStatus.notRequired,
      'not_started' => ChatroomCardBillingStatus.notStarted,
      'reserved' => ChatroomCardBillingStatus.reserved,
      'committed' => ChatroomCardBillingStatus.committed,
      'cancelled' => ChatroomCardBillingStatus.cancelled,
      _ => throw const FormatException('Invalid billing status'),
    };
    final version = json['pricing_version'];
    if (version != null && version is! String) {
      throw const FormatException('Invalid pricing version');
    }
    return ChatroomCardBilling(
      status: status,
      priceCent: json['price_cent'] == null
          ? null
          : llmCardInt(json['price_cent'], allowZero: true),
      pricingVersion: version as String?,
    );
  }
}

class ChatroomCardRegeneration {
  const ChatroomCardRegeneration({
    required this.conversationRoundId,
    required this.originalCardId,
    required this.cardId,
    required this.generationState,
    required this.billing,
    this.error,
  });
  final int conversationRoundId;
  final int originalCardId;
  final int cardId;
  final ChatroomCardGenerationState generationState;
  final ChatroomCardBilling billing;

  /// Error object shape is not specified in the supplied client guide.
  final Object? error;

  factory ChatroomCardRegeneration.fromJson(Object? value) {
    final json = llmCardMap(value);
    return ChatroomCardRegeneration(
      conversationRoundId: llmCardInt(json['conversation_round_id']),
      originalCardId: llmCardInt(json['original_card_id']),
      cardId: llmCardInt(json['card_id']),
      generationState: llmCardGenerationState(json['generation_state']),
      billing: ChatroomCardBilling.fromJson(json['billing']),
      error: json['error'],
    );
  }
}

class ChatroomCardSelection {
  const ChatroomCardSelection({
    required this.conversationRoundId,
    required this.selectedCardId,
    required this.confirmed,
    required this.startConversationRoundId,
    required this.endConversationRoundId,
    required this.newestMessageId,
  });
  final int conversationRoundId;
  final int selectedCardId;
  final bool confirmed;
  final int startConversationRoundId;
  final int endConversationRoundId;
  final int newestMessageId;

  factory ChatroomCardSelection.fromJson(Object? value) {
    final json = llmCardMap(value);
    final round = llmCardInt(json['conversation_round_id']);
    final start = llmCardInt(json['start_conversation_round_id']);
    final end = llmCardInt(json['end_conversation_round_id']);
    if (start > round || end < round || json['confirmed'] != true) {
      throw const FormatException('Invalid confirmed card range');
    }
    return ChatroomCardSelection(
      conversationRoundId: round,
      selectedCardId: llmCardInt(json['selected_card_id']),
      confirmed: true,
      startConversationRoundId: start,
      endConversationRoundId: end,
      newestMessageId: llmCardInt(json['newest_message_id'], allowZero: true),
    );
  }
}

class ChatroomLlmCardsResponse {
  const ChatroomLlmCardsResponse({
    required this.originalCardId,
    required this.selectedCardId,
    required this.activeCardId,
    required this.confirmed,
    required this.canRegenerate,
    required this.canConfirm,
    required this.list,
    required this.total,
    required this.rawJson,
  });
  final int originalCardId;
  final int selectedCardId;
  final int activeCardId;
  final bool confirmed;
  final bool canRegenerate;
  final bool canConfirm;

  /// The guide does not define the complete item/message schema. Preserve it
  /// losslessly until its companion OpenAPI is available; do not create bubbles.
  final List<Map<String, dynamic>> list;
  final int total;
  final Map<String, dynamic> rawJson;

  factory ChatroomLlmCardsResponse.fromJson(Object? value) {
    final json = llmCardMap(value);
    final rawList = json['list'];
    if (rawList is! List) throw const FormatException('Invalid cards list');
    final total = llmCardInt(json['total'], allowZero: true);
    if (total != rawList.length || total > 10) {
      throw const FormatException('Invalid card total');
    }
    return ChatroomLlmCardsResponse(
      originalCardId: llmCardInt(json['original_card_id'], allowZero: true),
      selectedCardId: llmCardInt(json['selected_card_id'], allowZero: true),
      activeCardId: llmCardInt(json['active_card_id'], allowZero: true),
      confirmed: _cardBool(json['confirmed']),
      canRegenerate: _cardBool(json['can_regenerate']),
      canConfirm: _cardBool(json['can_confirm']),
      list: List.unmodifiable(
        rawList.map(
          (item) => Map<String, dynamic>.unmodifiable(llmCardMap(item)),
        ),
      ),
      total: total,
      rawJson: Map.unmodifiable(json),
    );
  }
}

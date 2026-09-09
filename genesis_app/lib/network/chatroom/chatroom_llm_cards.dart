import 'chatroom_models.dart' show ChatroomV2Message;

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

/// A saved candidate message. Its V2 content never enters the formal cache.
class ChatroomLlmCardMessage {
  const ChatroomLlmCardMessage({
    required this.message,
    required this.cardId,
    required this.cardMessageIndex,
    required this.rawJson,
  });

  final ChatroomV2Message message;
  final int cardId, cardMessageIndex;
  final Map<String, dynamic> rawJson;
  int get globalMessageId => message.globalMessageId!;
  int get conversationRoundId => message.conversationRoundId!;
  String get content => message.payload['content'] as String;

  factory ChatroomLlmCardMessage.fromJson(Object? value) {
    final json = llmCardMap(value);
    llmCardInt(json['global_message_id']);
    llmCardInt(json['conversation_round_id']);
    if (json.containsKey('message_id') ||
        json.containsKey('location_message_id')) {
      throw const FormatException('Saved candidate cannot have formal cursors');
    }
    final message = ChatroomV2Message.fromJson(json);
    if (message.worldId.trim().isEmpty ||
        message.locationId.trim().isEmpty ||
        message.streamType.isNotEmpty ||
        message.payload['content'] is! String) {
      throw const FormatException('Invalid saved candidate message');
    }
    return ChatroomLlmCardMessage(
      message: message,
      cardId: llmCardInt(json['card_id']),
      cardMessageIndex: llmCardInt(json['card_message_index']),
      rawJson: Map.unmodifiable(json),
    );
  }
}

class ChatroomLlmCard {
  const ChatroomLlmCard({
    required this.cardId,
    required this.cardIndex,
    required this.isOriginal,
    required this.generationState,
    required this.canEdit,
    required this.canDelete,
    required this.messages,
    required this.billing,
    required this.createdAt,
    required this.rawJson,
    this.error,
  });

  final int cardId, cardIndex;
  final bool isOriginal, canEdit, canDelete;
  final ChatroomCardGenerationState generationState;
  final List<ChatroomLlmCardMessage> messages;
  final ChatroomCardBilling billing;
  final String createdAt;
  final Object? error;
  final Map<String, dynamic> rawJson;

  factory ChatroomLlmCard.fromJson(
    Object? value, {
    required int conversationRoundId,
  }) {
    final json = llmCardMap(value);
    final cardId = llmCardInt(json['card_id']);
    final rawMessages = json['messages'];
    if (rawMessages is! List || json['created_at'] is! String) {
      throw const FormatException('Invalid saved card');
    }
    final messages = rawMessages.map(ChatroomLlmCardMessage.fromJson).toList();
    final ids = <int>{};
    var lastIndex = 0;
    for (final message in messages) {
      if (message.cardId != cardId ||
          message.conversationRoundId != conversationRoundId ||
          !ids.add(message.globalMessageId) ||
          message.cardMessageIndex <= lastIndex) {
        throw const FormatException('Mismatched candidate identity or order');
      }
      lastIndex = message.cardMessageIndex;
    }
    final state = llmCardGenerationState(json['generation_state']);
    if (state != ChatroomCardGenerationState.succeeded && messages.isNotEmpty) {
      throw const FormatException('Incomplete card cannot have saved messages');
    }
    return ChatroomLlmCard(
      cardId: cardId,
      cardIndex: llmCardInt(json['card_index']),
      isOriginal: _cardBool(json['is_original']),
      generationState: state,
      canEdit: _cardBool(json['can_edit']),
      canDelete: _cardBool(json['can_delete']),
      messages: List.unmodifiable(messages),
      billing: ChatroomCardBilling.fromJson(json['billing']),
      createdAt: json['created_at'] as String,
      error: json['error'],
      rawJson: Map.unmodifiable(json),
    );
  }
}

class ChatroomCardMutationResult {
  const ChatroomCardMutationResult({
    required this.conversationRoundId,
    required this.card,
  });
  final int conversationRoundId;
  final ChatroomLlmCard card;

  factory ChatroomCardMutationResult.fromJson(Object? value) {
    final json = llmCardMap(value);
    final round = llmCardInt(json['conversation_round_id']);
    return ChatroomCardMutationResult(
      conversationRoundId: round,
      card: ChatroomLlmCard.fromJson(json['card'], conversationRoundId: round),
    );
  }
}

class ChatroomLlmCardsResponse {
  const ChatroomLlmCardsResponse({
    required this.conversationRoundId,
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
  final int conversationRoundId;
  final int originalCardId;
  final int selectedCardId;
  final int activeCardId;
  final bool confirmed;
  final bool canRegenerate;
  final bool canConfirm;

  final List<ChatroomLlmCard> list;
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
    final round = llmCardInt(json['conversation_round_id']);
    return ChatroomLlmCardsResponse(
      conversationRoundId: round,
      originalCardId: llmCardInt(json['original_card_id'], allowZero: true),
      selectedCardId: llmCardInt(json['selected_card_id'], allowZero: true),
      activeCardId: llmCardInt(json['active_card_id'], allowZero: true),
      confirmed: _cardBool(json['confirmed']),
      canRegenerate: _cardBool(json['can_regenerate']),
      canConfirm: _cardBool(json['can_confirm']),
      list: List.unmodifiable(
        rawList.map(
          (item) => ChatroomLlmCard.fromJson(item, conversationRoundId: round),
        ),
      ),
      total: total,
      rawJson: Map.unmodifiable(json),
    );
  }
}

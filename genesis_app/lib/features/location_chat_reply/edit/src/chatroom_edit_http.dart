part of '../../../../network/chatroom/chatroom_http_api.dart';

/// Feature-owned HTTP implementation; exposed through ChatroomHttpApi only.
extension ChatroomEditHttp on ChatroomHttpApi {
  String _llmCardPath(String worldId, String locationId, String action) =>
      'aitown-chat/api/v1/worlds/${Uri.encodeComponent(_required(worldId, 'worldId'))}/locations/${Uri.encodeComponent(_required(locationId, 'locationId'))}/llm-messages/$action';

  /// Atomically edit/delete 1–100 replies from one conversation round.
  Future<ChatroomMessageMutationResult> _executeBatchMutateLlmMessages({
    required String worldId,
    required String locationId,
    required int conversationRoundId,
    required List<ChatroomLlmMessageOperation> operations,
  }) async {
    final result = ChatroomMessageMutationResult.fromJson(
      await _postLlmMessageBatch(
        worldId: worldId,
        locationId: locationId,
        conversationRoundId: conversationRoundId,
        operations: operations,
      ),
    );
    if (result.startConversationRoundId > conversationRoundId ||
        result.endConversationRoundId < conversationRoundId) {
      throw ApiException(
        message: 'Message batch range excludes the submitted round',
        kind: ApiExceptionKind.response,
      );
    }
    return result;
  }

  /// Save edits to one candidate without selecting it or refreshing history.
  Future<ChatroomCardMutationResult> _executeBatchMutateLlmCardMessages({
    required String worldId,
    required String locationId,
    required int conversationRoundId,
    required int cardId,
    required List<ChatroomLlmMessageOperation> operations,
  }) async {
    validateLlmCardRequest(
      conversationRoundId: conversationRoundId,
      cardId: cardId,
    );
    final data = await _postLlmMessageBatch(
      worldId: worldId,
      locationId: locationId,
      conversationRoundId: conversationRoundId,
      cardId: cardId,
      operations: operations,
    );
    try {
      final result = ChatroomCardMutationResult.fromJson(data);
      if (result.conversationRoundId != conversationRoundId ||
          result.card.cardId != cardId) {
        throw const FormatException(
          'Candidate mutation response does not match request',
        );
      }
      return result;
    } on FormatException catch (error) {
      throw ApiException(
        message: error.message,
        kind: ApiExceptionKind.response,
      );
    }
  }

  Future<Object?> _postLlmMessageBatch({
    required String worldId,
    required String locationId,
    required int conversationRoundId,
    required List<ChatroomLlmMessageOperation> operations,
    int? cardId,
  }) async {
    if (conversationRoundId <= 0) {
      throw ArgumentError.value(conversationRoundId, 'conversationRoundId');
    }
    if (operations.isEmpty || operations.length > 100) {
      throw ArgumentError.value(
        operations.length,
        'operations',
        'requires 1–100 operations',
      );
    }
    final ids = <int>{};
    final encoded = operations
        .map((operation) {
          if (!ids.add(operation.globalMessageId)) {
            throw ArgumentError('Duplicate globalMessageId');
          }
          return operation.toJson();
        })
        .toList(growable: false);
    final world = Uri.encodeComponent(_required(worldId, 'worldId'));
    final location = Uri.encodeComponent(_required(locationId, 'locationId'));
    final json = await _client
        .copyWith(retryPolicy: ApiRetryPolicy.none)
        .post<Object?>(
          'aitown-chat/api/v1/worlds/$world/locations/$location/llm-messages/batch',
          body: {
            'conversation_round_id': conversationRoundId,
            if (cardId != null) 'card_id': cardId,
            'operations': encoded,
          },
        );
    if (json is! Map || json['err_no'] is! int) {
      throw ApiException(
        message: 'Invalid message batch response',
        kind: ApiExceptionKind.response,
      );
    }
    return handleV1ResponseErrNo(json);
  }
}

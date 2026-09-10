part of '../../../../network/chatroom/chatroom_http_api.dart';

/// Feature-owned HTTP implementation; exposed through ChatroomHttpApi only.
extension ChatroomInspirationHttp on ChatroomHttpApi {
  Future<ChatroomInspirationResponse> _executeGetInspirations({
    required String worldId,
    required String locationId,
    required int conversationRoundId,
    int? cardId,
    NetworkCancellationToken? cancellationToken,
  }) async {
    validateLlmCardRequest(
      conversationRoundId: conversationRoundId,
      cardId: cardId,
    );
    final world = Uri.encodeComponent(_required(worldId, 'worldId'));
    final location = Uri.encodeComponent(_required(locationId, 'locationId'));
    final json = await _client
        .copyWith(timeoutMs: 120000, retryPolicy: ApiRetryPolicy.none)
        .post<Object?>(
          'aitown-chat/api/v1/worlds/$world/locations/$location/inspiration',
          body: {
            'conversation_round_id': conversationRoundId,
            if (cardId != null) 'card_id': cardId,
          },
          cancellationToken: cancellationToken,
        );
    if (json is! Map || json['err_no'] is! int) {
      throw ApiException(
        message: 'Invalid inspiration envelope',
        kind: ApiExceptionKind.response,
      );
    }
    final data = handleV1ResponseErrNo(json);
    try {
      final result = ChatroomInspirationResponse.fromJson(data);
      if (result.conversationRoundId != conversationRoundId) {
        throw const FormatException(
          'Inspiration response has a different source round',
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
}

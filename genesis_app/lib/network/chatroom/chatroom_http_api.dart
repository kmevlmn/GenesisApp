import '../api_client.dart';
import '../api_exception.dart';
import '../http_transport.dart';
import '../json_utils.dart';
import '../multipart_body.dart';
import '../v1/v1_api_resource.dart';
import 'chatroom_http_models.dart';

class ChatroomHttpApi {
  const ChatroomHttpApi(this._client);

  final ApiClient _client;

  /// GET /aitown-chat/api/ulocation
  Future<ChatroomUserLocationsResponse> getUserLocations({
    required String worldId,
  }) async {
    final data = await _getMap(
      'aitown-chat/api/ulocation',
      v1Query({'world_id': _required(worldId, 'worldId')}),
    );
    return ChatroomUserLocationsResponse.fromJson(data);
  }

  /// GET /aitown-chat/internal/world/messages
  Future<ChatroomWorldMessagesResponse> getWorldMessages({
    required String worldId,
  }) async {
    final data = await _getMap(
      'aitown-chat/internal/world/messages',
      v1Query({'world_id': _required(worldId, 'worldId')}),
    );
    return ChatroomWorldMessagesResponse.fromJson(data);
  }

  /// GET /aitown-chat/api/v2/messages
  Future<ChatroomMessageListResponse> getMessages({
    required String worldId,
    required String locationId,
    int? since,
    int? limit,
    int? startConversationRoundId,
    int? endConversationRoundId,
    NetworkCancellationToken? cancellationToken,
  }) async {
    final start = startConversationRoundId ?? 0;
    final end = endConversationRoundId ?? 0;
    if ((start != 0 || end != 0) && (start <= 0 || end < start)) {
      throw ArgumentError(
        'Conversation range requires positive ordered bounds',
      );
    }
    final data = await _getMap(
      'aitown-chat/api/v2/messages',
      v1Query({
        'world_id': _required(worldId, 'worldId'),
        'location_id': _required(locationId, 'locationId'),
        'since': since,
        'limit': limit,
        'start_conversation_round_id': startConversationRoundId,
        'end_conversation_round_id': endConversationRoundId,
      }),
      cancellationToken: cancellationToken,
      strictEnvelope: cancellationToken != null || start > 0,
    );
    if ((cancellationToken != null || start > 0) &&
        (data['messages'] is! List ||
            data['has_more'] is! bool ||
            data['newest_message_id'] is! int ||
            (data['newest_message_id'] as int) < 0)) {
      throw ApiException(
        message: 'Invalid authoritative history response',
        kind: ApiExceptionKind.response,
      );
    }
    return ChatroomMessageListResponse.fromV2Json(data);
  }

  /// Read saved candidates without creating a card group or changing history.
  Future<ChatroomLlmCardsResponse> getLlmCards({
    required String worldId,
    required String locationId,
    required int conversationRoundId,
    NetworkCancellationToken? cancellationToken,
  }) async {
    validateLlmCardRequest(conversationRoundId: conversationRoundId);
    final data = await _getMap(
      _llmCardPath(worldId, locationId, 'cards'),
      {'conversation_round_id': conversationRoundId},
      cancellationToken: cancellationToken,
      strictEnvelope: true,
    );
    try {
      final result = ChatroomLlmCardsResponse.fromJson(data);
      if (result.conversationRoundId != conversationRoundId) {
        throw const FormatException(
          'Card query response does not match request',
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

  /// Confirm a complete card. Callers own retry/recovery using the same ID.
  /// This method returns the refresh range without applying it to chat state.
  Future<ChatroomCardSelection> selectLlmCard({
    required String worldId,
    required String locationId,
    required int conversationRoundId,
    required int cardId,
    required String clientMsgId,
  }) async {
    validateLlmCardRequest(
      conversationRoundId: conversationRoundId,
      cardId: cardId,
      clientMsgId: clientMsgId,
    );
    final json = await _client
        .copyWith(retryPolicy: ApiRetryPolicy.none)
        .post<Object?>(
          _llmCardPath(worldId, locationId, 'select'),
          body: {
            'conversation_round_id': conversationRoundId,
            'card_id': cardId,
            'client_msg_id': clientMsgId,
          },
        );
    if (json is! Map || json['err_no'] is! int) {
      throw ApiException(
        message: 'Invalid card selection response',
        kind: ApiExceptionKind.response,
      );
    }
    final data = handleV1ResponseErrNo(json);
    try {
      final selection = ChatroomCardSelection.fromJson(data);
      if (selection.conversationRoundId != conversationRoundId ||
          selection.selectedCardId != cardId) {
        throw const FormatException(
          'Card selection response does not match request',
        );
      }
      return selection;
    } on FormatException catch (error) {
      throw ApiException(
        message: error.message,
        kind: ApiExceptionKind.response,
      );
    }
  }

  String _llmCardPath(String worldId, String locationId, String action) =>
      'aitown-chat/api/v1/worlds/${Uri.encodeComponent(_required(worldId, 'worldId'))}/locations/${Uri.encodeComponent(_required(locationId, 'locationId'))}/llm-messages/$action';

  /// Atomically edit/delete 1–100 replies from one conversation round.
  Future<ChatroomMessageMutationResult> batchMutateLlmMessages({
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
  Future<ChatroomCardMutationResult> batchMutateLlmCardMessages({
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

  /// GET /aitown-chat/api/messages
  ///
  /// Legacy compatibility/debug endpoint. New location history should use
  /// [getMessages], whose cursor is `location_message_id`.
  Future<ChatroomMessageListResponse> getLegacyMessages({
    required String worldId,
    required String locationId,
    int? since,
    int? limit,
  }) async {
    final data = await _getMap(
      'aitown-chat/api/messages',
      v1Query({
        'world_id': _required(worldId, 'worldId'),
        'location_id': _required(locationId, 'locationId'),
        'since': since,
        'limit': limit,
      }),
    );
    return ChatroomMessageListResponse.fromJson(data);
  }

  /// POST /aitown-chat/internal/tick/lock
  Future<bool> lockWorld({required String worldId}) async {
    final resolvedWorldId = _required(worldId, 'worldId');
    final data = await _postMultipartMap(
      'aitown-chat/internal/tick/lock',
      fields: {'world_id': resolvedWorldId},
      query: {'world_id': resolvedWorldId},
    );
    return asBool(data['locked']);
  }

  /// GET /aitown-chat/internal/tick/is_locked
  Future<ChatroomTickLockStatus> tickLockStatus({
    required String worldId,
  }) async {
    final data = await _getMap(
      'aitown-chat/internal/tick/is_locked',
      v1Query({'world_id': _required(worldId, 'worldId')}),
    );
    return ChatroomTickLockStatus.fromJson(data);
  }

  /// GET /aitown-chat/internal/tick/progress
  Future<ChatroomTickProgress> tickProgress({required String worldId}) async {
    final data = await _getMap(
      'aitown-chat/internal/tick/progress',
      v1Query({'world_id': _required(worldId, 'worldId')}),
    );
    return ChatroomTickProgress.fromJson(data);
  }

  /// POST /aitown-chat/internal/tick/unlock
  Future<bool> unlockWorld({required String worldId}) async {
    final data = await _postMultipartMap(
      'aitown-chat/internal/tick/unlock',
      fields: {'world_id': _required(worldId, 'worldId')},
    );
    return asBool(data['unlocked']);
  }

  /// POST /aitown-chat/internal/narrator/write
  Future<int> writeNarrator({
    required String worldId,
    required String tickId,
    required List<ChatroomNarratorLocationGroup> locationGroups,
  }) async {
    final data = await _postJsonMap('aitown-chat/internal/narrator/write', {
      'world_id': _required(worldId, 'worldId'),
      'tick_id': _required(tickId, 'tickId'),
      'location_groups': locationGroups
          .map((group) => group.toJson())
          .toList(growable: false),
    });
    return asInt(data['message_id']);
  }

  Future<Map<String, dynamic>> _getMap(
    String path,
    Map<String, Object?> query, {
    NetworkCancellationToken? cancellationToken,
    bool strictEnvelope = false,
  }) async {
    final json = await _client.get<Object?>(
      path,
      query: query,
      cancellationToken: cancellationToken,
    );
    if (strictEnvelope && (json is! Map || json['err_no'] is! int)) {
      throw ApiException(
        message: 'Invalid history envelope',
        kind: ApiExceptionKind.response,
      );
    }
    final data = handleV1ResponseErrNo(json);
    return data == null ? <String, dynamic>{} : asJsonMap(data);
  }

  Future<Map<String, dynamic>> _postJsonMap(
    String path,
    Map<String, Object?> body,
  ) async {
    final json = await _client.post<Object?>(path, body: body);
    final data = handleV1ResponseErrNo(json);
    return data == null ? <String, dynamic>{} : asJsonMap(data);
  }

  Future<Map<String, dynamic>> _postMultipartMap(
    String path, {
    required Map<String, String> fields,
    Map<String, Object?>? query,
  }) async {
    final json = await _client.post<Object?>(
      path,
      query: query,
      body: MultipartBody(fields: fields),
    );
    final data = handleV1ResponseErrNo(json);
    return data == null ? <String, dynamic>{} : asJsonMap(data);
  }
}

String _required(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return trimmed;
}

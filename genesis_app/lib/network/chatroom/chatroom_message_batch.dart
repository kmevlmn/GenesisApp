import '../api_exception.dart';

enum ChatroomLlmMessageAction { edit, delete }

/// One operation in an atomic batch. Delete operations never serialize content.
class ChatroomLlmMessageOperation {
  const ChatroomLlmMessageOperation.edit({
    required this.globalMessageId,
    required String this.content,
  }) : action = ChatroomLlmMessageAction.edit;

  const ChatroomLlmMessageOperation.delete({required this.globalMessageId})
    : action = ChatroomLlmMessageAction.delete,
      content = null;

  final ChatroomLlmMessageAction action;
  final int globalMessageId;
  final String? content;

  Map<String, Object?> toJson() {
    if (globalMessageId <= 0) {
      throw ArgumentError.value(globalMessageId, 'globalMessageId');
    }
    if (action == ChatroomLlmMessageAction.edit &&
        (content == null || content!.trim().isEmpty)) {
      throw ArgumentError.value(content, 'content', 'must not be blank');
    }
    return {
      'action': action.name,
      'global_message_id': globalMessageId,
      if (action == ChatroomLlmMessageAction.edit) 'content': content,
    };
  }
}

class ChatroomMessageMutationResult {
  const ChatroomMessageMutationResult({
    required this.startConversationRoundId,
    required this.endConversationRoundId,
    required this.newestMessageId,
  });

  final int startConversationRoundId;
  final int endConversationRoundId;
  final int newestMessageId;

  factory ChatroomMessageMutationResult.fromJson(Object? json) {
    if (json is Map) {
      final start = json['start_conversation_round_id'];
      final end = json['end_conversation_round_id'];
      final newest = json['newest_message_id'];
      if (start is int &&
          end is int &&
          newest is int &&
          start > 0 &&
          end >= start &&
          newest >= 0) {
        return ChatroomMessageMutationResult(
          startConversationRoundId: start,
          endConversationRoundId: end,
          newestMessageId: newest,
        );
      }
    }
    throw ApiException(
      message: 'Invalid message batch refresh range',
      kind: ApiExceptionKind.response,
    );
  }
}

import '../../network/chatroom/chatroom_message_storage.dart';
import '../../network/chatroom/chatroom_timeline_payload.dart';
import '../../network/json_utils.dart';
import 'location_chat_debug_hub.dart';

class LocationChatDebugChatroomMessageStorage
    implements ChatroomMessageStorage {
  LocationChatDebugChatroomMessageStorage(this._delegate);

  final ChatroomMessageStorage _delegate;

  static ChatroomMessageStorage wrap(ChatroomMessageStorage delegate) {
    if (!LocationChatDebugHub.enabled) return delegate;
    if (delegate is LocationChatDebugChatroomMessageStorage) return delegate;
    return LocationChatDebugChatroomMessageStorage(delegate);
  }

  @override
  /// Atomically replaces a closed round range; omitted bounds replace the location.
  Future<void> replaceMessages({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required List<Map<String, dynamic>> messages,
    int? startConversationRoundId,
    int? endConversationRoundId,
    bool Function()? isCurrent,
    int maxMessagesPerLocation = 200,
  }) => _delegate.replaceMessages(
    ownerUid: ownerUid,
    worldId: worldId,
    locationId: locationId,
    messages: messages,
    startConversationRoundId: startConversationRoundId,
    endConversationRoundId: endConversationRoundId,
    isCurrent: isCurrent,
    maxMessagesPerLocation: maxMessagesPerLocation,
  );

  @override
  Future<List<Map<String, dynamic>>> loadLatestMessages({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int limit,
  }) async {
    final messages = await _delegate.loadLatestMessages(
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      limit: limit,
    );
    _record(
      action: 'loadLatest',
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      messages: messages,
      details: {'limit': limit, 'loaded': messages.length},
    );
    return messages;
  }

  @override
  Future<List<Map<String, dynamic>>> loadMessagesBefore({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int beforeMessageId,
    int beforeWorldMessageId = 0,
    required int limit,
  }) async {
    final messages = await _delegate.loadMessagesBefore(
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      beforeMessageId: beforeMessageId,
      beforeWorldMessageId: beforeWorldMessageId,
      limit: limit,
    );
    _record(
      action: 'loadBefore',
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      messages: messages,
      details: {
        'beforeMessageId': beforeMessageId,
        'beforeWorldMessageId': beforeWorldMessageId,
        'limit': limit,
        'loaded': messages.length,
      },
    );
    return messages;
  }

  @override
  Future<void> mergeMessages({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required List<Map<String, dynamic>> messages,
    int maxMessagesPerLocation = 200,
  }) async {
    await _delegate.mergeMessages(
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      messages: messages,
      maxMessagesPerLocation: maxMessagesPerLocation,
    );
    await _recordLatestSnapshot(
      action: 'merge',
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      limit: maxMessagesPerLocation,
      details: {
        'incoming': messages.length,
        'maxMessagesPerLocation': maxMessagesPerLocation,
      },
    );
  }

  @override
  Future<void> upsertMessage({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required Map<String, dynamic> message,
    int maxMessagesPerLocation = 200,
  }) async {
    await _delegate.upsertMessage(
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      message: message,
      maxMessagesPerLocation: maxMessagesPerLocation,
    );
    await _recordLatestSnapshot(
      action: 'upsert',
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      limit: maxMessagesPerLocation,
      details: {'maxMessagesPerLocation': maxMessagesPerLocation},
    );
  }

  @override
  Future<void> deleteMessagesAtOrBefore({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int maxLocationMessageId,
    int maxWorldMessageId = 0,
  }) async {
    await _delegate.deleteMessagesAtOrBefore(
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      maxLocationMessageId: maxLocationMessageId,
      maxWorldMessageId: maxWorldMessageId,
    );
    await _recordLatestSnapshot(
      action: 'deleteAtOrBefore',
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      limit: 200,
      details: {
        'maxLocationMessageId': maxLocationMessageId,
        'maxWorldMessageId': maxWorldMessageId,
      },
    );
  }

  @override
  Future<void> clearCache(String ownerUid) async {
    await _delegate.clearCache(ownerUid);
    LocationChatDebugHub.record(
      source: 'storage',
      action: 'clear',
      details: {'ownerUid': ownerUid},
    );
  }

  Future<void> _recordLatestSnapshot({
    required String action,
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int limit,
    required Map<String, Object?> details,
  }) async {
    if (!LocationChatDebugHub.enabled) return;
    final messages = await _delegate.loadLatestMessages(
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      limit: limit,
    );
    _record(
      action: action,
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      messages: messages,
      details: {
        ...details,
        'snapshotLimit': limit,
        'snapshotCount': messages.length,
      },
    );
  }

  void _record({
    required String action,
    required String ownerUid,
    required String worldId,
    required String locationId,
    required Iterable<Map<String, dynamic>> messages,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    if (!LocationChatDebugHub.enabled) return;
    final queue = _storageDebugQueue(messages);
    LocationChatDebugHub.record(
      source: 'storage',
      action: action,
      worldId: worldId,
      locationId: locationId,
      details: <String, Object?>{
        'ownerUid': ownerUid,
        ...details,
        'queue': queue,
      },
      snapshotKey: '$ownerUid|$worldId|$locationId',
      snapshot: <String, Object?>{
        'ownerUid': ownerUid,
        'worldId': worldId,
        'locationId': locationId,
        'count': queue.length,
        'messages': queue,
      },
    );
  }
}

List<Map<String, Object?>> _storageDebugQueue(
  Iterable<Map<String, dynamic>> messages,
) {
  return _sortMessageJson(messages)
      .map(
        (message) => <String, Object?>{
          'globalMsgId': _globalMessageId(message),
          'msgId': _messageId(message),
          'locationMsgId': _locationMessageId(message),
          'location_msg_id': _locationMessageId(message),
          'location_message_id': _locationMessageId(message),
          'queueMsgId': _locationQueueMessageId(message),
          'locationId': asString(message['location_id']),
          'type': asString(
            message['type'],
            fallback: asString(message['sender_type']),
          ),
          'streamType': asString(message['stream_type']),
          'senderType': asString(message['sender_type']),
          'senderId': asString(message['sender_id']),
          'clientMsgId': asString(message['client_msg_id']),
          'conversationRoundId': asString(message['conversation_round_id']),
          'minAppVersion': asInt(message['min_app_version']),
          'payloadKeys': message['payload'] is Map
              ? asJsonMap(message['payload']).keys.toList(growable: false)
              : const <String>[],
          'contentPreview': _preview(asString(message['content'])),
          'subTickNo': asInt(message['sub_tick_no']),
          'currentTime': asString(message['current_time']),
          'createdAt':
              (asDateTime(message['created_at']) ?? asDateTime(message['ts']))
                  ?.toIso8601String(),
        },
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> _sortMessageJson(
  Iterable<Map<String, dynamic>> messages,
) {
  final sorted = messages
      .map((message) => Map<String, dynamic>.from(message))
      .toList(growable: false);
  sorted.sort((a, b) {
    if (isChatroomMessageIdOrderedSupplemental(
          a['sender_type'],
          locationMessageId: _locationQueueMessageId(a),
        ) ||
        isChatroomMessageIdOrderedSupplemental(
          b['sender_type'],
          locationMessageId: _locationQueueMessageId(b),
        )) {
      final byMessageId = _messageId(a).compareTo(_messageId(b));
      if (byMessageId != 0) return byMessageId;
    }
    final byLocationMessage = _locationQueueMessageId(
      a,
    ).compareTo(_locationQueueMessageId(b));
    if (byLocationMessage != 0) return byLocationMessage;
    return _messageId(a).compareTo(_messageId(b));
  });
  return sorted;
}

int _messageId(Map<String, dynamic> message) {
  return asInt(message['msg_id'], fallback: asInt(message['message_id']));
}

int _globalMessageId(Map<String, dynamic> message) {
  return asInt(
    message['global_msg_id'],
    fallback: asInt(message['global_message_id']),
  );
}

int _locationMessageId(Map<String, dynamic> message) {
  return asInt(
    message['location_msg_id'],
    fallback: asInt(message['location_message_id']),
  );
}

int _locationQueueMessageId(Map<String, dynamic> message) {
  return _locationMessageId(message);
}

String _preview(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 80) return trimmed;
  return '${trimmed.substring(0, 80)}...';
}

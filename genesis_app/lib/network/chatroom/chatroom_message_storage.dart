import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../json_utils.dart';
import 'chatroom_timeline_payload.dart';

abstract class ChatroomMessageStorage {
  Future<List<Map<String, dynamic>>> loadLatestMessages({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> loadMessagesBefore({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int beforeMessageId,
    int beforeWorldMessageId = 0,
    required int limit,
  });

  Future<void> mergeMessages({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required List<Map<String, dynamic>> messages,
    int maxMessagesPerLocation = 200,
  });

  Future<void> deleteMessagesAtOrBefore({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int maxLocationMessageId,
    int maxWorldMessageId = 0,
  });

  Future<void> upsertMessage({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required Map<String, dynamic> message,
    int maxMessagesPerLocation = 200,
  });

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
  });

  Future<void> clearCache(String ownerUid);
}

class SqfliteChatroomMessageStorage implements ChatroomMessageStorage {
  SqfliteChatroomMessageStorage({
    this.databaseName = 'genesis_chatroom_messages.db',
    DatabaseFactory? databaseFactoryOverride,
    this.databasePath,
  }) : _databaseFactory = databaseFactoryOverride;

  final String databaseName;
  final String? databasePath;
  final DatabaseFactory? _databaseFactory;
  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;
    final factory = _databaseFactory ?? databaseFactory;
    final path =
        databasePath ?? '${await factory.getDatabasesPath()}/$databaseName';
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await db.execute(_createChatroomMessagesSql);
          await db.execute(_createChatroomMessagesIndexSql);
          await db.execute(_createChatroomMessagesLocationUniqueSql);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE chatroom_messages '
              'ADD COLUMN global_msg_id INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE chatroom_messages '
              'ADD COLUMN location_msg_id INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (oldVersion < 3) {
            await db.execute(_createChatroomMessagesIndexSql);
            await db.execute(_createChatroomMessagesLocationUniqueSql);
          }
          if (oldVersion < 4) {
            await _deleteLegacySupplementalRows(db);
          }
        },
      ),
    );
    _database = db;
    return db;
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  @override
  Future<List<Map<String, dynamic>>> loadLatestMessages({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int limit,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'chatroom_messages',
      where: 'owner_uid = ? AND world_id = ? AND location_id = ?',
      whereArgs: [ownerUid, worldId, locationId],
    );
    final messages = rows
        .map(_messageFromRow)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final descending = _sortMessageJson(
      messages,
    ).reversed.toList(growable: false);
    return _sortMessageJson(descending.take(limit));
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
    if (beforeMessageId <= 0) return const <Map<String, dynamic>>[];
    final db = await _db;
    final rows = await db.query(
      'chatroom_messages',
      where: 'owner_uid = ? AND world_id = ? AND location_id = ?',
      whereArgs: [ownerUid, worldId, locationId],
    );
    final descending = _sortMessageJson(
      rows
          .map(_messageFromRow)
          .whereType<Map<String, dynamic>>()
          .where(
            (message) => _messageIsBeforeLocationCursor(
              message,
              beforeMessageId,
              beforeWorldMessageId: beforeWorldMessageId,
            ),
          ),
    ).reversed.toList(growable: false);
    return _sortMessageJson(descending.take(limit));
  }

  @override
  Future<void> mergeMessages({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required List<Map<String, dynamic>> messages,
    int maxMessagesPerLocation = 200,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final message in messages) {
        await _insertMessage(txn, ownerUid, worldId, locationId, message);
      }
      await _pruneLocation(
        txn,
        ownerUid: ownerUid,
        worldId: worldId,
        locationId: locationId,
        maxMessages: maxMessagesPerLocation,
      );
    });
  }

  @override
  Future<void> upsertMessage({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required Map<String, dynamic> message,
    int maxMessagesPerLocation = 200,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await _insertMessage(txn, ownerUid, worldId, locationId, message);
      await _pruneLocation(
        txn,
        ownerUid: ownerUid,
        worldId: worldId,
        locationId: locationId,
        maxMessages: maxMessagesPerLocation,
      );
    });
  }

  @override
  Future<void> deleteMessagesAtOrBefore({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int maxLocationMessageId,
    int maxWorldMessageId = 0,
  }) async {
    if (maxLocationMessageId <= 0) return;
    final db = await _db;
    final rows = await db.query(
      'chatroom_messages',
      where: 'owner_uid = ? AND world_id = ? AND location_id = ?',
      whereArgs: [ownerUid, worldId, locationId],
    );
    for (final row in rows.where((row) {
      final message = _messageFromRow(row);
      return message != null &&
          _messageIsAtOrBeforeLocationCursor(
            message,
            maxLocationMessageId,
            maxWorldMessageId: maxWorldMessageId,
          );
    })) {
      await db.delete(
        'chatroom_messages',
        where:
            'owner_uid = ? AND world_id = ? AND location_id = ? '
            'AND location_msg_id = ? AND msg_id = ?',
        whereArgs: [
          ownerUid,
          worldId,
          locationId,
          row['location_msg_id'],
          row['msg_id'],
        ],
      );
    }
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
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'chatroom_messages',
        where: 'owner_uid = ? AND world_id = ? AND location_id = ?',
        whereArgs: [ownerUid, worldId, locationId],
      );
      final next = _replacementMessages(
        rows.map(_messageFromRow).whereType<Map<String, dynamic>>(),
        messages,
        startConversationRoundId,
        endConversationRoundId,
        maxMessagesPerLocation,
      );
      await txn.delete(
        'chatroom_messages',
        where: 'owner_uid = ? AND world_id = ? AND location_id = ?',
        whereArgs: [ownerUid, worldId, locationId],
      );
      for (final message in next) {
        await _insertMessage(txn, ownerUid, worldId, locationId, message);
      }
      if (isCurrent?.call() == false) {
        throw StateError('Stale history transaction');
      }
    });
  }

  @override
  Future<void> clearCache(String ownerUid) async {
    final db = await _db;
    await db.delete(
      'chatroom_messages',
      where: 'owner_uid = ?',
      whereArgs: [ownerUid],
    );
  }

  Future<void> _insertMessage(
    DatabaseExecutor executor,
    String ownerUid,
    String worldId,
    String locationId,
    Map<String, dynamic> message,
  ) async {
    final messageId = _messageId(message);
    final locationMessageId = _storageLocationMessageId(message);
    final resolvedLocationId = locationId.trim().isNotEmpty
        ? locationId.trim()
        : asString(message['location_id']).trim();
    if (messageId <= 0 || resolvedLocationId.isEmpty) return;
    final existingRows = await executor.query(
      'chatroom_messages',
      columns: const ['raw_json', 'global_msg_id', 'location_msg_id'],
      where: locationMessageId > 0
          ? 'owner_uid = ? AND world_id = ? AND location_id = ? AND location_msg_id = ?'
          : 'owner_uid = ? AND world_id = ? AND location_id = ? AND location_msg_id = 0 AND msg_id = ?',
      whereArgs: locationMessageId > 0
          ? [ownerUid, worldId, resolvedLocationId, locationMessageId]
          : [ownerUid, worldId, resolvedLocationId, messageId],
      limit: 1,
    );
    final existing = existingRows.isEmpty
        ? null
        : _messageFromRow(existingRows.first);
    if (_globalMessageId(message) > 0) {
      await executor.delete(
        'chatroom_messages',
        where:
            'owner_uid = ? AND world_id = ? AND location_id = ? AND global_msg_id = ?',
        whereArgs: [
          ownerUid,
          worldId,
          resolvedLocationId,
          _globalMessageId(message),
        ],
      );
    }
    final messageForStorage = _messageForStorage(
      _preservingLlmStreamFlag(message, existing),
      locationMessageId,
    );
    await executor.insert('chatroom_messages', {
      'owner_uid': ownerUid,
      'world_id': worldId,
      'location_id': resolvedLocationId,
      'global_msg_id': _globalMessageId(message),
      'msg_id': messageId,
      'location_msg_id': locationMessageId,
      'raw_json': jsonEncode(messageForStorage),
      'created_at': _messageSortValue(message),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _pruneLocation(
    DatabaseExecutor executor, {
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int maxMessages,
  }) async {
    if (maxMessages <= 0) return;
    final rows = await executor.query(
      'chatroom_messages',
      where: 'owner_uid = ? AND world_id = ? AND location_id = ?',
      whereArgs: [ownerUid, worldId, locationId],
      limit: 1000000,
    );
    final messages = rows
        .map(_messageFromRow)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final removeKeys = _sortMessageJson(
      messages,
    ).reversed.skip(maxMessages).map(_messageStorageKey).toSet();
    for (final row in rows.where((row) {
      return removeKeys.contains(_messageStorageKey(_messageFromRow(row)));
    })) {
      await executor.delete(
        'chatroom_messages',
        where:
            'owner_uid = ? AND world_id = ? AND location_id = ? '
            'AND location_msg_id = ? AND msg_id = ?',
        whereArgs: [
          ownerUid,
          worldId,
          locationId,
          row['location_msg_id'],
          row['msg_id'],
        ],
      );
    }
  }
}

class MemoryChatroomMessageStorage implements ChatroomMessageStorage {
  final Map<String, Map<String, Map<String, dynamic>>> _messages = {};

  @override
  Future<List<Map<String, dynamic>>> loadLatestMessages({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int limit,
  }) async {
    final descending = _sortMessageJson(
      _bucket(ownerUid, worldId, locationId).values,
    ).reversed.toList(growable: false);
    final messages = _sortMessageJson(descending.take(limit));
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
    if (beforeMessageId <= 0) return const <Map<String, dynamic>>[];
    final descending = _sortMessageJson(
      _bucket(ownerUid, worldId, locationId).values.where(
        (message) => _messageIsBeforeLocationCursor(
          message,
          beforeMessageId,
          beforeWorldMessageId: beforeWorldMessageId,
        ),
      ),
    ).reversed.toList(growable: false);
    final messages = _sortMessageJson(descending.take(limit));
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
    final bucket = _bucket(ownerUid, worldId, locationId);
    for (final message in messages) {
      if (_messageId(message) <= 0) continue;
      final key = _messageStorageKey(message);
      bucket.removeWhere(
        (oldKey, old) =>
            oldKey != key &&
            _storageLocationMessageId(message) > 0 &&
            _storageLocationMessageId(old) ==
                _storageLocationMessageId(message),
      );
      bucket[key] = _messageForStorage(
        _preservingLlmStreamFlag(message, bucket[key]),
        _storageLocationMessageId(message),
      );
    }
    _prune(bucket, maxMessagesPerLocation);
  }

  @override
  Future<void> upsertMessage({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required Map<String, dynamic> message,
    int maxMessagesPerLocation = 200,
  }) async {
    if (_messageId(message) <= 0) return;
    final bucket = _bucket(ownerUid, worldId, locationId);
    final key = _messageStorageKey(message);
    bucket.removeWhere(
      (oldKey, old) =>
          oldKey != key &&
          _storageLocationMessageId(message) > 0 &&
          _storageLocationMessageId(old) == _storageLocationMessageId(message),
    );
    bucket[key] = _messageForStorage(
      _preservingLlmStreamFlag(message, bucket[key]),
      _storageLocationMessageId(message),
    );
    _prune(bucket, maxMessagesPerLocation);
  }

  @override
  Future<void> deleteMessagesAtOrBefore({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int maxLocationMessageId,
    int maxWorldMessageId = 0,
  }) async {
    if (maxLocationMessageId <= 0) return;
    final bucket = _bucket(ownerUid, worldId, locationId);
    bucket.removeWhere((_, message) {
      return _messageIsAtOrBeforeLocationCursor(
        message,
        maxLocationMessageId,
        maxWorldMessageId: maxWorldMessageId,
      );
    });
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
  }) async {
    final bucket = _bucket(ownerUid, worldId, locationId);
    final next = _replacementMessages(
      bucket.values,
      messages,
      startConversationRoundId,
      endConversationRoundId,
      maxMessagesPerLocation,
    );
    if (isCurrent?.call() == false) return;
    bucket.clear();
    for (final message in next) {
      bucket[_messageStorageKey(message)] = _messageForStorage(
        message,
        _storageLocationMessageId(message),
      );
    }
  }

  @override
  Future<void> clearCache(String ownerUid) async {
    _messages.removeWhere((key, _) => key.startsWith('$ownerUid\u001F'));
  }

  Map<String, Map<String, dynamic>> _bucket(
    String ownerUid,
    String worldId,
    String locationId,
  ) {
    return _messages.putIfAbsent(
      '$ownerUid\u001F$worldId\u001F$locationId',
      () => <String, Map<String, dynamic>>{},
    );
  }

  void _prune(Map<String, Map<String, dynamic>> bucket, int maxMessages) {
    if (maxMessages <= 0 || bucket.length <= maxMessages) return;
    final keep = _sortMessageJson(
      bucket.values,
    ).reversed.take(maxMessages).map(_messageStorageKey).toSet();
    bucket.removeWhere((key, _) => !keep.contains(key));
  }
}

const _createChatroomMessagesSql = '''
  CREATE TABLE IF NOT EXISTS chatroom_messages (
    owner_uid TEXT NOT NULL,
    world_id TEXT NOT NULL,
    location_id TEXT NOT NULL,
    global_msg_id INTEGER NOT NULL DEFAULT 0,
    msg_id INTEGER NOT NULL,
    location_msg_id INTEGER NOT NULL DEFAULT 0,
    raw_json TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY(owner_uid, world_id, location_id, location_msg_id, msg_id)
  )
''';

const _createChatroomMessagesIndexSql = '''
  CREATE INDEX IF NOT EXISTS idx_chatroom_messages_location_created
  ON chatroom_messages(owner_uid, world_id, location_id, location_msg_id, msg_id)
''';

const _createChatroomMessagesLocationUniqueSql = '''
  CREATE UNIQUE INDEX IF NOT EXISTS idx_chatroom_messages_location_msg
  ON chatroom_messages(owner_uid, world_id, location_id, location_msg_id)
  WHERE location_msg_id > 0
''';

Map<String, dynamic>? _messageFromRow(Map<String, Object?> row) {
  try {
    final message = asJsonMap(jsonDecode('${row['raw_json']}'));
    message.putIfAbsent('global_msg_id', () => asInt(row['global_msg_id']));
    message.putIfAbsent('location_msg_id', () => asInt(row['location_msg_id']));
    return message;
  } catch (_) {
    return null;
  }
}

List<Map<String, dynamic>> _sortMessageJson(
  Iterable<Map<String, dynamic>> messages,
) {
  final sorted = messages
      .map((message) => Map<String, dynamic>.from(message))
      .toList(growable: false);
  sorted.sort((a, b) {
    final aIsCursorlessNonOrdered = _isCursorlessNonOrderedJson(a);
    final bIsCursorlessNonOrdered = _isCursorlessNonOrderedJson(b);
    if (aIsCursorlessNonOrdered != bIsCursorlessNonOrdered) {
      return aIsCursorlessNonOrdered ? -1 : 1;
    }
    final aIsMessageIdOrdered = _isMessageIdOrderedSupplementalJson(a);
    final bIsMessageIdOrdered = _isMessageIdOrderedSupplementalJson(b);
    if (aIsMessageIdOrdered || bIsMessageIdOrdered) {
      final byMessage = _messageId(a).compareTo(_messageId(b));
      if (byMessage != 0) return byMessage;
      final byLocation = _locationMessageId(a).compareTo(_locationMessageId(b));
      if (byLocation != 0) return byLocation;
    } else {
      final aHasLocationMessageId = _locationMessageId(a) > 0;
      final bHasLocationMessageId = _locationMessageId(b) > 0;
      if (aHasLocationMessageId && bHasLocationMessageId) {
        final byLocationMessage = _locationMessageId(
          a,
        ).compareTo(_locationMessageId(b));
        if (byLocationMessage != 0) return byLocationMessage;
      } else if (aHasLocationMessageId != bHasLocationMessageId) {
        return aHasLocationMessageId ? 1 : -1;
      }
    }
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

bool _isMessageIdOrderedSupplementalJson(Map<String, dynamic> message) {
  return isChatroomMessageIdOrderedSupplemental(
    message['sender_type'],
    locationMessageId: _locationMessageId(message),
  );
}

bool _isCursorlessNonOrderedJson(Map<String, dynamic> message) {
  return _locationMessageId(message) <= 0 &&
      !_isMessageIdOrderedSupplementalJson(message);
}

int _storageLocationMessageId(Map<String, dynamic> message) {
  return _isMessageIdOrderedSupplementalJson(message)
      ? 0
      : _locationMessageId(message);
}

bool _messageIsBeforeLocationCursor(
  Map<String, dynamic> message,
  int beforeMessageId, {
  int beforeWorldMessageId = 0,
}) {
  if (beforeMessageId <= 0) return false;
  if (_isMessageIdOrderedSupplementalJson(message)) {
    return beforeWorldMessageId > 0 &&
        _messageId(message) > 0 &&
        _messageId(message) < beforeWorldMessageId;
  }
  final locationMessageId = _locationMessageId(message);
  // Cursorless non-tick legacy timeline rows are display-only compatibility
  // records. Returning them for every location page would repeat the same row
  // indefinitely because they have no location cursor to advance.
  if (locationMessageId <= 0) return false;
  return locationMessageId < beforeMessageId;
}

bool _messageIsAtOrBeforeLocationCursor(
  Map<String, dynamic> message,
  int maxLocationMessageId, {
  int maxWorldMessageId = 0,
}) {
  if (maxLocationMessageId <= 0) return false;
  if (_isMessageIdOrderedSupplementalJson(message)) {
    return maxWorldMessageId > 0 &&
        _messageId(message) > 0 &&
        _messageId(message) <= maxWorldMessageId;
  }
  final locationMessageId = _locationMessageId(message);
  // A location gap boundary cannot classify a cursorless non-tick legacy row
  // as old or new, so retain it until ordinary cache pruning/clearing.
  if (locationMessageId <= 0) return false;
  return locationMessageId <= maxLocationMessageId;
}

String _messageStorageKey(Map<String, dynamic>? message) {
  if (message == null) return '';
  final globalId = _globalMessageId(message);
  if (globalId > 0) return 'global:$globalId';
  final locationMessageId = _storageLocationMessageId(message);
  if (locationMessageId > 0) return 'location:$locationMessageId';
  return 'message:${_messageId(message)}';
}

Map<String, dynamic> _messageForStorage(
  Map<String, dynamic> message,
  int locationMessageId,
) {
  final result = Map<String, dynamic>.from(message);
  final sourceLocationMessageId = _locationMessageId(message);
  result['location_msg_id'] =
      _isMessageIdOrderedSupplementalJson(message) &&
          sourceLocationMessageId > 0
      ? sourceLocationMessageId
      : locationMessageId;
  return result;
}

Map<String, dynamic> _preservingLlmStreamFlag(
  Map<String, dynamic> incoming,
  Map<String, dynamic>? existing,
) {
  if (incoming['payload'] is Map &&
      (incoming['payload'] as Map)['status'] == 20) {
    return incoming;
  }
  if (asBool(existing?['is_llm_stream']) &&
      !asBool(incoming['is_llm_stream'])) {
    return <String, dynamic>{...incoming, 'is_llm_stream': true};
  }
  return incoming;
}

int _messageSortValue(Map<String, dynamic> message) {
  final parsed = asDateTime(message['ts']) ?? asDateTime(message['created_at']);
  return parsed?.millisecondsSinceEpoch ?? _messageId(message);
}

Future<void> _deleteLegacySupplementalRows(DatabaseExecutor db) async {
  final rows = await db.query(
    'chatroom_messages',
    columns: const <String>[
      'owner_uid',
      'world_id',
      'location_id',
      'location_msg_id',
      'msg_id',
      'raw_json',
    ],
    where: 'location_msg_id = 0',
  );
  for (final row in rows) {
    Map<String, dynamic> message;
    try {
      message = asJsonMap(jsonDecode('${row['raw_json']}'));
    } catch (_) {
      continue;
    }
    final senderType = asString(message['sender_type']).trim().toLowerCase();
    if (!_legacySupplementalSenderTypesToDelete.contains(senderType)) continue;
    await db.delete(
      'chatroom_messages',
      where:
          'owner_uid = ? AND world_id = ? AND location_id = ? '
          'AND location_msg_id = ? AND msg_id = ?',
      whereArgs: <Object?>[
        row['owner_uid'],
        row['world_id'],
        row['location_id'],
        row['location_msg_id'],
        row['msg_id'],
      ],
    );
  }
}

const Set<String> _legacySupplementalSenderTypesToDelete = <String>{
  'tick',
  'story_events',
  'characters_moved',
};

List<Map<String, dynamic>> _replacementMessages(
  Iterable<Map<String, dynamic>> existing,
  List<Map<String, dynamic>> incoming,
  int? start,
  int? end,
  int limit,
) {
  if ((start != null || end != null) &&
      (start == null || end == null || start <= 0 || end < start)) {
    throw ArgumentError('Invalid replacement range');
  }
  final byId = <String, Map<String, dynamic>>{};
  for (final message in existing) {
    final round = asInt(message['conversation_round_id']);
    if (start != null && (round < start || round > end!)) {
      byId[_messageStorageKey(message)] = message;
    }
  }
  for (final message in incoming) {
    if (_messageId(message) > 0) byId[_messageStorageKey(message)] = message;
  }
  final sorted = _sortMessageJson(byId.values);
  return limit > 0 && sorted.length > limit
      ? sorted.sublist(sorted.length - limit)
      : sorted;
}

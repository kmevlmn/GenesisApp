import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'chatroom_inspiration_models.dart';

abstract class ChatroomInspirationStorage {
  Future<ChatroomInspirationResponse?> load(ChatroomInspirationSource source);
  Future<void> save(
    ChatroomInspirationSource source,
    ChatroomInspirationResponse value,
  );
  Future<void> clearLocation(
    String ownerUid,
    String worldId,
    String locationId, {
    int? keepRound,
    int minTailMessageId = 0,
  });
  Future<void> close();
}

class SqfliteChatroomInspirationStorage implements ChatroomInspirationStorage {
  SqfliteChatroomInspirationStorage({
    this.databasePath,
    DatabaseFactory? factory,
  }) : _factory = factory;
  final String? databasePath;
  final DatabaseFactory? _factory;
  Future<Database>? _opening;

  Future<Database> get _database => _opening ??= _open();
  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    return factory.openDatabase(
      databasePath ??
          '${await factory.getDatabasesPath()}/genesis_chatroom_inspirations.db',
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, _) => db.execute('''
CREATE TABLE inspirations (
 owner_uid TEXT NOT NULL, world_id TEXT NOT NULL, location_id TEXT NOT NULL,
 round_id INTEGER NOT NULL, source_card_id INTEGER NOT NULL,
 tail_message_id INTEGER NOT NULL, formal_source INTEGER NOT NULL, value TEXT NOT NULL,
 PRIMARY KEY (owner_uid, world_id, location_id, round_id, source_card_id)
)
'''),
      ),
    );
  }

  List<Object?> _key(ChatroomInspirationSource source) => [
    source.ownerUid,
    source.worldId,
    source.locationId,
    source.roundId,
    source.sourceCardId,
  ];

  @override
  Future<ChatroomInspirationResponse?> load(
    ChatroomInspirationSource source,
  ) async {
    final formal = source.cardId == null && source.sourceCardId == 0;
    final rows = await (await _database).query(
      'inspirations',
      where:
          'owner_uid = ? AND world_id = ? AND location_id = ? AND round_id = ? AND ${formal ? 'formal_source = 1' : 'source_card_id = ?'}',
      whereArgs: formal ? _key(source).take(4).toList() : _key(source),
      limit: 1,
    );
    if (rows.isEmpty ||
        (rows.single['tail_message_id'] as int) < source.tailMessageId) {
      return null;
    }
    return ChatroomInspirationResponse.fromJson(
      jsonDecode(rows.single['value'] as String),
    );
  }

  @override
  Future<void> save(
    ChatroomInspirationSource source,
    ChatroomInspirationResponse value,
  ) async {
    final db = await _database;
    await db.transaction((txn) async {
      if (source.cardId == null) {
        await txn.update(
          'inspirations',
          {'formal_source': 0},
          where:
              'owner_uid = ? AND world_id = ? AND location_id = ? AND round_id = ?',
          whereArgs: _key(source).take(4).toList(),
        );
      }
      await txn.insert('inspirations', {
        'owner_uid': source.ownerUid,
        'world_id': source.worldId,
        'location_id': source.locationId,
        'round_id': source.roundId,
        'source_card_id': source.sourceCardId,
        'tail_message_id': source.tailMessageId,
        'formal_source': source.cardId == null ? 1 : 0,
        'value': jsonEncode(value.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> clearLocation(
    String ownerUid,
    String worldId,
    String locationId, {
    int? keepRound,
    int minTailMessageId = 0,
  }) async {
    await (await _database).delete(
      'inspirations',
      where:
          'owner_uid = ? AND world_id = ? AND location_id = ?${keepRound == null ? '' : ' AND (round_id <> ? OR tail_message_id < ?)'}',
      whereArgs: [
        ownerUid,
        worldId,
        locationId,
        if (keepRound != null) ...[keepRound, minTailMessageId],
      ],
    );
  }

  @override
  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}

class MemoryChatroomInspirationStorage implements ChatroomInspirationStorage {
  final _values =
      <String, (ChatroomInspirationSource, ChatroomInspirationResponse)>{};
  @override
  Future<ChatroomInspirationResponse?> load(
    ChatroomInspirationSource source,
  ) async {
    final formal = source.cardId == null && source.sourceCardId == 0;
    final matches = _values.values.where(
      (entry) =>
          entry.$1.cardId == null &&
          entry.$1.ownerUid == source.ownerUid &&
          entry.$1.worldId == source.worldId &&
          entry.$1.locationId == source.locationId &&
          entry.$1.roundId == source.roundId,
    );
    final entry = formal ? matches.lastOrNull : _values[source.key];
    return entry != null && entry.$1.tailMessageId >= source.tailMessageId
        ? entry.$2
        : null;
  }

  @override
  Future<void> save(
    ChatroomInspirationSource source,
    ChatroomInspirationResponse value,
  ) async {
    _values[source.key] = (source, value);
  }

  @override
  Future<void> clearLocation(
    String ownerUid,
    String worldId,
    String locationId, {
    int? keepRound,
    int minTailMessageId = 0,
  }) async {
    _values.removeWhere(
      (_, entry) =>
          entry.$1.ownerUid == ownerUid &&
          entry.$1.worldId == worldId &&
          entry.$1.locationId == locationId &&
          (entry.$1.roundId != keepRound ||
              entry.$1.tailMessageId < minTailMessageId),
    );
  }

  @override
  Future<void> close() async {}
}

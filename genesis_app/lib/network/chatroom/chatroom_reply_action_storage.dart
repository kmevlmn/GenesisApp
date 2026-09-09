import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Private operation metadata. Candidate bodies stay in the server's card store.
abstract class ChatroomReplyActionStorage {
  Future<List<Map<String, dynamic>>> load({
    required String ownerUid,
    required String worldId,
    required String locationId,
  });

  Future<void> save({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int roundId,
    required Map<String, dynamic> value,
  });

  Future<void> close();
}

class SqfliteChatroomReplyActionStorage implements ChatroomReplyActionStorage {
  SqfliteChatroomReplyActionStorage({
    this.databasePath,
    DatabaseFactory? databaseFactoryOverride,
  }) : _factoryOverride = databaseFactoryOverride;

  final String? databasePath;
  final DatabaseFactory? _factoryOverride;
  Future<Database>? _opening;

  Future<Database> get _database => _opening ??= _open();

  Future<Database> _open() async {
    final factory = _factoryOverride ?? databaseFactory;
    return factory.openDatabase(
      databasePath ??
          '${await factory.getDatabasesPath()}/genesis_chatroom_reply_actions.db',
      options: OpenDatabaseOptions(
        version: 1,
        // Controllers for different worlds may overlap while old writes drain.
        // Closing one account's store must not close another controller's handle.
        singleInstance: false,
        onCreate: (db, _) => db.execute('''
CREATE TABLE reply_actions (
  owner_uid TEXT NOT NULL,
  world_id TEXT NOT NULL,
  location_id TEXT NOT NULL,
  round_id INTEGER NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (owner_uid, world_id, location_id, round_id)
)
'''),
      ),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> load({
    required String ownerUid,
    required String worldId,
    required String locationId,
  }) async {
    final rows = await (await _database).query(
      'reply_actions',
      columns: ['value'],
      where: 'owner_uid = ? AND world_id = ? AND location_id = ?',
      whereArgs: [ownerUid, worldId, locationId],
    );
    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['value'] as String) as Map,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> save({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int roundId,
    required Map<String, dynamic> value,
  }) async {
    if (ownerUid.isEmpty ||
        worldId.isEmpty ||
        locationId.isEmpty ||
        roundId <= 0) {
      throw ArgumentError('Reply state requires an account and round identity');
    }
    await (await _database).insert('reply_actions', {
      'owner_uid': ownerUid,
      'world_id': worldId,
      'location_id': locationId,
      'round_id': roundId,
      'value': jsonEncode(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}

class MemoryChatroomReplyActionStorage implements ChatroomReplyActionStorage {
  final _values = <String, Map<String, dynamic>>{};

  String _prefix(String uid, String world, String location) =>
      jsonEncode([uid, world, location]);

  @override
  Future<List<Map<String, dynamic>>> load({
    required String ownerUid,
    required String worldId,
    required String locationId,
  }) async {
    final prefix = '${_prefix(ownerUid, worldId, locationId)}:';
    return _values.entries
        .where((entry) => entry.key.startsWith(prefix))
        .map(
          (entry) => Map<String, dynamic>.from(
            jsonDecode(jsonEncode(entry.value)) as Map,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> save({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int roundId,
    required Map<String, dynamic> value,
  }) async {
    _values['${_prefix(ownerUid, worldId, locationId)}:$roundId'] =
        Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }

  @override
  Future<void> close() async {}
}

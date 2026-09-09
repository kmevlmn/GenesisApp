import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_reply_action_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'closing an old account store leaves the next account connection usable',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp('reply-state-');
      final first = SqfliteChatroomReplyActionStorage(
        databasePath: '${directory.path}/actions.db',
        databaseFactoryOverride: databaseFactoryFfi,
      );
      final second = SqfliteChatroomReplyActionStorage(
        databasePath: '${directory.path}/actions.db',
        databaseFactoryOverride: databaseFactoryFfi,
      );
      addTearDown(() async {
        await first.close();
        await second.close();
        await directory.delete(recursive: true);
      });
      await first.save(
        ownerUid: 'first',
        worldId: 'w',
        locationId: 'l',
        roundId: 1,
        value: {'round_id': 1},
      );
      expect(
        await second.load(ownerUid: 'second', worldId: 'w', locationId: 'l'),
        isEmpty,
      );
      await first.close();
      await second.save(
        ownerUid: 'second',
        worldId: 'w',
        locationId: 'l',
        roundId: 2,
        value: {'round_id': 2},
      );
      expect(
        (await second.load(
          ownerUid: 'second',
          worldId: 'w',
          locationId: 'l',
        )).single,
        {'round_id': 2},
      );
    },
  );
  test(
    'independent SQLite operation records isolate UID and preserve 64-bit IDs',
    () async {
      sqfliteFfiInit();
      final storage = SqfliteChatroomReplyActionStorage(
        databasePath: inMemoryDatabasePath,
        databaseFactoryOverride: databaseFactoryFfi,
      );
      addTearDown(storage.close);
      const round = 9007199254740993;
      final record = <String, dynamic>{
        'round_id': round,
        'viewed_card_id': round + 1,
        'drafts': {
          '${round + 1}': [
            {
              'action': 'edit',
              'global_message_id': round + 2,
              'content': 'Draft',
            },
          ],
        },
        'go_on': {'client_msg_id': 'request', 'round_id': null},
      };
      await storage.save(
        ownerUid: 'u',
        worldId: 'w',
        locationId: 'l',
        roundId: round,
        value: record,
      );
      expect(
        await storage.load(ownerUid: 'other', worldId: 'w', locationId: 'l'),
        isEmpty,
      );
      expect(
        await storage.load(ownerUid: 'u', worldId: 'other', locationId: 'l'),
        isEmpty,
      );
      final loaded = await storage.load(
        ownerUid: 'u',
        worldId: 'w',
        locationId: 'l',
      );
      expect(loaded.single, record);
      expect(loaded.single.containsKey('messages'), isFalse);
      record['viewed_card_id'] = round + 3;
      await storage.save(
        ownerUid: 'u',
        worldId: 'w',
        locationId: 'l',
        roundId: round,
        value: record,
      );
      expect(
        (await storage.load(
          ownerUid: 'u',
          worldId: 'w',
          locationId: 'l',
        )).single['viewed_card_id'],
        round + 3,
      );
    },
  );
}

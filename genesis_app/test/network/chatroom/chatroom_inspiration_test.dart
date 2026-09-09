import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_http_api.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_inspiration.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_inspiration_controller.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_inspiration_storage.dart';

const _round = 9007199254740993;
ChatroomInspirationSource _source({
  String owner = 'u',
  String world = 'w',
  String location = 'l',
  int round = _round,
  int sourceCard = 0,
  int? card,
  int tail = 10,
}) => ChatroomInspirationSource(
  ownerUid: owner,
  worldId: world,
  locationId: location,
  roundId: round,
  sourceCardId: sourceCard,
  cardId: card,
  tailMessageId: tail,
);

class _Http implements HttpTransport {
  final requests = <TransportRequest>[];
  Completer<void>? barrier;
  bool offline = false;
  Object? responseOverride;
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    if (offline) throw const SocketException('offline');
    final data = jsonDecode(utf8.decode(request.bodyBytes!)) as Map;
    final result =
        responseOverride ??
        {
          'err_no': 0,
          'err_msg': '',
          'data': {
            'conversation_round_id': data['conversation_round_id'],
            'card_id': data['card_id'] ?? 0,
            'source_card_id': data['card_id'] == 22 ? 0 : data['card_id'] ?? 0,
            'messages': ['First', 'Second', 'Third', 'Fourth'],
            'gateway_request_id': '',
          },
        };
    await barrier?.future;
    return TransportResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(result),
    );
  }
}

class _DelayedStorage extends MemoryChatroomInspirationStorage {
  final saving = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> save(
    ChatroomInspirationSource source,
    ChatroomInspirationResponse value,
  ) async {
    if (!saving.isCompleted) saving.complete();
    await release.future;
    await super.save(source, value);
  }
}

ChatroomHttpApi _api(_Http http) => ChatroomHttpApi(
  ApiClient(
    baseUrl: 'https://example.test/',
    transport: http,
    defaultHeaders: {
      'Authorization': 'Bearer test',
      'x-system-language': 'zh-CN',
    },
    retryPolicy: const ApiRetryPolicy(maxAttempts: 3, methods: {'POST'}),
  ),
);

void main() {
  test(
    'invalidation queued during a SQLite write cannot resurrect the old round',
    () async {
      final storage = _DelayedStorage();
      final controller = ChatroomInspirationController(
        ownerUid: 'u',
        worldId: 'w',
        httpApi: _api(_Http()),
        storage: storage,
      );
      addTearDown(controller.dispose);
      controller.observe('l', roundId: _round, tailMessageId: 10);
      final pending = controller.load(_source());
      await storage.saving.future;
      controller.observe('l', roundId: _round + 1, tailMessageId: 11);
      storage.release.complete();
      expect(await pending, isNull);
      await controller.load(_source(round: _round + 1, tail: 11));
      expect(await storage.load(_source()), isNull);
    },
  );

  test(
    'request fixes refresh=false, preserves int64, headers and a 120-second timeout',
    () async {
      final http = _Http();
      final result = await _api(http).getInspirations(
        worldId: 'w',
        locationId: 'l',
        conversationRoundId: _round,
        cardId: _round + 1,
      );
      final request = http.requests.single;
      expect(
        request.uri.path,
        '/aitown-chat/api/v1/worlds/w/locations/l/inspiration',
      );
      expect(jsonDecode(utf8.decode(request.bodyBytes!)), {
        'conversation_round_id': _round,
        'card_id': _round + 1,
        'refresh': false,
      });
      expect(request.timeoutMs, 120000);
      expect(request.headers['x-system-language'], 'zh-CN');
      expect(result.conversationRoundId, _round);
      expect(result.sourceCardId, _round + 1);
      expect(result.messages, hasLength(4));
      await _api(http).getInspirations(
        worldId: 'w',
        locationId: 'l',
        conversationRoundId: _round,
      );
      expect(
        jsonDecode(utf8.decode(http.requests.last.bodyBytes!)),
        isNot(contains('card_id')),
      );
    },
  );

  test('invalid inputs and responses fail without retries', () async {
    final http = _Http();
    for (final card in [0, -1]) {
      await expectLater(
        _api(http).getInspirations(
          worldId: 'w',
          locationId: 'l',
          conversationRoundId: _round,
          cardId: card,
        ),
        throwsArgumentError,
      );
    }
    expect(http.requests, isEmpty);
    http.offline = true;
    await expectLater(
      _api(http).getInspirations(
        worldId: 'w',
        locationId: 'l',
        conversationRoundId: _round,
      ),
      throwsA(isA<ApiException>()),
    );
    expect(http.requests, hasLength(1));
    http.offline = false;
    for (final response in [
      {'err_no': 5002, 'err_msg': 'save failed', 'data': {}},
      {
        'err_no': 0,
        'data': {
          'conversation_round_id': _round,
          'card_id': 0,
          'source_card_id': 0,
          'messages': [],
          'gateway_request_id': '',
        },
      },
      {
        'err_no': 0,
        'data': {
          'conversation_round_id': '$_round',
          'card_id': 0,
          'source_card_id': 0,
          'messages': ['ok'],
          'gateway_request_id': '',
        },
      },
    ]) {
      http.responseOverride = response;
      await expectLater(
        _api(http).getInspirations(
          worldId: 'w',
          locationId: 'l',
          conversationRoundId: _round,
        ),
        throwsA(isA<ApiException>()),
      );
    }
    expect(http.requests, hasLength(4));
  });

  test(
    'coalesces opens and reuses original inspiration after creating a card',
    () async {
      final http = _Http()..barrier = Completer<void>();
      final controller = ChatroomInspirationController(
        ownerUid: 'u',
        worldId: 'w',
        httpApi: _api(http),
        storage: MemoryChatroomInspirationStorage(),
      );
      addTearDown(controller.dispose);
      controller.observe('l', roundId: _round, tailMessageId: 10);
      final first = controller.load(_source());
      final duplicate = controller.load(_source());
      await Future<void>.delayed(Duration.zero);
      expect(http.requests, hasLength(1));
      http.barrier!.complete();
      expect(await first, same(await duplicate));
      expect(await controller.load(_source(card: 22)), isNotNull);
      expect(http.requests, hasLength(1));
      await controller.load(_source(card: 23, sourceCard: 23));
      await controller.load(_source());
      expect(http.requests, hasLength(2));
    },
  );

  test(
    'formal replies cache the selected source resolved by the server',
    () async {
      final storage = MemoryChatroomInspirationStorage();
      final http = _Http()
        ..responseOverride = {
          'err_no': 0,
          'err_msg': '',
          'data': {
            'conversation_round_id': _round,
            'card_id': 23,
            'source_card_id': 23,
            'messages': ['Selected formal reply'],
            'gateway_request_id': 'request-id',
          },
        };
      final controller = ChatroomInspirationController(
        ownerUid: 'u',
        worldId: 'w',
        httpApi: _api(http),
        storage: storage,
      );
      addTearDown(controller.dispose);
      controller.observe('l', roundId: _round, tailMessageId: 10);
      expect((await controller.load(_source()))!.sourceCardId, 23);
      expect(
        (await storage.load(_source(card: 23, sourceCard: 23)))!.sourceCardId,
        23,
      );
      expect((await storage.load(_source()))!.sourceCardId, 23);
      controller.suspend();
      controller.observe('l', roundId: _round, tailMessageId: 10);
      expect(await controller.load(_source()), isNotNull);
      expect(http.requests, hasLength(1));
    },
  );

  test(
    'switching cards or advancing history discards late results and never saves them',
    () async {
      final storage = MemoryChatroomInspirationStorage();
      final http = _Http()..barrier = Completer<void>();
      final controller = ChatroomInspirationController(
        ownerUid: 'u',
        worldId: 'w',
        httpApi: _api(http),
        storage: storage,
      );
      addTearDown(controller.dispose);
      controller.observe('l', roundId: _round, tailMessageId: 10);
      final old = controller.load(_source());
      await Future<void>.delayed(Duration.zero);
      controller.activate(_source(card: 23, sourceCard: 23));
      http.barrier!.complete();
      expect(await old, isNull);
      expect(await storage.load(_source()), isNull);
      http.barrier = Completer<void>();
      final oldRound = controller.load(_source());
      await Future<void>.delayed(Duration.zero);
      controller.observe('l', roundId: _round + 1, tailMessageId: 11);
      http.barrier!.complete();
      expect(await oldRound, isNull);
      expect(await storage.load(_source()), isNull);
    },
  );

  test(
    'new formal messages invalidate all cards; older pages and replacements do not',
    () async {
      final http = _Http();
      final controller = ChatroomInspirationController(
        ownerUid: 'u',
        worldId: 'w',
        httpApi: _api(http),
        storage: MemoryChatroomInspirationStorage(),
      );
      addTearDown(controller.dispose);
      controller.observe('l', roundId: _round, tailMessageId: 10);
      await controller.load(_source());
      await controller.load(_source(card: 23, sourceCard: 23));
      controller.observe('l', roundId: _round - 1, tailMessageId: 5);
      controller.observe('l', roundId: _round, tailMessageId: 10);
      await controller.load(_source());
      expect(http.requests, hasLength(2));
      controller.observe(
        'l',
        roundId: _round,
        tailMessageId: 11,
        replacing: true,
      );
      await controller.load(_source(tail: 11));
      expect(http.requests, hasLength(2));
      controller.observe('l', roundId: _round, tailMessageId: 12);
      await controller.load(_source(tail: 12));
      await controller.load(_source(card: 23, sourceCard: 23, tail: 12));
      expect(http.requests, hasLength(4));
    },
  );

  test(
    'SQLite survives restart and isolates account, world, location, round and card',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'inspiration-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/inspiration.db';
      final http = _Http();
      final first = SqfliteChatroomInspirationStorage(
        databasePath: path,
        factory: databaseFactoryFfi,
      );
      final response = await _api(http).getInspirations(
        worldId: 'w',
        locationId: 'l',
        conversationRoundId: _round,
      );
      await first.save(_source(), response);
      await first.close();
      final second = SqfliteChatroomInspirationStorage(
        databasePath: path,
        factory: databaseFactoryFfi,
      );
      addTearDown(second.close);
      expect((await second.load(_source()))!.messages, response.messages);
      for (final source in [
        _source(owner: 'other'),
        _source(world: 'other'),
        _source(location: 'other'),
        _source(round: _round + 1),
        _source(sourceCard: 23),
        _source(tail: 11),
      ]) {
        expect(await second.load(source), isNull);
      }
      await second.clearLocation('u', 'w', 'l');
      expect(await second.load(_source()), isNull);
    },
  );

  test(
    'controller restores verified persisted lists and suspends old requests',
    () async {
      final storage = MemoryChatroomInspirationStorage();
      final http = _Http();
      final first = ChatroomInspirationController(
        ownerUid: 'u',
        worldId: 'w',
        httpApi: _api(http),
        storage: storage,
      );
      first.observe('l', roundId: _round, tailMessageId: 10);
      await first.load(_source());
      first.dispose();
      final second = ChatroomInspirationController(
        ownerUid: 'u',
        worldId: 'w',
        httpApi: _api(http),
        storage: storage,
      );
      addTearDown(second.dispose);
      // Loading before authoritative history verification cannot display a cache.
      expect(await second.load(_source()), isNull);
      second.observe('l', roundId: _round, tailMessageId: 10);
      expect(await second.load(_source()), isNotNull);
      expect(http.requests, hasLength(1));
      second.observe('other', roundId: _round, tailMessageId: 10);
      await second.load(_source(location: 'other'));
      second.observe('other', roundId: _round + 1, tailMessageId: 20);
      await second.load(_source());
      expect(http.requests, hasLength(2));
      http.barrier = Completer<void>();
      final pending = second.load(_source(card: 23, sourceCard: 23));
      await Future<void>.delayed(Duration.zero);
      second.suspend();
      http.barrier!.complete();
      expect(await pending, isNull);
      expect(await storage.load(_source(card: 23, sourceCard: 23)), isNull);
    },
  );
}

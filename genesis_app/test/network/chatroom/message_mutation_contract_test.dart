import 'package:genesis_flutter_android/network/chatroom/chatroom_http_models.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_http_api.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_message_storage.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_models.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _largeId = 9007199254740993;

class _Transport implements HttpTransport {
  final requests = <TransportRequest>[];
  Object? response = {
    'err_no': 0,
    'err_msg': 'succ',
    'data': {
      'start_conversation_round_id': _largeId,
      'end_conversation_round_id': _largeId + 2,
      'newest_message_id': 0,
    },
  };
  bool fail = false;
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    if (fail) throw const SocketException('offline');
    return TransportResponse(
      statusCode: 200,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(response),
    );
  }
}

Map<String, dynamic> _edit({Object? id = _largeId}) => {
  'type': 'llm_message_updated',
  'stream_type': '',
  'world_id': 'w',
  'location_id': 'l',
  'global_message_id': id,
  'message_id': _largeId + 1,
  'location_message_id': 3,
  'conversation_round_id': _largeId + 2,
  'payload': {'content': 'edited', 'status': 20},
  'err_no': 0,
};
Map<String, dynamic> _row(int id, int location, int round) => {
  'global_message_id': _largeId + id,
  'message_id': id,
  'location_message_id': location,
  'conversation_round_id': round,
  'location_id': 'l',
  'sender_type': 'character',
  'content': '$id',
};

void main() {
  Future<ChatroomMessageMutationResult> submit(
    ChatroomHttpApi api, {
    int round = _largeId,
    List<ChatroomLlmMessageOperation>? operations,
  }) => api.batchMutateLlmMessages(
    worldId: 'w/a',
    locationId: 'l b',
    conversationRoundId: round,
    operations:
        operations ??
        const [
          ChatroomLlmMessageOperation.edit(
            globalMessageId: _largeId,
            content: '  full\nbody  ',
          ),
          ChatroomLlmMessageOperation.delete(globalMessageId: _largeId + 1),
        ],
  );

  test(
    'batch POST sends one atomic mixed body and preserves int64 and auth',
    () async {
      final transport = _Transport();
      final api = ChatroomHttpApi(
        ApiClient(
          baseUrl: 'https://chat.test/',
          transport: transport,
          requestHeaderProvider: () async => {'Authorization': 'Bearer test'},
          requestInterceptor: (request, send) {
            expect(request.headers['Authorization'], 'Bearer test');
            return send(request);
          },
        ),
      );
      final result = await submit(api);
      expect(result.startConversationRoundId, _largeId);
      expect(result.endConversationRoundId, _largeId + 2);
      expect(result.newestMessageId, 0);
      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(
        request.uri.toString(),
        'https://chat.test/aitown-chat/api/v1/worlds/w%2Fa/locations/l%20b/llm-messages/batch',
      );
      expect(jsonDecode(utf8.decode(request.bodyBytes!)), {
        'conversation_round_id': _largeId,
        'operations': [
          {
            'action': 'edit',
            'global_message_id': _largeId,
            'content': '  full\nbody  ',
          },
          {'action': 'delete', 'global_message_id': _largeId + 1},
        ],
      });
    },
  );

  test('batch validates bounds and duplicates before sending', () async {
    final transport = _Transport();
    final api = ChatroomHttpApi(
      ApiClient(baseUrl: 'https://chat.test/', transport: transport),
    );
    await expectLater(submit(api, round: 0), throwsArgumentError);
    for (final ops in <List<ChatroomLlmMessageOperation>>[
      [],
      List.generate(
        101,
        (i) => ChatroomLlmMessageOperation.delete(globalMessageId: i + 1),
      ),
      const [ChatroomLlmMessageOperation.delete(globalMessageId: 0)],
      const [
        ChatroomLlmMessageOperation.edit(globalMessageId: 1, content: ' \n'),
      ],
      const [
        ChatroomLlmMessageOperation.edit(globalMessageId: 1, content: 'edit'),
        ChatroomLlmMessageOperation.delete(globalMessageId: 1),
      ],
    ]) {
      await expectLater(submit(api, operations: ops), throwsArgumentError);
    }
    expect(transport.requests, isEmpty);
    await submit(
      api,
      operations: List.generate(
        100,
        (i) => ChatroomLlmMessageOperation.delete(globalMessageId: i + 1),
      ),
    );
    expect(transport.requests, hasLength(1));
  });

  test(
    'batch writes override retry policy even on ambiguous network failure',
    () async {
      final transport = _Transport()..fail = true;
      final api = ChatroomHttpApi(
        ApiClient(
          baseUrl: 'https://chat.test/',
          transport: transport,
          retryPolicy: const ApiRetryPolicy(maxAttempts: 3, methods: {'POST'}),
        ),
      );
      await expectLater(submit(api), throwsA(isA<ApiException>()));
      expect(transport.requests, hasLength(1));
    },
  );

  test('batch rejects business errors and malformed success ranges', () async {
    final transport = _Transport();
    final api = ChatroomHttpApi(
      ApiClient(baseUrl: 'https://chat.test/', transport: transport),
    );
    for (final code in [10001, 1001, 1009, 2011, 2012, 2013, 2014, 2004]) {
      transport.response = {
        'err_no': code,
        'err_msg': 'failure',
        'data': false,
      };
      await expectLater(
        submit(api),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', code)),
      );
    }
    for (final response in [
      true,
      {'data': true},
      {'err_no': 0, 'data': false},
      {'err_no': 0, 'data': true},
      for (final data in [
        {},
        {
          'start_conversation_round_id': _largeId.toDouble(),
          'end_conversation_round_id': _largeId + 1,
          'newest_message_id': 0,
        },
        {
          'start_conversation_round_id': _largeId,
          'end_conversation_round_id': _largeId - 1,
          'newest_message_id': 0,
        },
        {
          'start_conversation_round_id': _largeId,
          'end_conversation_round_id': _largeId,
          'newest_message_id': -1,
        },
        {
          'start_conversation_round_id': 1,
          'end_conversation_round_id': 1,
          'newest_message_id': 0,
        },
      ])
        {'err_no': 0, 'data': data},
    ]) {
      transport.response = response;
      await expectLater(
        submit(api),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiExceptionKind.response,
          ),
        ),
      );
    }
  });

  test(
    'history validates round bounds and forwards cancellation and zero cursor',
    () async {
      final transport = _Transport()
        ..response = {
          'err_no': 0,
          'data': {'messages': [], 'has_more': false, 'newest_message_id': 0},
        };
      final api = ChatroomHttpApi(
        ApiClient(baseUrl: 'https://chat.test/', transport: transport),
      );
      final token = NetworkCancellationToken();
      final page = await api.getMessages(
        worldId: 'w',
        locationId: 'l',
        startConversationRoundId: _largeId,
        endConversationRoundId: _largeId + 3,
        since: 0,
        limit: 100,
        cancellationToken: token,
      );
      expect(page.newestMessageId, 0);
      expect(
        transport
            .requests
            .single
            .uri
            .queryParameters['start_conversation_round_id'],
        '$_largeId',
      );
      expect(transport.requests.single.uri.queryParameters['since'], '0');
      expect(transport.requests.single.cancellationToken, same(token));
      for (final bounds in [(1, null), (null, 1), (0, 1), (3, 2), (-1, -1)]) {
        await expectLater(
          api.getMessages(
            worldId: 'w',
            locationId: 'l',
            startConversationRoundId: bounds.$1,
            endConversationRoundId: bounds.$2,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'V2 mutation events preserve int64 IDs and dispatch as control events',
    () {
      final event = chatroomEventFromV2Message(
        ChatroomV2Message.decode(jsonEncode(_edit())),
      );
      expect(event, isA<ChatroomLlmMessageUpdated>());
      expect((event as ChatroomLlmMessageUpdated).globalMessageId, _largeId);
      expect(event.conversationRoundId, _largeId + 2);
      var count = 0;
      ChatroomMessageHandlers(
        onLlmMessageUpdated: (_) => count++,
      ).handle(event);
      final range = chatroomEventFromV2Message(
        ChatroomV2Message.fromJson({
          'type': 'conversation_range_updated',
          'world_id': 'w',
          'location_id': 'l',
          'stream_type': '',
          'payload': {
            'start_conversation_round_id': _largeId,
            'end_conversation_round_id': _largeId + 1,
            'newest_message_id': 0,
          },
        }),
      );
      ChatroomMessageHandlers(
        onConversationRangeUpdated: (_) => count++,
      ).handle(range);
      expect(count, 2);
      expect(chatroomEventType(event), 'llm_message_updated');
      expect(chatroomEventType(range), 'conversation_range_updated');
      expect((range as ChatroomConversationRangeUpdated).newestMessageId, 0);
      for (final json in [
        _edit(id: 1.5),
        _edit()..['stream_type'] = 'llm_chunk',
        _edit()..['world_id'] = '',
        _edit()..['payload'] = {'content': 'x', 'status': 10},
      ]) {
        expect(
          () => chatroomEventFromV2Message(ChatroomV2Message.fromJson(json)),
          throwsA(isA<ChatroomProtocolException>()),
        );
      }
    },
  );

  for (final sqlite in [false, true]) {
    test(
      '${sqlite ? 'SQLite' : 'memory'} replaces empty rounds and reindexed IDs atomically',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chat-mutations-',
        );
        addTearDown(() => directory.delete(recursive: true));
        sqfliteFfiInit();
        final path = '${directory.path}/messages.db';
        ChatroomMessageStorage storage = sqlite
            ? SqfliteChatroomMessageStorage(
                databaseFactoryOverride: databaseFactoryFfi,
                databasePath: path,
              )
            : MemoryChatroomMessageStorage();
        Future<List<Map<String, dynamic>>> load() => storage.loadLatestMessages(
          ownerUid: 'u',
          worldId: 'w',
          locationId: 'l',
          limit: 200,
        );
        await storage.mergeMessages(
          ownerUid: 'u',
          worldId: 'w',
          locationId: 'l',
          messages: [_row(1, 1, 10), _row(2, 2, 11), _row(3, 3, 12)],
        );
        await storage.replaceMessages(
          ownerUid: 'u',
          worldId: 'w',
          locationId: 'l',
          startConversationRoundId: 11,
          endConversationRoundId: 12,
          messages: [_row(3, 2, 12)],
        );
        expect((await load()).map((m) => m['message_id']), [1, 3]);
        expect((await load()).last['location_message_id'], 2);
        if (sqlite) {
          await (storage as SqfliteChatroomMessageStorage).close();
          storage = SqfliteChatroomMessageStorage(
            databaseFactoryOverride: databaseFactoryFfi,
            databasePath: path,
          );
          expect((await load()).map((m) => m['message_id']), [1, 3]);
        }
        final replacement = storage.replaceMessages(
          ownerUid: 'u',
          worldId: 'w',
          locationId: 'l',
          messages: [],
          isCurrent: () => false,
        );
        if (sqlite) {
          await expectLater(replacement, throwsStateError);
        } else {
          await replacement;
        }
        expect((await load()).length, 2);
        await storage.replaceMessages(
          ownerUid: 'u',
          worldId: 'w',
          locationId: 'l',
          startConversationRoundId: 12,
          endConversationRoundId: 12,
          messages: [],
        );
        expect((await load()).map((m) => m['message_id']), [1]);
        await storage.replaceMessages(
          ownerUid: 'u',
          worldId: 'w',
          locationId: 'l',
          messages: [],
        );
        expect(await load(), isEmpty);
        if (sqlite) await (storage as SqfliteChatroomMessageStorage).close();
      },
    );
  }
}

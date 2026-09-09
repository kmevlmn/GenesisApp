import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_client.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_http_api.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_models.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_http_models.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_socket_transport.dart';
import 'package:genesis_flutter_android/network/genesis_api.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/platform/session/memory_user_session_store.dart';

const _id = 9007199254740993;
Map<String, Object?> _selection() => {
  'conversation_round_id': _id,
  'selected_card_id': _id + 1,
  'confirmed': true,
  'start_conversation_round_id': _id,
  'end_conversation_round_id': _id + 2,
  'newest_message_id': 0,
};
Map<String, Object?> _billing([String status = 'reserved']) => {
  'status': status,
  'price_cent': status == 'not_required' ? null : 180,
  'pricing_version': 'round_v3',
};
Map<String, Object?> _regen([String state = 'queued']) => {
  'conversation_round_id': _id,
  'original_card_id': _id + 2,
  'card_id': _id + 1,
  'generation_state': state,
  'billing': _billing(),
  if (state == 'failed') 'error': {'code': 9999, 'message': 'failed'},
};
Map<String, Object?> _cards() => {
  'conversation_round_id': _id,
  'original_card_id': 0,
  'selected_card_id': 0,
  'active_card_id': 0,
  'confirmed': false,
  'can_regenerate': false,
  'can_confirm': false,
  'list': [],
  'total': 0,
};
Map<String, Object?> _frame(
  String type, {
  Map<String, Object?>? payload,
  String stream = '',
  String world = 'w',
  String user = 'u',
  String location = 'l',
  int code = 0,
}) => {
  'type': type,
  'stream_type': stream,
  'world_id': world,
  'location_id': location,
  'user_id': user,
  'conversation_round_id': _id,
  if (type == 'llm_card_stream') 'global_message_id': _id + 3,
  'sender_type': 'character',
  'sender_id': 'c',
  'sender_name': 'Alice',
  'client_msg_id': 'request-1',
  'payload': payload ?? {},
  'err_no': code,
  'err_msg': code == 0 ? '' : 'server failure',
};

Map<String, Object?> _card({int cardId = _id, String content = 'Hello'}) => {
  'card_id': cardId,
  'card_index': 1,
  'is_original': true,
  'generation_state': 'succeeded',
  'can_edit': true,
  'can_delete': false,
  'messages': [
    {
      ..._frame('character', payload: {'content': content}),
      'card_id': cardId,
      'card_message_index': 1,
      'global_message_id': _id + 3,
    },
  ],
  'billing': _billing('not_required'),
  'created_at': '2026-09-08 16:00:00',
};

class _Http implements HttpTransport {
  final requests = <TransportRequest>[];
  Object? data = _selection();
  Object? code = 0;
  bool fail = false;
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    if (fail) throw const SocketException('offline');
    return TransportResponse(
      statusCode: 200,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'err_no': code,
        'err_msg': 'server failure',
        'data': data,
      }),
    );
  }
}

class _Socket implements ChatroomSocket {
  final incoming = StreamController<String>.broadcast();
  final sent = <Map<String, dynamic>>[];
  bool failSend = false;
  @override
  Stream<String> get messages => incoming.stream;
  @override
  Future<void> send(String message) async {
    sent.add(jsonDecode(message) as Map<String, dynamic>);
    if (failSend) throw const SocketException('send failed');
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await incoming.close();
  }

  void emit(Map<String, Object?> frame) => incoming.add(jsonEncode(frame));
}

class _SocketTransport implements ChatroomSocketTransport {
  _SocketTransport(this.socket);
  final _Socket socket;
  @override
  Future<ChatroomSocket> connect(
    Uri uri, {
    Map<String, String>? headers,
  }) async => socket;
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);
Future<ChatroomSession> _session(
  _Socket socket, {
  bool v2 = true,
  bool join = true,
}) async {
  final store = MemoryUserSessionStore();
  await store.saveUid('u');
  await store.saveAuthToken('token');
  final session = await ChatroomClient(
    wsBaseUrl: 'wss://chat.test/ws',
    sessionStore: store,
    transport: _SocketTransport(socket),
    autoHeartbeat: false,
    ackTimeout: const Duration(milliseconds: 100),
    requestHeaderProvider: () async => {
      'x-app-version': v2 ? '0.4.4' : '0.3.3',
    },
  ).connect(worldId: 'w', locationId: 'l');
  addTearDown(session.disconnect);
  if (join && v2) {
    final joined = session.join();
    await _tick();
    socket.emit({
      ..._frame('ack'),
      'client_msg_id': socket.sent.last['client_msg_id'],
    });
    await joined;
  }
  return session;
}

void main() {
  test(
    'Go on sends exact body and accepts a new round before any user echo',
    () async {
      final socket = _Socket();
      final session = await _session(socket);
      final events = <ChatroomEvent>[];
      final subscription = session.events.listen(events.add);
      addTearDown(subscription.cancel);
      final pending = session.goOn(
        locationId: 'l',
        sourceConversationRoundId: _id,
        clientMsgId: 'go-1',
      );
      await _tick();
      expect(socket.sent.last, {
        'type': 'go_on',
        'world_id': 'w',
        'client_msg_id': 'go-1',
        'payload': {'location_id': 'l', 'source_conversation_round_id': _id},
      });
      // A complete round may be broadcast before the receipt arrives.
      for (final type in [
        'waiting_conversation_round',
        'end_conversation_round',
      ]) {
        socket.emit({..._frame(type), 'conversation_round_id': _id + 1});
      }
      socket.emit({
        ..._frame(
          'ack',
          payload: {
            'billing': {
              'price': 1,
              'price_cent': 120,
              'pricing_version': 'round_v3',
            },
          },
        ),
        'conversation_round_id': _id + 1,
        'client_msg_id': 'go-1',
      });
      final receipt = await pending;
      await _tick();
      expect(receipt.sourceConversationRoundId, _id);
      expect(receipt.conversationRoundId, _id + 1);
      expect(receipt.clientMsgId, 'go-1');
      expect(receipt.worldId, 'w');
      expect(receipt.locationId, 'l');
      expect(receipt.billing!.priceCent, 120);
      expect(receipt.billing!.price, 1);
      expect(
        events.whereType<ChatroomWaitingConversationRound>(),
        hasLength(1),
      );
      expect(events.whereType<ChatroomEndConversationRound>(), hasLength(1));
      final ack = events.whereType<ChatroomAck>().single;
      expect(ack.receiptConversationRoundId, _id + 1);
      expect(ack.cardConversationRoundId, _id + 1);
      expect(ack.hasCanonicalMessageMetadata, isFalse);
      expect(events.whereType<ChatroomUserMessage>(), isEmpty);
    },
  );

  test(
    'Go on receipt billing is optional and does not invent missing prices',
    () async {
      final socket = _Socket();
      final session = await _session(socket);
      for (final payload in <Map<String, Object?>>[
        {},
        {'billing': {}},
        {
          'billing': {'price_cent': 0},
        },
      ]) {
        final pending = session.goOn(
          locationId: 'l',
          sourceConversationRoundId: _id,
          clientMsgId: 'go',
        );
        await _tick();
        socket.emit({
          ..._frame('ack', payload: payload),
          'conversation_round_id': _id + 1,
          'client_msg_id': 'go',
        });
        final receipt = await pending;
        if (payload.isEmpty) {
          expect(receipt.billing, isNull);
        } else {
          expect(receipt.billing!.price, isNull);
          expect(receipt.billing!.pricingVersion, isNull);
          expect(
            receipt.billing!.priceCent,
            (payload['billing'] as Map)['price_cent'],
          );
        }
      }
    },
  );

  test(
    'Go on rejects legacy, missing join and invalid arguments without sending',
    () async {
      for (final v2 in [false, true]) {
        final socket = _Socket();
        final session = await _session(socket, v2: v2, join: false);
        await expectLater(
          session.goOn(
            locationId: 'l',
            sourceConversationRoundId: _id,
            clientMsgId: 'go',
          ),
          throwsA(isA<ChatroomProtocolException>()),
        );
        expect(socket.sent, isEmpty);
      }
      final socket = _Socket();
      final session = await _session(socket);
      for (final args in [('', _id, 'go'), ('l', 0, 'go'), ('l', _id, ' ')]) {
        await expectLater(
          session.goOn(
            locationId: args.$1,
            sourceConversationRoundId: args.$2,
            clientMsgId: args.$3,
          ),
          throwsArgumentError,
        );
      }
      await expectLater(
        session.goOn(
          locationId: 'other',
          sourceConversationRoundId: _id,
          clientMsgId: 'go',
        ),
        throwsA(isA<ChatroomProtocolException>()),
      );
      expect(socket.sent, hasLength(1));
    },
  );

  test('Go on timeout, send failure and disconnect never resend', () async {
    for (final outcome in ['timeout', 'send', 'disconnect']) {
      final socket = _Socket();
      final session = await _session(socket);
      socket.failSend = outcome == 'send';
      final pending = session.goOn(
        locationId: 'l',
        sourceConversationRoundId: _id,
        clientMsgId: 'go',
      );
      final assertion = expectLater(
        pending,
        throwsA(isA<ChatroomFailureEvent>()),
      );
      await _tick();
      if (outcome == 'disconnect') await session.disconnect();
      await assertion;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(
        socket.sent.where((frame) => frame['type'] == 'go_on'),
        hasLength(1),
      );
    }
  });

  test(
    'Go on pending IDs, error ACKs and mismatched receipts stay isolated',
    () async {
      final socket = _Socket();
      final session = await _session(socket);
      final first = session.goOn(
        locationId: 'l',
        sourceConversationRoundId: _id,
        clientMsgId: 'go',
      );
      final failed = expectLater(
        first,
        throwsA(
          isA<ChatroomFailureEvent>()
              .having((e) => e.code, 'code', '2015')
              .having((e) => e.requestType, 'request', 'go_on'),
        ),
      );
      await expectLater(
        session.goOn(
          locationId: 'l',
          sourceConversationRoundId: _id,
          clientMsgId: 'go',
        ),
        throwsStateError,
      );
      socket.emit({..._frame('ack', code: 2015), 'client_msg_id': 'go'});
      await failed;
      for (final patch in <Map<String, Object?>>[
        {'world_id': 'other'},
        {'location_id': 'other'},
        {'conversation_round_id': null},
        {'conversation_round_id': 0},
        {'conversation_round_id': _id},
      ]) {
        final pending = session.goOn(
          locationId: 'l',
          sourceConversationRoundId: _id,
          clientMsgId: 'next',
        );
        final assertion = expectLater(
          pending,
          throwsA(isA<ChatroomProtocolException>()),
        );
        await _tick();
        socket.emit({
          ..._frame('ack'),
          'conversation_round_id': _id + 1,
          'client_msg_id': 'next',
          ...patch,
        });
        await assertion;
      }
    },
  );

  test(
    'V2 round errors preserve numeric code and routing without request ID',
    () async {
      final socket = _Socket();
      final session = await _session(socket);
      final errors = <ChatroomErrorEvent>[];
      final failures = <ChatroomFailureEvent>[];
      final a = session.errors.listen(errors.add);
      final b = session.failures.listen(failures.add);
      addTearDown(a.cancel);
      addTearDown(b.cancel);
      final error = _frame('error', code: 2015)..remove('client_msg_id');
      socket.emit(error);
      await _tick();
      await _tick();
      expect(errors.single.errNo, 2015);
      expect(errors.single.code, '2015');
      expect(errors.single.conversationRoundId, '$_id');
      expect(errors.single.worldId, 'w');
      expect(errors.single.locationId, 'l');
      expect(errors.single.userId, 'u');
      expect(errors.single.clientMsgId, isEmpty);
      expect(failures.single.code, '2015');
      expect(failures.single.cause, same(errors.single));
    },
  );

  test(
    'candidate batch uses same endpoint with card ID and returns saved card only',
    () async {
      final transport = _Http()
        ..data = {
          'conversation_round_id': _id,
          'card': _card(content: ' saved '),
        };
      final api = ChatroomHttpApi(
        ApiClient(baseUrl: 'https://chat.test/', transport: transport),
      );
      final result = await api.batchMutateLlmCardMessages(
        worldId: 'w',
        locationId: 'l',
        conversationRoundId: _id,
        cardId: _id,
        operations: const [
          ChatroomLlmMessageOperation.edit(
            globalMessageId: _id + 3,
            content: ' saved ',
          ),
          ChatroomLlmMessageOperation.delete(globalMessageId: _id + 4),
        ],
      );
      expect(result.card.messages.single.content, ' saved ');
      expect(result.card.messages.single.globalMessageId, _id + 3);
      final request = transport.requests.single;
      expect(
        request.uri.path,
        '/aitown-chat/api/v1/worlds/w/locations/l/llm-messages/batch',
      );
      expect(jsonDecode(utf8.decode(request.bodyBytes!)), {
        'conversation_round_id': _id,
        'card_id': _id,
        'operations': [
          {
            'action': 'edit',
            'global_message_id': _id + 3,
            'content': ' saved ',
          },
          {'action': 'delete', 'global_message_id': _id + 4},
        ],
      });
      transport.data = {
        'start_conversation_round_id': _id,
        'end_conversation_round_id': _id,
        'newest_message_id': 0,
      };
      final formal = await api.batchMutateLlmMessages(
        worldId: 'w',
        locationId: 'l',
        conversationRoundId: _id,
        operations: const [
          ChatroomLlmMessageOperation.delete(globalMessageId: _id + 3),
        ],
      );
      expect(formal.newestMessageId, 0);
      expect(
        jsonDecode(
          utf8.decode(transport.requests.last.bodyBytes!),
        ).containsKey('card_id'),
        isFalse,
      );
    },
  );

  test(
    'candidate batch rejects invalid operations, mismatched responses and never retries',
    () async {
      final transport = _Http();
      final api = ChatroomHttpApi(
        ApiClient(baseUrl: 'https://chat.test/', transport: transport),
      );
      Future<ChatroomCardMutationResult> submit({
        int cardId = _id,
        List<ChatroomLlmMessageOperation> operations = const [
          ChatroomLlmMessageOperation.delete(globalMessageId: _id + 3),
        ],
      }) => api.batchMutateLlmCardMessages(
        worldId: 'w',
        locationId: 'l',
        conversationRoundId: _id,
        cardId: cardId,
        operations: operations,
      );
      for (final id in [0, -1]) {
        await expectLater(submit(cardId: id), throwsArgumentError);
      }
      for (final operations in <List<ChatroomLlmMessageOperation>>[
        [],
        List.filled(
          101,
          const ChatroomLlmMessageOperation.delete(globalMessageId: _id),
        ),
        const [
          ChatroomLlmMessageOperation.delete(globalMessageId: _id),
          ChatroomLlmMessageOperation.edit(globalMessageId: _id, content: 'x'),
        ],
        const [
          ChatroomLlmMessageOperation.edit(globalMessageId: _id, content: ' '),
        ],
      ]) {
        await expectLater(submit(operations: operations), throwsArgumentError);
      }
      expect(transport.requests, isEmpty);
      for (final data in [
        {'conversation_round_id': _id + 1, 'card': _card()},
        {'conversation_round_id': _id, 'card': _card(cardId: _id + 1)},
        {'conversation_round_id': _id, 'card': false},
      ]) {
        transport.data = data;
        await expectLater(submit(), throwsA(isA<ApiException>()));
      }
      transport.code = 2025;
      await expectLater(submit(), throwsA(isA<ApiException>()));
      transport.fail = true;
      await expectLater(submit(), throwsA(isA<ApiException>()));
      expect(transport.requests, hasLength(5));
    },
  );

  test(
    'saved card models preserve stable IDs, fixed index gaps and V2 fields',
    () {
      final raw = _card();
      final first = (raw['messages'] as List).single as Map<String, Object?>;
      raw['messages'] = [
        first,
        {...first, 'global_message_id': _id + 4, 'card_message_index': 3},
      ];
      final card = ChatroomLlmCard.fromJson(
        jsonDecode(jsonEncode(raw)),
        conversationRoundId: _id,
      );
      expect(card.messages.map((m) => m.cardMessageIndex), [1, 3]);
      expect(card.messages.last.globalMessageId, _id + 4);
      expect(card.messages.first.message.senderId, 'c');
      expect(card.messages.first.message.payload['content'], 'Hello');
      for (final key in [
        'card_id',
        'global_message_id',
        'conversation_round_id',
        'card_message_index',
      ]) {
        for (final value in ['1', 1.0]) {
          expect(
            () => ChatroomLlmCardMessage.fromJson({...first, key: value}),
            throwsFormatException,
          );
        }
      }
      expect(
        () => ChatroomLlmCardMessage.fromJson({
          ...first,
          'location_message_id': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => ChatroomLlmCard.fromJson({
          ...raw,
          'generation_state': 'failed',
        }, conversationRoundId: _id),
        throwsFormatException,
      );
    },
  );

  test(
    'Go on ignores unrelated ACKs and exposes late receipts without resending',
    () async {
      final socket = _Socket();
      final session = await _session(socket);
      final receipts = <ChatroomAck>[];
      final subscription = session.events
          .where((e) => e is ChatroomAck)
          .cast<ChatroomAck>()
          .listen(receipts.add);
      addTearDown(subscription.cancel);
      final pending = session.goOn(
        locationId: 'l',
        sourceConversationRoundId: _id,
        clientMsgId: 'go',
      );
      final timedOut = expectLater(
        pending,
        throwsA(
          isA<ChatroomFailureEvent>().having(
            (e) => e.code,
            'code',
            'ack_timeout',
          ),
        ),
      );
      await _tick();
      socket.emit({
        ..._frame('ack'),
        'conversation_round_id': _id + 1,
        'client_msg_id': 'unrelated',
      });
      await timedOut;
      socket.emit({
        ..._frame('ack'),
        'conversation_round_id': _id + 1,
        'client_msg_id': 'go',
      });
      await _tick();
      await _tick();
      expect(receipts.last.clientMsgId, 'go');
      expect(receipts.last.receiptConversationRoundId, _id + 1);
      expect(socket.sent.where((f) => f['type'] == 'go_on'), hasLength(1));
    },
  );

  test(
    'new receipt and round error DTOs reject lossy IDs and malformed billing',
    () {
      for (final type in ['ack', 'error']) {
        for (final value in ['9007199254740993', 9007199254740993.toDouble()]) {
          expect(
            () => ChatroomV2Message.fromJson({
              ..._frame(type),
              'conversation_round_id': value,
            }),
            throwsFormatException,
          );
        }
      }
      for (final value in ['2015', 2015.0, null]) {
        expect(
          () =>
              ChatroomV2Message.fromJson({..._frame('error'), 'err_no': value}),
          throwsFormatException,
        );
      }
      for (final value in ['120', 120.0, -1]) {
        expect(
          () => ChatroomRoundBilling.fromJson({'price_cent': value}),
          throwsFormatException,
        );
      }
      expect(
        () => ChatroomRoundBilling.fromJson({'pricing_version': 1}),
        throwsFormatException,
      );
    },
  );

  test('cards query rejects a response for another round', () async {
    final transport = _Http()
      ..data = {..._cards(), 'conversation_round_id': _id + 1};
    final api = ChatroomHttpApi(
      ApiClient(baseUrl: 'https://chat.test/', transport: transport),
    );
    await expectLater(
      api.getLlmCards(worldId: 'w', locationId: 'l', conversationRoundId: _id),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'cards GET and select POST preserve auth, paths, IDs and exact bodies',
    () async {
      final transport = _Http()..data = _cards();
      var intercepted = 0;
      final api = ChatroomHttpApi(
        ApiClient(
          baseUrl: 'https://chat.test/',
          transport: transport,
          requestHeaderProvider: () async => {'Authorization': 'Bearer token'},
          requestInterceptor: (request, send) {
            intercepted++;
            expect(request.headers['Authorization'], 'Bearer token');
            return send(request);
          },
        ),
      );
      final token = NetworkCancellationToken();
      final cards = await api.getLlmCards(
        worldId: 'w/a',
        locationId: 'l b',
        conversationRoundId: _id,
        cancellationToken: token,
      );
      expect(cards.list, isEmpty);
      expect(cards.originalCardId, 0);
      expect(
        transport.requests.single.uri.toString(),
        'https://chat.test/aitown-chat/api/v1/worlds/w%2Fa/locations/l%20b/llm-messages/cards?conversation_round_id=$_id',
      );
      expect(transport.requests.single.cancellationToken, same(token));
      expect(transport.requests.single.bodyBytes, isNull);
      transport.data = _selection();
      final selection = await api.selectLlmCard(
        worldId: 'w/a',
        locationId: 'l b',
        conversationRoundId: _id,
        cardId: _id + 1,
        clientMsgId: 'select-1',
      );
      expect(selection.endConversationRoundId, _id + 2);
      expect(selection.newestMessageId, 0);
      expect(transport.requests.last.method, 'POST');
      expect(jsonDecode(utf8.decode(transport.requests.last.bodyBytes!)), {
        'conversation_round_id': _id,
        'card_id': _id + 1,
        'client_msg_id': 'select-1',
      });
      expect(intercepted, 2);
      expect(transport.requests, hasLength(2));
    },
  );

  test(
    'card HTTP validates parameters and malformed selection without retries',
    () async {
      final transport = _Http();
      final api = ChatroomHttpApi(
        ApiClient(
          baseUrl: 'https://chat.test/',
          transport: transport,
          retryPolicy: const ApiRetryPolicy(maxAttempts: 3, methods: {'POST'}),
        ),
      );
      Future<Object> select({
        int round = _id,
        int card = _id + 1,
        String request = 'id',
      }) => api.selectLlmCard(
        worldId: 'w',
        locationId: 'l',
        conversationRoundId: round,
        cardId: card,
        clientMsgId: request,
      );
      for (final future in [
        select(round: 0),
        select(card: 0),
        select(request: ''),
        select(request: 'a' * 129),
      ]) {
        await expectLater(future, throwsArgumentError);
      }
      expect(transport.requests, isEmpty);
      for (final value in [
        true,
        false,
        {},
        {..._selection(), 'confirmed': false},
        {..._selection(), 'selected_card_id': _id},
        {..._selection(), 'conversation_round_id': _id.toDouble()},
        {..._selection(), 'newest_message_id': -1},
      ]) {
        transport.data = value;
        await expectLater(
          select(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.kind,
              'kind',
              ApiExceptionKind.response,
            ),
          ),
        );
      }
      transport.fail = true;
      final before = transport.requests.length;
      await expectLater(select(), throwsA(isA<ApiException>()));
      expect(transport.requests.length, before + 1);
    },
  );

  test(
    'card HTTP keeps global login and server error toast rules including unknown codes',
    () async {
      final http = _Http();
      final toasts = <String>[];
      var expired = 0;
      final api = GenesisApi(
        transport: http,
        useMock: false,
        sessionStore: MemoryUserSessionStore(),
        appHeaderProvider: () async => {},
        onSessionExpired: (_) async {
          expired++;
        },
        onChatroomMessageMutationError: toasts.add,
      );
      for (final code in [10001, 2020, 2021, 2023, 9876]) {
        http.code = code;
        await expectLater(
          api.chatroomHttp.selectLlmCard(
            worldId: 'w',
            locationId: 'l',
            conversationRoundId: _id,
            cardId: _id + 1,
            clientMsgId: 'id',
          ),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', code)),
        );
      }
      expect(expired, 1);
      expect(toasts, List.filled(4, 'server failure'));
      http.code = 2020;
      await expectLater(
        api.chatroomHttp.getLlmCards(
          worldId: 'w',
          locationId: 'l',
          conversationRoundId: _id,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(toasts, hasLength(5));
    },
  );

  test('cards snapshots preserve unspecified content and billing states', () {
    final raw = {
      ..._cards(),
      'original_card_id': _id,
      'list': [
        {
          ..._card(),
          'opaque_snapshot': {'nested_id': _id + 1},
        },
      ],
      'total': 1,
    };
    final cards = ChatroomLlmCardsResponse.fromJson(raw);
    expect(cards.list.single.rawJson['opaque_snapshot'], {
      'nested_id': _id + 1,
    });
    expect(
      () => ChatroomLlmCardsResponse.fromJson({...raw, 'total': 2}),
      throwsFormatException,
    );
    expect(
      () => ChatroomLlmCardsResponse.fromJson({
        ...raw,
        'original_card_id': _id.toDouble(),
      }),
      throwsFormatException,
    );
    for (final state in [
      'not_required',
      'not_started',
      'reserved',
      'committed',
      'cancelled',
    ]) {
      final billing = ChatroomCardBilling.fromJson(_billing(state));
      expect(billing.priceCent, state == 'not_required' ? isNull : 180);
    }
  });

  test(
    'WS card commands send exact private payloads and return typed receipts',
    () async {
      final socket = _Socket();
      final session = await _session(socket);
      final regen = session.regenerateLlmCard(
        locationId: 'l',
        conversationRoundId: _id,
        clientMsgId: 'request-1',
      );
      await _tick();
      expect(socket.sent.last, {
        'type': 'regenerate_llm_card',
        'world_id': 'w',
        'conversation_round_id': _id,
        'client_msg_id': 'request-1',
        'payload': {'location_id': 'l'},
      });
      await expectLater(
        session.regenerateLlmCard(
          locationId: 'l',
          conversationRoundId: _id,
          clientMsgId: 'request-1',
        ),
        throwsStateError,
      );
      socket.emit(_frame('ack', payload: {'regeneration': _regen()}));
      expect((await regen).generationState, ChatroomCardGenerationState.queued);
      // Manual retry of the same key accepts its existing failed candidate, not a new generation.
      final retry = session.regenerateLlmCard(
        locationId: 'l',
        conversationRoundId: _id,
        clientMsgId: 'request-1',
      );
      await _tick();
      socket.emit(_frame('ack', payload: {'regeneration': _regen('failed')}));
      expect((await retry).error, isNotNull);
      final select = session.selectLlmCard(
        locationId: 'old-location',
        conversationRoundId: _id,
        cardId: _id + 1,
        clientMsgId: 'request-1',
      );
      await _tick();
      expect(socket.sent.last, {
        'type': 'select_llm_card',
        'world_id': 'w',
        'conversation_round_id': _id,
        'client_msg_id': 'request-1',
        'payload': {'location_id': 'old-location', 'card_id': _id + 1},
      });
      socket.emit(
        _frame(
          'ack',
          location: 'old-location',
          payload: {'selection': _selection()},
        ),
      );
      expect((await select).newestMessageId, 0);
      expect(session.streams, isA<Stream<ChatroomAiMessageStream>>());
    },
  );

  test(
    'WS cards require V2 and joined regeneration location, preserve failures, never auto retry',
    () async {
      final socket = _Socket();
      final session = await _session(socket);
      await expectLater(
        session.regenerateLlmCard(
          locationId: 'other',
          conversationRoundId: _id,
          clientMsgId: 'id',
        ),
        throwsA(isA<ChatroomProtocolException>()),
      );
      final rejected = session.regenerateLlmCard(
        locationId: 'l',
        conversationRoundId: _id,
        clientMsgId: 'request-1',
      );
      await _tick();
      final check = expectLater(
        rejected,
        throwsA(
          isA<ChatroomFailureEvent>().having((e) => e.code, 'code', '2023'),
        ),
      );
      socket.emit(_frame('ack', code: 2023));
      await check;
      final timeout = session.regenerateLlmCard(
        locationId: 'l',
        conversationRoundId: _id,
        clientMsgId: 'timeout',
      );
      await expectLater(
        timeout,
        throwsA(
          isA<ChatroomFailureEvent>().having(
            (e) => e.code,
            'code',
            'ack_timeout',
          ),
        ),
      );
      expect(
        socket.sent.where((message) => message['client_msg_id'] == 'timeout'),
        hasLength(1),
      );
      final legacy = await _session(_Socket(), v2: false, join: false);
      await expectLater(
        legacy.selectLlmCard(
          locationId: 'l',
          conversationRoundId: _id,
          cardId: _id + 1,
          clientMsgId: 'id',
        ),
        throwsA(isA<ChatroomProtocolException>()),
      );
    },
  );

  test(
    'private candidate events never append formal streams or emit ACKs',
    () async {
      final socket = _Socket();
      final session = await _session(socket);
      final events = <ChatroomEvent>[];
      final streams = <ChatroomAiMessageStream>[];
      final failures = <ChatroomFailureEvent>[];
      final a = session.events.listen(events.add);
      final b = session.streams.listen(streams.add);
      final c = session.failures.listen(failures.add);
      addTearDown(a.cancel);
      addTearDown(b.cancel);
      addTearDown(c.cancel);
      final before = socket.sent.length;
      final payload = {
        'card_id': _id + 1,
        'card_message_index': 1,
        'seq': 1,
        'content': 'Hello',
      };
      for (final type in ['start', 'chunk', 'end']) {
        socket.emit(_frame('llm_card_stream', stream: type, payload: payload));
      }
      socket.emit(
        _frame(
          'llm_card_generation_end',
          payload: {
            'card_id': _id + 1,
            'generation_state': 'succeeded',
            'billing': _billing(),
          },
        ),
      );
      socket.emit(
        _frame(
          'llm_card_stream',
          world: 'other',
          stream: 'chunk',
          payload: payload,
        ),
      );
      socket.emit(
        _frame(
          'llm_card_stream',
          user: 'other',
          stream: 'chunk',
          payload: payload,
        ),
      );
      socket.emit(
        _frame(
          'llm_card_stream',
          stream: 'chunk',
          payload: {...payload, 'card_id': _id.toDouble()},
        ),
      );
      await _tick();
      await _tick();
      expect(events.whereType<ChatroomLlmCardStream>(), hasLength(3));
      expect(
        events.whereType<ChatroomLlmCardGenerationEnd>().single.generationState,
        ChatroomCardGenerationState.succeeded,
      );
      expect(streams, isEmpty);
      expect(socket.sent.length, before);
      expect(failures.single.code, 'protocol_error');
      expect(events.whereType<ChatroomLlmCardStream>().first.cardId, _id + 1);
      expect(
        events.any(
          (e) => e is ChatroomNarratorMessage || e is ChatroomAiStreamChunk,
        ),
        isFalse,
      );
    },
  );

  test(
    'candidate business errors enter global failure channel without ACK or stream append',
    () async {
      final socket = _Socket();
      final session = await _session(socket);
      final failures = <ChatroomFailureEvent>[];
      final streams = <ChatroomAiMessageStream>[];
      final a = session.failures.listen(failures.add);
      final b = session.streams.listen(streams.add);
      addTearDown(a.cancel);
      addTearDown(b.cancel);
      final sent = socket.sent.length;
      for (final type in ['llm_card_stream', 'llm_card_generation_end']) {
        for (final code in [2023, 10001]) {
          socket.emit(
            _frame(
              type,
              code: code,
              stream: type == 'llm_card_stream' ? 'end' : '',
              payload: {
                'card_id': _id + 1,
                'card_message_index': 1,
                'seq': 1,
                'content': '',
                'generation_state': 'failed',
                'billing': _billing('cancelled'),
              },
            ),
          );
        }
      }
      await _tick();
      expect(failures.map((e) => e.code), ['2023', '10001', '2023', '10001']);
      expect(failures.map((e) => e.message), everyElement('server failure'));
      expect(
        failures.map((e) => e.requestType),
        everyElement('regenerate_llm_card'),
      );
      expect(streams, isEmpty);
      expect(socket.sent.length, sent);
    },
  );

  test('candidate frame validation and handlers isolate malformed input', () {
    ChatroomEvent parse(Map<String, Object?> frame) =>
        chatroomEventFromV2Message(
          ChatroomV2Message.fromJson(Map<String, dynamic>.from(frame)),
        );
    final raw = _frame(
      'llm_card_stream',
      stream: 'chunk',
      payload: {
        'card_id': _id,
        'card_message_index': 1,
        'seq': 1,
        'content': 'x',
      },
    );
    for (final bad in [
      {...raw, 'conversation_round_id': _id.toDouble()},
      {...raw, 'type': 'character'},
      {...raw, 'stream_type': 'llm_chunk'},
      {...raw, 'global_message_id': 0},
      {...raw, 'global_message_id': _id.toDouble()},
      {...raw, 'message_id': _id},
    ]) {
      expect(
        () => parse(bad),
        throwsA(
          anyOf(isA<FormatException>(), isA<ChatroomProtocolException>()),
        ),
      );
    }
    var chunks = 0;
    var ends = 0;
    final handlers = ChatroomMessageHandlers(
      onLlmCardStream: (_) {
        chunks++;
      },
      onLlmCardGenerationEnd: (_) {
        ends++;
      },
    );
    final chunk = parse(raw);
    handlers.handle(chunk);
    expect(chatroomEventType(chunk), 'llm_card_stream');
    final end = parse(
      _frame(
        'llm_card_generation_end',
        code: 9999,
        payload: {
          'card_id': _id,
          'generation_state': 'failed',
          'billing': _billing('cancelled'),
          'error': 'failure',
        },
      ),
    );
    handlers.handle(end);
    expect(chunks, 1);
    expect(ends, 1);
    expect((end as ChatroomLlmCardGenerationEnd).errNo, 9999);
    final ack =
        parse(_frame('ack', payload: {'selection': _selection()}))
            as ChatroomAck;
    expect(ack.cardConversationRoundId, _id);
    expect(ack.hasCanonicalMessageMetadata, isFalse);
    expect(ack.selection!.selectedCardId, _id + 1);
  });
}

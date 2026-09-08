import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_client.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_http_api.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_models.dart';
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
  'sender_type': 'character',
  'sender_id': 'c',
  'sender_name': 'Alice',
  'client_msg_id': 'request-1',
  'payload': payload ?? {},
  'err_no': code,
  'err_msg': code == 0 ? '' : 'server failure',
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
  @override
  Stream<String> get messages => incoming.stream;
  @override
  Future<void> send(String message) async {
    sent.add(jsonDecode(message) as Map<String, dynamic>);
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
          'card_id': _id,
          'opaque_snapshot': {'nested_id': _id + 1},
        },
      ],
      'total': 1,
    };
    final cards = ChatroomLlmCardsResponse.fromJson(raw);
    expect(cards.list.single['opaque_snapshot'], {'nested_id': _id + 1});
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
      {...raw, 'global_message_id': _id},
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

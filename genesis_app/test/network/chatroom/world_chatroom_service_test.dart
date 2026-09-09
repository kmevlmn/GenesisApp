import 'package:genesis_flutter_android/network/api_exception.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_client.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_connection_controller.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_http_models.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_message_storage.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_reply_action_storage.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_models.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_socket_transport.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_timeline_payload.dart';
import 'package:genesis_flutter_android/network/chatroom/world_chatroom_service.dart';
import 'package:genesis_flutter_android/network/genesis_api.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/models/origin.dart';
import 'package:genesis_flutter_android/network/models/world.dart';
import 'package:genesis_flutter_android/platform/device/device_id_service.dart';
import 'package:genesis_flutter_android/platform/session/memory_user_session_store.dart';

void main() {
  _replyCompletionTests();
  _messageMutationTests();
  test('WorldChatroomMessage defaults missing location message id to zero', () {
    final constructed = WorldChatroomMessage(
      messageId: 1,
      locationMessageId: null,
      conversationRoundId: '1',
      roundOrder: 0,
      locationId: 'loc-1',
      senderType: 'character',
      senderId: 'char-1',
      senderName: 'Guide',
      content: 'hello',
      createdAt: null,
    );
    final stored = WorldChatroomMessage.fromStorageJson({
      'msg_id': 2,
      'location_msg_id': null,
      'conversation_round_id': '1',
      'location_id': 'loc-1',
      'sender_type': 'character',
      'sender_id': 'char-1',
      'sender_name': 'Guide',
      'content': 'hello',
      'is_llm_stream': true,
    });

    expect(constructed.locationMessageId, 0);
    expect(constructed.messageType, 'text');
    expect(stored.locationMessageId, 0);
    expect(stored.messageType, 'text');
    expect(stored.isLlmStreamMessage, isTrue);
  });

  test('positive-cursor tick is canonical without a decoded V2 payload', () {
    const canonical = WorldChatroomMessage(
      messageId: 10,
      locationMessageId: 7,
      conversationRoundId: '1',
      roundOrder: 0,
      tickNo: 0,
      locationId: 'loc-1',
      senderType: 'tick',
      businessType: 'tick',
      senderId: 'tick',
      senderName: 'Time',
      content: 'fallback',
      createdAt: null,
    );
    const cursorless = WorldChatroomMessage(
      messageId: 11,
      locationMessageId: 0,
      conversationRoundId: '1',
      roundOrder: 0,
      tickNo: 0,
      locationId: 'loc-1',
      senderType: 'tick',
      businessType: 'tick',
      senderId: 'tick',
      senderName: 'Time',
      content: 'legacy',
      createdAt: null,
    );

    expect(canonical.v2TickPayload, isNull);
    expect(canonical.isV2LocationTick, isTrue);
    expect(cursorless.isV2LocationTick, isFalse);
  });

  test(
    'WorldChatroomMessage normalizes stored message types and copies them',
    () {
      final stored = WorldChatroomMessage.fromStorageJson({
        'msg_id': 2,
        'location_msg_id': 2,
        'location_id': 'loc-1',
        'message_type': ' Future_Format ',
      });

      expect(stored.messageType, 'future_format');
      expect(stored.hasExplicitBusinessType, isFalse);
      final copied = stored.copyWith(locationId: 'loc-2');
      expect(copied.messageType, 'future_format');
      expect(copied.hasExplicitBusinessType, isFalse);
    },
  );

  test(
    'stored V2 type remains explicit and restores its typed Tick payload',
    () {
      final stored = WorldChatroomMessage.fromStorageJson({
        'type': 'tick',
        'sender_type': 'tick',
        'msg_id': 3,
        'location_msg_id': 3,
        'location_id': 'loc-1',
        'message_type': 'text',
        'created_at': '2026-08-10T10:00:00Z',
        'ts': 1,
        'payload': {
          'current_time': 'Day 1',
          'tick_no': 0,
          'sub_tick_no': 0,
          'global': 'A bell rings.',
          'story_events': <Object?>[],
          'characters_moved': <Object?>[],
        },
      });

      expect(stored.hasExplicitBusinessType, isTrue);
      expect(stored.businessType, 'tick');
      expect(stored.v2TickPayload?.globalText, 'A bell rings.');
      expect(stored.createdAt, DateTime.utc(2026, 8, 10, 10));
    },
  );

  test('stored legacy nar_pic messages default to image only when absent', () {
    final legacy = WorldChatroomMessage.fromStorageJson({
      'msg_id': 3,
      'location_msg_id': 3,
      'location_id': 'loc-1',
      'sender_type': 'narrator',
      'sender_id': 'nar_pic',
      'content': 'https://cdn.example.com/legacy.png',
    });
    final explicitText = WorldChatroomMessage.fromStorageJson({
      'msg_id': 4,
      'location_msg_id': 4,
      'location_id': 'loc-1',
      'sender_type': 'narrator',
      'sender_id': 'nar_pic',
      'content': 'This is text',
      'message_type': 'text',
    });

    expect(legacy.messageType, 'image');
    expect(explicitText.messageType, 'text');
  });

  test('plain user enter history synthesizes a timeline payload', () {
    final message = WorldChatroomMessage.fromHttpMessage(
      ChatroomHttpMessage.fromJson({
        'global_message_id': 901,
        'message_id': 101,
        'location_message_id': 11,
        'location_id': 'loc-1',
        'conversation_round_id': 501,
        'sender_type': 'user_enter_location',
        'sender_id': 'char-1',
        'sender_name': 'Alice',
        'user_id': 'user-1',
        'content': 'Alice entered the cafe.',
        'message_type': 'text',
        'created_at': '2026-08-07 12:00:00',
      }),
    );

    expect(message.locationMessageId, 11);
    expect(message.timelinePayload, isA<ChatroomUserEnterLocationPayload>());
    final payload = message.timelinePayload as ChatroomUserEnterLocationPayload;
    expect(payload.charId, 'char-1');
    expect(payload.toLocationId, 'loc-1');
    expect(payload.text, 'Alice entered the cafe.');
  });

  test(
    'message storage keeps an existing LLM stream marker during merge',
    () async {
      final storage = MemoryChatroomMessageStorage();
      await storage.upsertMessage(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        message: {
          'msg_id': 1,
          'location_msg_id': 1,
          'content': r'Line\nTwo',
          'is_llm_stream': true,
        },
      );
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        messages: [
          {'msg_id': 1, 'location_msg_id': 1, 'content': r'Line\nTwo'},
        ],
      );

      final messages = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 1,
      );
      expect(messages.single['is_llm_stream'], isTrue);
    },
  );

  test('setInputBlocked publishes shared composer block state', () async {
    final service = await _service(
      socketTransport: _FakeChatroomTransport(_FakeChatroomSocket()),
    );
    final states = <WorldChatroomState>[];
    final sub = service.states.listen(states.add);

    service.setInputBlocked(true);
    service.setInputBlocked(true);
    service.setInputBlocked(false);
    await Future<void>.delayed(Duration.zero);

    expect(states.map((state) => state.inputBlocked).toList(), [true, false]);
    expect(service.state.inputBlocked, isFalse);

    await sub.cancel();
    await service.dispose();
  });

  test('tick notifications update shared composer block state', () async {
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
    );

    await service.connect(worldId: 'world-1', identity: _identity());

    socket.serverFrame('world_change', {
      'world_id': 'world-1',
      'payload': {'event_type': 'tick_start'},
    });
    await _waitFor(() => service.state.inputBlocked);

    socket.serverFrame('world_change', {
      'world_id': 'world-1',
      'payload': {'event_type': 'tick_done'},
    });
    await _waitFor(() => !service.state.inputBlocked);

    await service.dispose();
  });

  test('new user join notification publishes latest join state', () async {
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
    );

    await service.connect(worldId: 'world-1', identity: _identity());

    socket.serverFrame('new_user_join', {
      'world_id': 'world-1',
      'payload': {
        'char_id': 'char-1',
        'type': 'ai',
        'name': 'Old Name',
        'player_uid': 'user-1',
        'player_username': 'Player One',
      },
    });
    await _waitFor(() => service.state.latestNewUserJoinRevision == 1);

    socket.serverFrame('new_user_join', {
      'world_id': 'world-1',
      'payload': {
        'char_id': 'char-2',
        'type': 'custom',
        'name': 'New Name',
        'player_uid': 'user-2',
        'player_username': 'Player Two',
      },
    });
    await _waitFor(() => service.state.latestNewUserJoinRevision == 2);

    final latest = service.state.latestNewUserJoin;
    expect(latest?.characterId, 'char-2');
    expect(latest?.characterType, 'custom');
    expect(latest?.characterName, 'New Name');
    expect(latest?.playerUid, 'user-2');
    expect(latest?.playerUsername, 'Player Two');

    await service.dispose();
  });

  test('balance_low publishes a low balance alert', () async {
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
    );
    await service.connect(worldId: 'world-1', identity: _identity());
    final alertFuture = service.balanceAlerts.first;

    socket.serverFrame('balance_low', {
      'payload': {'balance_cent': 1000, 'message': 'Low balance'},
    });

    final alert = await alertFuture;
    expect(alert.kind, GemBalanceAlertKind.low);
    expect(alert.balanceCent, 1000);
    expect(alert.message, 'Low balance');
    await service.dispose();
  });

  test('ack 3001 publishes an insufficient balance alert', () async {
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
    );
    await service.connect(worldId: 'world-1', identity: _identity());
    final alerts = <GemBalanceAlert>[];
    final alertSubscription = service.balanceAlerts.listen(alerts.add);

    socket.serverFrame('ack', {
      'payload': {
        'err_no': 3001,
        'err_msg': 'Insufficient balance',
        'err_detail': 'Insufficient balance, please recharge',
      },
    });

    await _waitFor(() => alerts.isNotEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(alerts, hasLength(1));
    final alert = alerts.single;
    expect(alert.kind, GemBalanceAlertKind.insufficient);
    expect(alert.message, 'Insufficient balance, please recharge');
    await alertSubscription.cancel();
    await service.dispose();
  });

  test('connect hydrates world detail and user locations', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
    );

    await service.connect(worldId: 'world-1', identity: _identity());

    expect(service.identity?.senderId, 'user-1');
    expect(service.identity?.senderName, 'Player One');
    expect(service.state.world?.worldId, 'world-1');
    expect(service.state.world?.name, 'World One');
    expect(service.state.locationTree, hasLength(1));
    expect(service.state.entitiesById['char-1']?.locationId, 'loc-1');
    expect(service.state.entitiesById['user-1']?.locationId, 'loc-2');
    expect(service.state.entitiesById['user-1']?.name, 'Role One');
    expect(
      service.state.entitiesByLocation['loc-1']!.map((entity) => entity.id),
      contains('char-1'),
    );
    expect(
      service.state.entitiesByLocation['loc-2']!.map((entity) => entity.id),
      contains('user-1'),
    );
    expect(
      service.state.messagesByLocation.keys,
      containsAll(['loc-1', 'loc-2']),
    );
    expect(service.state.messagesByLocation['loc-1'], isEmpty);
    expect(service.state.messagesByLocation['loc-2'], isEmpty);
    expect(http.detailRequests, 1);
    expect(http.userLocationRequests, 1);
    expect(http.messagesRequestsByLocation, isEmpty);

    await service.dispose();
  });

  test(
    'connect does not warm message caches before opening a location',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport();
      final storage = MemoryChatroomMessageStorage();
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        messages: [
          _httpMessageJson(
            messageId: 1,
            locationId: 'loc-1',
            content: 'cached',
          ),
        ],
      );
      http.messagesByLocation['loc-1'] = [
        _httpMessageJson(messageId: 2, locationId: 'loc-1', content: 'remote'),
      ];
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
      );

      await service.connect(worldId: 'world-1', identity: _identity());

      expect(service.state.messagesByLocation['loc-1'], isEmpty);
      expect(http.messagesRequestsByLocation, isEmpty);
      final cached = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );
      expect(cached.map((message) => message['content']).toList(), ['cached']);
      await service.dispose();
    },
  );

  test(
    'join loads cached location messages before websocket connects',
    () async {
      final socket = _FakeChatroomSocket();
      final connectCompleter = Completer<void>();
      final socketTransport = _BlockingChatroomTransport(
        socket,
        connectCompleter,
      );
      final storage = MemoryChatroomMessageStorage();
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        messages: [
          _httpMessageJson(
            messageId: 1,
            locationId: 'loc-1',
            content: 'cached before socket',
          ),
        ],
      );
      final service = await _service(
        socketTransport: socketTransport,
        messageStorage: storage,
      );

      final connectFuture = service.connect(
        worldId: 'world-1',
        identity: _identity(),
      );
      await _waitFor(() => socketTransport.connectStarted);

      final joinFuture = service.join(locationId: 'loc-1');
      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-1']?.any(
              (message) => message.content == 'cached before socket',
            ) ??
            false,
      );

      expect(socket.sentTypes, isNot(contains('join')));

      connectCompleter.complete();
      await _waitFor(() => socket.sentTypes.contains('join'));
      socket.serverJoinAck();
      await joinFuture;
      await connectFuture;
      await service.dispose();
    },
  );

  test(
    'explicit location entry sends once and automatic reconnect does not resend',
    () async {
      final firstSocket = _FakeChatroomSocket();
      final secondSocket = _FakeChatroomSocket();
      final transport = _SequencedChatroomTransport([
        firstSocket,
        secondSocket,
      ]);
      final service = await _service(
        socketTransport: transport,
        reconnectInterval: const Duration(milliseconds: 5),
      );

      await service.connect(worldId: 'world-1', identity: _identity());
      final firstJoin = service.join(locationId: 'loc-1');
      await _waitFor(() => firstSocket.sentTypes.contains('join'));
      expect(
        firstSocket.sentTypes.where((type) => type == 'user_enter_location'),
        hasLength(1),
      );
      final enterFrame = firstSocket.sent
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .singleWhere((frame) => frame['type'] == 'user_enter_location');
      expect(enterFrame['world_id'], 'world-1');
      expect(enterFrame['payload'], {'loc_id': 'loc-1'});
      expect(enterFrame, isNot(contains('client_msg_id')));
      firstSocket.serverJoinAck();
      await firstJoin;

      await service.join(locationId: 'loc-1');
      expect(
        firstSocket.sentTypes.where((type) => type == 'user_enter_location'),
        hasLength(1),
      );

      await firstSocket.serverClose();
      await _waitFor(() => secondSocket.sentTypes.contains('join'));
      expect(secondSocket.sentTypes, isNot(contains('user_enter_location')));
      secondSocket.serverJoinAck();
      await _waitFor(() => service.state.joinedLocationId == 'loc-1');

      await service.leave();
      final reenter = service.join(locationId: 'loc-1');
      await _waitFor(
        () => secondSocket.sentTypes
            .where((type) => type == 'user_enter_location')
            .isNotEmpty,
      );
      secondSocket.serverJoinAck();
      await reenter;
      expect(
        secondSocket.sentTypes.where((type) => type == 'user_enter_location'),
        hasLength(1),
      );
      await service.dispose();
    },
  );

  test('silent initial entry joins without user_enter_location', () async {
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    final join = service.join(locationId: 'loc-1', announceUserEntry: false);
    await _waitFor(() => socket.sentTypes.contains('join'));

    expect(socket.sentTypes, isNot(contains('user_enter_location')));
    socket.serverJoinAck();
    await join;
    expect(service.state.joinedLocationId, 'loc-1');
    expect(socket.sentTypes, isNot(contains('user_enter_location')));

    await service.dispose();
  });

  test('user_enter_location send failure does not fail join', () async {
    final socket = _FakeChatroomSocket()..failUserEnterLocationSend = true;
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
    );
    final failures = <ChatroomFailureEvent>[];
    final subscription = service.failures.listen(failures.add);

    await service.connect(worldId: 'world-1', identity: _identity());
    final join = service.join(locationId: 'loc-1');
    await _waitFor(() => socket.sentTypes.contains('join'));
    socket.serverJoinAck();
    await join;

    expect(service.state.joinedLocationId, 'loc-1');
    expect(
      failures.where((failure) => failure.sourceType == 'user_enter_location'),
      isEmpty,
    );
    await subscription.cancel();
    await service.dispose();
  });

  test(
    'HTTP image history preserves message type through cache hydration',
    () async {
      final storage = MemoryChatroomMessageStorage();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = [
          _httpMessageJson(
            messageId: 21,
            locationId: 'loc-1',
            content: 'https://cdn.example.com/history.png',
            messageType: ' IMAGE ',
          ),
        ]
        ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
      final service = await _service(
        socketTransport: _FakeChatroomTransport(_FakeChatroomSocket()),
        httpTransport: http,
        messageStorage: storage,
      );

      await service.connect(worldId: 'world-1', identity: _identity());
      final fetched = await service.refreshLatestMessages(locationId: 'loc-1');

      expect(fetched.single.messageType, 'image');
      expect(
        service.state.messagesByLocation['loc-1']!.single.messageType,
        'image',
      );
      final cached = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );
      expect(cached.single['message_type'], 'image');
      await service.dispose();

      final hydratedService = await _service(
        socketTransport: _FakeChatroomTransport(_FakeChatroomSocket()),
        messageStorage: storage,
      );
      await hydratedService.hydrateLocalMessages(
        worldId: 'world-1',
        locationId: 'loc-1',
        ownerUid: 'user-1',
      );

      expect(
        hydratedService.state.messagesByLocation['loc-1']!.single.messageType,
        'image',
      );
      await hydratedService.dispose();
    },
  );

  test('join fetches latest history for the joined location', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport()
      ..messagesByLocation['loc-1'] = [
        _httpMessageJson(
          messageId: 10,
          locationId: 'loc-1',
          content: 'joined history 1',
        ),
        _httpMessageJson(
          messageId: 11,
          locationId: 'loc-1',
          content: 'joined history 2',
        ),
        _httpMessageJson(
          messageId: 12,
          locationId: 'loc-1',
          content: 'joined history 3',
        ),
      ];
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    final historyStateLengths = <int>[];
    final stateSub = service.states.listen((state) {
      final length = state.messagesByLocation['loc-1']?.length;
      if (length != null) historyStateLengths.add(length);
    });
    final joinFuture = service.join(locationId: 'loc-1');
    await _waitFor(() => socket.sentTypes.contains('join'));
    socket.serverJoinAck();
    await joinFuture;

    await _waitFor(
      () =>
          service.state.messagesByLocation['loc-1']?.any(
            (message) => message.content == 'joined history 3',
          ) ??
          false,
    );

    expect(http.worldMessagesRequests, 0);
    expect(http.messageSinceByLocation['loc-1'], [0]);
    expect(historyStateLengths.where((length) => length > 0), contains(3));
    expect(historyStateLengths.where((length) => length > 0).last, 3);
    await stateSub.cancel();
    await service.dispose();
  });

  test(
    'hydrateLocalMessages maps cached location aliases into target queue',
    () async {
      final storage = MemoryChatroomMessageStorage();
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'point-loc-1',
        messages: [
          _httpMessageJson(
            messageId: 1,
            locationId: 'point-loc-1',
            content: 'cached alias message',
          ),
        ],
      );
      final socket = _FakeChatroomSocket();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        messageStorage: storage,
      );

      await service.hydrateLocalMessages(
        worldId: 'world-1',
        locationId: 'scene-loc-1',
        ownerUid: 'user-1',
        locationAliases: const ['point-loc-1'],
      );

      expect(
        service.state.messagesByLocation['scene-loc-1']!
            .map((message) => '${message.locationId}:${message.content}')
            .toList(),
        ['scene-loc-1:cached alias message'],
      );
      expect(service.state.messagesByLocation['point-loc-1'], isNull);
      expect(socket.sentTypes, isEmpty);
      await service.dispose();
    },
  );

  test(
    'hydrateLocalMessages publishes an alias before a slower empty alias',
    () async {
      final storage = _BlockingChatroomMessageStorage('scene-loc-1');
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'point-loc-1',
        messages: [
          _httpMessageJson(
            messageId: 1,
            locationId: 'point-loc-1',
            content: 'cached fast alias message',
          ),
        ],
      );
      final socket = _FakeChatroomSocket();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        messageStorage: storage,
      );

      var hydrateCompleted = false;
      final hydrate = service
          .hydrateLocalMessages(
            worldId: 'world-1',
            locationId: 'scene-loc-1',
            ownerUid: 'user-1',
            locationAliases: const ['point-loc-1'],
          )
          .then((_) => hydrateCompleted = true);

      await _waitFor(
        () =>
            service.state.messagesByLocation['scene-loc-1']?.any(
              (message) => message.content == 'cached fast alias message',
            ) ??
            false,
      );

      expect(hydrateCompleted, false);
      expect(storage.blockingLoadStarted, true);
      expect(socket.sentTypes, isEmpty);

      storage.completeBlockingLoad();
      await hydrate;
      expect(hydrateCompleted, true);
      await service.dispose();
    },
  );

  test('hydrateLocalMessages waits for an in-flight cache load', () async {
    final storage = _BlockingChatroomMessageStorage('point-loc-1');
    await storage.mergeMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'point-loc-1',
      messages: [
        _httpMessageJson(
          messageId: 1,
          locationId: 'point-loc-1',
          content: 'cached after blocking load',
        ),
      ],
    );
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      messageStorage: storage,
    );

    final firstHydrate = service.hydrateLocalMessages(
      worldId: 'world-1',
      locationId: 'scene-loc-1',
      ownerUid: 'user-1',
      locationAliases: const ['point-loc-1'],
    );
    await _waitFor(() => storage.blockingLoadStarted);

    var secondCompleted = false;
    final secondHydrate = service
        .hydrateLocalMessages(
          worldId: 'world-1',
          locationId: 'scene-loc-1',
          ownerUid: 'user-1',
          locationAliases: const ['point-loc-1'],
        )
        .then((_) => secondCompleted = true);
    await Future<void>.delayed(Duration.zero);

    expect(secondCompleted, false);

    storage.completeBlockingLoad();
    await firstHydrate;
    await secondHydrate;

    expect(
      service.state.messagesByLocation['scene-loc-1']!
          .map((message) => message.content)
          .toList(),
      ['cached after blocking load'],
    );
    expect(secondCompleted, true);
    expect(socket.sentTypes, isEmpty);
    await service.dispose();
  });

  test('hydrateLocalMessages loads cache before connect starts', () async {
    final storage = MemoryChatroomMessageStorage();
    await storage.mergeMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      messages: [
        _httpMessageJson(
          messageId: 1,
          locationId: 'loc-1',
          content: 'cached before connect',
        ),
      ],
    );
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      messageStorage: storage,
    );

    await service.hydrateLocalMessages(
      worldId: 'world-1',
      locationId: 'loc-1',
      ownerUid: 'user-1',
    );

    expect(
      service.state.messagesByLocation['loc-1']!
          .map((message) => message.content)
          .toList(),
      ['cached before connect'],
    );
    expect(socket.sentTypes, isEmpty);
    await service.dispose();
  });

  test('connect skips location history warmup', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport()
      ..failedMessageLocationIds.add('loc-1');
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
    );
    final failures = <ChatroomFailureEvent>[];
    final failureSub = service.failures.listen(failures.add);

    await service.connect(worldId: 'world-1', identity: _identity());

    expect(http.messagesRequestsByLocation, isEmpty);
    expect(http.userLocationRequests, 1);
    expect(
      failures.where((failure) => failure.code == 'snapshot_failed'),
      isEmpty,
    );
    await failureSub.cancel();
    await service.dispose();
  });

  test(
    'history messages use requested location when response omits location id',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = [
          _httpMessageJson(
            messageId: 11,
            locationId: '',
            content: 'without location',
          ),
        ]
        ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
      final storage = MemoryChatroomMessageStorage();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
      );

      await service.connect(worldId: 'world-1', identity: _identity());
      final page = await service.loadOlderMessages(
        locationId: 'loc-1',
        beforeMessageId: 100,
        limit: 20,
      );

      final message = service.state.messagesByLocation['loc-1']!.singleWhere(
        (message) => message.messageId == 11,
      );
      expect(page.loadedCount, 1);
      expect(message.globalMessageId, 90011);
      expect(message.locationMessageId, 11);
      expect(message.locationId, 'loc-1');
      final cached = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );
      expect(cached.single['location_id'], 'loc-1');
      expect(cached.single['global_msg_id'], 90011);
      expect(cached.single['location_msg_id'], 11);
      await service.dispose();
    },
  );

  test(
    'chatroom message storage prunes each location to 200 messages',
    () async {
      final storage = MemoryChatroomMessageStorage();
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        messages: [
          for (var id = 1; id <= 205; id += 1)
            _storageMessageJson(
              messageId: id,
              locationId: 'loc-1',
              content: 'message-$id',
            ),
        ],
      );

      final records = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 250,
      );

      expect(records, hasLength(200));
      expect(records.first['msg_id'], 6);
      expect(records.first['global_msg_id'], 90006);
      expect(records.first['location_msg_id'], 6);
      expect(records.last['msg_id'], 205);
      expect(records.last['global_msg_id'], 90205);
      expect(records.last['location_msg_id'], 205);
    },
  );

  test('chatroom message storage loads messages before cursor', () async {
    final storage = MemoryChatroomMessageStorage();
    await storage.mergeMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      messages: [
        for (var id = 1; id <= 5; id += 1)
          _storageMessageJson(
            messageId: id,
            locationId: 'loc-1',
            content: 'message-$id',
          ),
      ],
    );

    final records = await storage.loadMessagesBefore(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      beforeMessageId: 4,
      limit: 2,
    );

    expect(records.map((message) => message['msg_id']).toList(), [2, 3]);
  });

  test(
    'chatroom message storage deletes messages at or before cursor',
    () async {
      final storage = MemoryChatroomMessageStorage();
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        messages: [
          for (var id = 1; id <= 5; id += 1)
            _storageMessageJson(
              messageId: id,
              locationId: 'loc-1',
              content: 'message-$id',
            ),
        ],
      );

      await storage.deleteMessagesAtOrBefore(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        maxLocationMessageId: 2,
      );

      final records = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );
      expect(records.map((message) => message['location_msg_id']).toList(), [
        3,
        4,
        5,
      ]);
    },
  );

  test(
    'chatroom message storage orders and pages by location message id',
    () async {
      final storage = MemoryChatroomMessageStorage();
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        messages: [
          _storageMessageJson(
            messageId: 100,
            locationMessageId: 1,
            locationId: 'loc-1',
            content: 'first in location',
          ),
          _storageMessageJson(
            messageId: 20,
            locationMessageId: 2,
            locationId: 'loc-1',
            content: 'second in location',
          ),
          _storageMessageJson(
            messageId: 30,
            locationMessageId: 3,
            locationId: 'loc-1',
            content: 'third in location',
          ),
        ],
      );

      final latest = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 2,
      );
      expect(latest.map((message) => message['location_msg_id']).toList(), [
        2,
        3,
      ]);
      expect(latest.map((message) => message['msg_id']).toList(), [20, 30]);

      final older = await storage.loadMessagesBefore(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        beforeMessageId: 3,
        limit: 2,
      );
      expect(older.map((message) => message['location_msg_id']).toList(), [
        1,
        2,
      ]);
      expect(older.map((message) => message['msg_id']).toList(), [100, 20]);
    },
  );

  test(
    'chatroom message storage keeps cursorless messages before location ids',
    () async {
      final storage = MemoryChatroomMessageStorage();
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        messages: [
          _storageMessageJson(
            messageId: 100,
            locationMessageId: 0,
            locationId: 'loc-1',
            content: 'missing location queue id',
          ),
          _storageMessageJson(
            messageId: 101,
            locationMessageId: 1,
            locationId: 'loc-1',
            content: 'first location queue message',
          ),
        ],
      );

      final records = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );

      expect(records.map((message) => message['msg_id']).toList(), [100, 101]);
      expect(records.map((message) => message['location_msg_id']).toList(), [
        0,
        1,
      ]);
    },
  );

  test('chatroom message storage orders ticks by message id', () async {
    final storage = MemoryChatroomMessageStorage();
    await storage.mergeMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      messages: [
        _storageMessageJson(
          messageId: 100,
          locationMessageId: 200,
          locationId: 'loc-1',
          content: 'location 200',
        ),
        _storageMessageJson(
          messageId: 150,
          locationMessageId: 0,
          locationId: 'loc-1',
          content: 'tick 150',
          senderType: 'tick',
        ),
        _storageMessageJson(
          messageId: 200,
          locationMessageId: 201,
          locationId: 'loc-1',
          content: 'location 201',
        ),
      ],
    );

    final records = await storage.loadLatestMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      limit: 20,
    );

    expect(records.map((message) => message['msg_id']).toList(), [
      100,
      150,
      200,
    ]);
    expect(records.map((message) => message['location_msg_id']).toList(), [
      200,
      0,
      201,
    ]);
  });

  test(
    'cursorless non-tick timelines stay outside canonical location ordering',
    () async {
      final storage = MemoryChatroomMessageStorage();
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        messages: [
          _storageMessageJson(
            messageId: 100,
            locationMessageId: 10,
            locationId: 'loc-1',
            content: 'location 10',
          ),
          _storageMessageJson(
            messageId: 110,
            locationMessageId: 0,
            locationId: 'loc-1',
            content: '{}',
            senderType: 'story_events',
          ),
          _storageMessageJson(
            messageId: 120,
            locationMessageId: 11,
            locationId: 'loc-1',
            content: 'location 11',
          ),
          _storageMessageJson(
            messageId: 130,
            locationMessageId: 0,
            locationId: 'loc-1',
            content: '{}',
            senderType: 'characters_moved',
          ),
        ],
      );

      final records = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );

      expect(records.map((message) => message['msg_id']).toList(), [
        110,
        130,
        100,
        120,
      ]);
      expect(records.map((message) => message['location_msg_id']).toList(), [
        0,
        0,
        10,
        11,
      ]);
    },
  );

  test('positive location id deduplicates regardless of sender type', () async {
    final storage = MemoryChatroomMessageStorage();
    await storage.mergeMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      messages: [
        _storageMessageJson(
          messageId: 100,
          locationMessageId: 10,
          locationId: 'loc-1',
          content: 'ordinary',
        ),
        _storageMessageJson(
          messageId: 110,
          locationMessageId: 10,
          locationId: 'loc-1',
          content: '{}',
          senderType: chatroomStoryEventsSenderType,
        ),
      ],
    );

    final records = await storage.loadLatestMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      limit: 20,
    );

    expect(records.map((message) => message['msg_id']).toList(), [110]);
    expect(records.map((message) => message['location_msg_id']).toList(), [10]);
  });

  test(
    'only cursorless tick pages and deletes with dual cursor boundaries',
    () async {
      final storage = MemoryChatroomMessageStorage();
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        messages: [
          _storageMessageJson(
            messageId: 100,
            locationMessageId: 10,
            locationId: 'loc-1',
            content: 'location 10',
          ),
          _storageMessageJson(
            messageId: 110,
            locationMessageId: 0,
            locationId: 'loc-1',
            content: '{}',
            senderType: 'user_enter_location',
          ),
          _storageMessageJson(
            messageId: 115,
            locationMessageId: 0,
            locationId: 'loc-1',
            content: 'legacy tick',
            senderType: 'tick',
          ),
          _storageMessageJson(
            messageId: 120,
            locationMessageId: 11,
            locationId: 'loc-1',
            content: 'location 11',
          ),
          _storageMessageJson(
            messageId: 130,
            locationMessageId: 0,
            locationId: 'loc-1',
            content: '{}',
            senderType: 'story_events',
          ),
          _storageMessageJson(
            messageId: 140,
            locationMessageId: 12,
            locationId: 'loc-1',
            content: 'location 12',
          ),
        ],
      );

      final older = await storage.loadMessagesBefore(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        beforeMessageId: 12,
        beforeWorldMessageId: 140,
        limit: 20,
      );
      expect(older.map((message) => message['msg_id']).toList(), [
        100,
        115,
        120,
      ]);

      await storage.deleteMessagesAtOrBefore(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        maxLocationMessageId: 11,
        maxWorldMessageId: 120,
      );
      final remaining = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );
      expect(remaining.map((message) => message['msg_id']).toList(), [
        110,
        130,
        140,
      ]);
    },
  );

  test('clearCachedMessages clears persisted and in-memory history', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport()
      ..messagesByLocation['loc-1'] = const <Map<String, dynamic>>[]
      ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
    final storage = MemoryChatroomMessageStorage();
    await storage.mergeMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      messages: [
        _storageMessageJson(
          messageId: 1,
          locationId: 'loc-1',
          content: 'old-1',
        ),
      ],
    );
    await storage.mergeMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-2',
      messages: [
        _storageMessageJson(
          messageId: 7,
          locationId: 'loc-2',
          content: 'other-location',
        ),
      ],
    );
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
      messageStorage: storage,
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    await service.hydrateLocalMessages(
      worldId: 'world-1',
      locationId: 'loc-1',
      locationAliases: const ['loc-1'],
    );
    expect(service.state.messagesByLocation['loc-1'], isNotEmpty);

    await service.clearCachedMessages();

    final loc1 = await storage.loadLatestMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      limit: 20,
    );
    final loc2 = await storage.loadLatestMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-2',
      limit: 20,
    );

    expect(loc1, isEmpty);
    expect(loc2, isEmpty);
    expect(service.state.messagesByLocation['loc-1'], isEmpty);
    expect(service.state.messagesByLocation['loc-2'], isEmpty);
    expect(service.state.worldMessages, isEmpty);
    await service.dispose();
  });

  test('loadOlderMessages requests remote history before cursor', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport()
      ..messagesByLocation['loc-1'] = [
        _httpMessageJson(
          messageId: 1,
          locationId: 'loc-1',
          content: 'remote-old',
        ),
        _httpMessageJson(
          messageId: 2,
          locationId: 'loc-1',
          content: 'remote-new',
        ),
      ]
      ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    final page = await service.loadOlderMessages(
      locationId: 'loc-1',
      beforeMessageId: 3,
      limit: 20,
    );

    expect(page.loadedCount, 2);
    expect(page.hasMore, isFalse);
    expect(http.messageSinceByLocation['loc-1']?.last, 3);
    expect(
      service.state.messagesByLocation['loc-1']!
          .map((message) => message.content)
          .toList(),
      ['remote-old', 'remote-new'],
    );
    await service.dispose();
  });

  test(
    'loadOlderMessages publishes cached history as one state update',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = const <Map<String, dynamic>>[]
        ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
      final storage = MemoryChatroomMessageStorage();
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        messages: [
          for (var id = 1; id <= 20; id += 1)
            _storageMessageJson(
              messageId: id,
              locationId: 'loc-1',
              content: 'cached-$id',
            ),
        ],
      );
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
      );
      await service.connect(worldId: 'world-1', identity: _identity());
      var stateUpdateCount = 0;
      final stateSubscription = service.states.listen((_) {
        stateUpdateCount += 1;
      });

      final page = await service.loadOlderMessages(
        locationId: 'loc-1',
        beforeMessageId: 21,
        limit: 20,
      );
      await Future<void>.delayed(Duration.zero);

      expect(page.loadedCount, 20);
      expect(service.state.messagesByLocation['loc-1'], hasLength(20));
      expect(stateUpdateCount, 1);
      await stateSubscription.cancel();
      await service.dispose();
    },
  );

  test(
    'flat cursorless timelines join the queue outside location ordering',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = [
          _httpMessageJson(
            messageId: 100,
            locationMessageId: 10,
            locationId: 'loc-1',
            content: 'location ten',
          ),
          _httpMessageJson(
            messageId: 110,
            locationMessageId: 0,
            locationId: '',
            senderType: chatroomUserEnterLocationSenderType,
            content: jsonEncode({
              'char_id': 'char-alice',
              'to_location_id': 'loc-1',
              'text': 'Alice entered.',
            }),
          ),
          _httpMessageJson(
            messageId: 120,
            locationMessageId: 11,
            locationId: 'loc-1',
            content: 'location eleven',
          ),
          _httpMessageJson(
            messageId: 130,
            locationMessageId: 0,
            locationId: '',
            senderType: chatroomStoryEventsSenderType,
            content: jsonEncode({
              'location_id': 'loc-1',
              'location_name': 'Square',
              'paragraphs': [
                {
                  'timestamp': 'Day 2, 10:15',
                  'visibility': 'public',
                  'visible_to': <String>[],
                  'text': 'The bell rang.',
                  'clue': '',
                },
              ],
            }),
          ),
          _httpMessageJson(
            messageId: 135,
            locationMessageId: 0,
            locationId: '',
            senderType: chatroomCharactersMovedSenderType,
            content: jsonEncode({
              'movements': [
                {'char_id': 'char-alice', 'to_loc_id': 'loc-2'},
              ],
            }),
          ),
          _httpMessageJson(
            messageId: 140,
            locationMessageId: 12,
            locationId: 'loc-1',
            content: 'location twelve',
          ),
        ]
        ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
      final storage = MemoryChatroomMessageStorage();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
      );

      await service.connect(worldId: 'world-1', identity: _identity());
      final page = await service.loadOlderMessages(
        locationId: 'loc-1',
        beforeMessageId: 13,
        limit: 20,
      );

      final queue = service.state.messagesByLocation['loc-1']!;
      expect(queue.map((message) => message.messageId).toList(), [
        110,
        130,
        135,
        100,
        120,
        140,
      ]);
      expect(queue.map((message) => message.locationId), everyElement('loc-1'));
      expect(queue[0].timelinePayload, isA<ChatroomUserEnterLocationPayload>());
      expect(queue[1].timelinePayload, isA<ChatroomStoryEventsPayload>());
      expect(queue[2].timelinePayload, isA<ChatroomCharactersMovedPayload>());
      expect(page.loadedCount, 6);
      final cached = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );
      expect(cached.map((message) => message['msg_id']).toList(), [
        110,
        130,
        135,
        100,
        120,
        140,
      ]);
      await service.dispose();
    },
  );

  test(
    'V2 HTTP messages deduplicate by positive location message id',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = [
          _httpMessageJson(
            messageId: 100,
            locationMessageId: 10,
            locationId: 'loc-1',
            content: 'ordinary',
          ),
          _httpMessageJson(
            messageId: 110,
            locationMessageId: 10,
            locationId: 'loc-1',
            senderType: chatroomStoryEventsSenderType,
            content: jsonEncode({
              'location_id': 'loc-1',
              'location_name': 'Square',
              'paragraphs': <Map<String, Object?>>[],
            }),
          ),
        ]
        ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
      final storage = MemoryChatroomMessageStorage();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
      );

      await service.connect(worldId: 'world-1', identity: _identity());
      final page = await service.loadOlderMessages(
        locationId: 'loc-1',
        beforeMessageId: 11,
        limit: 20,
      );

      expect(page.loadedCount, 1);
      expect(
        service.state.messagesByLocation['loc-1']!.map(
          (message) => message.messageId,
        ),
        [110],
      );
      final cached = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );
      expect(cached.map((message) => message['location_msg_id']), [10]);
      await service.dispose();
    },
  );

  test('event-only HTTP page stops a non-advancing location cursor', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport()
      ..messagesByLocation['loc-1'] = [
        for (var messageId = 110; messageId <= 130; messageId += 10)
          _httpMessageJson(
            messageId: messageId,
            locationMessageId: 0,
            locationId: '',
            senderType: chatroomUserEnterLocationSenderType,
            content: jsonEncode({
              'char_id': 'char-$messageId',
              'to_location_id': 'loc-1',
              'text': 'entered $messageId',
            }),
          ),
      ]
      ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    final page = await service.loadOlderMessages(
      locationId: 'loc-1',
      beforeMessageId: 10,
      limit: 2,
    );

    expect(page.loadedCount, 2);
    expect(page.hasMore, isFalse);
    expect(http.messageSinceByLocation['loc-1']?.last, 10);
    await service.dispose();
  });

  test('invalid HTTP timeline payload stays cached but is not typed', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport()
      ..messagesByLocation['loc-1'] = [
        _httpMessageJson(
          messageId: 110,
          locationMessageId: 0,
          locationId: '',
          senderType: chatroomStoryEventsSenderType,
          content: '{"broken":',
        ),
      ]
      ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
    final storage = MemoryChatroomMessageStorage();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
      messageStorage: storage,
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    await service.loadOlderMessages(
      locationId: 'loc-1',
      beforeMessageId: 10,
      limit: 20,
    );

    final message = service.state.messagesByLocation['loc-1']!.single;
    expect(message.timelinePayload, isNull);
    expect(message.content, '{"broken":');
    final cached = await storage.loadLatestMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      limit: 20,
    );
    expect(cached.single['sender_type'], chatroomStoryEventsSenderType);
    expect(cached.single['content'], '{"broken":');
    await service.dispose();
  });

  test('oversized HTTP timeline payload stays raw but is not typed', () async {
    final socket = _FakeChatroomSocket();
    final oversizedContent = jsonEncode({
      'location_id': 'loc-1',
      'location_name': 'Square',
      'paragraphs': [
        {
          'timestamp': '',
          'visibility': 'public',
          'visible_to': <String>[],
          'text': 'x' * (chatroomMaxStringCodeUnits + 1),
          'clue': '',
        },
      ],
    });
    final http = _WorldChatroomHttpTransport()
      ..messagesByLocation['loc-1'] = [
        _httpMessageJson(
          messageId: 111,
          locationMessageId: 0,
          locationId: '',
          senderType: chatroomStoryEventsSenderType,
          content: oversizedContent,
        ),
      ]
      ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
    final storage = MemoryChatroomMessageStorage();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
      messageStorage: storage,
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    await service.loadOlderMessages(
      locationId: 'loc-1',
      beforeMessageId: 10,
      limit: 20,
    );

    final message = service.state.messagesByLocation['loc-1']!.single;
    expect(message.timelinePayload, isNull);
    expect(message.content, oversizedContent);
    final cached = await storage.loadLatestMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      limit: 20,
    );
    expect(cached.single['content'], oversizedContent);
    await service.dispose();
  });

  test(
    'loadOlderMessages trusts explicit remote has_more when page is full',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = [
          for (var id = 1; id <= 20; id += 1)
            _httpMessageJson(
              messageId: id,
              locationId: 'loc-1',
              content: 'remote $id',
            ),
        ]
        ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
      );

      await service.connect(worldId: 'world-1', identity: _identity());
      final page = await service.loadOlderMessages(
        locationId: 'loc-1',
        beforeMessageId: 21,
        limit: 20,
      );

      expect(page.loadedCount, 20);
      expect(page.hasMore, isFalse);
      await service.dispose();
    },
  );

  test(
    'initializeLeafLocationQueues fetches latest history for leaf locations',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = [
          _httpMessageJson(messageId: 1, locationId: 'loc-1', content: 'one'),
        ]
        ..messagesByLocation['loc-2'] = [
          _httpMessageJson(messageId: 2, locationId: 'loc-2', content: 'two'),
        ];
      final storage = MemoryChatroomMessageStorage();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
      );

      service.applyWorldSnapshot(_worldSnapshot());
      await service.connect(worldId: 'world-1', identity: _identity());
      await service.initializeLeafLocationQueues();

      expect(http.worldMessagesRequests, 0);
      expect(http.messageSinceByLocation['loc-1'], [0]);
      expect(http.messageSinceByLocation['loc-2'], [0]);
      expect(
        service.state.messagesByLocation['loc-1']!
            .map((message) => message.content)
            .toList(),
        ['one'],
      );
      final cached = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-2',
        limit: 20,
      );
      expect(cached.single['location_msg_id'], 2);
      await service.dispose();
    },
  );

  test(
    'initializeLeafLocationQueues fills recoverable location id gaps',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = [
          for (var id = 1; id <= 5; id += 1)
            _httpMessageJson(
              messageId: id,
              locationId: 'loc-1',
              content: 'remote-$id',
            ),
        ]
        ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
      final storage = MemoryChatroomMessageStorage();
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        messages: [
          _storageMessageJson(
            messageId: 1,
            locationId: 'loc-1',
            content: 'old-1',
          ),
          _storageMessageJson(
            messageId: 2,
            locationId: 'loc-1',
            content: 'old-2',
          ),
        ],
      );
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
      );

      await service.connect(worldId: 'world-1', identity: _identity());
      await service.hydrateLocalMessages(
        worldId: 'world-1',
        locationId: 'loc-1',
      );
      await service.initializeLeafLocationQueues(
        locationIds: const ['loc-1'],
        latestLimit: 2,
      );

      expect(http.messageSinceByLocation['loc-1'], [0, 4]);
      expect(
        service.state.messagesByLocation['loc-1']!
            .map((message) => message.locationMessageId)
            .toList(),
        [1, 2, 3, 4, 5],
      );
      await service.dispose();
    },
  );

  test(
    'large-gap discard retains cursorless non-tick timeline records',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = [
          _httpMessageJson(
            messageId: 80,
            locationId: 'loc-1',
            content: 'eighty',
          ),
          _httpMessageJson(
            messageId: 81,
            locationId: 'loc-1',
            content: 'newest',
          ),
        ]
        ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
      final storage = MemoryChatroomMessageStorage();
      await storage.mergeMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        messages: [
          _storageMessageJson(
            messageId: 100,
            locationMessageId: 1,
            locationId: 'loc-1',
            content: 'old-1',
          ),
          _storageMessageJson(
            messageId: 105,
            locationMessageId: 0,
            locationId: 'loc-1',
            content: '{}',
            senderType: 'user_enter_location',
          ),
          _storageMessageJson(
            messageId: 110,
            locationMessageId: 0,
            locationId: 'loc-1',
            content: 'legacy tick',
            senderType: 'tick',
          ),
          _storageMessageJson(
            messageId: 115,
            locationMessageId: 0,
            locationId: 'loc-1',
            content: '{}',
            senderType: 'story_events',
          ),
          _storageMessageJson(
            messageId: 120,
            locationMessageId: 2,
            locationId: 'loc-1',
            content: 'old-2',
          ),
        ],
      );
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
      );

      await service.connect(worldId: 'world-1', identity: _identity());
      await service.hydrateLocalMessages(
        worldId: 'world-1',
        locationId: 'loc-1',
      );
      await service.initializeLeafLocationQueues(
        locationIds: const ['loc-1'],
        latestLimit: 2,
      );

      expect(http.messageSinceByLocation['loc-1'], [0]);
      expect(
        service.state.messagesByLocation['loc-1']!
            .map((message) => '${message.senderType}:${message.messageId}')
            .toList(),
        ['user_enter_location:105', 'story_events:115', 'user:80', 'user:81'],
      );
      final cached = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );
      expect(cached.map((message) => message['msg_id']).toList(), [
        105,
        115,
        80,
        81,
      ]);
      await service.dispose();
    },
  );

  test('initializeLeafLocationQueues retries unrecovered gaps twice', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport()
      ..messagesByLocation['loc-1'] = [
        _httpMessageJson(messageId: 1, locationId: 'loc-1', content: 'one'),
        _httpMessageJson(messageId: 2, locationId: 'loc-1', content: 'two'),
        _httpMessageJson(messageId: 4, locationId: 'loc-1', content: 'four'),
        _httpMessageJson(messageId: 5, locationId: 'loc-1', content: 'five'),
      ]
      ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
    final storage = MemoryChatroomMessageStorage();
    await storage.mergeMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      messages: [
        _storageMessageJson(
          messageId: 1,
          locationId: 'loc-1',
          content: 'old-1',
        ),
        _storageMessageJson(
          messageId: 2,
          locationId: 'loc-1',
          content: 'old-2',
        ),
      ],
    );
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
      messageStorage: storage,
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    await service.hydrateLocalMessages(worldId: 'world-1', locationId: 'loc-1');
    await service.initializeLeafLocationQueues(
      locationIds: const ['loc-1'],
      latestLimit: 2,
    );

    expect(http.messageSinceByLocation['loc-1'], [0, 4, 4, 4]);
    expect(
      service.state.messagesByLocation['loc-1']!
          .map((message) => message.locationMessageId)
          .toList(),
      [1, 2, 4, 5],
    );
    await service.dispose();
  });

  test('user message uses required top-level sender id', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport()
      ..messagesByLocation['loc-1'] = const <Map<String, dynamic>>[]
      ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    socket.serverFrame('user_message', {
      'world_id': 'world-1',
      'session_id': 'sess-1',
      'location_id': 'loc-1',
      'user_id': 'user-1',
      'sender_id': 'user-1',
      'sender_name': 'Player One',
      'global_msg_id': 90061,
      'msg_id': 61,
      'location_msg_id': 61,
      'conversation_round_id': 1280,
      'current_time': 'Day 3, 19:46',
      'payload': {'content': '你是谁', 'client_msg_id': 'client-1'},
    });

    await _waitFor(
      () =>
          service.state.messagesByLocation['loc-1']?.any(
            (message) => message.messageId == 61,
          ) ==
          true,
    );
    final message = service.state.messagesByLocation['loc-1']!.singleWhere(
      (message) => message.messageId == 61,
    );
    expect(message.globalMessageId, 90061);
    expect(message.locationMessageId, 61);
    expect(message.userId, 'user-1');
    expect(message.senderId, 'user-1');
    expect(message.clientMsgId, 'client-1');
    expect(message.currentTime, 'Day 3, 19:46');
    expect(service.state.latestSocketCurrentTime, 'Day 3, 19:46');
    expect(service.state.world?.currentTime, 'Day 3, 19:46');
    expect(service.state.latestSocketTickNo, 0);
    expect(service.state.latestSocketCurrentTimeRevision, 1);

    socket.serverFrame('user_message', {
      'world_id': 'world-1',
      'session_id': 'sess-1',
      'location_id': 'loc-1',
      'user_id': 'user-1',
      'sender_id': 'user-1',
      'sender_name': 'Player One',
      'global_msg_id': 90062,
      'msg_id': 62,
      'location_msg_id': 62,
      'conversation_round_id': 1281,
      'payload': {
        'content': '嵌套时间',
        'message': {'current_time': 'Day 3, 19:47'},
      },
    });
    await _waitFor(
      () =>
          service.state.messagesByLocation['loc-1']?.any(
            (message) => message.messageId == 62,
          ) ==
          true,
    );
    final nestedTimeMessage = service.state.messagesByLocation['loc-1']!
        .singleWhere((message) => message.messageId == 62);
    expect(nestedTimeMessage.currentTime, 'Day 3, 19:47');
    expect(service.state.latestSocketCurrentTime, 'Day 3, 19:47');
    expect(service.state.world?.currentTime, 'Day 3, 19:47');
    expect(service.state.latestSocketCurrentTimeRevision, 2);
    await service.dispose();
  });

  test(
    'tick advance push enters every leaf location queue as system time message',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = const <Map<String, dynamic>>[]
        ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
      final storage = MemoryChatroomMessageStorage();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
      );

      await service.connect(worldId: 'world-1', identity: _identity());
      socket.serverFrame('tick_advance', {
        'ts': 1780840607650,
        'world_id': 'world-1',
        'global_msg_id': 90154,
        'msg_id': 154,
        'location_msg_id': 0,
        'conversation_round_id': 1348,
        'current_time': 'Day 45, 19:30',
        'payload': {'content': 'Day 45, 19:30', 'tick_no': 7, 'sub_tick_no': 3},
      });

      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-1']?.any(
                  (message) => message.messageId == 154,
                ) ==
                true &&
            service.state.messagesByLocation['loc-2']?.any(
                  (message) => message.messageId == 154,
                ) ==
                true,
      );
      for (final locationId in const ['loc-1', 'loc-2']) {
        final message = service.state.messagesByLocation[locationId]!
            .singleWhere((message) => message.messageId == 154);
        expect(message.globalMessageId, 90154);
        expect(message.locationMessageId, 0);
        expect(message.locationId, locationId);
        expect(message.senderType, 'tick');
        expect(message.senderId, 'tick');
        expect(message.senderName, 'Time');
        expect(message.tickNo, 7);
        expect(message.subTickNo, 3);
        expect(message.content, 'Day 45, 19:30');
      }
      expect(service.state.latestSocketCurrentTime, 'Day 45, 19:30');
      expect(service.state.latestSocketTickNo, 7);
      expect(service.state.latestSocketSubTickNo, 3);
      expect(service.state.world?.currentTime, 'Day 45, 19:30');
      expect(service.state.world?.tickCount, 7);
      expect(service.state.world?.subTickNo, 3);
      expect(service.state.messagesByLocation.containsKey('loc-root'), isFalse);
      for (final locationId in const ['loc-1', 'loc-2']) {
        final records = await storage.loadLatestMessages(
          ownerUid: 'user-1',
          worldId: 'world-1',
          locationId: locationId,
          limit: 20,
        );
        final cached = records.singleWhere(
          (message) => message['msg_id'] == 154,
        );
        expect(cached['sender_type'], 'tick');
        expect(cached['location_msg_id'], 0);
      }
      await service.dispose();
    },
  );

  test(
    'non-tick push without location message id enters queue before location ids',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = const <Map<String, dynamic>>[]
        ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
      );

      await service.connect(worldId: 'world-1', identity: _identity());
      socket.serverFrame('nar_new_message', {
        'ts': 1780840607640,
        'world_id': 'world-1',
        'payload': {'content': 'valid location message'},
        'global_msg_id': 90155,
        'msg_id': 155,
        'location_msg_id': 55,
        'conversation_round_id': 1349,
        'sender_id': 'nar',
        'sender_name': 'Narrator',
        'location_id': 'loc-1',
      });
      socket.serverFrame('nar_new_message', {
        'ts': 1780840607650,
        'world_id': 'world-1',
        'payload': {'content': '*dirty record without location id*'},
        'global_msg_id': 90156,
        'msg_id': 156,
        'location_msg_id': 0,
        'conversation_round_id': 1350,
        'sender_id': 'char_1',
        'sender_name': 'Character',
        'location_id': 'loc-1',
      });
      socket.serverFrame('nar_new_message', {
        'ts': 1780840607660,
        'world_id': 'world-1',
        'payload': {'content': '*second dirty record without location id*'},
        'global_msg_id': 90157,
        'msg_id': 157,
        'location_msg_id': 0,
        'conversation_round_id': 1350,
        'sender_id': 'char_1',
        'sender_name': 'Character',
        'location_id': 'loc-1',
      });

      await _waitFor(
        () => (service.state.messagesByLocation['loc-1']?.length ?? 0) >= 3,
      );

      expect(
        service.state.messagesByLocation['loc-1']!
            .map((message) => message.messageId)
            .toList(),
        [156, 157, 155],
      );
      final cursorless = service.state.messagesByLocation['loc-1']!.first;
      expect(cursorless.locationMessageId, 0);
      expect(cursorless.content, '*dirty record without location id*');
      expect(
        service.state.worldMessages.any((message) => message.messageId == 156),
        isTrue,
      );
      await service.dispose();
    },
  );

  test('narrator push with top-level fields enters location queue', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport()
      ..messagesByLocation['loc-1'] = const <Map<String, dynamic>>[]
      ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    socket.serverFrame('nar_new_message', {
      'ts': 1780840607650,
      'world_id': 'world-1',
      'payload': {
        'content': 'https://cdn.example.com/narrator.png',
        'message_type': ' IMAGE ',
      },
      'global_msg_id': 90155,
      'msg_id': 155,
      'location_msg_id': 55,
      'conversation_round_id': 1349,
      'sender_id': 'nar',
      'sender_name': '旁白',
      'location_id': 'loc-1',
      'broadcast': true,
    });

    await _waitFor(
      () =>
          service.state.messagesByLocation['loc-1']?.any(
            (message) => message.messageId == 155,
          ) ==
          true,
    );
    final message = service.state.messagesByLocation['loc-1']!.singleWhere(
      (message) => message.messageId == 155,
    );
    expect(message.globalMessageId, 90155);
    expect(message.locationMessageId, 55);
    expect(message.conversationRoundId, '1349');
    expect(message.locationId, 'loc-1');
    expect(message.senderType, 'narrator');
    expect(message.senderId, 'nar');
    expect(message.senderName, '旁白');
    expect(message.content, 'https://cdn.example.com/narrator.png');
    expect(message.messageType, 'image');
    await service.dispose();
  });

  test(
    'narrator image push preserves message type through cache hydration',
    () async {
      final socket = _FakeChatroomSocket();
      final storage = MemoryChatroomMessageStorage();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = const <Map<String, dynamic>>[]
        ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
      );

      await service.connect(worldId: 'world-1', identity: _identity());
      socket.serverFrame('nar_new_message', {
        'ts': 1780840607650,
        'world_id': 'world-1',
        'payload': {
          'content': 'https://cdn.example.com/push.png',
          'message_type': ' IMAGE ',
        },
        'global_msg_id': 90255,
        'msg_id': 255,
        'location_msg_id': 155,
        'conversation_round_id': 1449,
        'sender_id': 'nar_pic',
        'sender_name': '旁白',
        'location_id': 'loc-1',
      });

      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-1']?.any(
              (message) =>
                  message.messageId == 255 && message.messageType == 'image',
            ) ==
            true,
      );
      final cached = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );
      final live = service.state.messagesByLocation['loc-1']!.single;
      expect(live.senderType, 'narrator');
      expect(live.senderId, 'nar_pic');
      expect(cached.single['message_type'], 'image');
      await service.dispose();

      final hydratedService = await _service(
        socketTransport: _FakeChatroomTransport(_FakeChatroomSocket()),
        messageStorage: storage,
      );
      await hydratedService.hydrateLocalMessages(
        worldId: 'world-1',
        locationId: 'loc-1',
        ownerUid: 'user-1',
      );

      final hydrated =
          hydratedService.state.messagesByLocation['loc-1']!.single;
      expect(hydrated.content, 'https://cdn.example.com/push.png');
      expect(hydrated.messageType, 'image');
      await hydratedService.dispose();
    },
  );

  test('narrator push from non-nar sender enters queue as character', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport()
      ..messagesByLocation['loc-1'] = const <Map<String, dynamic>>[]
      ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    socket.serverFrame('nar_new_message', {
      'world_id': 'world-1',
      'payload': {'content': '角色旁白式发言'},
      'global_msg_id': 90156,
      'msg_id': 156,
      'location_msg_id': 56,
      'conversation_round_id': 1350,
      'sender_id': 'char-1',
      'sender_name': 'Alice',
      'location_id': 'loc-1',
      'broadcast': true,
    });

    await _waitFor(
      () =>
          service.state.messagesByLocation['loc-1']?.any(
            (message) => message.messageId == 156,
          ) ==
          true,
    );
    final message = service.state.messagesByLocation['loc-1']!.singleWhere(
      (message) => message.messageId == 156,
    );
    expect(message.globalMessageId, 90156);
    expect(message.locationMessageId, 56);
    expect(message.conversationRoundId, '1350');
    expect(message.senderId, 'char-1');
    expect(message.senderType, 'character');
    expect(message.content, '角色旁白式发言');
    await service.dispose();
  });

  test('active disconnect does not reconnect', () async {
    final socket = _FakeChatroomSocket();
    final transport = _SequencedChatroomTransport([socket]);
    final service = await _service(
      socketTransport: transport,
      heartbeatInterval: const Duration(milliseconds: 5),
      reconnectInterval: const Duration(milliseconds: 5),
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    await service.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(transport.connectCount, 1);
    expect(service.state.reconnecting, false);
    await service.dispose();
  });

  test('socket close reconnects when it was not user initiated', () async {
    final firstSocket = _FakeChatroomSocket();
    final secondSocket = _FakeChatroomSocket();
    final transport = _SequencedChatroomTransport([firstSocket, secondSocket]);
    final service = await _service(
      socketTransport: transport,
      reconnectInterval: const Duration(milliseconds: 5),
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    await firstSocket.serverClose();

    await _waitFor(() => transport.connectCount == 2);
    expect(service.state.reconnecting, false);
    await service.dispose();
  });

  test('disconnect removes provisional stream records only', () async {
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      useV2Protocol: true,
    );
    await service.connect(worldId: 'world-1', identity: _identity());
    socket.serverV2Message(
      type: 'character',
      senderId: 'char-2',
      senderName: 'Bob',
      messageId: 101,
      locationMessageId: 101,
      roundId: 101,
      content: 'keep me',
    );
    socket.serverV2StreamFrame(
      streamType: 'llm_chunk',
      senderId: 'char-1',
      messageId: 0,
      locationMessageId: 0,
      roundId: 102,
      seq: 1,
      content: 'remove me',
    );
    await _waitFor(
      () =>
          service.state.streamMessagesByKey.isNotEmpty &&
          service.state.messagesByLocation['loc-1']?.any(
                (message) => message.streaming,
              ) ==
              true,
    );

    await service.disconnect();

    expect(service.state.streamMessagesByKey, isEmpty);
    expect(
      service.state.worldMessages.any((message) => message.streaming),
      isFalse,
    );
    expect(
      service.state.messagesByLocation.values
          .expand((messages) => messages)
          .any((message) => message.streaming),
      isFalse,
    );
    expect(
      service.state.messagesByLocation['loc-1']?.any(
        (message) => message.content == 'keep me',
      ),
      isTrue,
    );
    await service.dispose();
  });

  test(
    'socket reconnect clears provisional stream and accepts late final',
    () async {
      final firstSocket = _FakeChatroomSocket();
      final secondSocket = _FakeChatroomSocket();
      final transport = _SequencedChatroomTransport([
        firstSocket,
        secondSocket,
      ]);
      final service = await _service(
        socketTransport: transport,
        reconnectInterval: const Duration(milliseconds: 5),
        useV2Protocol: true,
      );
      await service.connect(worldId: 'world-1', identity: _identity());
      firstSocket.serverV2StreamFrame(
        streamType: 'llm_chunk',
        senderId: 'char-1',
        messageId: 102,
        locationMessageId: 102,
        roundId: 103,
        seq: 1,
        content: 'interrupted',
      );
      await _waitFor(() => service.state.streamMessagesByKey.isNotEmpty);

      firstSocket.serverV2StreamFrame(
        streamType: 'llm_chunk',
        senderId: 'char-1',
        messageId: 102,
        locationMessageId: 102,
        roundId: 103,
        seq: 2,
        content: ' queued',
      );
      await firstSocket.serverClose();
      await _waitFor(
        () => transport.connectCount == 2 && service.state.connected,
      );
      expect(service.state.streamMessagesByKey, isEmpty);
      expect(
        service.state.messagesByLocation['loc-1']?.any(
              (message) => message.streaming,
            ) ??
            false,
        isFalse,
      );
      expect(
        service.state.messagesByLocation['loc-1']?.any(
              (message) => message.locationMessageId == 102,
            ) ??
            false,
        isFalse,
      );

      secondSocket.serverV2Message(
        type: 'character',
        senderId: 'char-1',
        senderName: 'Alice',
        messageId: 103,
        locationMessageId: 103,
        roundId: 103,
        content: 'late canonical final',
      );
      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-1']?.any(
              (message) => message.locationMessageId == 103,
            ) ==
            true,
      );
      final lateFinal = service.state.messagesByLocation['loc-1']!.singleWhere(
        (message) => message.locationMessageId == 103,
      );
      expect(lateFinal.content, 'late canonical final');
      expect(lateFinal.streaming, isFalse);
      await service.dispose();
    },
  );

  test('heartbeat sends frames without ack timeout reconnects', () async {
    final firstSocket = _FakeChatroomSocket();
    final secondSocket = _FakeChatroomSocket();
    final transport = _SequencedChatroomTransport([firstSocket, secondSocket]);
    final service = await _service(
      socketTransport: transport,
      heartbeatInterval: const Duration(milliseconds: 5),
      reconnectInterval: const Duration(milliseconds: 5),
      ackTimeout: const Duration(milliseconds: 5),
    );

    await service.connect(worldId: 'world-1', identity: _identity());

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(transport.connectCount, 1);
    expect(
      firstSocket.sentTypes.where((type) => type == 'heartbeat').length,
      greaterThanOrEqualTo(1),
    );
    await service.dispose();
  });

  test('world_change and user_location_change refresh snapshots', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
    );

    await service.connect(worldId: 'world-1', identity: _identity());

    http.worldName = 'World Changed';
    socket.serverFrame('world_change', {
      'world_id': 'world-1',
      'payload': {'event_type': 'world_change', 'current_time': 'Day 9, 10:00'},
    });
    await _waitFor(() => service.state.world?.name == 'World Changed');
    expect(service.state.latestSocketCurrentTime, 'Day 9, 10:00');

    http.userLocationId = 'loc-1';
    socket.serverFrame('user_location_change', {
      'world_id': 'world-1',
      'payload': {
        'event_type': 'user_location_change',
        'currentTime': 'Day 9, 10:01',
      },
    });
    await _waitFor(
      () => service.state.entitiesById['user-1']?.locationId == 'loc-1',
    );
    expect(service.state.latestSocketCurrentTime, 'Day 9, 10:01');
    expect(service.state.entitiesById['user-1']?.name, 'Role One');
    expect(service.state.entitiesById['user-1']?.name, isNot('Player One'));

    expect(http.detailRequests, 2);
    expect(http.userLocationRequests, 2);
    await service.dispose();
  });

  test(
    'user_enter_location refreshes the local user location snapshot',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()..userLocationId = 'loc-1';
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        refreshInitialSnapshotOnConnect: false,
      );
      service.applyWorldSnapshot(_worldSnapshot());
      await service.connect(worldId: 'world-1', identity: _identity());

      socket.serverFrame('user_enter_location', {
        'schema_version': 1,
        'event_id': 'evt-enter-1',
        'world_id': 'world-1',
        'location_id': 'loc-1',
        'payload': {
          'char_id': 'char-user-1',
          'to_location_id': 'loc-1',
          'text': 'Role One entered Square',
        },
      });

      await _waitFor(
        () => service.state.entitiesById['user-1']?.locationId == 'loc-1',
      );
      expect(http.userLocationRequests, 1);
      expect(http.detailRequests, 0);
      expect(
        service.state.entitiesByLocation['loc-1']?.map((entity) => entity.id),
        contains('user-1'),
      );
      expect(
        service.state.world?.userPositions.any(
          (position) =>
              position['uid'] == 'user-1' && position['location_id'] == 'loc-1',
        ),
        isTrue,
      );
      await service.dispose();
    },
  );

  test(
    'canonical user_enter_location is persisted and refreshes locations',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()..userLocationId = 'loc-1';
      final storage = _RecordingChatroomMessageStorage();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
        refreshInitialSnapshotOnConnect: false,
      );
      service.applyWorldSnapshot(_worldSnapshot());
      await service.connect(worldId: 'world-1', identity: _identity());

      socket.serverFrame('user_enter_location', {
        'ts': 1786000000000,
        'world_id': 'world-1',
        'session_id': 'sess-1',
        'global_msg_id': 1006,
        'msg_id': 506,
        'location_msg_id': 203,
        'conversation_round_id': 126,
        'user_id': 'user-1',
        'sender_id': 'char-user-1',
        'sender_name': 'Role One',
        'location_id': 'loc-1',
        'err_no': '',
        'err_msg': '',
        'broadcast': true,
        'payload': {
          'content': 'Role One entered Square.',
          'message_type': 'text',
        },
      });

      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-1']?.any(
              (message) => message.messageId == 506,
            ) ==
            true,
      );
      await _waitFor(() => http.userLocationRequests == 1);
      final message = service.state.messagesByLocation['loc-1']!.singleWhere(
        (message) => message.messageId == 506,
      );
      expect(message.locationMessageId, 203);
      expect(message.senderType, 'user_enter_location');
      expect(message.userId, 'user-1');
      expect(message.content, 'Role One entered Square.');
      expect(message.timelinePayload, isA<ChatroomUserEnterLocationPayload>());
      expect(storage.lastUpsertedMessage?['location_msg_id'], 203);
      expect(
        storage.lastUpsertedMessage?['content'],
        'Role One entered Square.',
      );

      http.messagesByLocation['loc-1'] = [
        {
          'global_message_id': 1006,
          'message_id': 506,
          'location_message_id': 203,
          'location_id': 'loc-1',
          'conversation_round_id': 126,
          'tick_no': 0,
          'sender_type': 'user_enter_location',
          'sender_id': 'char-user-1',
          'sender_name': 'HTTP Role One',
          'user_id': 'user-1',
          'content': 'Role One entered Square.',
          'message_type': 'text',
          'current_time': '',
          'created_at': '2026-08-07 10:00:00',
        },
      ];
      await service.refreshLatestMessages(locationId: 'loc-1');

      final merged = service.state.messagesByLocation['loc-1']!;
      expect(merged, hasLength(1));
      expect(merged.single.messageId, 506);
      expect(merged.single.locationMessageId, 203);
      expect(merged.single.senderName, 'HTTP Role One');
      expect(
        merged.single.timelinePayload,
        isA<ChatroomUserEnterLocationPayload>(),
      );
      final cached = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );
      expect(cached, hasLength(1));
      expect(cached.single['msg_id'], 506);
      await service.dispose();
    },
  );

  test(
    'user location event storm keeps one active and one trailing refresh',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _SequencedUserLocationsHttpTransport();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        refreshInitialSnapshotOnConnect: false,
      );
      service.applyWorldSnapshot(_worldSnapshot());
      await service.connect(worldId: 'world-1', identity: _identity());

      socket.serverFrame('user_enter_location', {
        'schema_version': 1,
        'event_id': 'evt-enter-older',
        'world_id': 'world-1',
        'location_id': 'loc-2',
        'payload': {
          'char_id': 'char-user-1',
          'to_location_id': 'loc-2',
          'text': 'Role One entered Cafe',
        },
      });
      await _waitFor(() => http.pendingUserLocations.length == 1);

      for (var index = 1; index < 100; index += 1) {
        socket.serverFrame('user_enter_location', {
          'schema_version': 1,
          'event_id': 'evt-enter-$index',
          'world_id': 'world-1',
          'location_id': 'loc-1',
          'payload': {
            'char_id': 'char-user-1',
            'to_location_id': 'loc-1',
            'text': 'Role One entered Square',
          },
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(http.pendingUserLocations, hasLength(1));

      http.pendingUserLocations[0].complete('loc-2');
      await _waitFor(() => http.pendingUserLocations.length == 2);
      http.pendingUserLocations[1].complete('loc-1');
      await _waitFor(
        () => service.state.entitiesById['user-1']?.locationId == 'loc-1',
      );

      expect(http.userLocationRequests, 2);
      expect(service.state.entitiesById['user-1']?.locationId, 'loc-1');
      await service.dispose();
    },
  );

  test(
    'characters moved event storm keeps one active and one trailing history refresh',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _SequencedWorldMessagesHttpTransport();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        refreshInitialSnapshotOnConnect: false,
      );
      service.applyWorldSnapshot(_worldSnapshot());
      await service.connect(worldId: 'world-1', identity: _identity());

      for (var index = 0; index < 100; index += 1) {
        socket.serverFrame('characters_moved', {
          'event_id': 'evt-moved-storm-$index',
          'world_id': 'world-1',
          'payload': {
            'movements': [
              {'char_id': 'char-1', 'to_loc_id': 'loc-2'},
            ],
          },
        });
      }
      await _waitFor(() => http.pendingWorldMessages.length == 2);
      await _waitFor(
        () =>
            (service.state.messagesByLocation['loc-1'] ?? const []).length ==
            100,
      );
      expect(http.worldMessagesRequests, 0);

      http.pendingWorldMessages[0].complete();
      http.pendingWorldMessages[1].complete();
      await _waitFor(() => http.pendingWorldMessages.length == 4);
      http.pendingWorldMessages[2].complete();
      http.pendingWorldMessages[3].complete();
      await _waitFor(() => http.completedWorldMessages == 4);

      expect(http.messagesRequests, 4);
      expect(http.messagesRequestsByLocation['loc-1'], 2);
      expect(http.messagesRequestsByLocation['loc-2'], 2);
      await service.dispose();
    },
  );

  test(
    'disposing during a refresh drops its state commit and errors',
    () async {
      final unhandledErrors = <Object>[];

      await runZonedGuarded<Future<void>>(() async {
        final socket = _FakeChatroomSocket();
        final http = _SequencedUserLocationsHttpTransport();
        final service = await _service(
          socketTransport: _FakeChatroomTransport(socket),
          httpTransport: http,
          refreshInitialSnapshotOnConnect: false,
        );
        service.applyWorldSnapshot(_worldSnapshot());
        await service.connect(worldId: 'world-1', identity: _identity());

        socket.serverFrame('user_enter_location', {
          'event_id': 'evt-enter-dispose',
          'world_id': 'world-1',
          'location_id': 'loc-1',
          'payload': {
            'char_id': 'char-user-1',
            'to_location_id': 'loc-1',
            'text': 'Role One entered Square',
          },
        });
        await _waitFor(() => http.pendingUserLocations.length == 1);

        await service.dispose();
        http.pendingUserLocations.single.complete('loc-1');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(service.state.entitiesById['user-1']?.locationId, 'loc-2');
      }, (error, _) => unhandledErrors.add(error));

      expect(unhandledErrors, isEmpty);
    },
  );

  test(
    'dispose skips a queued event location refresh without unhandled errors',
    () async {
      final unhandledErrors = <Object>[];

      await runZonedGuarded<Future<void>>(() async {
        final socket = _FakeChatroomSocket();
        final http = _BlockingWorldDetailHttpTransport();
        final service = await _service(
          socketTransport: _FakeChatroomTransport(socket),
          httpTransport: http,
          refreshInitialSnapshotOnConnect: false,
        );
        service.applyWorldSnapshot(_worldSnapshot());
        await service.connect(worldId: 'world-1', identity: _identity());

        socket.serverFrame('world_change', {
          'world_id': 'world-1',
          'payload': {'event_type': 'world_change'},
        });
        await _waitFor(() => http.worldDetailStarted);

        socket.serverFrame('world_new_message', {
          'world_id': 'world-1',
          'location_id': 'loc-1',
          'payload': {'event_type': 'world_new_message'},
        });
        await Future<void>.delayed(Duration.zero);
        final dispose = service.dispose();
        http.completeWorldDetail();
        await dispose;
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(http.detailRequests, 1);
        expect(http.messagesRequests, 0);
      }, (error, _) => unhandledErrors.add(error));

      expect(unhandledErrors, isEmpty);
    },
  );

  test(
    'world content notifications share one detail refresh and publish new items',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        refreshInitialSnapshotOnConnect: false,
      );
      await service.connect(worldId: 'world-1', identity: _identity());
      await service.refreshWorldSnapshot();
      http.detailRequests = 0;
      http.worldTickCount = 1;
      const newCharacterAvatarUrl =
          'https://cdn-001.worldo.ai/app/uploads/20260702/'
          '2072507310906806272_356_356.jpg?x-oss-process=image/format,webp';
      const newLocationImageUrl =
          'https://cdn-001.worldo.ai/app/uploads/20260702/'
          '2072508055576121344_640_360.jpg?x-oss-process=image/format,webp';
      http.charactersOverride = [
        ...http.defaultCharacters,
        {
          'char_id': 'char-new',
          'type': 'ai',
          'name': 'New Wanderer',
          'identity': 'Wandering swordsman',
          'avatar': newCharacterAvatarUrl,
          'location_id': 'loc-new',
          'is_new': true,
        },
      ];
      http.locationsOverride = [
        ...http.defaultLocations,
        {
          'location_id': 'loc-harbor-district',
          'location_pid': 'loc-root',
          'name': 'Harbor District',
          'is_new': false,
        },
        {
          'location_id': 'loc-new',
          'location_pid': 'loc-harbor-district',
          'name': 'New Harbor',
          'description': 'Harbor desc',
          'image': newLocationImageUrl,
          'is_new': true,
        },
      ];

      socket.serverFrame('world_change', {
        'world_id': 'world-1',
        'payload': <String, Object?>{},
      });
      socket.serverFrame('map_updated', {
        'world_id': 'world-1',
        'payload': <String, Object?>{},
      });
      socket.serverFrame('character_updated', {
        'world_id': 'world-1',
        'payload': <String, Object?>{},
      });
      socket.serverFrame('tick_done', {
        'world_id': 'world-1',
        'payload': <String, Object?>{},
      });
      await _waitFor(() => service.state.contentUpdateNoticeRevision == 1);

      expect(service.state.mapUpdatedRevision, 1);
      expect(http.detailRequests, 1);
      expect(
        service.state.latestContentUpdateNotices
            .map((notice) => notice.kind)
            .toList(growable: false),
        const [
          WorldContentUpdateKind.location,
          WorldContentUpdateKind.character,
        ],
      );
      expect(
        service.state.latestContentUpdateNotices
            .map((notice) => notice.entityId)
            .toList(growable: false),
        const ['loc-new', 'char-new'],
      );
      expect(
        service.state.latestContentUpdateNotices.last.targetLocationId,
        'loc-new',
      );
      final locationNotice = service.state.latestContentUpdateNotices
          .singleWhere(
            (notice) => notice.kind == WorldContentUpdateKind.location,
          );
      expect(locationNotice.entityId, 'loc-new');
      expect(locationNotice.name, 'New Harbor');
      expect(locationNotice.avatarUrl, newLocationImageUrl);
      expect(locationNotice.contextLabel, 'Harbor District');
      final characterNotice = service.state.latestContentUpdateNotices
          .singleWhere(
            (notice) => notice.kind == WorldContentUpdateKind.character,
          );
      expect(characterNotice.entityId, 'char-new');
      expect(characterNotice.name, 'New Wanderer');
      expect(characterNotice.avatarUrl, newCharacterAvatarUrl);
      expect(characterNotice.contextLabel, 'Wandering swordsman');
      expect(http.userLocationRequests, 0);
      expect(http.worldMessagesRequests, 0);
      expect(http.messagesRequests, 0);

      http.worldTickCount = 2;
      http.locationsOverride = [
        ...http.locationsOverride!,
        {
          'location_id': 'loc-not-marked-new',
          'location_pid': 'loc-root',
          'name': 'Existing Harbor',
          'description': 'Harbor desc',
          'is_new': false,
        },
      ];
      http.charactersOverride = [
        ...http.charactersOverride!,
        {
          'char_id': 'char-not-marked-new',
          'type': 'ai',
          'name': 'Existing Wanderer',
          'avatar': 'wanderer.png',
          'location_id': 'loc-new',
          'is_new': false,
        },
      ];
      socket.serverFrame('map_updated', {
        'world_id': 'world-1',
        'payload': <String, Object?>{},
      });
      socket.serverFrame('character_updated', {
        'world_id': 'world-1',
        'payload': <String, Object?>{},
      });
      await _waitFor(() => http.detailRequests == 2);
      await _waitFor(() => service.state.world?.tickCount == 2);

      // Existing IDs remain marked is_new=true, while the newly added IDs are
      // is_new=false. Neither case satisfies both notification conditions.
      expect(service.state.contentUpdateNoticeRevision, 1);
      expect(
        service.state.latestContentUpdateNotices
            .map((notice) => notice.entityId)
            .toList(growable: false),
        const ['loc-new', 'char-new'],
      );
      await service.dispose();
    },
  );

  test(
    'characters_moved is persisted and replaced by matching HTTP message id',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport();
      final storage = _RecordingChatroomMessageStorage();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
        refreshInitialSnapshotOnConnect: false,
      );
      service.applyWorldSnapshot(_worldSnapshot());
      await service.connect(worldId: 'world-1', identity: _identity());
      const socketPayload = ChatroomCharactersMovedPayload(
        movements: [
          ChatroomCharacterMovement(charId: 'char-1', toLocationId: 'loc-2'),
        ],
      );

      socket.serverFrame('characters_moved', {
        'schema_version': 1,
        'event_id': 'evt-moved-233',
        'ts': 1785890000000,
        'world_id': 'world-1',
        'location_id': 'loc-1',
        'global_msg_id': 5627,
        'msg_id': 233,
        'location_msg_id': 33,
        'conversation_round_id': 6817,
        'sender_id': 'sub_tick',
        'sender_name': 'SubTick',
        'current_time': 'Day 2, 00:09:15',
        'tick_no': 4,
        'sub_tick_no': 1,
        'payload': socketPayload.toJson(),
      });

      await _waitFor(
        () => service.state.messagesByLocation['loc-1']?.length == 1,
      );
      final socketMessage = service.state.messagesByLocation['loc-1']!.single;
      expect(socketMessage.globalMessageId, 5627);
      expect(socketMessage.messageId, 233);
      expect(socketMessage.locationMessageId, 33);
      expect(socketMessage.locationId, 'loc-1');
      expect(socketMessage.conversationRoundId, '6817');
      expect(socketMessage.senderType, chatroomCharactersMovedSenderType);
      expect(socketMessage.senderId, 'sub_tick');
      expect(socketMessage.senderName, 'SubTick');
      expect(socketMessage.tickNo, 4);
      expect(socketMessage.subTickNo, 1);
      expect(socketMessage.currentTime, 'Day 2, 00:09:15');
      expect(
        socketMessage.timelinePayload,
        isA<ChatroomCharactersMovedPayload>(),
      );
      expect(
        (socketMessage.timelinePayload as ChatroomCharactersMovedPayload)
            .movements
            .single
            .toLocationId,
        'loc-2',
      );
      expect(service.state.worldMessages, hasLength(1));
      expect(service.state.worldMessages.single.messageId, 233);
      expect(service.state.lastMessageId, 233);
      expect(http.detailRequests, 0);
      expect(http.userLocationRequests, 0);
      expect(http.worldMessagesRequests, 0);
      expect(http.messagesRequests, 0);

      await _waitFor(() => storage.lastUpsertedMessage?['msg_id'] == 233);
      expect(storage.lastUpsertedMessage?['global_msg_id'], 5627);
      expect(storage.lastUpsertedMessage?['location_msg_id'], 33);
      expect(storage.lastUpsertedMessage?['location_id'], 'loc-1');
      expect(storage.lastUpsertedMessage?['current_time'], 'Day 2, 00:09:15');
      final restored = WorldChatroomMessage.fromStorageJson(
        storage.lastUpsertedMessage!,
      );
      expect(restored.timelinePayload, isA<ChatroomCharactersMovedPayload>());
      expect(restored.tickNo, 4);
      expect(restored.subTickNo, 1);

      const httpPayload = ChatroomCharactersMovedPayload(
        movements: [
          ChatroomCharacterMovement(charId: 'char-1', toLocationId: 'loc-3'),
        ],
      );
      http.messagesByLocation['loc-1'] = [
        {
          'global_message_id': 5627,
          'message_id': 233,
          'location_message_id': 33,
          'location_id': 'loc-1',
          'conversation_round_id': 6817,
          'tick_no': 4,
          'sub_tick_no': 1,
          'sender_type': chatroomCharactersMovedSenderType,
          'sender_id': 'sub_tick',
          'sender_name': 'HTTP SubTick',
          'user_id': null,
          'content': encodeChatroomTimelinePayload(httpPayload),
          'message_type': 'text',
          'current_time': 'Day 2, 00:09:15',
          'created_at': '2026-08-06 20:57:54',
        },
      ];
      await service.refreshLatestMessages(locationId: 'loc-1');

      final merged = service.state.messagesByLocation['loc-1']!;
      expect(merged, hasLength(1));
      expect(merged.single.messageId, 233);
      expect(merged.single.senderName, 'HTTP SubTick');
      expect(
        (merged.single.timelinePayload as ChatroomCharactersMovedPayload)
            .movements
            .single
            .toLocationId,
        'loc-3',
      );
      expect(service.state.worldMessages, hasLength(1));
      expect(service.state.worldMessages.single.senderName, 'HTTP SubTick');
      final cached = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );
      expect(cached, hasLength(1));
      expect(cached.single['msg_id'], 233);
      expect(cached.single['sender_name'], 'HTTP SubTick');
      await service.dispose();
    },
  );

  test(
    'broadcast characters_moved is copied into every leaf location queue',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        refreshInitialSnapshotOnConnect: false,
      );
      service.applyWorldSnapshot(_worldSnapshot());
      await service.connect(worldId: 'world-1', identity: _identity());

      socket.serverFrame('characters_moved', {
        'event_id': 'evt-moved-broadcast',
        'world_id': 'world-1',
        'msg_id': 234,
        'broadcast': true,
        'payload': {
          'movements': [
            {'char_id': 'char-1', 'to_loc_id': 'loc-2'},
          ],
        },
      });

      await _waitFor(
        () =>
            (service.state.messagesByLocation['loc-1'] ?? const []).any(
              (message) => message.messageId == 234,
            ) &&
            (service.state.messagesByLocation['loc-2'] ?? const []).any(
              (message) => message.messageId == 234,
            ),
      );
      expect(service.state.worldMessages, hasLength(1));
      expect(http.worldMessagesRequests, 0);
      expect(http.messagesRequests, 0);
      await service.dispose();
    },
  );

  test(
    'legacy characters_moved enters queues before canonical HTTP is available',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport()
        ..messagesByLocation['loc-1'] = <Map<String, dynamic>>[]
        ..messagesByLocation['loc-2'] = <Map<String, dynamic>>[];
      const payload = ChatroomCharactersMovedPayload(
        movements: [
          ChatroomCharacterMovement(charId: 'char-1', toLocationId: 'loc-2'),
        ],
      );
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        refreshInitialSnapshotOnConnect: false,
      );
      service.applyWorldSnapshot(_worldSnapshot());
      await service.connect(worldId: 'world-1', identity: _identity());

      socket.serverFrame('characters_moved', {
        'event_id': 'evt-moved-without-canonical',
        'world_id': 'world-1',
        'payload': payload.toJson(),
      });

      await _waitFor(
        () =>
            (service.state.messagesByLocation['loc-1'] ?? const []).any(
              (message) =>
                  message.senderType == chatroomCharactersMovedSenderType,
            ) &&
            (service.state.messagesByLocation['loc-2'] ?? const []).any(
              (message) =>
                  message.senderType == chatroomCharactersMovedSenderType,
            ),
      );
      final loc1Message = service.state.messagesByLocation['loc-1']!.single;
      expect(loc1Message.conversationRoundId, startsWith('ws-event:'));
      expect(
        encodeChatroomTimelinePayload(loc1Message.timelinePayload!),
        encodeChatroomTimelinePayload(payload),
      );
      await _waitFor(
        () =>
            http.messagesRequestsByLocation['loc-1'] == 1 &&
            http.messagesRequestsByLocation['loc-2'] == 1,
      );
      expect(http.worldMessagesRequests, 0);
      await service.dispose();
    },
  );

  test(
    'legacy characters_moved notification fetches canonical HTTP message',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport();
      const payload = ChatroomCharactersMovedPayload(
        movements: [
          ChatroomCharacterMovement(charId: 'char-1', toLocationId: 'loc-2'),
        ],
      );
      http.messagesByLocation
        ..['loc-1'] = [
          {
            'global_message_id': 5628,
            'message_id': 235,
            'location_message_id': 34,
            'location_id': 'loc-1',
            'conversation_round_id': 6818,
            'sender_type': chatroomCharactersMovedSenderType,
            'sender_id': 'sub_tick',
            'sender_name': 'SubTick',
            'content': encodeChatroomTimelinePayload(payload),
            'message_type': 'text',
          },
        ]
        ..['loc-2'] = <Map<String, dynamic>>[];
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        refreshInitialSnapshotOnConnect: false,
      );
      service.applyWorldSnapshot(_worldSnapshot());
      await service.connect(worldId: 'world-1', identity: _identity());

      socket.serverFrame('characters_moved', {
        'event_id': 'evt-moved-legacy',
        'world_id': 'world-1',
        'payload': payload.toJson(),
      });

      await _waitFor(
        () =>
            http.messagesRequestsByLocation['loc-1'] == 1 &&
            http.messagesRequestsByLocation['loc-2'] == 1 &&
            service.state.messagesByLocation['loc-1']?.any(
                  (message) => message.messageId == 235,
                ) ==
                true,
      );
      expect(
        service.state.messagesByLocation['loc-1']!
            .singleWhere((message) => message.messageId == 235)
            .timelinePayload,
        isA<ChatroomCharactersMovedPayload>(),
      );
      expect(http.worldMessagesRequests, 0);
      expect(http.messagesRequests, 2);
      await service.dispose();
    },
  );

  test(
    'story_events is persisted and replaced by matching HTTP message id',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport();
      final storage = _RecordingChatroomMessageStorage();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        messageStorage: storage,
        refreshInitialSnapshotOnConnect: false,
      );
      service.applyWorldSnapshot(_worldSnapshot());
      await service.connect(worldId: 'world-1', identity: _identity());
      const storyPayload = ChatroomStoryEventsPayload(
        locationId: 'loc-1',
        locationName: 'Square',
        paragraphs: [
          ChatroomStoryEventParagraph(
            timestamp: 'Day 1, 08:00',
            visibility: 'public',
            visibleTo: <String>[],
            text: 'A bell rang.',
            clue: '',
          ),
        ],
      );

      socket.serverFrame('story_events', {
        'schema_version': 1,
        'event_id': 'evt-story-232',
        'ts': 1785890000000,
        'world_id': 'world-1',
        'location_id': 'loc-1',
        'global_msg_id': 5626,
        'msg_id': 232,
        'location_msg_id': 0,
        'conversation_round_id': 6816,
        'sender_id': 'sub_tick',
        'sender_name': 'sub_tick',
        'current_time': 'Day 2, 00:09:15',
        'tick_no': 4,
        'sub_tick_no': 1,
        'payload': storyPayload.toJson(),
      });

      await _waitFor(
        () => service.state.messagesByLocation['loc-1']?.length == 1,
      );
      final socketMessage = service.state.messagesByLocation['loc-1']!.single;
      expect(socketMessage.messageId, 232);
      expect(socketMessage.senderType, chatroomStoryEventsSenderType);
      expect(socketMessage.tickNo, 4);
      expect(socketMessage.subTickNo, 1);
      expect(socketMessage.currentTime, 'Day 2, 00:09:15');
      expect(socketMessage.timelinePayload, isA<ChatroomStoryEventsPayload>());
      expect(service.state.lastMessageId, 232);
      await _waitFor(() => storage.lastUpsertedMessage?['msg_id'] == 232);
      expect(storage.lastUpsertedMessage?['sub_tick_no'], 1);
      final restored = WorldChatroomMessage.fromStorageJson(
        storage.lastUpsertedMessage!,
      );
      expect(restored.tickNo, 4);
      expect(restored.subTickNo, 1);
      expect(restored.currentTime, 'Day 2, 00:09:15');

      http.messagesByLocation['loc-1'] = [
        {
          'global_message_id': 5626,
          'message_id': 232,
          'location_message_id': 0,
          'location_id': 'loc-1',
          'conversation_round_id': 6816,
          'tick_no': 4,
          'sub_tick_no': 1,
          'sender_type': chatroomStoryEventsSenderType,
          'sender_id': 'sub_tick',
          'sender_name': 'HTTP sub tick',
          'user_id': null,
          'content': encodeChatroomTimelinePayload(storyPayload),
          'message_type': '',
          'current_time': 'Day 2, 00:09:15',
          'created_at': '2026-08-04 18:46:33',
        },
      ];
      await service.refreshLatestMessages(locationId: 'loc-1');

      final merged = service.state.messagesByLocation['loc-1']!;
      expect(merged, hasLength(1));
      expect(merged.single.messageId, 232);
      expect(merged.single.subTickNo, 0);
      expect(merged.single.senderName, 'HTTP sub tick');
      expect(merged.single.timelinePayload, isA<ChatroomStoryEventsPayload>());
      final cached = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 20,
      );
      expect(cached, hasLength(1));
      expect(cached.single['msg_id'], 232);
      await service.dispose();
    },
  );

  test(
    'snapshot-seeded connect waits for push events before refetching',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        refreshInitialSnapshotOnConnect: false,
      );
      service.applyWorldSnapshot(_worldSnapshot());

      await service.connect(worldId: 'world-1', identity: _identity());
      expect(http.detailRequests, 0);
      expect(http.userLocationRequests, 0);

      http.worldName = 'World Changed';
      socket.serverFrame('world_change', {
        'world_id': 'world-1',
        'payload': {'event_type': 'world_change'},
      });
      await _waitFor(() => service.state.world?.name == 'World Changed');
      expect(http.detailRequests, 1);
      expect(http.userLocationRequests, 0);

      http.userLocationId = 'loc-1';
      socket.serverFrame('user_location_change', {
        'world_id': 'world-1',
        'payload': {'event_type': 'user_location_change'},
      });
      await _waitFor(
        () =>
            service.state.world?.characters.any(
              (character) =>
                  character['player_uid'] == 'user-1' &&
                  character['location_id'] == 'loc-1',
            ) ==
            true,
      );
      expect(http.detailRequests, 1);
      expect(http.userLocationRequests, 1);
      expect(
        service.state.world?.characterPositions.any(
          (position) =>
              position['location_id'] == 'loc-1' &&
              (position['character'] as Map?)?['name'] == 'Role One' &&
              (position['character'] as Map?)?['player_uid'] == 'user-1',
        ),
        true,
      );
      await service.dispose();
    },
  );

  test(
    'user_location_change removes a role that leaves every location',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _WorldChatroomHttpTransport();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        refreshInitialSnapshotOnConnect: false,
      );
      service.applyWorldSnapshot(_worldSnapshot());

      await service.connect(worldId: 'world-1', identity: _identity());
      expect(service.state.entitiesByLocation['loc-2'], isNotEmpty);

      http.userLocationId = null;
      socket.serverFrame('user_location_change', {
        'world_id': 'world-1',
        'payload': {'event_type': 'user_location_change'},
      });

      await _waitFor(
        () =>
            service.state.world?.characters.any(
              (character) =>
                  character['player_uid'] == 'user-1' &&
                  !character.containsKey('location_id'),
            ) ==
            true,
      );

      expect(service.state.entitiesById['user-1']?.locationId, isEmpty);
      expect(
        service.state.entitiesByLocation['loc-2']?.map((entity) => entity.id),
        isNot(contains('user-1')),
      );
      expect(
        service.state.world?.characterPositions.any(
          (position) => (position['character'] as Map?)?['name'] == 'Role One',
        ),
        false,
      );
      expect(service.state.world?.userPositions, isEmpty);

      await service.dispose();
    },
  );

  test('world snapshot resolves image object role avatars', () async {
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      refreshInitialSnapshotOnConnect: false,
    );
    final avatar = {
      'sm_url': 'https://cdn.example.com/role-sm.png',
      'xl_url': 'https://cdn.example.com/role-xl.png',
      'object_key': 'avatars/role.png',
    };

    service.applyWorldSnapshot(
      _worldSnapshot().copyWith(
        characters: [
          {
            'char_id': 'char-user-1',
            'type': 'player',
            'player_uid': 'user-1',
            'name': 'Role One',
            'avatar': avatar,
            'location_id': 'loc-2',
          },
        ],
        characterPositions: [
          {
            'location_id': 'loc-2',
            'character': {
              'id': 'char-user-1',
              'type': 'player',
              'player_uid': 'user-1',
              'name': 'Role One',
              'avatar': avatar,
            },
          },
        ],
        userPositions: const <Map<String, dynamic>>[],
      ),
    );

    expect(
      service.state.entitiesById['user-1']?.avatarUrl,
      'https://cdn.example.com/role-xl.png',
    );
    expect(
      service.state.entitiesByLocation['loc-2']?.single.avatarUrl,
      'https://cdn.example.com/role-xl.png',
    );

    await service.dispose();
  });

  test('push message id gaps do not fetch missing messages', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport()
      ..messagesByLocation['loc-1'] = [
        _httpMessageJson(
          messageId: 1,
          locationId: 'loc-1',
          content: 'loc-1-first',
        ),
        _httpMessageJson(
          messageId: 2,
          locationId: 'loc-1',
          content: 'loc-1-gap',
        ),
      ]
      ..messagesByLocation['loc-2'] = const <Map<String, dynamic>>[];
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    socket.serverUserMessage(messageId: 1, roundId: 1, content: 'loc-1-one');
    await _waitFor(
      () =>
          service.state.messagesByLocation['loc-1']?.any(
            (message) => message.messageId == 1,
          ) ==
          true,
    );

    socket.serverUserMessage(messageId: 3, roundId: 3, content: 'loc-1-three');
    await _waitFor(
      () =>
          service.state.messagesByLocation['loc-1']?.any(
            (message) => message.messageId == 3,
          ) ==
          true,
    );

    expect(http.messagesRequestsByLocation['loc-1'], isNull);
    expect(
      service.state.messagesByLocation['loc-1']!
          .map((message) => message.messageId)
          .toList(),
      [1, 3],
    );
    await service.dispose();
  });

  test('V2 send resolves receipt before canonical echo', () async {
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      ackTimeout: const Duration(milliseconds: 500),
      useV2Protocol: true,
    );
    await service.connect(worldId: 'world-1', identity: _identity());

    final handle = service.sendMessage(
      'hello',
      clientMsgId: 'client-ack-first',
    );
    var canonicalCompleted = false;
    unawaited(
      handle.canonicalMessage.then((_) {
        canonicalCompleted = true;
      }),
    );
    await _waitFor(() => socket.sentTypes.contains('send_message'));

    socket.serverV2Ack(clientMsgId: handle.clientMsgId);
    final receipt = await handle.receipt;
    expect(receipt.clientMsgId, 'client-ack-first');
    expect(canonicalCompleted, isFalse);

    socket.serverV2Message(
      type: 'user',
      senderId: 'user-1',
      senderName: 'Player One',
      messageId: 70,
      locationMessageId: 7,
      roundId: 700,
      content: 'hello',
      clientMsgId: handle.clientMsgId,
    );
    final canonical = await handle.canonicalMessage;
    expect(canonical.globalMessageId, 90070);
    expect(canonical.messageId, 70);
    expect(canonical.locationMessageId, 7);
    expect(canonical.conversationRoundId, '700');
    expect(canonical.clientMsgId, handle.clientMsgId);
    await service.dispose();
  });

  test(
    'V2 send stays locked after character messages until matching end',
    () async {
      final socket = _FakeChatroomSocket();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        ackTimeout: const Duration(milliseconds: 500),
        useV2Protocol: true,
      );
      await service.connect(worldId: 'world-1', identity: _identity());
      final joinFuture = service.join(locationId: 'loc-1');
      await _waitFor(() => socket.sentTypes.contains('join'));
      final joinFrame = socket.sent
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .lastWhere((frame) => frame['type'] == 'join');
      socket.serverV2Ack(clientMsgId: joinFrame['client_msg_id'] as String);
      await joinFuture;

      final handle = service.sendMessage('hello', clientMsgId: 'client-round');
      var roundState = service.state.conversationRoundStatesByLocation['loc-1'];
      expect(roundState?.phase, ConversationRoundPhase.submitting);
      expect(roundState?.clientMsgId, 'client-round');

      await _waitFor(() => socket.sentTypes.contains('send_message'));
      socket.serverV2Ack(clientMsgId: handle.clientMsgId);
      await handle.receipt;
      roundState = service.state.conversationRoundStatesByLocation['loc-1'];
      expect(roundState?.phase, ConversationRoundPhase.awaitingRound);

      socket.serverV2Message(
        type: 'user',
        senderId: 'user-1',
        senderName: 'Player One',
        messageId: 71,
        locationMessageId: 8,
        roundId: 701,
        content: 'hello',
        clientMsgId: handle.clientMsgId,
      );
      await handle.canonicalMessage;
      await _waitFor(
        () =>
            service
                .state
                .conversationRoundStatesByLocation['loc-1']
                ?.conversationRoundId ==
            '701',
      );

      socket.serverV2Message(
        type: 'character',
        senderId: 'char-1',
        senderName: 'Alice',
        messageId: 72,
        locationMessageId: 9,
        roundId: 701,
        content: 'finished character response',
      );
      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-1']?.any(
              (message) => message.locationMessageId == 9,
            ) ==
            true,
      );
      expect(
        service.state.conversationRoundStatesByLocation['loc-1'],
        isNotNull,
      );

      socket.serverEndConversationRound(locationId: 'loc-1', roundId: 701);
      await _waitFor(
        () => !service.state.conversationRoundStatesByLocation.containsKey(
          'loc-1',
        ),
      );
      await service.dispose();
    },
  );

  test('V2 send fallback starts when waiting event is missing', () async {
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      ackTimeout: const Duration(milliseconds: 500),
      conversationRoundTimeout: const Duration(milliseconds: 30),
      useV2Protocol: true,
    );
    await service.connect(worldId: 'world-1', identity: _identity());
    final joinFuture = service.join(locationId: 'loc-1');
    await _waitFor(() => socket.sentTypes.contains('join'));
    final joinFrame = socket.sent
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .lastWhere((frame) => frame['type'] == 'join');
    socket.serverV2Ack(clientMsgId: joinFrame['client_msg_id'] as String);
    await joinFuture;

    final handle = service.sendMessage(
      'hello without waiting',
      clientMsgId: 'client-no-waiting',
    );
    await _waitFor(() => socket.sentTypes.contains('send_message'));
    socket.serverV2Ack(clientMsgId: handle.clientMsgId);
    await handle.receipt;
    expect(
      service.state.conversationRoundStatesByLocation['loc-1']?.phase,
      ConversationRoundPhase.awaitingRound,
    );

    await _waitFor(
      () =>
          !service.state.conversationRoundStatesByLocation.containsKey('loc-1'),
    );
    await service.dispose();
  });

  test(
    'V2 waiting conversation round locks until matching end event',
    () async {
      final socket = _FakeChatroomSocket();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        useV2Protocol: true,
      );
      await service.connect(worldId: 'world-1', identity: _identity());

      socket.serverWaitingConversationRound(locationId: 'loc-1', roundId: 301);
      await _waitFor(
        () =>
            service.state.waitingConversationRoundIdsByLocation['loc-1'] ==
            '301',
      );

      socket.serverWaitingConversationRound(locationId: 'loc-1', roundId: 301);
      socket.serverWaitingConversationRound(locationId: 'loc-2', roundId: 401);
      await _waitFor(
        () => service.state.waitingConversationRoundIdsByLocation.length == 2,
      );

      socket.serverV2Message(
        type: 'user_enter_location',
        senderId: 'char-1',
        senderName: 'Character One',
        messageId: 299,
        locationMessageId: 299,
        roundId: 301,
        content: 'Character One entered',
      );
      socket.serverV2Message(
        type: 'narrator',
        senderId: 'nar',
        senderName: 'Narrator',
        messageId: 300,
        locationMessageId: 300,
        roundId: 301,
        content: 'same round narrator message',
      );
      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-1']?.any(
              (message) => message.locationMessageId == 300,
            ) ==
            true,
      );
      expect(
        service.state.waitingConversationRoundIdsByLocation,
        <String, String>{'loc-1': '301', 'loc-2': '401'},
      );

      socket.serverV2StreamFrame(
        streamType: 'llm_stream_start',
        senderId: 'char-1',
        messageId: 301,
        locationMessageId: 301,
        roundId: 301,
      );
      socket.serverV2StreamFrame(
        streamType: 'llm_chunk',
        senderId: 'char-1',
        messageId: 301,
        locationMessageId: 301,
        roundId: 301,
        seq: 1,
        content: 'still streaming',
      );
      socket.serverV2Message(
        type: 'character',
        senderId: 'char-2',
        senderName: 'Other',
        messageId: 302,
        locationMessageId: 302,
        roundId: 999,
        content: 'different round',
      );
      await _waitFor(
        () =>
            service.state.streamMessagesByKey.isNotEmpty &&
            service.state.messagesByLocation['loc-1']?.any(
                  (message) => message.conversationRoundId == '999',
                ) ==
                true,
      );
      expect(
        service.state.waitingConversationRoundIdsByLocation,
        <String, String>{'loc-1': '301', 'loc-2': '401'},
      );

      socket.serverV2StreamFrame(
        streamType: 'llm_stream_end',
        senderId: 'char-1',
        messageId: 303,
        locationMessageId: 303,
        roundId: 301,
        content: 'complete response',
      );
      await _waitFor(() => service.state.streamMessagesByKey.isEmpty);
      expect(
        service.state.waitingConversationRoundIdsByLocation['loc-1'],
        '301',
      );

      socket.serverEndConversationRound(locationId: 'loc-1', roundId: 999);
      await Future<void>.delayed(Duration.zero);
      expect(
        service.state.waitingConversationRoundIdsByLocation['loc-1'],
        '301',
      );

      socket.serverEndConversationRound(locationId: 'loc-1', roundId: 301);
      await _waitFor(
        () => !service.state.waitingConversationRoundIdsByLocation.containsKey(
          'loc-1',
        ),
      );
      expect(
        service.state.waitingConversationRoundIdsByLocation,
        <String, String>{'loc-2': '401'},
      );

      socket.serverWaitingConversationRound(locationId: 'loc-2', roundId: 402);
      await _waitFor(
        () =>
            service.state.waitingConversationRoundIdsByLocation['loc-2'] ==
            '402',
      );
      socket.serverV2Message(
        type: 'user',
        senderId: 'user-1',
        senderName: 'Player One',
        messageId: 304,
        locationMessageId: 304,
        roundId: 402,
        content: 'user message does not unlock',
        locationId: 'loc-2',
      );
      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-2']?.any(
              (message) => message.locationMessageId == 304,
            ) ==
            true,
      );
      expect(
        service.state.waitingConversationRoundIdsByLocation['loc-2'],
        '402',
      );

      socket.serverEndConversationRound(locationId: 'loc-2', roundId: 402);
      await _waitFor(
        () => !service.state.waitingConversationRoundIdsByLocation.containsKey(
          'loc-2',
        ),
      );

      socket.serverWaitingConversationRound(
        locationId: 'loc-error',
        roundId: 501,
        errNo: 5000,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        service.state.waitingConversationRoundIdsByLocation,
        isNot(contains('loc-error')),
      );

      await service.disconnect();
      expect(service.state.waitingConversationRoundIdsByLocation, isEmpty);
      await service.dispose();
    },
  );

  test('V2 waiting conversation round survives automatic reconnect', () async {
    final firstSocket = _FakeChatroomSocket();
    final secondSocket = _FakeChatroomSocket();
    final transport = _SequencedChatroomTransport([firstSocket, secondSocket]);
    final service = await _service(
      socketTransport: transport,
      reconnectInterval: const Duration(milliseconds: 5),
      refreshInitialSnapshotOnConnect: false,
      useV2Protocol: true,
    );
    await service.connect(worldId: 'world-1', identity: _identity());

    firstSocket.serverWaitingConversationRound(
      locationId: 'loc-1',
      roundId: 601,
    );
    await _waitFor(
      () =>
          service.state.waitingConversationRoundIdsByLocation['loc-1'] == '601',
    );
    await firstSocket.serverClose();
    await _waitFor(
      () => transport.connectCount == 2 && service.state.connected,
    );
    expect(service.state.waitingConversationRoundIdsByLocation['loc-1'], '601');

    secondSocket.serverV2Message(
      type: 'character',
      senderId: 'char-1',
      senderName: 'Alice',
      messageId: 601,
      locationMessageId: 601,
      roundId: 601,
      content: 'response after reconnect',
    );
    await _waitFor(
      () =>
          service.state.messagesByLocation['loc-1']?.any(
            (message) => message.locationMessageId == 601,
          ) ==
          true,
    );
    expect(service.state.waitingConversationRoundIdsByLocation['loc-1'], '601');

    secondSocket.serverEndConversationRound(locationId: 'loc-1', roundId: 601);
    await _waitFor(
      () => service.state.waitingConversationRoundIdsByLocation.isEmpty,
    );
    await service.dispose();
  });

  test('disposing clears a V2 waiting conversation round', () async {
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      refreshInitialSnapshotOnConnect: false,
      useV2Protocol: true,
    );
    await service.connect(worldId: 'world-1', identity: _identity());
    socket.serverWaitingConversationRound(locationId: 'loc-1', roundId: 701);
    await _waitFor(
      () =>
          service.state.waitingConversationRoundIdsByLocation['loc-1'] == '701',
    );

    await service.dispose();
    expect(service.state.waitingConversationRoundIdsByLocation, isEmpty);
  });

  test('V2 conversation round unlocks after the fallback timeout', () async {
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      refreshInitialSnapshotOnConnect: false,
      useV2Protocol: true,
      conversationRoundTimeout: const Duration(milliseconds: 30),
    );
    await service.connect(worldId: 'world-1', identity: _identity());
    socket.serverWaitingConversationRound(locationId: 'loc-1', roundId: 801);
    await _waitFor(
      () =>
          service.state.waitingConversationRoundIdsByLocation['loc-1'] == '801',
    );

    await _waitFor(
      () => service.state.waitingConversationRoundIdsByLocation.isEmpty,
    );
    socket.serverWaitingConversationRound(locationId: 'loc-1', roundId: 801);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(service.state.waitingConversationRoundIdsByLocation, isEmpty);
    await service.dispose();
  });

  test('V2 send accepts canonical echo before receipt', () async {
    final socket = _FakeChatroomSocket();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      ackTimeout: const Duration(milliseconds: 500),
      useV2Protocol: true,
    );
    await service.connect(worldId: 'world-1', identity: _identity());

    final handle = service.sendMessage(
      'echo first',
      clientMsgId: 'client-echo-first',
    );
    var receiptCompleted = false;
    unawaited(
      handle.receipt.then((_) {
        receiptCompleted = true;
      }),
    );
    await _waitFor(() => socket.sentTypes.contains('send_message'));

    socket.serverV2Message(
      type: 'user',
      senderId: 'user-1',
      senderName: 'Player One',
      messageId: 71,
      locationMessageId: 8,
      roundId: 701,
      content: 'echo first',
      clientMsgId: handle.clientMsgId,
    );
    final canonical = await handle.canonicalMessage;
    expect(canonical.messageId, 71);
    expect(receiptCompleted, isFalse);

    socket.serverV2Ack(clientMsgId: handle.clientMsgId);
    final receipt = await handle.receipt;
    expect(receipt.clientMsgId, 'client-echo-first');
    await service.dispose();
  });

  test(
    'canonical echo wait can be cancelled without blocking late ingest',
    () async {
      final socket = _FakeChatroomSocket();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        ackTimeout: const Duration(milliseconds: 500),
        useV2Protocol: true,
      );
      await service.connect(worldId: 'world-1', identity: _identity());

      final handle = service.sendMessage(
        'late echo',
        clientMsgId: 'client-cancel-echo',
      );
      await _waitFor(() => socket.sentTypes.contains('send_message'));
      socket.serverV2Ack(clientMsgId: handle.clientMsgId);
      await handle.receipt;

      expect(
        service.cancelCanonicalMessageWait(
          handle.clientMsgId,
          reason: TimeoutException('echo timeout'),
        ),
        isTrue,
      );
      await expectLater(
        handle.canonicalMessage,
        throwsA(isA<TimeoutException>()),
      );
      expect(service.cancelCanonicalMessageWait(handle.clientMsgId), isFalse);

      socket.serverV2Message(
        type: 'user',
        senderId: 'user-1',
        senderName: 'Player One',
        messageId: 72,
        locationMessageId: 9,
        roundId: 702,
        content: 'late echo',
        clientMsgId: handle.clientMsgId,
      );
      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-1']?.any(
              (message) => message.messageId == 72,
            ) ==
            true,
      );
      await service.dispose();
    },
  );

  test('canonical V2 tick stays in its own location queue', () async {
    final socket = _FakeChatroomSocket();
    final storage = _RecordingChatroomMessageStorage();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      messageStorage: storage,
      useV2Protocol: true,
    );
    service.applyWorldSnapshot(_worldSnapshot());
    await service.connect(worldId: 'world-1', identity: _identity());

    socket.serverV2Tick(
      messageId: 80,
      locationMessageId: 18,
      locationId: 'loc-1',
      globalText: 'The bell rings.',
    );
    await _waitFor(
      () =>
          service.state.messagesByLocation['loc-1']?.any(
            (message) => message.locationMessageId == 18,
          ) ==
          true,
    );

    final tick = service.state.messagesByLocation['loc-1']!.singleWhere(
      (message) => message.locationMessageId == 18,
    );
    expect(tick.businessType, 'tick');
    expect(tick.isV2LocationTick, isTrue);
    expect(tick.tickNo, 0);
    expect(tick.v2TickPayload?.globalText, 'The bell rings.');
    expect(
      service.state.messagesByLocation['loc-2']?.any(
            (message) => message.locationMessageId == 18,
          ) ??
          false,
      isFalse,
    );
    await _waitFor(() => storage.lastUpsertedMessage?['location_msg_id'] == 18);
    final storedEnvelope = storage.lastUpsertedMessage!;
    expect(storedEnvelope['type'], 'tick');
    expect(storedEnvelope['stream_type'], '');
    expect(storedEnvelope['world_id'], 'world-1');
    expect(storedEnvelope['global_message_id'], 90080);
    expect(storedEnvelope['message_id'], 80);
    expect(storedEnvelope['location_message_id'], 18);
    expect(storedEnvelope['conversation_round_id'], 800);
    expect(storedEnvelope['client_msg_id'], '');
    expect(storedEnvelope['message_type'], 'text');
    expect(storedEnvelope['min_app_version'], 0);
    expect(storedEnvelope['payload'], isA<Map<String, dynamic>>());
    expect(storedEnvelope['err_no'], 0);
    expect(storedEnvelope['err_msg'], '');
    expect(storedEnvelope['created_at'], isA<String>());
    expect(storedEnvelope['ts'], isA<int>());
    final restored = WorldChatroomMessage.fromStorageJson(storedEnvelope);
    expect(restored.hasExplicitBusinessType, isTrue);
    expect(restored.v2TickPayload?.globalText, 'The bell rings.');
    await service.dispose();
  });

  test('legacy socket persistence does not synthesize a V2 type', () async {
    final socket = _FakeChatroomSocket();
    final storage = _RecordingChatroomMessageStorage();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      messageStorage: storage,
      refreshInitialSnapshotOnConnect: false,
    );
    await service.connect(worldId: 'world-1', identity: _identity());

    socket.serverUserMessage(
      messageId: 82,
      roundId: 802,
      content: 'legacy message',
    );
    await _waitFor(() => storage.lastUpsertedMessage?['msg_id'] == 82);

    final storedEnvelope = storage.lastUpsertedMessage!;
    expect(storedEnvelope, isNot(contains('type')));
    final restored = WorldChatroomMessage.fromStorageJson(storedEnvelope);
    expect(restored.businessType, 'user');
    expect(restored.hasExplicitBusinessType, isFalse);
    await service.dispose();
  });

  test('V2 HTTP persistence retains the diagnostic envelope fields', () async {
    final socket = _FakeChatroomSocket();
    final http = _WorldChatroomHttpTransport()
      ..messagesByLocation['loc-1'] = [
        {
          'type': 'narrator',
          'stream_type': '',
          'ts': 1786327200123,
          'world_id': 'world-1',
          'location_id': 'loc-1',
          'session_id': 'session-http',
          'global_message_id': 90083,
          'message_id': 83,
          'location_message_id': 20,
          'conversation_round_id': 803,
          'sender_type': 'narrator',
          'sender_id': 'narrator',
          'sender_name': 'Narrator',
          'user_id': '',
          'client_msg_id': 'client-http',
          'message_type': 'image',
          'min_app_version': 304,
          'created_at': '2026-08-10 10:00:00',
          'payload': {
            'content': 'https://cdn.example.com/image.png',
            'future_field': 'preserved',
          },
          'err_no': 23,
          'err_msg': 'diagnostic',
        },
      ];
    final storage = MemoryChatroomMessageStorage();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
      messageStorage: storage,
      refreshInitialSnapshotOnConnect: false,
      useV2Protocol: true,
    );
    await service.connect(worldId: 'world-1', identity: _identity());

    await service.refreshLatestMessages(locationId: 'loc-1');
    final storedEnvelope = (await storage.loadLatestMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      limit: 20,
    )).single;
    expect(storedEnvelope['type'], 'narrator');
    expect(storedEnvelope['stream_type'], '');
    expect(storedEnvelope['world_id'], 'world-1');
    expect(storedEnvelope['session_id'], 'session-http');
    expect(storedEnvelope['global_message_id'], 90083);
    expect(storedEnvelope['message_id'], 83);
    expect(storedEnvelope['location_message_id'], 20);
    expect(storedEnvelope['conversation_round_id'], 803);
    expect(storedEnvelope['client_msg_id'], 'client-http');
    expect(storedEnvelope['message_type'], 'image');
    expect(storedEnvelope['min_app_version'], 304);
    expect(storedEnvelope['payload'], {
      'content': 'https://cdn.example.com/image.png',
      'future_field': 'preserved',
    });
    expect(storedEnvelope['err_no'], 23);
    expect(storedEnvelope['err_msg'], 'diagnostic');
    expect(storedEnvelope['created_at'], '2026-08-10 10:00:00');
    expect(storedEnvelope['ts'], 1786327200123);
    final restored = WorldChatroomMessage.fromStorageJson(storedEnvelope);
    expect(restored.hasExplicitBusinessType, isTrue);
    expect(restored.businessType, 'narrator');
    expect(restored.clientMsgId, 'client-http');
    expect(restored.rawPayload['future_field'], 'preserved');
    await service.dispose();
  });

  test(
    'positive-cursor tick without a typed payload does not fan out',
    () async {
      final socket = _FakeChatroomSocket();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
      );
      service.applyWorldSnapshot(_worldSnapshot());
      await service.connect(worldId: 'world-1', identity: _identity());

      socket.serverFrame('tick_advance', {
        'ts': 1786327200000,
        'world_id': 'world-1',
        'location_id': 'loc-1',
        'global_msg_id': 90081,
        'msg_id': 81,
        'location_msg_id': 19,
        'conversation_round_id': 801,
        'current_time': 'Day 8, 10:01',
        'payload': <String, Object?>{
          'content': 'Fallback Tick content',
          'tick_no': 0,
          'sub_tick_no': 0,
        },
      });
      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-1']?.any(
              (message) => message.locationMessageId == 19,
            ) ==
            true,
      );

      final tick = service.state.messagesByLocation['loc-1']!.singleWhere(
        (message) => message.locationMessageId == 19,
      );
      expect(tick.v2TickPayload, isNull);
      expect(tick.isV2LocationTick, isTrue);
      expect(tick.tickNo, 0);
      expect(
        service.state.messagesByLocation['loc-2']?.any(
              (message) => message.locationMessageId == 19,
            ) ??
            false,
        isFalse,
      );
      await service.dispose();
    },
  );

  test('V2 streams order and deduplicate chunks and isolate senders', () async {
    final socket = _FakeChatroomSocket();
    final messageStorage = _RecordingChatroomMessageStorage();
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      messageStorage: messageStorage,
      useV2Protocol: true,
    );

    await service.connect(worldId: 'world-1', identity: _identity());
    const firstKey = 'world-1|loc-1|8|char-1';
    const secondKey = 'world-1|loc-1|8|char-2';
    socket.serverV2StreamFrame(
      streamType: 'llm_stream_start',
      senderId: 'char-1',
      senderName: 'Alice',
      messageId: 10,
      locationMessageId: 10,
      roundId: 8,
    );
    socket.serverV2StreamFrame(
      streamType: 'llm_stream_start',
      senderId: 'char-2',
      senderName: 'Bob',
      messageId: 11,
      locationMessageId: 11,
      roundId: 8,
    );
    await _waitFor(
      () =>
          service.state.streamMessagesByKey.containsKey(firstKey) &&
          service.state.streamMessagesByKey.containsKey(secondKey),
    );

    socket.serverV2StreamFrame(
      streamType: 'llm_chunk',
      senderId: 'char-1',
      messageId: 10,
      locationMessageId: 10,
      roundId: 8,
      seq: 2,
      content: 'lo',
    );
    socket.serverV2StreamFrame(
      streamType: 'llm_chunk',
      senderId: 'char-1',
      messageId: 10,
      locationMessageId: 10,
      roundId: 8,
      seq: 2,
      content: 'duplicate',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(service.state.streamMessagesByKey[firstKey]?.content, isEmpty);

    socket.serverV2StreamFrame(
      streamType: 'llm_chunk',
      senderId: 'char-2',
      messageId: 11,
      locationMessageId: 11,
      roundId: 8,
      seq: 1,
      content: 'other',
    );
    socket.serverV2StreamFrame(
      streamType: 'llm_chunk',
      senderId: 'char-1',
      messageId: 10,
      locationMessageId: 10,
      roundId: 8,
      seq: 1,
      content: 'hel',
      currentTime: 'Day 8, 09:11',
    );
    await _waitFor(
      () =>
          service.state.streamMessagesByKey[firstKey]?.content == 'hello' &&
          service.state.streamMessagesByKey[secondKey]?.content == 'other',
    );
    expect(service.state.latestSocketCurrentTime, 'Day 8, 09:11');

    socket.serverV2StreamFrame(
      streamType: 'llm_stream_end',
      senderId: 'char-1',
      messageId: 12,
      locationMessageId: 12,
      roundId: 8,
      content: 'authoritative final',
      currentTime: 'Day 8, 09:12',
    );
    await _waitFor(
      () => !service.state.streamMessagesByKey.containsKey(firstKey),
    );
    expect(service.state.streamMessagesByKey, contains(secondKey));

    final message = service.state.messagesByLocation['loc-1']!.singleWhere(
      (message) => message.locationMessageId == 12,
    );
    expect(
      service.state.messagesByLocation['loc-1']!.where(
        (item) => item.locationMessageId == 10,
      ),
      isEmpty,
    );
    expect(
      service.state.worldMessages.where(
        (item) =>
            item.locationId == 'loc-1' &&
            item.conversationRoundId == '8' &&
            item.senderId == 'char-1',
      ),
      hasLength(1),
    );
    expect(message.globalMessageId, 90012);
    expect(message.content, 'authoritative final');
    expect(message.currentTime, 'Day 8, 09:12');
    expect(message.streaming, false);
    expect(message.isLlmStreamMessage, isTrue);
    await _waitFor(
      () => messageStorage.lastUpsertedMessage?['location_msg_id'] == 12,
    );
    expect(messageStorage.lastUpsertedMessage?['is_llm_stream'], isTrue);
    final cachedAfterEnd = await messageStorage.loadLatestMessages(
      ownerUid: 'user-1',
      worldId: 'world-1',
      locationId: 'loc-1',
      limit: 20,
    );
    expect(
      cachedAfterEnd.where((item) => item['location_msg_id'] == 10),
      isEmpty,
    );
    expect(service.state.latestSocketCurrentTime, 'Day 8, 09:12');

    socket.serverV2Message(
      type: 'character',
      senderId: 'char-1',
      senderName: 'Alice',
      messageId: 12,
      locationMessageId: 12,
      roundId: 8,
      content: 'authoritative',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final deduplicated = service.state.messagesByLocation['loc-1']!
        .where((item) => item.locationMessageId == 12)
        .toList(growable: false);
    expect(deduplicated, hasLength(1));
    expect(deduplicated.single.globalMessageId, 90012);
    expect(deduplicated.single.messageId, 12);
    expect(deduplicated.single.content, 'authoritative final');
    await _waitFor(
      () =>
          messageStorage.lastUpsertedMessage?['content'] ==
          'authoritative final',
    );
    expect(messageStorage.lastUpsertedMessage?['msg_id'], 12);
    expect(messageStorage.lastUpsertedMessage?['location_msg_id'], 12);
    await service.dispose();
  });

  test(
    'V2 direct chunk without ids enters queue and merges through final',
    () async {
      final socket = _FakeChatroomSocket();
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        useV2Protocol: true,
      );
      await service.connect(worldId: 'world-1', identity: _identity());
      const streamKey = 'world-1|loc-1|9|char-1';

      socket.serverV2Message(
        type: 'character',
        senderId: 'char-2',
        senderName: 'Bob',
        messageId: 89,
        locationMessageId: 17,
        roundId: 7,
        content: 'existing history',
      );
      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-1']?.any(
              (message) => message.locationMessageId == 17,
            ) ==
            true,
      );

      socket.serverV2StreamFrame(
        streamType: 'llm_chunk',
        senderId: 'char-1',
        messageId: 0,
        locationMessageId: 0,
        roundId: 9,
        seq: 1,
        content: 'partial',
      );
      await _waitFor(
        () =>
            service.state.streamMessagesByKey[streamKey]?.content ==
                'partial' &&
            service.state.messagesByLocation['loc-1']?.any(
                  (message) =>
                      message.conversationRoundId == '9' &&
                      message.senderId == 'char-1' &&
                      message.streaming,
                ) ==
                true,
      );
      final transient = service.state.messagesByLocation['loc-1']!.singleWhere(
        (message) =>
            message.conversationRoundId == '9' && message.senderId == 'char-1',
      );
      expect(transient.globalMessageId, 0);
      expect(transient.messageId, 0);
      expect(transient.locationMessageId, 0);
      expect(
        service.state.messagesByLocation['loc-1']!.last.conversationRoundId,
        '9',
      );
      expect(
        service.state.messagesByLocation['loc-1']!.first.locationMessageId,
        17,
      );

      socket.serverV2StreamFrame(
        streamType: 'llm_stream_end',
        senderId: 'char-1',
        messageId: 0,
        locationMessageId: 0,
        roundId: 9,
        content: 'complete response',
      );
      await _waitFor(
        () =>
            !service.state.streamMessagesByKey.containsKey(streamKey) &&
            service.state.messagesByLocation['loc-1']?.any(
                  (message) =>
                      message.conversationRoundId == '9' &&
                      !message.streaming &&
                      message.content == 'complete response',
                ) ==
                true,
      );
      expect(
        service.state.messagesByLocation['loc-1']!.where(
          (message) =>
              message.conversationRoundId == '9' &&
              message.senderId == 'char-1',
        ),
        hasLength(1),
      );

      socket.serverV2Message(
        type: 'character',
        senderId: 'char-1',
        senderName: 'Alice',
        messageId: 90,
        locationMessageId: 19,
        roundId: 9,
        content: 'complete',
      );
      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-1']?.any(
              (message) => message.locationMessageId == 19,
            ) ==
            true,
      );
      final canonical = service.state.messagesByLocation['loc-1']!
          .where(
            (message) =>
                message.conversationRoundId == '9' &&
                message.senderId == 'char-1',
          )
          .toList(growable: false);
      expect(canonical, hasLength(1));
      expect(canonical.single.globalMessageId, 90090);
      expect(canonical.single.messageId, 90);
      expect(canonical.single.locationMessageId, 19);
      expect(canonical.single.content, 'complete response');
      expect(canonical.single.isLlmStreamMessage, isTrue);
      expect(canonical.single.streaming, isFalse);
      expect(
        service.state.messagesByLocation['loc-1']!.last.locationMessageId,
        19,
      );
      await service.dispose();
    },
  );
}

Future<WorldChatroomService> _service({
  required ChatroomSocketTransport socketTransport,
  HttpTransport? httpTransport,
  Duration heartbeatInterval = const Duration(seconds: 2),
  Duration reconnectInterval = const Duration(milliseconds: 20),
  Duration ackTimeout = const Duration(milliseconds: 20),
  Duration conversationRoundTimeout = conversationRoundFallbackTimeout,
  ChatroomMessageStorage? messageStorage,
  bool refreshInitialSnapshotOnConnect = true,
  bool useV2Protocol = false,
}) async {
  final store = MemoryUserSessionStore();
  await store.saveUid('user-1');
  await store.saveAuthToken('token-1');
  final api = GenesisApi(
    transport: httpTransport ?? _WorldChatroomHttpTransport(),
    useMock: false,
    deviceIdService: const _FakeDeviceIdService(),
    sessionStore: store,
    chatroomHttpBaseUrl: 'https://chatroom.test/',
  );
  final client = ChatroomClient(
    wsBaseUrl: 'ws://localhost:8082/aitown-chat/ws',
    sessionStore: store,
    deviceIdService: const _FakeDeviceIdService(),
    transport: socketTransport,
    heartbeatInterval: heartbeatInterval,
    ackTimeout: ackTimeout,
    autoHeartbeat: false,
    requestHeaderProvider: useV2Protocol
        ? () async => const <String, String>{'X-App-Version': '0.3.4'}
        : null,
  );
  return WorldChatroomService(
    api: api,
    client: client,
    messageStorage: messageStorage ?? MemoryChatroomMessageStorage(),
    replyActionStorage: MemoryChatroomReplyActionStorage(),
    heartbeatInterval: heartbeatInterval,
    reconnectInterval: reconnectInterval,
    conversationRoundTimeout: conversationRoundTimeout,
    refreshInitialSnapshotOnConnect: refreshInitialSnapshotOnConnect,
  );
}

WorldDetail _worldSnapshot() {
  return WorldDetail(
    id: 1,
    worldId: 'world-1',
    originId: 1,
    ownerUid: 'owner-1',
    name: 'World Snapshot',
    tickCount: 0,
    connectCount: 1,
    characterCount: 2,
    playerCount: 1,
    currentTime: '',
    latestTickAt: null,
    latestNarrator: '',
    isProgressing: false,
    relationStatus: 'owner',
    metric: const <String, dynamic>{},
    inviteToken: 'world-1',
    createdAt: null,
    updatedAt: null,
    origin: const OriginSummary(
      id: 1,
      oid: 'origin-1',
      name: 'World Snapshot',
      description: '',
      mapImage: '',
      worldMap: '',
      worldView: '',
      copyCount: 0,
      interactCount: 1,
      tags: <String>[],
      createdAt: null,
      updatedAt: null,
      characters: <OriginCharacter>[],
      locations: <OriginLocation>[],
    ),
    characters: const [
      {
        'char_id': 'char-1',
        'type': 'ai',
        'name': 'Alice',
        'location_id': 'loc-1',
      },
      {
        'char_id': 'char-user-1',
        'type': 'player',
        'player_uid': 'user-1',
        'name': 'Role One',
        'location_id': 'loc-2',
      },
    ],
    ticks: const <Map<String, dynamic>>[],
    locations: const [
      {'location_id': 'loc-1', 'location_pid': '', 'location_name': 'Square'},
      {'location_id': 'loc-2', 'location_pid': '', 'location_name': 'Cafe'},
    ],
    characterPositions: const [
      {
        'location_id': 'loc-1',
        'character': {'id': 'char-1', 'name': 'Alice', 'type': 'ai'},
      },
      {
        'location_id': 'loc-2',
        'character': {
          'id': 'char-user-1',
          'name': 'Role One',
          'type': 'player',
        },
      },
    ],
    userPositions: const [
      {'uid': 'user-1', 'location_id': 'loc-2'},
    ],
  );
}

ChatroomConnectionIdentity _identity() {
  return const ChatroomConnectionIdentity(
    userId: 'user-1',
    senderId: 'user-1',
    senderName: 'Player One',
  );
}

Map<String, dynamic> _httpMessageJson({
  required int messageId,
  required String locationId,
  required String content,
  int? locationMessageId,
  String? messageType,
  String senderType = 'user',
}) {
  return {
    'global_message_id': 90000 + messageId,
    'message_id': messageId,
    'location_message_id': locationMessageId ?? messageId,
    'location_id': locationId,
    'conversation_round_id': messageId,
    'tick_no': 0,
    'sender_type': senderType,
    'sender_id': senderType == 'user' ? 'user-$messageId' : 'sub_tick',
    'sender_name': senderType == 'user' ? 'User $messageId' : 'sub_tick',
    'user_id': senderType == 'user' ? 'user-$messageId' : null,
    'content': content,
    if (messageType != null) 'message_type': messageType,
    'current_time': '',
    'created_at': '2026-07-01 10:00:${messageId.toString().padLeft(2, '0')}',
  };
}

Map<String, dynamic> _asV2HttpMessage(Map<String, dynamic> message) {
  if (message.containsKey('type') && message['payload'] is Map) {
    return Map<String, dynamic>.from(message);
  }
  final senderType = '${message['sender_type'] ?? ''}'.trim();
  final content = '${message['content'] ?? ''}';
  return <String, dynamic>{
    'type': senderType.isEmpty ? 'user' : senderType,
    'stream_type': '',
    'ts': message['ts'],
    'world_id': message['world_id'] ?? 'world-1',
    'location_id': message['location_id'] ?? '',
    'session_id': message['session_id'] ?? '',
    'global_message_id': message['global_message_id'] ?? 0,
    'message_id': message['message_id'] ?? 0,
    'location_message_id':
        message['location_message_id'] ?? message['location_msg_id'] ?? 0,
    'conversation_round_id': message['conversation_round_id'] ?? 0,
    'sender_type': senderType,
    'sender_id': message['sender_id'] ?? '',
    'sender_name': message['sender_name'] ?? '',
    'user_id': message['user_id'] ?? '',
    'client_msg_id': message['client_msg_id'] ?? '',
    if (message.containsKey('message_type'))
      'message_type': message['message_type'],
    'min_app_version': message['min_app_version'] ?? 0,
    'created_at': message['created_at'] ?? '',
    'payload': <String, dynamic>{'content': content},
    'err_no': 0,
    'err_msg': '',
  };
}

Map<String, dynamic> _storageMessageJson({
  required int messageId,
  required String locationId,
  required String content,
  int? locationMessageId,
  String senderType = 'user',
}) {
  return {
    'global_msg_id': 90000 + messageId,
    'msg_id': messageId,
    'location_msg_id': locationMessageId ?? messageId,
    'location_id': locationId,
    'conversation_round_id': messageId,
    'round_order': 1,
    'tick_no': 0,
    'sender_type': senderType,
    'sender_id': 'user-$messageId',
    'sender_name': 'User $messageId',
    'user_id': 'user-$messageId',
    'client_msg_id': '',
    'content': content,
    'current_time': '',
    'ts': 1717300000000 + messageId,
  };
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  if (!condition()) {
    fail('Condition was not met within $timeout');
  }
}

class _WorldChatroomHttpTransport implements HttpTransport {
  String worldName = 'World One';
  String? userLocationId = 'loc-2';
  int worldTickCount = 0;
  int detailRequests = 0;
  int userLocationRequests = 0;
  int worldMessagesRequests = 0;
  int messagesRequests = 0;
  List<Map<String, Object?>>? charactersOverride;
  List<Map<String, Object?>>? locationsOverride;
  final Set<String> failedMessageLocationIds = <String>{};
  final Map<String, int> messagesRequestsByLocation = {};
  final Map<String, List<int?>> messageSinceByLocation = {};
  final Map<String, List<Map<String, dynamic>>> messagesByLocation = {
    'loc-1': [
      _httpMessageJson(messageId: 2, locationId: 'loc-1', content: 'gap'),
    ],
    'loc-2': [
      _httpMessageJson(messageId: 4, locationId: 'loc-2', content: 'loc-2'),
    ],
  };

  List<Map<String, Object?>> get defaultCharacters => [
    {
      'char_id': 'char-1',
      'type': 'ai',
      'name': 'Alice',
      'avatar': 'alice.png',
      'location_id': 'loc-1',
    },
    {
      'char_id': 'char-user-1',
      'type': 'player',
      'player_uid': 'user-1',
      'name': 'Role One',
      'avatar': 'role.png',
      'location_id': 'loc-2',
    },
  ];

  List<Map<String, Object?>> get defaultLocations => [
    {
      'location_id': 'loc-root',
      'location_pid': '',
      'name': 'Town',
      'description': 'Town desc',
    },
    {
      'location_id': 'loc-1',
      'location_pid': 'loc-root',
      'name': 'Square',
      'description': 'Square desc',
    },
    {
      'location_id': 'loc-2',
      'location_pid': 'loc-root',
      'name': 'Cafe',
      'description': 'Cafe desc',
    },
  ];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    final path = request.uri.path;
    if (path.endsWith('/api/v1/world/detail')) {
      detailRequests += 1;
      return _json({'err_no': 0, 'err_msg': 'succ', 'data': _worldDetail()});
    }
    if (path.endsWith('/aitown-chat/api/ulocation')) {
      userLocationRequests += 1;
      final locations = <Map<String, Object?>>[];
      void addUser(String locationId, Map<String, Object?> user) {
        Map<String, Object?>? group;
        for (final location in locations) {
          if (location['location_id'] == locationId) {
            group = location;
            break;
          }
        }
        final resolvedGroup =
            group ??
            <String, Object?>{
              'location_id': locationId,
              'users': <Map<String, Object?>>[],
            };
        if (group == null) locations.add(resolvedGroup);
        (resolvedGroup['users'] as List<Map<String, Object?>>).add(user);
      }

      final resolvedUserLocationId = userLocationId?.trim();
      if (resolvedUserLocationId != null && resolvedUserLocationId.isNotEmpty) {
        addUser(resolvedUserLocationId, {
          'user_id': 'user-1',
          'user_name': 'Player One',
          'avatar': '',
        });
      }
      return _json({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {'world_id': 'world-1', 'locations': locations},
      });
    }
    if (path.endsWith('/aitown-chat/internal/world/messages')) {
      worldMessagesRequests += 1;
      final locations = messagesByLocation.entries
          .map((entry) => {'location_id': entry.key, 'messages': entry.value})
          .toList(growable: false);
      return _json({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {'locations': locations},
      });
    }
    if (path.endsWith('/aitown-chat/api/v2/messages')) {
      messagesRequests += 1;
      final locationId = request.uri.queryParameters['location_id'] ?? '';
      final since = int.tryParse(request.uri.queryParameters['since'] ?? '');
      messagesRequestsByLocation[locationId] =
          (messagesRequestsByLocation[locationId] ?? 0) + 1;
      messageSinceByLocation.putIfAbsent(locationId, () => <int?>[]).add(since);
      if (failedMessageLocationIds.contains(locationId)) {
        return _json({'err_no': 500, 'err_msg': 'history failed', 'data': {}});
      }
      final allMessages =
          messagesByLocation[locationId] ?? const <Map<String, dynamic>>[];
      final requestedLimit =
          int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 20;
      final messages =
          allMessages
              .where((message) {
                final locationMessageId =
                    (message['location_message_id'] as int?) ??
                    (message['message_id'] as int?) ??
                    0;
                return since == null || since <= 0 || locationMessageId < since;
              })
              .toList(growable: false)
            ..sort((left, right) {
              final leftId =
                  (left['location_message_id'] as int?) ??
                  (left['message_id'] as int?) ??
                  0;
              final rightId =
                  (right['location_message_id'] as int?) ??
                  (right['message_id'] as int?) ??
                  0;
              return rightId.compareTo(leftId);
            });
      final page = messages
          .take(requestedLimit <= 0 ? 20 : requestedLimit)
          .map(_asV2HttpMessage)
          .toList(growable: false);
      return _json({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {
          'messages': page,
          'has_more': messages.length > page.length,
          'newest_message_id': messages.fold<int>(0, (previous, message) {
            final locationMessageId =
                (message['location_message_id'] as int?) ??
                (message['location_msg_id'] as int?) ??
                (message['message_id'] as int?) ??
                0;
            return locationMessageId > previous ? locationMessageId : previous;
          }),
        },
      });
    }
    return _json({
      'err_no': 404,
      'err_msg': 'Unhandled test request: $path',
      'data': {},
    });
  }

  Map<String, Object?> _worldDetail() {
    return {
      'info': {
        'world_id': 'world-1',
        'world_name': worldName,
        'origin_id': 'origin-1',
        'origin_version': 1,
        'owner_uid': 'owner-1',
        'owner_name': 'Owner',
        'brief': 'brief',
        'setting': 'setting',
        'metric': {},
        'created_at': 1717300000000,
        'updated_at': 1717300000000,
        'status': 10,
      },
      'stats': {
        'character_cnt': 1,
        'connect_cnt': 1,
        'location_cnt': 2,
        'tick_cnt': worldTickCount,
        'player_cnt': 1,
      },
      'relation_status': 'owner',
      'characters': charactersOverride ?? defaultCharacters,
      'locations': locationsOverride ?? defaultLocations,
      'ticks': [],
    };
  }

  TransportResponse _json(Map<String, Object?> body) {
    return TransportResponse(
      statusCode: 200,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(body),
    );
  }
}

class _SequencedUserLocationsHttpTransport extends _WorldChatroomHttpTransport {
  final List<Completer<String?>> pendingUserLocations = <Completer<String?>>[];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    if (!request.uri.path.endsWith('/aitown-chat/api/ulocation')) {
      return super.send(request);
    }
    userLocationRequests += 1;
    final completer = Completer<String?>();
    pendingUserLocations.add(completer);
    final locationId = (await completer.future)?.trim() ?? '';
    return _json({
      'err_no': 0,
      'err_msg': 'succ',
      'data': {
        'world_id': 'world-1',
        'locations': locationId.isEmpty
            ? <Map<String, Object?>>[]
            : <Map<String, Object?>>[
                {
                  'location_id': locationId,
                  'users': <Map<String, Object?>>[
                    {
                      'user_id': 'user-1',
                      'user_name': 'Player One',
                      'avatar': '',
                    },
                  ],
                },
              ],
      },
    });
  }
}

class _SequencedWorldMessagesHttpTransport extends _WorldChatroomHttpTransport {
  final List<Completer<void>> pendingWorldMessages = <Completer<void>>[];
  int completedWorldMessages = 0;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    if (!request.uri.path.endsWith('/aitown-chat/api/v2/messages')) {
      return super.send(request);
    }
    final completer = Completer<void>();
    pendingWorldMessages.add(completer);
    await completer.future;
    completedWorldMessages += 1;
    return super.send(request);
  }
}

class _BlockingWorldDetailHttpTransport extends _WorldChatroomHttpTransport {
  final Completer<void> _worldDetailCompleter = Completer<void>();
  bool worldDetailStarted = false;

  void completeWorldDetail() {
    if (!_worldDetailCompleter.isCompleted) {
      _worldDetailCompleter.complete();
    }
  }

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    if (request.uri.path.endsWith('/api/v1/world/detail')) {
      worldDetailStarted = true;
      await _worldDetailCompleter.future;
    }
    return super.send(request);
  }
}

class _FakeDeviceIdService implements DeviceIdService {
  const _FakeDeviceIdService();

  @override
  Future<String> getDeviceId() async => 'test-device-id';
}

class _BlockingChatroomMessageStorage extends MemoryChatroomMessageStorage {
  _BlockingChatroomMessageStorage(this.blockingLocationId);

  final String blockingLocationId;
  final Completer<void> _loadCompleter = Completer<void>();
  bool blockingLoadStarted = false;

  void completeBlockingLoad() {
    if (!_loadCompleter.isCompleted) _loadCompleter.complete();
  }

  @override
  Future<List<Map<String, dynamic>>> loadLatestMessages({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required int limit,
  }) async {
    if (locationId == blockingLocationId) {
      blockingLoadStarted = true;
      await _loadCompleter.future;
    }
    return super.loadLatestMessages(
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      limit: limit,
    );
  }
}

class _RecordingChatroomMessageStorage extends MemoryChatroomMessageStorage {
  Map<String, dynamic>? lastUpsertedMessage;

  @override
  Future<void> upsertMessage({
    required String ownerUid,
    required String worldId,
    required String locationId,
    required Map<String, dynamic> message,
    int maxMessagesPerLocation = 200,
  }) async {
    lastUpsertedMessage = Map<String, dynamic>.from(message);
    await super.upsertMessage(
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      message: message,
      maxMessagesPerLocation: maxMessagesPerLocation,
    );
  }
}

class _SequencedChatroomTransport implements ChatroomSocketTransport {
  _SequencedChatroomTransport(this.results);

  final List<ChatroomSocket> results;
  int connectCount = 0;

  @override
  Future<ChatroomSocket> connect(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    connectCount += 1;
    if (results.isEmpty) {
      throw StateError('no socket result queued');
    }
    return results.removeAt(0);
  }
}

class _FakeChatroomTransport implements ChatroomSocketTransport {
  _FakeChatroomTransport(this.socket);

  final _FakeChatroomSocket socket;

  @override
  Future<ChatroomSocket> connect(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    return socket;
  }
}

class _BlockingChatroomTransport implements ChatroomSocketTransport {
  _BlockingChatroomTransport(this.socket, this.connectCompleter);

  final _FakeChatroomSocket socket;
  final Completer<void> connectCompleter;
  bool connectStarted = false;

  @override
  Future<ChatroomSocket> connect(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    connectStarted = true;
    await connectCompleter.future;
    return socket;
  }
}

class _FakeChatroomSocket implements ChatroomSocket {
  final _messages = StreamController<String>.broadcast();
  final sent = <String>[];
  bool closed = false;
  bool failUserEnterLocationSend = false;

  List<String> get sentTypes {
    return sent
        .map(
          (raw) => (jsonDecode(raw) as Map<String, dynamic>)['type'] as String,
        )
        .toList(growable: false);
  }

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> send(String message) async {
    if (closed) throw StateError('socket closed');
    final frame = jsonDecode(message) as Map<String, dynamic>;
    if (failUserEnterLocationSend && frame['type'] == 'user_enter_location') {
      throw StateError('user_enter_location send failed');
    }
    sent.add(message);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
    await _messages.close();
  }

  Future<void> serverClose() async {
    await _messages.close();
  }

  void serverFrame(String type, Map<String, Object?> fields) {
    _messages.add(jsonEncode(<String, Object?>{'type': type, ...fields}));
  }

  void serverJoinAck() {
    final joinFrame = sent
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .lastWhere((frame) => frame['type'] == 'join');
    serverFrame('ack', {
      'world_id': 'world-1',
      'session_id': 'sess-1',
      'location_id': joinFrame['location_id'],
      'user_id': 'user-1',
      'payload': {'client_msg_id': joinFrame['client_msg_id']},
    });
  }

  void serverUserMessage({
    required int messageId,
    required int roundId,
    required String content,
    String locationId = 'loc-1',
  }) {
    serverFrame('user_message', {
      'world_id': 'world-1',
      'session_id': 'sess-1',
      'location_id': locationId,
      'global_msg_id': 90000 + messageId,
      'msg_id': messageId,
      'location_msg_id': messageId,
      'conversation_round_id': roundId,
      'payload': {
        'round_order': 1,
        'sender_type': 'user',
        'sender_id': 'user-1',
        'sender_name': 'Player One',
        'content': content,
        'created_at': 1717300000000 + messageId,
      },
    });
  }

  void serverV2Ack({required String clientMsgId, int errNo = 0}) {
    serverFrame('ack', {
      'stream_type': '',
      'ts': 1786327200000,
      'world_id': 'world-1',
      'location_id': '',
      'session_id': 'sess-1',
      'sender_type': '',
      'sender_id': '',
      'sender_name': '',
      'user_id': 'user-1',
      'client_msg_id': clientMsgId,
      'message_type': '',
      'min_app_version': 0,
      'created_at': '',
      'payload': <String, Object?>{},
      'err_no': errNo,
      'err_msg': errNo == 0 ? '' : 'rejected',
    });
  }

  void serverWaitingConversationRound({
    required String locationId,
    required int roundId,
    int errNo = 0,
  }) {
    serverFrame('waiting_conversation_round', {
      'stream_type': '',
      'ts': 1785890000000,
      'world_id': 'world-1',
      'location_id': locationId,
      'session_id': 'sess-1',
      'conversation_round_id': roundId,
      'payload': <String, Object?>{},
      'err_no': errNo,
      'err_msg': errNo == 0 ? '' : 'waiting rejected',
    });
  }

  void serverEndConversationRound({
    required String locationId,
    required int roundId,
    int errNo = 0,
  }) {
    serverFrame('end_conversation_round', {
      'stream_type': '',
      'ts': 1785890001000,
      'world_id': 'world-1',
      'location_id': locationId,
      'session_id': 'sess-1',
      'conversation_round_id': roundId,
      'payload': <String, Object?>{},
      'err_no': errNo,
      'err_msg': errNo == 0 ? '' : 'end rejected',
    });
  }

  void serverV2Tick({
    required int messageId,
    required int locationMessageId,
    required String locationId,
    required String globalText,
  }) {
    serverFrame('tick', {
      'stream_type': '',
      'ts': 1786327200000,
      'world_id': 'world-1',
      'location_id': locationId,
      'session_id': 'sess-1',
      'global_message_id': messageId > 0 ? 90000 + messageId : 0,
      'message_id': messageId,
      'location_message_id': locationMessageId,
      'conversation_round_id': 800,
      'sender_type': 'tick',
      'sender_id': 'tick',
      'sender_name': 'Time',
      'user_id': '',
      'client_msg_id': '',
      'message_type': 'text',
      'min_app_version': 0,
      'created_at': '2026-08-10 10:00:00',
      'payload': <String, Object?>{
        'current_time': 'Day 8, 10:00',
        'tick_no': 0,
        'sub_tick_no': 0,
        'global': globalText,
        'story_events': <Object?>[],
        'characters_moved': <Object?>[],
      },
      'err_no': 0,
      'err_msg': '',
    });
  }

  void serverV2StreamFrame({
    required String streamType,
    required String senderId,
    String senderName = '',
    required int messageId,
    required int locationMessageId,
    required int roundId,
    int? seq,
    String content = '',
    String currentTime = '',
    String locationId = 'loc-1',
  }) {
    serverFrame('character', {
      'stream_type': streamType,
      'world_id': 'world-1',
      'session_id': 'sess-1',
      'location_id': locationId,
      'global_message_id': messageId > 0 ? 90000 + messageId : 0,
      'message_id': messageId,
      'location_message_id': locationMessageId,
      'conversation_round_id': roundId,
      'sender_type': 'character',
      'sender_id': senderId,
      'sender_name': senderName,
      'user_id': '',
      'client_msg_id': '',
      'message_type': 'text',
      'min_app_version': 0,
      'created_at': '2026-08-10 10:00:00',
      'payload': <String, Object?>{
        if (seq != null) 'seq': seq,
        'content': content,
        if (currentTime.isNotEmpty) 'current_time': currentTime,
      },
      'err_no': 0,
      'err_msg': '',
    });
  }

  void serverV2Message({
    required String type,
    required String senderId,
    required String senderName,
    required int messageId,
    required int locationMessageId,
    required int roundId,
    required String content,
    String clientMsgId = '',
    String locationId = 'loc-1',
  }) {
    serverFrame(type, {
      'stream_type': '',
      'world_id': 'world-1',
      'session_id': 'sess-1',
      'location_id': locationId,
      'global_message_id': 90000 + messageId,
      'message_id': messageId,
      'location_message_id': locationMessageId,
      'conversation_round_id': roundId,
      'sender_type': type,
      'sender_id': senderId,
      'sender_name': senderName,
      'user_id': type == 'user' ? 'user-1' : '',
      'client_msg_id': clientMsgId,
      'message_type': 'text',
      'min_app_version': 0,
      'created_at': '2026-08-10 10:00:00',
      'payload': <String, Object?>{'content': content},
      'err_no': 0,
      'err_msg': '',
    });
  }
}

class _MutationHttpTransport extends _WorldChatroomHttpTransport {
  final cardRequests = <TransportRequest>[];
  Completer<void>? cardBarrier;
  Object? cardError;
  final historyRequests = <TransportRequest>[];
  final writeRequests = <TransportRequest>[];
  Future<TransportResponse> Function(TransportRequest)? history;
  Future<TransportResponse> Function(TransportRequest)? write;
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    if (request.uri.path.endsWith('/api/v2/messages')) {
      historyRequests.add(request);
      if (history != null) return history!(request);
      final query = request.uri.queryParameters;
      final all = messagesByLocation[query['location_id']] ?? [];
      final start = int.tryParse(query['start_conversation_round_id'] ?? '');
      final end = int.tryParse(query['end_conversation_round_id'] ?? '');
      final since = int.tryParse(query['since'] ?? '0') ?? 0;
      final limit = int.tryParse(query['limit'] ?? '20') ?? 20;
      final filtered =
          all
              .where(
                (m) =>
                    (start == null ||
                        (m['conversation_round_id'] as int) >= start) &&
                    (end == null ||
                        (m['conversation_round_id'] as int) <= end) &&
                    (since == 0 || (m['location_message_id'] as int) < since),
              )
              .toList()
            ..sort(
              (a, b) => (b['location_message_id'] as int).compareTo(
                a['location_message_id'] as int,
              ),
            );
      return _page(
        filtered.take(limit).toList(),
        hasMore: filtered.length > limit,
        newest: all.fold<int>(
          0,
          (v, m) => (m['location_message_id'] as int) > v
              ? m['location_message_id'] as int
              : v,
        ),
      );
    }
    if (request.method == 'GET' &&
        request.uri.path.endsWith('/llm-messages/cards')) {
      cardRequests.add(request);
      await cardBarrier?.future;
      if (cardError != null) throw cardError!;
      return _json({
        'err_no': 0,
        'data': {
          'conversation_round_id': int.parse(
            request.uri.queryParameters['conversation_round_id']!,
          ),
          'original_card_id': 0,
          'selected_card_id': 0,
          'active_card_id': 0,
          'confirmed': false,
          'can_regenerate': true,
          'can_confirm': false,
          'list': [],
          'total': 0,
        },
      });
    }
    if (request.uri.path.contains('/llm-messages/')) {
      writeRequests.add(request);
      return write != null
          ? write!(request)
          : _json({
              'err_no': 0,
              'data': {
                'start_conversation_round_id': 10,
                'end_conversation_round_id': 10,
                'newest_message_id': 0,
              },
            });
    }
    return super.send(request);
  }

  TransportResponse _page(
    List<Map<String, dynamic>> rows, {
    bool hasMore = false,
    int newest = 0,
  }) => _json({
    'err_no': 0,
    'data': {
      'messages': rows.map(_asV2HttpMessage).toList(),
      'has_more': hasMore,
      'newest_message_id': newest,
    },
  });
}

Map<String, dynamic> _mutationRow(
  int id,
  int cursor,
  int round, {
  String content = 'original',
}) => {
  ..._httpMessageJson(
    messageId: id,
    locationId: 'loc-1',
    content: content,
    locationMessageId: cursor,
    senderType: 'character',
  ),
  'sender_id': 'char-1',
  'sender_name': 'Alice',
  'conversation_round_id': round,
};
void _editFrame(
  _FakeChatroomSocket socket, {
  int id = 1,
  int cursor = 1,
  int round = 10,
  String world = 'world-1',
  String content = 'edited',
}) {
  socket.serverFrame('llm_message_updated', {
    'world_id': world,
    'location_id': 'loc-1',
    'stream_type': '',
    'global_message_id': 90000 + id,
    'message_id': id,
    'location_message_id': cursor,
    'conversation_round_id': round,
    'payload': {'content': content, 'status': 20},
    'err_no': 0,
  });
}

void _rangeFrame(
  _FakeChatroomSocket socket,
  int start,
  int end, {
  int newest = 0,
}) {
  socket.serverFrame('conversation_range_updated', {
    'world_id': 'world-1',
    'location_id': 'loc-1',
    'stream_type': '',
    'payload': {
      'start_conversation_round_id': start,
      'end_conversation_round_id': end,
      'newest_message_id': newest,
    },
    'err_no': 0,
  });
}

void _messageMutationTests() {
  Future<WorldChatroomService> setup(
    _FakeChatroomSocket socket,
    _MutationHttpTransport http, {
    ChatroomMessageStorage? storage,
  }) async {
    final service = await _service(
      socketTransport: _FakeChatroomTransport(socket),
      httpTransport: http,
      messageStorage: storage,
      useV2Protocol: true,
      refreshInitialSnapshotOnConnect: false,
    );
    addTearDown(service.dispose);
    await service.connect(worldId: 'world-1', identity: _identity());
    service.applyWorldSnapshot(_worldSnapshot());
    await service.refreshLatestMessages(locationId: 'loc-1', limit: 200);
    return service;
  }

  test(
    'batch blocks duplicate submission and refreshes HTTP range without WS',
    () async {
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [
          _mutationRow(1, 1, 9),
          _mutationRow(2, 2, 10),
          _mutationRow(3, 3, 10),
          _mutationRow(4, 4, 11),
        ];
      final service = await setup(_FakeChatroomSocket(), http);
      final reply = Completer<TransportResponse>();
      http.write = (_) => reply.future;
      final operations = [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: 90002,
          content: 'draft',
        ),
        const ChatroomLlmMessageOperation.delete(globalMessageId: 90003),
      ];
      final write = service.batchMutateLlmMessages(
        locationId: 'loc-1',
        conversationRoundId: 10,
        operations: operations,
      );
      expect(
        service.isMutatingLlmMessages(
          locationId: 'loc-1',
          conversationRoundId: 10,
        ),
        isTrue,
      );
      await expectLater(
        service.batchMutateLlmMessages(
          locationId: 'loc-1',
          conversationRoundId: 10,
          operations: operations,
        ),
        throwsStateError,
      );
      await _waitFor(() => http.writeRequests.length == 1);
      http.messagesByLocation['loc-1'] = [
        _mutationRow(1, 1, 9),
        _mutationRow(2, 2, 10, content: 'edited'),
        _mutationRow(4, 3, 11),
      ];
      reply.complete(
        http._json({
          'err_no': 0,
          'data': {
            'start_conversation_round_id': 10,
            'end_conversation_round_id': 11,
            'newest_message_id': 3,
          },
        }),
      );
      final result = await write;
      expect(result.endConversationRoundId, 11);
      await _waitFor(
        () => service.state.messagesByLocation['loc-1']!.length == 3,
      );
      expect(
        service.state.messagesByLocation['loc-1']!.map(
          (m) => m.globalMessageId,
        ),
        [90001, 90002, 90004],
      );
      expect(service.state.messagesByLocation['loc-1']![1].content, 'edited');
      expect(service.state.newestLocationMessageIds['loc-1'], 3);
      expect(
        http.historyRequests.last.uri.queryParameters,
        containsPair('end_conversation_round_id', '11'),
      );
      expect(
        service.isMutatingLlmMessages(
          locationId: 'loc-1',
          conversationRoundId: 10,
        ),
        isFalse,
      );
      expect(operations.first.content, 'draft');
    },
  );

  test(
    'batch ambiguous timeout refreshes committed state without retrying write',
    () async {
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [_mutationRow(1, 1, 10)];
      final service = await setup(_FakeChatroomSocket(), http);
      http.write = (_) async {
        http.messagesByLocation['loc-1'] = [];
        throw ApiException(message: 'timeout', kind: ApiExceptionKind.timeout);
      };
      await expectLater(
        service.batchMutateLlmMessages(
          locationId: 'loc-1',
          conversationRoundId: 10,
          operations: const [
            ChatroomLlmMessageOperation.delete(globalMessageId: 90001),
          ],
        ),
        throwsA(isA<ApiException>()),
      );
      await _waitFor(() => service.state.messagesByLocation['loc-1']!.isEmpty);
      expect(http.writeRequests, hasLength(1));
      expect(service.state.newestLocationMessageIds['loc-1'], 0);
      expect(
        service.isMutatingLlmMessages(
          locationId: 'loc-1',
          conversationRoundId: 10,
        ),
        isFalse,
      );
    },
  );

  test(
    'batch HTTP range merges with in-flight WS range and discards stale response',
    () async {
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [_mutationRow(1, 1, 10)];
      final socket = _FakeChatroomSocket();
      final service = await setup(socket, http);
      final old = Completer<TransportResponse>();
      http.history = (_) => old.future;
      _rangeFrame(socket, 11, 12);
      await _waitFor(() => http.historyRequests.length == 2);
      final cancelled = http.historyRequests.last.cancellationToken!;
      http.history = (_) async => http._page([]);
      await service.batchMutateLlmMessages(
        locationId: 'loc-1',
        conversationRoundId: 10,
        operations: const [
          ChatroomLlmMessageOperation.delete(globalMessageId: 90001),
        ],
      );
      await _waitFor(() => service.state.messagesByLocation['loc-1']!.isEmpty);
      expect(cancelled.isCancelled, isTrue);
      expect(
        http.historyRequests.last.uri.queryParameters,
        allOf(
          containsPair('start_conversation_round_id', '10'),
          containsPair('end_conversation_round_id', '12'),
          containsPair('since', '0'),
        ),
      );
      old.complete(http._page([_mutationRow(1, 1, 10)]));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(service.state.messagesByLocation['loc-1'], isEmpty);
    },
  );

  test(
    'batch late success after dispose does not refresh or mutate state',
    () async {
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [_mutationRow(1, 1, 10)];
      final service = await setup(_FakeChatroomSocket(), http);
      final response = Completer<TransportResponse>();
      http.write = (_) => response.future;
      final write = service.batchMutateLlmMessages(
        locationId: 'loc-1',
        conversationRoundId: 10,
        operations: const [
          ChatroomLlmMessageOperation.delete(globalMessageId: 90001),
        ],
      );
      await _waitFor(() => http.writeRequests.length == 1);
      final reads = http.historyRequests.length;
      service.dispose();
      response.complete(
        http._json({
          'err_no': 0,
          'data': {
            'start_conversation_round_id': 10,
            'end_conversation_round_id': 10,
            'newest_message_id': 0,
          },
        }),
      );
      expect(await write, isA<ChatroomMessageMutationResult>());
      expect(http.historyRequests.length, reads);
    },
  );

  test(
    'private card events leave formal history and service state unchanged',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [_mutationRow(1, 1, 10)];
      final service = await setup(socket, http);
      final state = service.state;
      final reads = http.historyRequests.length;
      for (final stream in ['start', 'chunk', 'end']) {
        socket.serverFrame('llm_card_stream', {
          'stream_type': stream,
          'world_id': 'world-1',
          'location_id': 'loc-1',
          'user_id': 'user-1',
          'conversation_round_id': 10,
          'global_message_id': 9007199254740994,
          'sender_type': 'character',
          'sender_id': 'char-1',
          'sender_name': 'Alice',
          'payload': {
            'card_id': 9007199254740993,
            'card_message_index': 1,
            'seq': 1,
            'content': 'candidate only',
          },
          'err_no': 0,
        });
      }
      socket.serverFrame('llm_card_generation_end', {
        'stream_type': '',
        'world_id': 'world-1',
        'location_id': 'loc-1',
        'user_id': 'user-1',
        'conversation_round_id': 10,
        'payload': {
          'card_id': 9007199254740993,
          'generation_state': 'succeeded',
          'billing': {
            'status': 'committed',
            'price_cent': 180,
            'pricing_version': 'round_v3',
          },
        },
        'err_no': 0,
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(service.state, same(state));
      expect(http.historyRequests.length, reads);
      expect(
        service.state.messagesByLocation['loc-1']!.single.content,
        'original',
      );
    },
  );

  test(
    'mutation late edit during deletion refresh cannot resurrect the deleted row',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [_mutationRow(1, 1, 10)];
      final service = await setup(socket, http);
      final oldPage = Completer<TransportResponse>();
      http.history = (_) => oldPage.future;
      _rangeFrame(socket, 10, 10);
      await _waitFor(() => http.historyRequests.length == 2);
      http.history = (_) async => http._page([]);
      _editFrame(socket);
      await _waitFor(() => service.state.messagesByLocation['loc-1']!.isEmpty);
      oldPage.complete(http._page([_mutationRow(1, 1, 10)]));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(service.state.messagesByLocation['loc-1'], isEmpty);
    },
  );

  test(
    'mutation unknown edit fetches its round without fabricating a bubble',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()..messagesByLocation['loc-1'] = [];
      final service = await setup(socket, http);
      _editFrame(socket, id: 88, round: 88);
      await _waitFor(() => http.historyRequests.length == 2);
      expect(
        http
            .historyRequests
            .last
            .uri
            .queryParameters['start_conversation_round_id'],
        '88',
      );
      expect(service.state.messagesByLocation['loc-1'] ?? [], isEmpty);
    },
  );

  test(
    'mutation snapshot caps cache without treating older valid messages as deleted',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [_mutationRow(1, 1, 1)];
      final service = await setup(socket, http);
      http.messagesByLocation['loc-1'] = [
        for (var i = 1; i <= 205; i++) _mutationRow(i, i, i),
      ];
      await service.refreshLocationHistory(locationId: 'loc-1');
      expect(service.state.messagesByLocation['loc-1']!.length, 200);
      expect(service.state.messagesByLocation['loc-1']!.first.messageId, 6);
      // Older pagination can still retrieve records evicted by the bounded snapshot.
      await service.loadOlderMessages(locationId: 'loc-1', beforeMessageId: 6);
      final older = await service.loadCachedMessages(
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 200,
      );
      expect(older, isNotEmpty);
      expect(
        service.state.worldMessages.any((m) => m.globalMessageId == 90001),
        isTrue,
      );
    },
  );

  test(
    'mutation rejoining location removes offline deletions from persisted cache',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [_mutationRow(1, 1, 10)];
      final storage = MemoryChatroomMessageStorage();
      final service = await setup(socket, http, storage: storage);
      http.messagesByLocation['loc-1'] = [];
      final joined = service.join(locationId: 'loc-1');
      await _waitFor(() => socket.sentTypes.contains('join'));
      final frame = socket.sent
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .lastWhere((f) => f['type'] == 'join');
      socket.serverV2Ack(clientMsgId: frame['client_msg_id'] as String);
      await joined;
      await _waitFor(() => service.state.messagesByLocation['loc-1']!.isEmpty);
      expect(
        await storage.loadLatestMessages(
          ownerUid: 'user-1',
          worldId: 'world-1',
          locationId: 'loc-1',
          limit: 200,
        ),
        isEmpty,
      );
    },
  );

  test(
    'mutation snapshot does not overwrite chunks received during storage commit',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()..messagesByLocation['loc-1'] = [];
      final storage = _BlockingMutationStorage();
      final service = await setup(socket, http, storage: storage);
      socket.serverV2StreamFrame(
        streamType: 'llm_chunk',
        senderId: 'char-1',
        messageId: 0,
        locationMessageId: 0,
        roundId: 30,
        seq: 1,
        content: 'A',
      );
      await _waitFor(() => service.state.streamMessagesByKey.isNotEmpty);
      final refresh = service.refreshLocationHistory(locationId: 'loc-1');
      await storage.entered.future;
      socket.serverV2StreamFrame(
        streamType: 'llm_chunk',
        senderId: 'char-1',
        messageId: 0,
        locationMessageId: 0,
        roundId: 30,
        seq: 2,
        content: 'B',
      );
      await _waitFor(
        () => service.state.streamMessagesByKey.values.single.content == 'AB',
      );
      storage.release.complete();
      await refresh;
      expect(service.state.messagesByLocation['loc-1']!.single.content, 'AB');
    },
  );

  test(
    'mutation edit preserves sender, invalidates old history and emits no ACK',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [_mutationRow(1, 1, 10)];
      final storage = MemoryChatroomMessageStorage();
      final service = await setup(socket, http, storage: storage);
      final oldPage = Completer<TransportResponse>();
      http.history = (_) => oldPage.future;
      final oldFetch = service.refreshLatestMessages(locationId: 'loc-1');
      await _waitFor(() => http.historyRequests.length == 2);
      final sentBefore = socket.sent.length;
      _editFrame(socket, world: 'wrong-world');
      _editFrame(socket, cursor: 2);
      await _waitFor(
        () =>
            service.state.messagesByLocation['loc-1']!.single.content ==
            'edited',
      );
      oldPage.complete(http._page([_mutationRow(1, 1, 10)], newest: 1));
      await oldFetch;
      final message = service.state.messagesByLocation['loc-1']!.single;
      expect(message.senderName, 'Alice');
      expect(message.locationMessageId, 2);
      expect(message.rawPayload['status'], 20);
      expect(service.state.worldMessages.single.content, 'edited');
      await _waitFor(() => socket.sent.length == sentBefore);
      final stored = await storage.loadLatestMessages(
        ownerUid: 'user-1',
        worldId: 'world-1',
        locationId: 'loc-1',
        limit: 200,
      );
      expect(stored.single['content'], 'edited');
      expect(stored.single['payload'], containsPair('status', 20));
    },
  );

  test(
    'mutation range clears empty rounds, allows lower newest and ignores late edit',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [
          _mutationRow(1, 1, 10),
          _mutationRow(2, 2, 20),
        ];
      final service = await setup(socket, http);
      http.messagesByLocation['loc-1'] = [_mutationRow(1, 1, 10)];
      _rangeFrame(socket, 20, 20, newest: 1);
      await _waitFor(
        () => service.state.messagesByLocation['loc-1']!.length == 1,
      );
      expect(service.state.newestLocationMessageIds['loc-1'], 1);
      final requests = http.historyRequests.length;
      _editFrame(socket, id: 2, cursor: 2, round: 20);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        service.state.messagesByLocation['loc-1']!.single.globalMessageId,
        90001,
      );
      expect(http.historyRequests.length, requests);
      http.messagesByLocation['loc-1'] = [];
      await service.refreshLocationHistory(locationId: 'loc-1');
      expect(service.state.messagesByLocation['loc-1'], isEmpty);
      expect(service.state.newestLocationMessageIds['loc-1'], 0);
    },
  );

  test(
    'mutation range paginates by minimum location ID and preserves outside rounds',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [
          _mutationRow(1, 1, 10),
          _mutationRow(2, 2, 20),
        ];
      final service = await setup(socket, http);
      http.messagesByLocation['loc-1'] = [
        _mutationRow(1, 1, 10),
        for (var i = 3; i <= 107; i++) _mutationRow(i, i - 1, 20),
      ];
      _rangeFrame(socket, 20, 20, newest: 106);
      await _waitFor(
        () => service.state.messagesByLocation['loc-1']!.length == 106,
      );
      final queries = http.historyRequests
          .skip(1)
          .map((r) => r.uri.queryParameters)
          .toList();
      expect(queries.map((q) => q['since']), ['0', '7']);
      expect(
        queries.every(
          (q) =>
              q['start_conversation_round_id'] == '20' &&
              q['end_conversation_round_id'] == '20',
        ),
        isTrue,
      );
      expect(
        service.state.messagesByLocation['loc-1']!.first.globalMessageId,
        90001,
      );
      expect(
        service.state.messagesByLocation['loc-1']!.any(
          (m) => m.globalMessageId == 90002,
        ),
        isFalse,
      );
      expect(service.state.newestLocationMessageIds['loc-1'], 106);
    },
  );

  test('mutation overlap cancels old request and ignores late pages', () async {
    final socket = _FakeChatroomSocket();
    final http = _MutationHttpTransport()
      ..messagesByLocation['loc-1'] = [
        _mutationRow(1, 1, 10),
        _mutationRow(2, 2, 20),
      ];
    final service = await setup(socket, http);
    final oldPage = Completer<TransportResponse>();
    http.history = (_) => oldPage.future;
    _rangeFrame(socket, 20, 20);
    await _waitFor(() => http.historyRequests.length == 2);
    final oldToken = http.historyRequests.last.cancellationToken!;
    http.history = (_) async => http._page([]);
    _rangeFrame(socket, 10, 10);
    await _waitFor(() => service.state.messagesByLocation['loc-1']!.isEmpty);
    expect(oldToken.isCancelled, isTrue);
    expect(
      http
          .historyRequests
          .last
          .uri
          .queryParameters['start_conversation_round_id'],
      '10',
    );
    expect(
      http
          .historyRequests
          .last
          .uri
          .queryParameters['end_conversation_round_id'],
      '20',
    );
    oldPage.complete(http._page([_mutationRow(2, 2, 20)], newest: 2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.state.messagesByLocation['loc-1'], isEmpty);
  });

  test(
    'mutation failed second page commits nothing and retry recovers',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [_mutationRow(1, 1, 10)];
      final service = await setup(socket, http);
      final failures = <ChatroomFailureEvent>[];
      final subscription = service.failures.listen(failures.add);
      addTearDown(subscription.cancel);
      http.history = (r) async => r.uri.queryParameters['since'] == '0'
          ? http._page([_mutationRow(2, 2, 10)], hasMore: true, newest: 2)
          : http._json({'err_no': 2004, 'err_msg': 'storage unavailable'});
      _rangeFrame(socket, 10, 10);
      await _waitFor(
        () => failures.any((f) => f.code == 'history_replacement_failed'),
      );
      expect(
        service.state.messagesByLocation['loc-1']!.single.globalMessageId,
        90001,
      );
      await expectLater(
        service.loadOlderMessages(locationId: 'loc-1', beforeMessageId: 2),
        throwsA(isA<ChatroomProtocolException>()),
      );
      http.history = null;
      http.messagesByLocation['loc-1'] = [];
      await service.refreshLocationHistory(locationId: 'loc-1');
      expect(service.state.messagesByLocation['loc-1'], isEmpty);
    },
  );

  test(
    'mutation successful write stays successful when fallback refresh fails',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [_mutationRow(1, 1, 10)];
      final service = await setup(socket, http);
      http.history = (_) async =>
          http._json({'err_no': 2004, 'err_msg': 'read failed'});
      expect(
        await service.batchMutateLlmMessages(
          locationId: 'loc-1',
          conversationRoundId: 10,
          operations: [
            ChatroomLlmMessageOperation.edit(
              globalMessageId: 90001,
              content: 'edit',
            ),
          ],
        ),
        isA<ChatroomMessageMutationResult>(),
      );
      await _waitFor(
        () => service.state.lastFailure?.code == 'history_replacement_failed',
      );
      expect(http.writeRequests.single.method, 'POST');
      expect(
        http.writeRequests.single.headers.entries.any(
          (e) =>
              e.key.toLowerCase() == 'authorization' &&
              e.value == 'Bearer token-1',
        ),
        isTrue,
      );
      http.history = null;
      http.messagesByLocation['loc-1'] = [];
      expect(
        await service.batchMutateLlmMessages(
          locationId: 'loc-1',
          conversationRoundId: 10,
          operations: [
            ChatroomLlmMessageOperation.delete(globalMessageId: 90001),
          ],
        ),
        isA<ChatroomMessageMutationResult>(),
      );
      await _waitFor(() => service.state.messagesByLocation['loc-1']!.isEmpty);
      expect(http.writeRequests.last.method, 'POST');
    },
  );

  test('mutation broadcast before HTTP response remains idempotent', () async {
    final socket = _FakeChatroomSocket();
    final http = _MutationHttpTransport()
      ..messagesByLocation['loc-1'] = [_mutationRow(1, 1, 10)];
    final service = await setup(socket, http);
    final response = Completer<TransportResponse>();
    http.write = (_) => response.future;
    final write = service.batchMutateLlmMessages(
      locationId: 'loc-1',
      conversationRoundId: 10,
      operations: [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: 90001,
          content: 'edited',
        ),
      ],
    );
    await _waitFor(() => http.writeRequests.isNotEmpty);
    http.messagesByLocation['loc-1'] = [
      _mutationRow(1, 1, 10, content: 'edited'),
    ];
    _rangeFrame(socket, 10, 10, newest: 1);
    await _waitFor(
      () =>
          service.state.messagesByLocation['loc-1']!.single.content == 'edited',
    );
    http.messagesByLocation['loc-1'] = [
      _mutationRow(1, 1, 10, content: 'edited'),
    ];
    response.complete(
      http._json({
        'err_no': 0,
        'data': {
          'start_conversation_round_id': 10,
          'end_conversation_round_id': 10,
          'newest_message_id': 0,
        },
      }),
    );
    expect(await write, isA<ChatroomMessageMutationResult>());
    await _waitFor(
      () =>
          http.historyRequests.length >= 2 &&
          service.state.newestLocationMessageIds['loc-1'] == 1,
    );
    expect(service.state.messagesByLocation['loc-1']!.length, 1);
    expect(service.state.messagesByLocation['loc-1']!.single.content, 'edited');
  });

  test(
    'mutation range preserves active streams and disposal rejects late response',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [_mutationRow(1, 1, 10)];
      final service = await setup(socket, http);
      socket.serverV2StreamFrame(
        streamType: 'llm_chunk',
        senderId: 'char-1',
        messageId: 0,
        locationMessageId: 0,
        roundId: 30,
        seq: 1,
        content: 'partial',
      );
      await _waitFor(() => service.state.streamMessagesByKey.isNotEmpty);
      http.messagesByLocation['loc-1'] = [];
      _rangeFrame(socket, 10, 30);
      await _waitFor(
        () => service.state.newestLocationMessageIds['loc-1'] == 0,
      );
      expect(
        service.state.streamMessagesByKey.values.single.content,
        'partial',
      );
      expect(
        service.state.messagesByLocation['loc-1']!.single.streaming,
        isTrue,
      );
      final delayed = Completer<TransportResponse>();
      http.history = (_) => delayed.future;
      final refresh = service.refreshLocationHistory(locationId: 'loc-1');
      await _waitFor(() => http.historyRequests.length == 3);
      await service.dispose();
      delayed.complete(http._page([_mutationRow(2, 1, 10)], newest: 1));
      await refresh;
      expect(
        service.state.messagesByLocation['loc-1']!.any(
          (m) => m.globalMessageId == 90002,
        ),
        isFalse,
      );
    },
  );
}

class _BlockingMutationStorage extends MemoryChatroomMessageStorage {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
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
    if (!entered.isCompleted) entered.complete();
    await release.future;
    await super.replaceMessages(
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
      messages: messages,
      startConversationRoundId: startConversationRoundId,
      endConversationRoundId: endConversationRoundId,
      isCurrent: isCurrent,
      maxMessagesPerLocation: maxMessagesPerLocation,
    );
  }
}

void _replyCompletionTests() {
  test(
    'unjoined preload, latest refresh and pagination share card history loading',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [
          {..._mutationRow(1, 1, 9), 'user_id': 'user-1'},
          {..._mutationRow(2, 2, 10), 'user_id': 'user-1'},
        ];
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        useV2Protocol: true,
        refreshInitialSnapshotOnConnect: false,
      );
      addTearDown(service.dispose);
      await service.connect(worldId: 'world-1', identity: _identity());
      service.applyWorldSnapshot(_worldSnapshot());
      http.cardBarrier = Completer<void>();
      var completed = false;
      final loading = service
          .initializeLeafLocationQueues(locationIds: ['loc-1'])
          .then((_) => completed = true);
      await _waitFor(() => http.cardRequests.isNotEmpty);
      expect(completed, isFalse, reason: 'History includes the card read');
      http.cardBarrier!.complete();
      await loading;
      expect(socket.sentTypes, isNot(contains('join')));
      expect(http.cardRequests, hasLength(1));
      expect(
        http.cardRequests.single.uri.queryParameters['conversation_round_id'],
        '10',
      );
      await service.refreshLatestMessages(locationId: 'loc-1');
      expect(http.cardRequests, hasLength(2));
      await service.loadOlderMessages(locationId: 'loc-1', beforeMessageId: 3);
      expect(http.cardRequests, hasLength(3));
      await service.loadOlderMessages(locationId: 'loc-1', beforeMessageId: 2);
      expect(
        http.cardRequests,
        hasLength(3),
        reason: 'Older rounds do not refetch the tail card group',
      );
      http.cardError = StateError('card read failed');
      final history = await service.refreshLatestMessages(locationId: 'loc-1');
      expect(history, hasLength(2));
      expect(service.state.lastFailure?.code, 'card_history_failed');
      expect(service.state.messagesByLocation['loc-1'], hasLength(2));
    },
  );
  for (final closeBeforeHistory in [false, true]) {
    test(
      'entry supplements cards only after history, disposed=$closeBeforeHistory',
      () async {
        final socket = _FakeChatroomSocket();
        final history = Completer<TransportResponse>();
        final http = _MutationHttpTransport()..history = (_) => history.future;
        final service = await _service(
          socketTransport: _FakeChatroomTransport(socket),
          httpTransport: http,
          useV2Protocol: true,
          ackTimeout: const Duration(seconds: 1),
          refreshInitialSnapshotOnConnect: false,
        );
        addTearDown(service.dispose);
        await service.connect(worldId: 'world-1', identity: _identity());
        service.applyWorldSnapshot(_worldSnapshot());
        final joining = service.join(locationId: 'loc-1');
        await _waitFor(() => socket.sentTypes.contains('join'));
        final join = socket.sent
            .map((raw) => jsonDecode(raw) as Map)
            .lastWhere((frame) => frame['type'] == 'join');
        socket.serverV2Ack(clientMsgId: join['client_msg_id'] as String);
        await joining;
        await _waitFor(() => http.historyRequests.isNotEmpty);
        expect(http.cardRequests, isEmpty);
        if (closeBeforeHistory) await service.dispose();
        history.complete(
          http._page([
            {..._mutationRow(1, 1, 10), 'user_id': 'user-1'},
          ], newest: 1),
        );
        if (closeBeforeHistory) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(http.cardRequests, isEmpty);
        } else {
          await _waitFor(() => http.cardRequests.isNotEmpty);
          expect(
            http
                .cardRequests
                .single
                .uri
                .queryParameters['conversation_round_id'],
            '10',
          );
          expect(
            service.state.messagesByLocation['loc-1']!.single.content,
            'original',
          );
          await service.refreshLocationHistory(locationId: 'loc-1');
          expect(
            http.cardRequests,
            hasLength(2),
            reason: 'Cards belong to each matching history refresh',
          );
        }
      },
    );
  }
  test(
    'Go on round end replaces unfinished streams with empty authoritative history',
    () async {
      final socket = _FakeChatroomSocket();
      final http = _MutationHttpTransport()
        ..messagesByLocation['loc-1'] = [
          {..._mutationRow(1, 1, 10), 'user_id': 'user-1'},
        ];
      final service = await _service(
        socketTransport: _FakeChatroomTransport(socket),
        httpTransport: http,
        useV2Protocol: true,
        ackTimeout: const Duration(seconds: 1),
        refreshInitialSnapshotOnConnect: false,
      );
      addTearDown(service.dispose);
      await service.connect(worldId: 'world-1', identity: _identity());
      service.applyWorldSnapshot(_worldSnapshot());
      final joining = service.join(locationId: 'loc-1');
      await _waitFor(() => socket.sentTypes.contains('join'));
      final joinFrame =
          jsonDecode(
                socket.sent.lastWhere(
                  (raw) => (jsonDecode(raw) as Map)['type'] == 'join',
                ),
              )
              as Map;
      socket.serverV2Ack(clientMsgId: joinFrame['client_msg_id'] as String);
      await joining;
      await service.refreshLocationHistory(locationId: 'loc-1');
      final actions = service.replyActions!;
      await actions.restore('loc-1');
      expect(actions.stateFor('loc-1')!.canGoOn, isTrue);
      final pending = actions.goOn('loc-1');
      await _waitFor(() => socket.sentTypes.contains('go_on'));
      final command =
          jsonDecode(
                socket.sent.lastWhere(
                  (raw) => (jsonDecode(raw) as Map)['type'] == 'go_on',
                ),
              )
              as Map;
      socket.serverFrame('ack', {
        'world_id': 'world-1',
        'location_id': 'loc-1',
        'user_id': 'user-1',
        'client_msg_id': command['client_msg_id'],
        'conversation_round_id': 20,
        'payload': <String, Object?>{},
        'err_no': 0,
      });
      await pending;
      socket.serverV2StreamFrame(
        streamType: 'llm_stream_start',
        senderId: 'char-1',
        messageId: 2,
        locationMessageId: 2,
        roundId: 20,
      );
      socket.serverV2StreamFrame(
        streamType: 'llm_chunk',
        senderId: 'char-1',
        messageId: 2,
        locationMessageId: 2,
        roundId: 20,
        seq: 1,
        content: 'Not persisted',
      );
      await _waitFor(
        () => service.state.messagesByLocation['loc-1']!.any(
          (m) => m.content == 'Not persisted',
        ),
      );
      socket.serverEndConversationRound(locationId: 'loc-1', roundId: 20);
      await _waitFor(() => !actions.stateForRound('loc-1', 10)!.goOnPending);
      expect(
        service.state.messagesByLocation['loc-1']!.where(
          (m) => m.conversationRoundNumber == 20,
        ),
        isEmpty,
      );
      expect(
        service.state.streamMessagesByKey.values.where(
          (m) => m.conversationRoundNumber == 20,
        ),
        isEmpty,
      );
      expect(actions.stateForRound('loc-1', 20)!.error, isNotNull);
      // A late single-message end cannot resurrect content after authoritative recovery.
      socket.serverV2StreamFrame(
        streamType: 'llm_stream_end',
        senderId: 'char-1',
        messageId: 2,
        locationMessageId: 2,
        roundId: 20,
        content: 'Late reply',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        service.state.messagesByLocation['loc-1']!.where(
          (m) => m.conversationRoundNumber == 20,
        ),
        isEmpty,
      );
      expect(socket.sentTypes.where((type) => type == 'go_on'), hasLength(1));
    },
  );
}

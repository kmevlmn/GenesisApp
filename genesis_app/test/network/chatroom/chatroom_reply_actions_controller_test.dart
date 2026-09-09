import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_client.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_http_api.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_http_models.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_models.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_reply_action_storage.dart';
import 'package:genesis_flutter_android/network/chatroom/world_chatroom_service.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';

const _round = 9007199254740993;
const _messageId = _round + 10;

ChatroomV2Message _v2(
  String type, {
  int round = _round,
  int id = _messageId,
  String user = 'u',
  String content = 'Original',
}) => ChatroomV2Message(
  type: type,
  worldId: 'w',
  locationId: 'l',
  userId: user,
  globalMessageId: id,
  messageId: id,
  locationMessageId: id,
  conversationRoundId: round,
  senderType: type,
  senderId: 'character-id',
  senderName: 'Alice',
  payload: {'content': content},
);
WorldChatroomMessage _formal({
  int round = _round,
  String user = 'u',
  String type = 'character',
}) => WorldChatroomMessage.fromHttpMessage(
  ChatroomHttpMessage.fromV2Message(_v2(type, round: round, user: user)),
);
ChatroomLlmCard _card(
  int id, {
  int index = 1,
  String content = 'Original',
  String generation = 'succeeded',
  bool canDelete = true,
  int messages = 2,
}) => ChatroomLlmCard.fromJson({
  'card_id': id,
  'card_index': index,
  'is_original': index == 1,
  'generation_state': generation,
  'can_edit': generation == 'succeeded',
  'can_delete': canDelete,
  'messages': generation != 'succeeded'
      ? []
      : List.generate(
          messages,
          (i) => {
            'type': 'character',
            'world_id': 'w',
            'location_id': 'l',
            'user_id': 'u',
            'conversation_round_id': _round,
            'global_message_id': _messageId + i,
            'card_id': id,
            'card_message_index': 1 + i * 2,
            'sender_type': 'character',
            'sender_id': 'c',
            'payload': {'content': i == 0 ? content : 'Second'},
          },
        ),
  'billing': {'status': 'not_required'},
  'created_at': '2026-09-08',
}, conversationRoundId: _round);
ChatroomLlmCardsResponse _cards(
  List<ChatroomLlmCard> cards, {
  bool confirmed = false,
  bool canRegenerate = true,
  int selected = 0,
  int round = _round,
}) => ChatroomLlmCardsResponse(
  conversationRoundId: round,
  originalCardId: cards.isEmpty ? 0 : cards.first.cardId,
  selectedCardId: selected,
  activeCardId: cards.isEmpty ? 0 : cards.last.cardId,
  confirmed: confirmed,
  canRegenerate: canRegenerate,
  canConfirm: cards.isNotEmpty,
  list: cards,
  total: cards.length,
  rawJson: const {},
);

class _Api extends ChatroomHttpApi {
  _Api() : super(ApiClient(baseUrl: 'https://unused.test'));
  ChatroomLlmCardsResponse cards = _cards([]);
  final history = <int, List<ChatroomHttpMessage>>{
    _round: [ChatroomHttpMessage.fromV2Message(_v2('character'))],
  };
  final calls = <String>[];
  Completer<ChatroomLlmCardsResponse>? cardsBarrier;
  Completer<void>? saveBarrier;
  Object? batchError;
  Object? selectionError;
  bool applyBeforeError = false;
  @override
  Future<ChatroomLlmCardsResponse> getLlmCards({
    required String worldId,
    required String locationId,
    required int conversationRoundId,
    NetworkCancellationToken? cancellationToken,
  }) async {
    calls.add('cards:$conversationRoundId');
    if (cardsBarrier != null) {
      final barrier = cardsBarrier!;
      cardsBarrier = null;
      return barrier.future;
    }
    return cards;
  }

  @override
  Future<ChatroomMessageListResponse> getMessages({
    required String worldId,
    required String locationId,
    int? since,
    int? limit,
    int? startConversationRoundId,
    int? endConversationRoundId,
    NetworkCancellationToken? cancellationToken,
  }) async {
    calls.add('history:$startConversationRoundId');
    return ChatroomMessageListResponse(
      messages: history[startConversationRoundId] ?? [],
      hasMore: false,
      newestMessageId: 0,
    );
  }

  @override
  Future<ChatroomCardMutationResult> batchMutateLlmCardMessages({
    required String worldId,
    required String locationId,
    required int conversationRoundId,
    required int cardId,
    required List<ChatroomLlmMessageOperation> operations,
  }) async {
    calls.add('batch-card:$cardId');
    if (saveBarrier != null) await saveBarrier!.future;
    if (batchError != null && !applyBeforeError) throw batchError!;
    final card = cards.list.firstWhere((item) => item.cardId == cardId);
    final raw = Map<String, dynamic>.from(card.rawJson);
    final messages = card.messages
        .map((message) => Map<String, dynamic>.from(message.rawJson))
        .toList();
    for (final operation in operations) {
      final index = messages.indexWhere(
        (message) => message['global_message_id'] == operation.globalMessageId,
      );
      if (operation.action == ChatroomLlmMessageAction.delete) {
        messages.removeAt(index);
      } else {
        messages[index]['payload'] = {'content': operation.content};
      }
    }
    raw['messages'] = messages;
    final saved = ChatroomLlmCard.fromJson(raw, conversationRoundId: _round);
    cards = _cards([
      for (final item in cards.list)
        if (item.cardId == cardId) saved else item,
    ]);
    if (batchError != null) throw batchError!;
    return ChatroomCardMutationResult(conversationRoundId: _round, card: saved);
  }

  @override
  Future<ChatroomMessageMutationResult> batchMutateLlmMessages({
    required String worldId,
    required String locationId,
    required int conversationRoundId,
    required List<ChatroomLlmMessageOperation> operations,
  }) async {
    calls.add('batch-formal');
    if (batchError != null) throw batchError!;
    return const ChatroomMessageMutationResult(
      startConversationRoundId: _round,
      endConversationRoundId: _round,
      newestMessageId: _messageId,
    );
  }

  @override
  Future<ChatroomCardSelection> selectLlmCard({
    required String worldId,
    required String locationId,
    required int conversationRoundId,
    required int cardId,
    required String clientMsgId,
  }) async {
    calls.add('select:$cardId');
    cards = _cards(cards.list, confirmed: true, selected: cardId);
    if (selectionError != null) throw selectionError!;
    return ChatroomCardSelection(
      conversationRoundId: conversationRoundId,
      selectedCardId: cardId,
      confirmed: true,
      startConversationRoundId: conversationRoundId,
      endConversationRoundId: conversationRoundId,
      newestMessageId: _messageId,
    );
  }
}

class _Session implements ChatroomSession {
  Future<ChatroomCardRegeneration> Function()? regenerateHandler;
  Future<ChatroomGoOnReceipt> Function(String request)? goOnHandler;
  final requests = <String>[];
  @override
  Future<ChatroomCardRegeneration> regenerateLlmCard({
    required String locationId,
    required int conversationRoundId,
    required String clientMsgId,
  }) {
    requests.add('regenerate:$clientMsgId');
    return regenerateHandler!();
  }

  @override
  Future<ChatroomGoOnReceipt> goOn({
    required String locationId,
    required int sourceConversationRoundId,
    required String clientMsgId,
  }) {
    requests.add('go-on:$clientMsgId');
    return goOnHandler!(clientMsgId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness({MemoryChatroomReplyActionStorage? storage, String owner = 'u'}) {
    controller = ChatroomReplyActionsController(
      worldId: 'w',
      ownerUid: owner,
      httpApi: api,
      session: () => session,
      isReady: (_) => ready,
      isTickLocked: () => locked,
      refreshFormalRange: (location, start, end) async {
        api.calls.add('refresh:$start');
      },
      refreshWallet: () async {
        walletRefreshes++;
      },
      storage: storage ?? MemoryChatroomReplyActionStorage(),
    );
    controller.observeMessages('l', [_formal(user: owner)]);
  }
  final api = _Api();
  final session = _Session();
  late ChatroomReplyActionsController controller;
  bool ready = true, locked = false;
  int walletRefreshes = 0;
  ChatroomReplyRoundState get state => controller.stateForRound('l', _round)!;
}

Future<void> _settle() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ChatroomLlmCardStream _stream(
  String stream, {
  int seq = 1,
  String content = '',
  int id = _messageId,
}) => ChatroomLlmCardStream.fromV2Message(
  ChatroomV2Message(
    type: 'llm_card_stream',
    streamType: stream,
    worldId: 'w',
    locationId: 'l',
    userId: 'u',
    conversationRoundId: _round,
    globalMessageId: id,
    senderType: 'character',
    senderId: 'c',
    payload: {
      'card_id': 102,
      'card_message_index': id == _messageId ? 1 : 3,
      'seq': seq,
      'content': content,
    },
  ),
);
ChatroomLlmCardGenerationEnd _terminal(String state) =>
    ChatroomLlmCardGenerationEnd.fromV2Message(
      ChatroomV2Message(
        type: 'llm_card_generation_end',
        worldId: 'w',
        locationId: 'l',
        userId: 'u',
        conversationRoundId: _round,
        payload: {
          'card_id': 102,
          'generation_state': state,
          'billing': {'status': 'not_required'},
        },
      ),
    );

void main() {
  test(
    'ownership uses user ID and refuses to infer it from the character sender',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.controller.observeMessages('l', [_formal(user: 'someone-else')]);
      expect(h.state.canGoOn, isFalse);
      expect(h.state.canRegenerate, isFalse);
      await expectLater(h.controller.prepareEditor('l'), throwsStateError);
      h.controller.observeMessages('l', [_formal()]);
      expect(h.state.canGoOn, isTrue);
      h.locked = true;
      expect(h.state.canGoOn, isFalse);
    },
  );

  test(
    'original remains during preflight and candidate appears only after approval',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      final barrier = Completer<ChatroomLlmCardsResponse>();
      h.api.cardsBarrier = barrier;
      final ack = Completer<ChatroomCardRegeneration>();
      h.session.regenerateHandler = () => ack.future;
      final action = h.controller.regenerate('l');
      await _settle();
      expect(h.state.showCandidates, isFalse);
      expect(h.state.displayedMessages.single.content, 'Original');
      expect(h.session.requests, isEmpty);
      expect(h.state.canRegenerate, isFalse);
      barrier.complete(_cards([]));
      await _settle();
      expect(h.state.showCandidates, isTrue);
      expect(h.state.displayedMessages, isEmpty);
      expect(h.state.cardPosition, 2);
      expect(h.state.cardCount, 2);
      expect(h.state.canRegenerate, isFalse);
      expect(h.state.canGoOn, isFalse);
      await h.controller.browse('l', -1);
      expect(h.state.displayedMessages.single.content, 'Original');
      h.api.cards = _cards([
        _card(101),
        _card(102, index: 2, generation: 'generating'),
      ]);
      ack.complete(
        const ChatroomCardRegeneration(
          conversationRoundId: _round,
          originalCardId: 101,
          cardId: 102,
          generationState: ChatroomCardGenerationState.generating,
          billing: ChatroomCardBilling(
            status: ChatroomCardBillingStatus.reserved,
          ),
        ),
      );
      await action;
      expect(h.state.viewedCardId, 101);
      expect(h.state.lastCompleteCardId, 101);
      expect(h.state.canEdit, isTrue);
      expect(h.state.canGoOn, isTrue);
    },
  );

  for (final fails in [false, true]) {
    test(
      'preflight ${fails ? 'failure' : 'denial'} never removes the original reply',
      () async {
        final h = _Harness();
        addTearDown(h.controller.dispose);
        await h.controller.restore('l');
        final revision = h.state.presentationRevision;
        final snapshots = <List<String>>[];
        h.controller.addListener(() {
          snapshots.add(
            h.state.displayedMessages.map((m) => m.content).toList(),
          );
          expect(h.state.showCandidates, isFalse);
          expect(h.state.presentationRevision, revision);
        });
        final barrier = Completer<ChatroomLlmCardsResponse>();
        h.api.cardsBarrier = barrier;
        final action = h.controller.regenerate('l');
        final rejected = expectLater(action, throwsStateError);
        await _settle();
        expect(h.state.displayedMessages.single.content, 'Original');
        expect(h.session.requests, isEmpty);
        if (fails) {
          barrier.completeError(StateError('offline'));
        } else {
          barrier.complete(_cards([], canRegenerate: false));
        }
        await rejected;
        expect(snapshots, isNotEmpty);
        expect(snapshots, everyElement(equals(['Original'])));
        expect(h.state.generating, isFalse);
        expect(h.state.displayedMessages.single.content, 'Original');
        expect(h.session.requests, isEmpty);
      },
    );
  }

  test(
    'candidate chunks dedupe seq, sort fixed indices, end replaces text, and browsing survives terminal',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.api.cards = _cards([_card(101)]);
      await h.controller.prepareEditor('l');
      final ack = Completer<ChatroomCardRegeneration>();
      h.session.regenerateHandler = () => ack.future;
      final action = h.controller.regenerate('l');
      await _settle();
      h.controller.receiveEvent(_stream('chunk', seq: 2, content: 'B'));
      h.controller.receiveEvent(_stream('chunk', seq: 1, content: 'A'));
      h.controller.receiveEvent(_stream('chunk', seq: 2, content: 'duplicate'));
      final revision = h.state.presentationRevision;
      expect(h.state.displayedMessages.single.content, 'AB');
      h.controller.receiveEvent(_stream('end', content: 'Full'));
      h.controller.receiveEvent(_stream('chunk', seq: 3, content: 'late'));
      h.controller.receiveEvent(
        _stream('end', content: 'Second', id: _messageId + 1),
      );
      expect(h.state.displayedMessages.map((m) => m.content), [
        'Full',
        'Second',
      ]);
      expect(
        h.state.displayedMessages.every((m) => m.locationMessageId == 0),
        isTrue,
      );
      expect(h.state.presentationRevision, revision);
      h.api.cards = _cards([
        _card(101),
        _card(102, index: 2, generation: 'generating'),
      ]);
      ack.complete(
        const ChatroomCardRegeneration(
          conversationRoundId: _round,
          originalCardId: 101,
          cardId: 102,
          generationState: ChatroomCardGenerationState.generating,
          billing: ChatroomCardBilling(
            status: ChatroomCardBillingStatus.reserved,
          ),
        ),
      );
      await action;
      await h.controller.browse('l', -1);
      h.api.cards = _cards([
        _card(101),
        _card(102, index: 2, content: 'Saved candidate'),
      ]);
      h.controller.receiveEvent(_terminal('succeeded'));
      await _settle();
      expect(h.state.viewedCardId, 101);
      expect(h.walletRefreshes, 1);
      await h.controller.browse('l', 1);
      expect(h.state.displayedMessages.first.content, 'Saved candidate');
      h.controller.receiveEvent(_stream('end', content: 'stale'));
      expect(h.state.displayedMessages.first.content, 'Saved candidate');
    },
  );

  test(
    'candidate save stays private and blank intermediate drafts persist but cannot submit',
    () async {
      final storage = MemoryChatroomReplyActionStorage();
      final h = _Harness(storage: storage);
      addTearDown(h.controller.dispose);
      h.api.cards = _cards([_card(101)]);
      final target = await h.controller.prepareEditor('l');
      const blank = [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: '',
        ),
      ];
      await h.controller.setDraft(target, blank);
      expect(
        (await storage.load(
          ownerUid: 'u',
          worldId: 'w',
          locationId: 'l',
        )).single['drafts'],
        isNotEmpty,
      );
      await expectLater(h.controller.save(target, blank), throwsArgumentError);
      const edit = [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: '  saved\n@name  ',
        ),
      ];
      await h.controller.save(target, edit);
      expect(h.state.displayedMessages.first.content, '  saved\n@name  ');
      expect(h.api.calls.where((c) => c.startsWith('refresh:')), isEmpty);
      expect(h.state.confirmed, isFalse);
      expect(target.draftOperations, isEmpty);
      await expectLater(
        h.controller.save(await h.controller.prepareEditor('l'), const [
          ChatroomLlmMessageOperation.delete(globalMessageId: _messageId),
          ChatroomLlmMessageOperation.delete(globalMessageId: _messageId + 1),
        ]),
        throwsStateError,
      );
    },
  );

  test(
    'formal saves omit card path and an unchanged editor does not send a batch',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      final target = await h.controller.prepareEditor('l');
      expect(target.cardId, isNull);
      await h.controller.save(target, []);
      expect(h.api.calls.contains('batch-formal'), isFalse);
      await h.controller.save(target, const [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: 'changed',
        ),
      ]);
      expect(h.api.calls.contains('batch-formal'), isTrue);
      expect(h.api.calls.contains('refresh:$_round'), isTrue);
    },
  );

  test(
    'unknown delete is reconciled with GET without resending an applied batch',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.api.cards = _cards([_card(101)]);
      final target = await h.controller.prepareEditor('l');
      h.api.batchError = TimeoutException('lost response');
      h.api.applyBeforeError = true;
      const changes = [
        ChatroomLlmMessageOperation.delete(globalMessageId: _messageId),
      ];
      await expectLater(
        h.controller.save(target, changes),
        throwsA(isA<TimeoutException>()),
      );
      h.api.batchError = null;
      await h.controller.save(target, changes);
      expect(h.api.calls.where((c) => c == 'batch-card:101').length, 1);
      expect(target.draftOperations, isEmpty);
    },
  );

  test(
    'send preparation saves then selects the browsed full card and refreshes',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.api.cards = _cards([_card(101), _card(102, index: 2, content: 'New')]);
      await h.controller.prepareEditor('l');
      await h.controller.browse('l', 1);
      final target = await h.controller.prepareEditor('l');
      await h.controller.setDraft(target, const [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: 'Draft',
        ),
      ]);
      h.api.calls.clear();
      await h.controller.finalizeBeforeSend('l');
      expect(h.api.calls, [
        'cards:$_round',
        'batch-card:102',
        'select:102',
        'refresh:$_round',
      ]);
      expect(h.state.confirmed, isTrue);
      expect(h.state.showCandidates, isFalse);
    },
  );

  test(
    'an external next round freezes an open editor and saves its current draft',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.api.cards = _cards([
        _card(101),
        _card(102, index: 2, generation: 'generating'),
      ]);
      final target = await h.controller.prepareEditor('l');
      await h.controller.setDraft(target, const [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: 'Open draft',
        ),
      ]);
      await h.controller.browse('l', 1);
      final event = ChatroomUserMessage.fromV2Message(
        _v2('user', round: _round + 1, id: _messageId + 20, user: 'another'),
      );
      h.controller.receiveEvent(event);
      expect(target.frozen, isTrue);
      await _settle();
      expect(h.api.calls.contains('batch-card:101'), isTrue);
      expect(h.api.calls.contains('select:101'), isTrue);
      expect(h.state.confirmed, isTrue);
      final before = h.api.calls.length;
      h.controller.receiveEvent(event);
      await _settle();
      expect(h.api.calls.length, before);
    },
  );

  test(
    'Go On ACK loss persists uncertainty by UID and reconnect never submits again',
    () async {
      final storage = MemoryChatroomReplyActionStorage();
      final h = _Harness(storage: storage);
      h.session.goOnHandler = (_) async => throw TimeoutException('lost ACK');
      await expectLater(
        h.controller.goOn('l'),
        throwsA(isA<TimeoutException>()),
      );
      expect(h.state.goOnUnknown, isTrue);
      expect(h.state.canGoOn, isFalse);
      await h.controller.reconnect();
      expect(h.session.requests.length, 1);
      final saved = await storage.load(
        ownerUid: 'u',
        worldId: 'w',
        locationId: 'l',
      );
      expect(saved.single['go_on'], isNotNull);
      h.controller.dispose();
      await _settle();
      final restored = _Harness(storage: storage);
      addTearDown(restored.controller.dispose);
      await restored.controller.restore('l');
      expect(restored.state.goOnUnknown, isTrue);
      expect(restored.session.requests, isEmpty);
      final other = _Harness(storage: storage, owner: 'another');
      addTearDown(other.controller.dispose);
      await other.controller.restore('l');
      expect(other.state.goOnUnknown, isFalse);
    },
  );

  test(
    'Go On rejected ACK unlocks retry, unlike unknown transport errors',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.session.goOnHandler = (_) async => throw const ChatroomFailureEvent(
        code: '2015',
        message: 'source expired',
        requestType: 'go_on',
      );
      await expectLater(
        h.controller.goOn('l'),
        throwsA(isA<ChatroomFailureEvent>()),
      );
      expect(h.state.goOnPending, isFalse);
    },
  );

  test(
    'Go On end before ACK is restored by new round, with no user echo required',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.session.goOnHandler = (request) async {
        h.controller.receiveEvent(
          ChatroomWaitingConversationRound.fromV2Message(
            _v2('waiting_conversation_round', round: _round + 1),
          ),
        );
        h.controller.receiveEvent(
          ChatroomEndConversationRound.fromV2Message(
            _v2('end_conversation_round', round: _round + 1),
          ),
        );
        h.api.history[_round + 1] = [
          ChatroomHttpMessage.fromV2Message(
            _v2(
              'character',
              round: _round + 1,
              id: _messageId + 1,
              content: 'Continued',
            ),
          ),
        ];
        return ChatroomGoOnReceipt(
          worldId: 'w',
          locationId: 'l',
          sourceConversationRoundId: _round,
          conversationRoundId: _round + 1,
          clientMsgId: request,
        );
      };
      await h.controller.goOn('l');
      expect(h.controller.stateFor('l')!.roundId, _round + 1);
      expect(
        h.controller.stateFor('l')!.displayedMessages.single.content,
        'Continued',
      );
      expect(h.state.goOnPending, isFalse);
      expect(h.session.requests.length, 1);
      expect(h.api.calls.contains('refresh:${_round + 1}'), isTrue);
    },
  );

  test('save failures preserve draft and stop Go On before sending', () async {
    final h = _Harness();
    addTearDown(h.controller.dispose);
    h.api.cards = _cards([_card(101)]);
    final target = await h.controller.prepareEditor('l');
    await h.controller.setDraft(target, const [
      ChatroomLlmMessageOperation.edit(
        globalMessageId: _messageId,
        content: 'Draft',
      ),
    ]);
    h.api.batchError = ApiException(
      message: 'no',
      kind: ApiExceptionKind.business,
    );
    await expectLater(h.controller.goOn('l'), throwsA(isA<ApiException>()));
    expect(h.session.requests, isEmpty);
    expect(target.draftOperations, isNotEmpty);
    expect(h.state.error, isNotNull);
  });
  test(
    'accepted Go On recovers atomic persisted AI history even if round end was lost',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      final ack = Completer<ChatroomGoOnReceipt>();
      h.session.goOnHandler = (request) => ack.future;
      final run = h.controller.goOn('l');
      await _settle();
      expect(h.state.goOnPending, isTrue);
      expect(h.state.goOnUnknown, isFalse);
      ack.complete(
        const ChatroomGoOnReceipt(
          worldId: 'w',
          locationId: 'l',
          sourceConversationRoundId: _round,
          conversationRoundId: _round + 1,
          clientMsgId: 'test',
        ),
      );
      await run;
      h.api.history[_round + 1] = [
        ChatroomHttpMessage.fromV2Message(_v2('user', round: _round + 1)),
      ];
      await h.controller.reconnect();
      expect(h.state.goOnPending, isTrue);
      expect(h.session.requests.length, 1);
      h.api.history[_round + 1] = [
        ChatroomHttpMessage.fromV2Message(_v2('character', round: _round + 1)),
      ];
      await h.controller.reconnect();
      expect(h.state.goOnPending, isFalse);
    },
  );

  test(
    'completed Go On empty history clears the new round rather than accepting streamed text',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.session.goOnHandler = (request) async => ChatroomGoOnReceipt(
        worldId: 'w',
        locationId: 'l',
        sourceConversationRoundId: _round,
        conversationRoundId: _round + 1,
        clientMsgId: request,
      );
      await h.controller.goOn('l');
      h.controller.observeMessages(
        'l',
        [_formal(), _formal(round: _round + 1).copyWith(streaming: true)],
        activeRoundIds: {_round + 1},
      );
      h.controller.receiveEvent(
        ChatroomEndConversationRound.fromV2Message(
          _v2('end_conversation_round', round: _round + 1),
        ),
      );
      await _settle();
      expect(h.controller.stateFor('l')!.displayedMessages, isEmpty);
      expect(h.state.goOnPending, isFalse);
      expect(h.controller.stateFor('l')!.error, isNotNull);
    },
  );

  test(
    'a zero-change formal editor freezes and closes for a new canonical AI round',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      final editor = await h.controller.prepareEditor('l');
      h.controller.receiveEvent(
        ChatroomAiStreamStart.fromV2Message(
          ChatroomV2Message(
            type: 'character',
            streamType: 'llm_stream_start',
            worldId: 'w',
            locationId: 'l',
            conversationRoundId: _round + 1,
            globalMessageId: _messageId + 30,
            messageId: _messageId + 30,
            locationMessageId: _messageId + 30,
            senderType: 'character',
          ),
        ),
      );
      expect(editor.frozen, isTrue);
      await _settle();
      expect(editor.editorShouldClose, isTrue);
      expect(h.api.calls.any((call) => call.startsWith('batch-')), isFalse);
    },
  );

  test(
    'a confirmed formal editor saves on external next round and does not reselect',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.api.cards = _cards([_card(101)], confirmed: true, selected: 101);
      final editor = await h.controller.prepareEditor('l');
      expect(editor.cardId, isNull);
      await h.controller.setDraft(editor, const [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: 'Formal draft',
        ),
      ]);
      h.controller.receiveEvent(
        ChatroomUserMessage.fromV2Message(
          _v2('user', round: _round + 1, id: _messageId + 40, user: 'other'),
        ),
      );
      expect(editor.frozen, isTrue);
      await _settle();
      expect(h.api.calls.contains('batch-formal'), isTrue);
      expect(editor.editorShouldClose, isTrue);
      expect(h.api.calls.any((call) => call.startsWith('select:')), isFalse);
    },
  );

  test(
    'missing initial owner is queried once and never inferred from sender ID',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      final controller = ChatroomReplyActionsController(
        worldId: 'w',
        ownerUid: 'u',
        httpApi: h.api,
        session: () => h.session,
        isReady: (_) => true,
        isTickLocked: () => false,
        refreshFormalRange: (_, _, _) async {},
        storage: MemoryChatroomReplyActionStorage(),
      );
      addTearDown(controller.dispose);
      controller.observeMessages('l', [_formal(user: '')]);
      await _settle();
      expect(controller.stateFor('l')!.isOwnRound, isTrue);
      controller.observeMessages('l', [_formal(user: '')]);
      await _settle();
      expect(h.api.calls.where((call) => call == 'history:$_round').length, 1);
    },
  );

  test(
    'a timed out delete reconciles after app restart without deleting again',
    () async {
      final storage = MemoryChatroomReplyActionStorage();
      final h = _Harness(storage: storage);
      h.api.cards = _cards([_card(101)]);
      final target = await h.controller.prepareEditor('l');
      h.api.batchError = TimeoutException('lost');
      h.api.applyBeforeError = true;
      const changes = [
        ChatroomLlmMessageOperation.delete(globalMessageId: _messageId),
      ];
      await expectLater(
        h.controller.save(target, changes),
        throwsA(isA<TimeoutException>()),
      );
      h.controller.dispose();
      await _settle();
      final second = _Harness(storage: storage);
      addTearDown(second.controller.dispose);
      second.api.cards = h.api.cards;
      await second.controller.restore('l');
      await second.controller.finalizeBeforeSend('l');
      expect(
        second.api.calls.where((call) => call.startsWith('batch-')),
        isEmpty,
      );
      expect(second.state.confirmed, isTrue);
    },
  );
  test(
    'a query started during save cannot replace its committed content',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.api.cards = _cards([_card(101), _card(102, index: 2)]);
      final target = await h.controller.prepareEditor('l');
      final old = h.api.cards;
      final saving = Completer<void>();
      h.api.saveBarrier = saving;
      final save = h.controller.save(target, const [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: 'Newest',
        ),
      ]);
      await _settle();
      final query = Completer<ChatroomLlmCardsResponse>();
      h.api.cardsBarrier = query;
      h.controller.receiveEvent(_terminal('succeeded'));
      await _settle();
      saving.complete();
      await save;
      query.complete(old);
      await _settle();
      expect(h.state.displayedMessages.first.content, 'Newest');
    },
  );

  test(
    'failed candidate retains its page and never exposes uncommitted text',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.api.cards = _cards([
        _card(101),
        _card(102, index: 2, generation: 'generating'),
      ]);
      await h.controller.prepareEditor('l');
      await h.controller.browse('l', 1);
      h.controller.receiveEvent(_stream('chunk', content: 'Must disappear'));
      expect(h.state.displayedMessages.single.content, 'Must disappear');
      h.api.cards = _cards([
        _card(101),
        _card(102, index: 2, generation: 'failed'),
      ]);
      h.controller.receiveEvent(_terminal('failed'));
      await _settle();
      expect(h.state.displayedMessages, isEmpty);
      expect(h.state.cardCount, 2);
      expect(h.state.cardPosition, 2);
      expect(h.state.canEdit, isFalse);
      await h.controller.browse('l', -1);
      expect(h.state.canEdit, isTrue);
    },
  );

  test(
    'only a newer world Tick fixes the card; old Tick replay cannot freeze an editor',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.controller.observeMessages('l', [
        _formal(),
        _formal(type: 'tick').copyWith(tickNo: 10, subTickNo: 1),
      ]);
      h.api.cards = _cards([_card(101)]);
      final target = await h.controller.prepareEditor('l');
      ChatroomTickAdvanceMessage tick(int number) => ChatroomTickAdvanceMessage(
        sessionId: '',
        worldId: 'w',
        locationId: 'l',
        userId: '',
        code: 0,
        codeMsg: '',
        ts: null,
        messageId: number,
        globalMessageId: number,
        locationMessageId: number,
        conversationRoundId: '${_round + 1}',
        roundOrder: 0,
        senderType: 'tick',
        senderId: 'tick',
        senderName: '',
        content: '',
        broadcast: true,
        tickNo: number,
        subTickNo: 1,
        currentTime: '',
      );
      h.controller.receiveEvent(tick(9));
      await _settle();
      expect(target.frozen, isFalse);
      expect(target.editorShouldClose, isFalse);
      h.controller.receiveEvent(tick(11));
      expect(target.frozen, isTrue);
      await _settle();
      expect(target.editorShouldClose, isTrue);
      expect(h.api.calls.where((call) => call.startsWith('select:')).length, 1);
    },
  );

  test(
    'draft persistence includes only changed message baselines and empty save removes them',
    () async {
      final storage = MemoryChatroomReplyActionStorage();
      final h = _Harness(storage: storage);
      addTearDown(h.controller.dispose);
      h.api.cards = _cards([_card(101)]);
      final target = await h.controller.prepareEditor('l');
      await h.controller.setDraft(target, const [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: 'Draft',
        ),
      ]);
      var saved = (await storage.load(
        ownerUid: 'u',
        worldId: 'w',
        locationId: 'l',
      )).single;
      expect((saved['draft_baselines'] as Map)['101'], {
        '$_messageId': 'Original',
      });
      await h.controller.save(target, []);
      saved = (await storage.load(
        ownerUid: 'u',
        worldId: 'w',
        locationId: 'l',
      )).single;
      expect(saved['draft_baselines'], isEmpty);
      expect(saved['drafts'], isEmpty);
      expect(h.api.calls.any((call) => call.startsWith('batch-')), isFalse);
    },
  );

  test(
    'a save response after controller disposal cannot notify the old page',
    () async {
      final h = _Harness();
      h.api.cards = _cards([_card(101)]);
      final target = await h.controller.prepareEditor('l');
      final barrier = Completer<void>();
      h.api.saveBarrier = barrier;
      var updates = 0;
      h.controller.addListener(() => updates++);
      final save = h.controller.save(target, const [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: 'Draft',
        ),
      ]);
      final failure = expectLater(save, throwsStateError);
      await _settle();
      h.controller.dispose();
      final before = updates;
      barrier.complete();
      await failure;
      expect(updates, before);
    },
  );
  test(
    'documented infrastructure error ACKs retain the non-idempotent request',
    () async {
      for (final code in [2002, 2003, 2004, 5000, 5001, 5002]) {
        final h = _Harness();
        h.session.goOnHandler = (_) async => throw ChatroomFailureEvent(
          code: '$code',
          message: 'infrastructure error',
          requestType: 'go_on',
        );
        await expectLater(
          h.controller.goOn('l'),
          throwsA(isA<ChatroomFailureEvent>()),
        );
        expect(h.state.goOnUnknown, isTrue, reason: 'err_no=$code');
        await h.controller.reconnect();
        expect(h.session.requests.length, 1);
        h.controller.dispose();
      }
    },
  );

  test(
    'source expired ACK invalidates the old source and refreshes latest history',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      var refreshes = 0;
      final controller = ChatroomReplyActionsController(
        worldId: 'w',
        ownerUid: 'u',
        httpApi: h.api,
        session: () => h.session,
        isReady: (_) => true,
        isTickLocked: () => false,
        refreshFormalRange: (_, _, _) async {},
        refreshLatestHistory: (_) async {
          refreshes++;
        },
        storage: MemoryChatroomReplyActionStorage(),
      );
      addTearDown(controller.dispose);
      controller.observeMessages('l', [_formal()]);
      h.session.goOnHandler = (_) async => throw const ChatroomFailureEvent(
        code: '2015',
        message: 'source expired',
        requestType: 'go_on',
      );
      await expectLater(
        controller.goOn('l'),
        throwsA(isA<ChatroomFailureEvent>()),
      );
      expect(refreshes, 1);
      expect(controller.stateFor('l')!.canGoOn, isFalse);
      expect(controller.stateFor('l')!.goOnPending, isFalse);
    },
  );
  test(
    'completed Go On receipt restores ownership absent from formal history',
    () async {
      final storage = MemoryChatroomReplyActionStorage();
      final h = _Harness(storage: storage);
      h.session.goOnHandler = (request) async => ChatroomGoOnReceipt(
        worldId: 'w',
        locationId: 'l',
        sourceConversationRoundId: _round,
        conversationRoundId: _round + 1,
        clientMsgId: request,
      );
      await h.controller.goOn('l');
      h.api.history[_round + 1] = [
        ChatroomHttpMessage.fromV2Message(
          _v2('character', round: _round + 1, user: ''),
        ),
      ];
      await h.controller.reconnect();
      expect(h.state.goOnPending, isFalse);
      h.controller.dispose();
      await _settle();
      final restored = _Harness(storage: storage);
      addTearDown(restored.controller.dispose);
      restored.controller.observeMessages('l', [
        _formal(round: _round + 1, user: ''),
      ]);
      await restored.controller.restore('l');
      expect(restored.controller.stateFor('l')!.roundId, _round + 1);
      expect(restored.controller.stateFor('l')!.isOwnRound, isTrue);
      expect(restored.controller.stateFor('l')!.canGoOn, isTrue);
    },
  );
  test(
    'confirming one of two drafted cards retires alternatives and future sends remain unblocked',
    () async {
      final storage = MemoryChatroomReplyActionStorage();
      final h = _Harness(storage: storage);
      addTearDown(h.controller.dispose);
      h.api.cards = _cards([_card(101), _card(102, index: 2)]);
      final first = await h.controller.prepareEditor('l');
      await h.controller.setDraft(first, const [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: 'Unselected draft',
        ),
      ]);
      await h.controller.browse('l', 1);
      final selected = await h.controller.prepareEditor('l');
      await h.controller.setDraft(selected, const [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: 'Selected draft',
        ),
      ]);
      h.api.calls.clear();
      await h.controller.finalizeBeforeSend('l');
      expect(h.api.calls, [
        'cards:$_round',
        'batch-card:102',
        'select:102',
        'refresh:$_round',
      ]);
      final saved = (await storage.load(
        ownerUid: 'u',
        worldId: 'w',
        locationId: 'l',
      )).single;
      expect(saved['drafts'], isEmpty);
      expect(saved['draft_baselines'], isEmpty);
      expect(saved['uncertain_batches'], isEmpty);
      h.api.calls.clear();
      await h.controller.finalizeBeforeSend('l');
      expect(h.api.calls, isEmpty);
    },
  );

  test(
    'recovering a lost selection ACK retires only drafts of unselected cards',
    () async {
      final storage = MemoryChatroomReplyActionStorage();
      final h = _Harness(storage: storage);
      addTearDown(h.controller.dispose);
      h.api.cards = _cards([_card(101), _card(102, index: 2)]);
      final first = await h.controller.prepareEditor('l');
      await h.controller.setDraft(first, const [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: 'Unselected draft',
        ),
      ]);
      await h.controller.browse('l', 1);
      final selected = await h.controller.prepareEditor('l');
      await h.controller.setDraft(selected, const [
        ChatroomLlmMessageOperation.edit(
          globalMessageId: _messageId,
          content: 'Selected draft',
        ),
      ]);
      h.api.selectionError = TimeoutException('lost ACK');
      await expectLater(
        h.controller.finalizeBeforeSend('l'),
        throwsA(isA<TimeoutException>()),
      );
      h.api.selectionError = null;
      h.api.calls.clear();
      await h.controller.finalizeBeforeSend('l');
      expect(h.api.calls, ['cards:$_round', 'refresh:$_round']);
      final saved = (await storage.load(
        ownerUid: 'u',
        worldId: 'w',
        locationId: 'l',
      )).single;
      expect(saved['drafts'], isEmpty);
      h.api.calls.clear();
      await h.controller.finalizeBeforeSend('l');
      expect(h.api.calls, isEmpty);
    },
  );

  test(
    'a selected card draft is preserved when confirmed recovery cannot prove it was saved',
    () async {
      final storage = MemoryChatroomReplyActionStorage();
      await storage.save(
        ownerUid: 'u',
        worldId: 'w',
        locationId: 'l',
        roundId: _round,
        value: {
          'round_id': _round,
          'owner': 'u',
          'viewed_card_id': 102,
          'last_complete_card_id': 102,
          'fixed_card_id': 102,
          'selection_request_id': 'pending-selection',
          'frozen': true,
          'drafts': {
            '101': [
              {
                'action': 'edit',
                'global_message_id': _messageId,
                'content': 'Unselected',
              },
            ],
            '102': [
              {
                'action': 'edit',
                'global_message_id': _messageId,
                'content': 'Still unsaved',
              },
            ],
          },
        },
      );
      final h = _Harness(storage: storage);
      addTearDown(h.controller.dispose);
      h.api.cards = _cards(
        [_card(101), _card(102, index: 2)],
        confirmed: true,
        selected: 102,
      );
      await h.controller.restore('l');
      expect(h.state.error, isA<StateError>());
      final saved = (await storage.load(
        ownerUid: 'u',
        worldId: 'w',
        locationId: 'l',
      )).single;
      expect((saved['drafts'] as Map).keys, ['102']);
      expect(
        ((saved['drafts'] as Map)['102'] as List).single['content'],
        'Still unsaved',
      );
      expect(h.api.calls.any((call) => call.startsWith('batch-')), isFalse);
    },
  );
}

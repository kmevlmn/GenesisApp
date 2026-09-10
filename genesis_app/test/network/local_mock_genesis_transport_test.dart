import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_http_models.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_timeline_payload.dart';
import 'package:genesis_flutter_android/network/genesis_api.dart';
import 'package:genesis_flutter_android/network/local_mock_genesis_transport.dart';
import 'package:genesis_flutter_android/network/mock_data/mock_v1_data.dart';
import 'package:genesis_flutter_android/network/models/gem_purchase_report.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/network/models/origin.dart';
import 'package:genesis_flutter_android/network/models/search_v2.dart';
import 'package:genesis_flutter_android/network/models/world.dart';

void main() {
  test(
    'local mock never acknowledges a membership receipt or prepares a purchase identity',
    () async {
      final api = GenesisApi(useMock: true);
      await expectLater(
        api.v1.membership.claimGuest(
          const MembershipPurchaseRequest(
            product: MembershipProduct(
              title: 'Test',
              benefits: [],
              planCode: 'pro_monthly',
              provider: MembershipProvider.google,
              storeProductId: 'test-pro',
              basePlanId: 'test-month',
              billingMonths: 1,
              monthlyGemsCent: 100,
              priceCurrencyCode: 'USD',
              priceAmount: 999,
              canPurchase: true,
              purchaseBlockReason: '',
            ),
            requestId: 'test-claim',
            purchaseToken: 'test-proof',
            guest: MembershipGuestIdentity(
              accountUuid: '4b74ec68-7abc-4cce-a223-e997e31dc811',
            ),
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 5000)),
      );
      await expectLater(
        api.v1.membership.prepareGuest(
          provider: MembershipProvider.google,
          deviceId: 'test-device',
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 5000)),
      );
      final product = MembershipProduct(
        title: 'Test Pro Monthly',
        benefits: const [],
        planCode: 'pro_monthly',
        provider: MembershipProvider.google,
        storeProductId: 'test-pro',
        basePlanId: 'test-month',
        billingMonths: 1,
        monthlyGemsCent: 100,
        priceCurrencyCode: 'USD',
        priceAmount: 999,
        canPurchase: true,
        purchaseBlockReason: '',
      );
      await expectLater(
        api.v1.membership.reportPurchase(
          MembershipPurchaseRequest(
            product: product,
            requestId: 'test-request',
            purchaseToken: 'test-token',
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 5000)),
      );
    },
  );
  test('local membership catalog uses the documented empty response', () async {
    final api = GenesisApi(useMock: true);
    for (final provider in MembershipProvider.values) {
      final result = await api.v1.membership.products(provider: provider);
      expect(result.products, isEmpty);
    }
  });

  test('WorldDetail parses last chat location compatibly', () {
    expect(
      WorldDetail.fromJson(const {
        'world_id': 'w_1',
        'last_chat_location_id': ' loc_1 ',
      }).lastChatLocationId,
      'loc_1',
    );
    expect(
      WorldDetail.fromJson(const {
        'world_id': 'w_1',
        'last_chat_location_id': 123,
      }).lastChatLocationId,
      '',
    );
    expect(
      WorldDetail.fromJson(const {'world_id': 'w_1'}).lastChatLocationId,
      '',
    );
  });

  test('local mock chatroom messages preserve message_type', () async {
    final api = GenesisApi(useMock: true);

    final textHistory = await api.chatroomHttp.getMessages(
      worldId: 'w_mock_001',
      locationId: 'loc_hub',
      since: 0,
      limit: 20,
    );
    expect(textHistory.messages, isNotEmpty);
    expect(
      textHistory.messages.every((message) => message.messageType == 'text'),
      isTrue,
    );

    const imageWorldId = 'w_image_message_contract_test';
    const imageLocationId = 'loc_image_message_contract_test';
    const imageUrl = 'https://cdn.example.com/narrator.webp';
    final narratorMessageId = await api.chatroomHttp.writeNarrator(
      worldId: imageWorldId,
      tickId: 'tick_image_message_contract_test',
      locationGroups: const [
        ChatroomNarratorLocationGroup(
          locationId: imageLocationId,
          locationName: 'Image Message Test',
          locationSummary: '',
          characters: [],
          initialDialogue: [
            ChatroomNarratorDialogueLine(
              charId: 'nar_pic',
              charName: 'Narrator',
              content: imageUrl,
            ),
          ],
        ),
      ],
    );
    expect(narratorMessageId, greaterThan(0));

    final imageHistory = await api.chatroomHttp.getMessages(
      worldId: imageWorldId,
      locationId: imageLocationId,
      since: 0,
      limit: 20,
    );
    expect(imageHistory.messages, hasLength(1));
    expect(imageHistory.messages.single.content, imageUrl);
    expect(imageHistory.messages.single.messageType, 'image');
    expect(imageHistory.messages.single.businessType, 'narrator');

    final imageWorldMessages = await api.chatroomHttp.getWorldMessages(
      worldId: imageWorldId,
    );
    expect(imageWorldMessages.locations, hasLength(1));
    expect(imageWorldMessages.locations.single.messages, hasLength(1));
    expect(
      imageWorldMessages.locations.single.messages.single.messageType,
      'image',
    );
  });

  test('local mock keeps legacy flat supplemental history explicit', () async {
    const worldId = 'w_timeline_message_contract_test';
    const locationId = 'loc_timeline_message_contract_test';
    LocalMockGenesisTransport.instance.seedChatroomTimelineMessages(
      worldId: worldId,
      locationId: locationId,
    );
    final api = GenesisApi(useMock: true);

    final history = await api.chatroomHttp.getLegacyMessages(
      worldId: worldId,
      locationId: locationId,
      since: 0,
      limit: 20,
    );

    expect(history.messages, hasLength(3));
    expect(history.hasMore, isFalse);
    expect(history.newestMessageId, greaterThan(0));
    final bySenderType = {
      for (final message in history.messages) message.senderType: message,
    };
    expect(bySenderType.keys, {
      chatroomUserEnterLocationSenderType,
      chatroomStoryEventsSenderType,
      chatroomCharactersMovedSenderType,
    });
    expect(
      bySenderType[chatroomUserEnterLocationSenderType]?.timelinePayload,
      isA<ChatroomUserEnterLocationPayload>(),
    );
    expect(
      bySenderType[chatroomUserEnterLocationSenderType]?.locationMessageId,
      greaterThan(0),
    );
    expect(
      bySenderType[chatroomUserEnterLocationSenderType]?.locationId,
      locationId,
    );
    expect(
      bySenderType[chatroomUserEnterLocationSenderType]?.content,
      'Iris Vale entered the location.',
    );
    expect(bySenderType[chatroomStoryEventsSenderType]?.locationMessageId, 0);
    expect(
      bySenderType[chatroomCharactersMovedSenderType]?.locationMessageId,
      0,
    );
    expect(
      bySenderType[chatroomStoryEventsSenderType]?.timelinePayload,
      isA<ChatroomStoryEventsPayload>(),
    );
    expect(
      bySenderType[chatroomCharactersMovedSenderType]?.timelinePayload,
      isA<ChatroomCharactersMovedPayload>(),
    );
  });

  test('local mock V2 history pages only by location message id', () async {
    const worldId = 'w_v2_message_contract_test';
    const locationId = 'loc_v2_message_contract_test';
    LocalMockGenesisTransport.instance.seedChatroomV2TickMessage(
      worldId: worldId,
      locationId: locationId,
    );
    final api = GenesisApi(useMock: true);
    await api.chatroomHttp.writeNarrator(
      worldId: worldId,
      tickId: 'tick_v2_message_contract_test',
      locationGroups: const <ChatroomNarratorLocationGroup>[
        ChatroomNarratorLocationGroup(
          locationId: locationId,
          locationName: 'V2 Mock Location',
          locationSummary: '',
          characters: <ChatroomNarratorCharacter>[],
          initialDialogue: <ChatroomNarratorDialogueLine>[
            ChatroomNarratorDialogueLine(
              charId: 'nar',
              charName: 'Narrator',
              content: 'A newer narrator message.',
            ),
            ChatroomNarratorDialogueLine(
              charId: 'c_mock_iris',
              charName: 'Iris Vale',
              content: 'Narrator rows from characters downgrade.',
            ),
          ],
        ),
      ],
    );

    final newestPage = await api.chatroomHttp.getMessages(
      worldId: worldId,
      locationId: locationId,
      since: 0,
      limit: 1,
    );
    expect(newestPage.messages, hasLength(1));
    expect(newestPage.hasMore, isTrue);
    expect(newestPage.messages.single.businessType, 'character');
    expect(newestPage.messages.single.senderType, 'narrator');
    expect(
      newestPage.messages.single.payload['content'],
      'Narrator rows from characters downgrade.',
    );
    expect(
      newestPage.newestMessageId,
      newestPage.messages.single.locationMessageId,
    );

    final olderPage = await api.chatroomHttp.getMessages(
      worldId: worldId,
      locationId: locationId,
      since: newestPage.messages.single.locationMessageId,
      limit: 20,
    );
    expect(olderPage.messages, hasLength(2));
    final narrator = olderPage.messages.first;
    expect(narrator.businessType, 'narrator');
    expect(narrator.senderId, 'nar');
    final tick = olderPage.messages.last;
    expect(tick.businessType, 'tick');
    expect(tick.senderType, 'tick');
    expect(tick.locationMessageId, greaterThan(0));
    expect(tick.v2TickPayload?.tickNo, 4);
    expect(tick.v2TickPayload?.subTickNo, 1);
    expect(tick.v2TickPayload?.storyEvents.single.locationId, locationId);
    expect(olderPage.hasMore, isFalse);
    expect(olderPage.newestMessageId, newestPage.newestMessageId);
  });

  test(
    'local mock edits and deletes replies with closed range history',
    () async {
      const world = 'w_mock_mutations';
      const location = 'loc_mock_mutations';
      final api = GenesisApi(useMock: true);
      await api.chatroomHttp.writeNarrator(
        worldId: world,
        tickId: 'tick_mock_mutations',
        locationGroups: const [
          ChatroomNarratorLocationGroup(
            locationId: location,
            locationName: 'Mutation fixture',
            locationSummary: '',
            characters: [],
            initialDialogue: [
              ChatroomNarratorDialogueLine(
                charId: 'nar',
                charName: 'Narrator',
                content: 'Original',
              ),
            ],
          ),
        ],
      );
      final initial = await api.chatroomHttp.getMessages(
        worldId: world,
        locationId: location,
      );
      final target = initial.messages.single;
      expect(
        await api.chatroomHttp.batchMutateLlmMessages(
          worldId: world,
          locationId: location,
          conversationRoundId: target.conversationRoundId,
          operations: [
            ChatroomLlmMessageOperation.edit(
              globalMessageId: target.globalMessageId,
              content: '  Edited reply  ',
            ),
          ],
        ),
        isA<ChatroomMessageMutationResult>(),
      );
      final edited = await api.chatroomHttp.getMessages(
        worldId: world,
        locationId: location,
        startConversationRoundId: target.conversationRoundId,
        endConversationRoundId: target.conversationRoundId,
      );
      expect(edited.messages.single.payload['content'], '  Edited reply  ');
      final outside = await api.chatroomHttp.getMessages(
        worldId: world,
        locationId: location,
        startConversationRoundId: target.conversationRoundId + 1,
        endConversationRoundId: target.conversationRoundId + 1,
      );
      expect(outside.messages, isEmpty);
      expect(outside.hasMore, isFalse);
      expect(outside.newestMessageId, initial.newestMessageId);
      expect(
        await api.chatroomHttp.batchMutateLlmMessages(
          worldId: world,
          locationId: location,
          conversationRoundId: target.conversationRoundId,
          operations: [
            ChatroomLlmMessageOperation.delete(
              globalMessageId: target.globalMessageId,
            ),
          ],
        ),
        isA<ChatroomMessageMutationResult>(),
      );
      final deleted = await api.chatroomHttp.getMessages(
        worldId: world,
        locationId: location,
        startConversationRoundId: target.conversationRoundId,
        endConversationRoundId: target.conversationRoundId,
      );
      expect(deleted.messages, isEmpty);
      expect(deleted.newestMessageId, 0);
      await expectLater(
        api.chatroomHttp.batchMutateLlmMessages(
          worldId: world,
          locationId: location,
          conversationRoundId: target.conversationRoundId,
          operations: [
            ChatroomLlmMessageOperation.edit(
              globalMessageId: target.globalMessageId,
              content: 'Late edit',
            ),
          ],
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 2013)),
      );
    },
  );

  test(
    'local mock batch validation is atomic and mixed deletion expands range',
    () async {
      const world = 'w_batch_atomic';
      const location = 'loc_batch_atomic';
      final api = GenesisApi(useMock: true);
      Future<void> seed(List<String> contents) async {
        await api.chatroomHttp.writeNarrator(
          worldId: world,
          tickId: 'tick',
          locationGroups: [
            ChatroomNarratorLocationGroup(
              locationId: location,
              locationName: '',
              locationSummary: '',
              characters: const [],
              initialDialogue: contents
                  .map(
                    (text) => ChatroomNarratorDialogueLine(
                      charId: 'nar',
                      charName: 'Narrator',
                      content: text,
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      }

      await seed(['one', 'two', 'three']);
      final initial = await api.chatroomHttp.getMessages(
        worldId: world,
        locationId: location,
      );
      final rows = initial.messages.reversed.toList();
      final round = rows.first.conversationRoundId;
      await seed(['later']);
      final before = await api.chatroomHttp.getMessages(
        worldId: world,
        locationId: location,
      );
      final later = before.messages.first;
      final client = ApiClient(
        baseUrl: 'https://mock.test/',
        transport: LocalMockGenesisTransport.instance,
      );
      final path =
          'aitown-chat/api/v1/worlds/$world/locations/$location/llm-messages/batch';
      final edit = {
        'action': 'edit',
        'global_message_id': rows[0].globalMessageId,
        'content': 'changed',
      };
      for (final (operations, code) in <(List<Object?>, int)>[
        ([], 1001),
        ([edit, edit], 1001),
        (
          [
            edit,
            {'action': 'invalid', 'global_message_id': rows[1].globalMessageId},
          ],
          1001,
        ),
        (
          [
            edit,
            {
              'action': 'edit',
              'global_message_id': rows[1].globalMessageId,
              'content': ' ',
            },
          ],
          1009,
        ),
        (
          [
            edit,
            {
              'action': 'delete',
              'global_message_id': rows[1].globalMessageId,
              'content': null,
            },
          ],
          1001,
        ),
        (
          [
            edit,
            {'action': 'delete', 'global_message_id': later.globalMessageId},
          ],
          2011,
        ),
        (
          [
            edit,
            {'action': 'delete', 'global_message_id': 9223372036854775000},
          ],
          2011,
        ),
      ]) {
        final response = await client.post<Map>(
          path,
          body: {'conversation_round_id': round, 'operations': operations},
        );
        expect(response['err_no'], code);
        final after = await api.chatroomHttp.getMessages(
          worldId: world,
          locationId: location,
        );
        expect(
          after.messages.map((m) => m.content),
          before.messages.map((m) => m.content),
        );
        expect(after.newestMessageId, before.newestMessageId);
      }
      final edited = await api.chatroomHttp.batchMutateLlmMessages(
        worldId: world,
        locationId: location,
        conversationRoundId: round,
        operations: [
          for (final row in rows)
            ChatroomLlmMessageOperation.edit(
              globalMessageId: row.globalMessageId,
              content: '  ${row.content} edited  ',
            ),
        ],
      );
      expect(edited.startConversationRoundId, round);
      expect(edited.endConversationRoundId, round);
      expect(edited.newestMessageId, before.newestMessageId);
      final mixed = await api.chatroomHttp.batchMutateLlmMessages(
        worldId: world,
        locationId: location,
        conversationRoundId: round,
        operations: [
          ChatroomLlmMessageOperation.delete(
            globalMessageId: rows[2].globalMessageId,
          ),
          ChatroomLlmMessageOperation.edit(
            globalMessageId: rows[0].globalMessageId,
            content: '  preserved  ',
          ),
          ChatroomLlmMessageOperation.delete(
            globalMessageId: rows[1].globalMessageId,
          ),
        ],
      );
      expect(mixed.startConversationRoundId, round);
      expect(mixed.endConversationRoundId, later.conversationRoundId);
      expect(mixed.newestMessageId, before.newestMessageId - 2);
      final after = await api.chatroomHttp.getMessages(
        worldId: world,
        locationId: location,
      );
      expect(after.messages.map((m) => m.globalMessageId), [
        later.globalMessageId,
        rows.first.globalMessageId,
      ]);
      expect(after.messages.last.content, '  preserved  ');
      await expectLater(
        client.request<Object?>(
          'PATCH',
          path.replaceFirst('/batch', '/${rows.first.globalMessageId}'),
          body: {'content': 'old route'},
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      await expectLater(
        client.delete<Object?>(
          path.replaceFirst('/batch', '/${rows.first.globalMessageId}'),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
    },
  );

  test(
    'local mock cards lookup is read only and does not simulate selection',
    () async {
      final api = GenesisApi(useMock: true);
      for (var i = 0; i < 2; i++) {
        final cards = await api.chatroomHttp.getLlmCards(
          worldId: 'w_cards_contract',
          locationId: 'l_cards_contract',
          conversationRoundId: 9007199254740993,
        );
        expect(cards.list, isEmpty);
        expect(cards.total, 0);
        expect(cards.conversationRoundId, 9007199254740993);
        expect(cards.originalCardId, 0);
      }
      await expectLater(
        api.chatroomHttp.batchMutateLlmCardMessages(
          worldId: 'w_cards_contract',
          locationId: 'l_cards_contract',
          conversationRoundId: 9007199254740993,
          cardId: 9007199254740994,
          operations: const [
            ChatroomLlmMessageOperation.delete(
              globalMessageId: 9007199254740995,
            ),
          ],
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 501)),
      );
      await expectLater(
        api.chatroomHttp.selectLlmCard(
          worldId: 'w_cards_contract',
          locationId: 'l_cards_contract',
          conversationRoundId: 9007199254740993,
          cardId: 9007199254740994,
          clientMsgId: 'selection',
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 501)),
      );
    },
  );

  test('local mock persists Gem model selection per world', () async {
    final api = GenesisApi(useMock: true);
    await api.loginWithGoogle(idToken: 'google-token');

    final initialUserInfo = await api.v1.user.info();
    final initial = await api.v1.gem.models(worldId: 'W_MODEL_TEST');
    final selected = await api.v1.gem.selectModel(
      worldId: 'W_MODEL_TEST',
      modelCode: 'sake_pro',
    );
    final refreshed = await api.v1.gem.models(worldId: 'W_MODEL_TEST');
    final refreshedUserInfo = await api.v1.user.info();

    expect(initial.groups.single.models.length, 4);
    expect(initialUserInfo['selected_model_code'], 'top_pick_v3');
    expect(initial.selectedModelCode, 'top_pick_v3');
    expect(selected.selectedModelCode, 'sake_pro');
    expect(refreshed.selectedModelCode, 'sake_pro');
    expect(refreshedUserInfo['selected_model_code'], 'sake_pro');
  });

  test('local mock app version check defaults to no upgrade', () async {
    final api = GenesisApi(useMock: true);

    final response = await api.v1.app.versionCheck(
      appId: 'aitown',
      platform: 'android',
      channel: 'default',
      versionCode: 1,
    );

    expect(response.needUpgrade, false);
    expect(response.forceUpgrade, false);
    expect(response.shouldForceUpgrade, false);
  });

  test('local mock app config returns global opening sheet flag', () async {
    final api = GenesisApi(useMock: true);

    final config = await api.v1.app.config();

    expect(config, {
      'show_opening_sheet': false,
      'api_trace_sampling_rate': 1.0,
    });
  });

  test(
    'local mock Origin feed advances cursor and deduplicates exposure',
    () async {
      final api = GenesisApi(useMock: true);

      final firstPage = await api.v1.origin.feed(startScore: 0, rn: 2);
      final firstItems = firstPage['list']! as List;
      final firstInfo = (firstItems.first as Map)['info']! as Map;
      final firstOriginId = '${firstInfo['origin_id']}';

      expect(firstItems, hasLength(2));
      expect(firstPage['next_score'], 2);
      expect(firstPage['has_more'], true);
      expect(await api.v1.origin.reportFeedExposure([firstOriginId]), 1);
      expect(await api.v1.origin.reportFeedExposure([firstOriginId]), 0);

      final filteredPage = await api.v1.origin.feed(startScore: 0, rn: 2);
      final filteredIds = (filteredPage['list']! as List)
          .map((item) => '${((item as Map)['info'] as Map)['origin_id']}')
          .toList(growable: false);
      expect(filteredIds, isNot(contains(firstOriginId)));
      expect(filteredPage['next_score'], 2);
    },
  );

  test('local mock exposes detail definition versions and map APIs', () async {
    final api = GenesisApi(useMock: true);

    final origins = await api.getOrigins(limit: 1);
    final originId = origins.data.single.oid;
    final origin = await api.getOrigin(originId);
    final originMap = await api.getOriginMap(
      originId: originId,
      locationId: 'root',
    );

    expect(origin.definitionVersion, 2);
    expect(originMap.isAvailable, true);
    expect(originMap.tileTypes, isNotEmpty);
    expect(originMap.tiles.single.type, 'mock_tile');
    expect(originMap.tiles.single.shadow, 0);
    expect(originMap.mapJson!.width, 1);
    expect(originMap.mapJson!.height, 1);
    expect(originMap.tiles.single.locationId, 'loc_hub');

    final worlds = await api.getMyWorlds(limit: 1);
    final worldId = worlds.single.wid;
    final world = await api.getWorld(worldId);
    final worldMap = await api.getWorldMap(
      worldId: worldId,
      locationId: 'loc_hub',
    );

    expect(world.definitionVersion, 2);
    expect(worldMap.isAvailable, true);
    expect(worldMap.tileTypes, isNotEmpty);
    expect(worldMap.tiles.single.type, 'mock_tile');
    expect(worldMap.tiles.single.shadow, 0);
    expect(worldMap.mapJson!.width, 1);
    expect(worldMap.mapJson!.height, 1);
    expect(worldMap.tiles.single.locationId, isNull);
  });

  test('local mock tracks preset character launch history', () async {
    final api = GenesisApi(useMock: true);
    final origins = await api.getOrigins(limit: 1);
    final originId = origins.data.single.oid;

    expect(await api.getMyLaunchPresetCharacters(originId, limit: 5), isEmpty);

    await api.v1.origin.launch(
      originId: originId,
      presetCharacterId: 'c_mock_iris',
    );
    final characters = await api.getMyLaunchPresetCharacters(
      originId,
      limit: 5,
    );

    expect(characters, hasLength(1));
    expect(characters.single.charId, 'c_mock_iris');
    expect(characters.single.type, 'ai');
    expect(characters.single.name, 'Iris Vale');
    expect(characters.single.initialLocationId, 'loc_hub');
    expect(characters.single.lastLaunchedAt, greaterThan(0));
    expect(characters.single.worldId, isNotEmpty);
    expect(characters.single.tickCount, greaterThanOrEqualTo(0));
    expect(characters.single.subTickNo, greaterThanOrEqualTo(0));
    expect(characters.single.messageCount, greaterThanOrEqualTo(0));
    expect(characters.single.currentTime, isNotEmpty);
    expect(characters.single.lastActiveAt, isNotEmpty);
  });

  test('local mock supports origin world and chat flow', () async {
    final api = GenesisApi(useMock: true);

    await api.loginWithGoogle(idToken: 'google-token');
    await api.bindDevice(did: 'device_mock_1');

    final search = await api.search(query: 'steam', limit: 20);
    expect(search.origins.isNotEmpty, true);

    final origins = await api.getOrigins(limit: 20, offset: 0);
    expect(origins.data.isNotEmpty, true);

    final firstOrigin = origins.data.first;
    final detail = await api.getOrigin(firstOrigin.oid);
    expect(detail.name.isNotEmpty, true);
    expect(detail.definitionVersion, 2);
    expect(detail.worldMap, kMockV1SteamMapImage);
    final originMap = await api.getOriginMap(
      originId: firstOrigin.oid,
      locationId: 'root',
    );
    expect(originMap.isAvailable, true);
    expect(originMap.tileTypes, isNotEmpty);
    expect(originMap.tiles.single.type, 'mock_tile');
    expect(detail.locationTree.map((node) => node.id), [
      originSyntheticRootLocationId,
    ]);
    expect(detail.locationTree.single.children.map((node) => node.id), [
      'loc_hub',
      'loc_gate',
      'loc_market',
      'loc_canal',
    ]);
    expect(
      detail.processedLocationTree.renderRoots.first.value.mapUrl,
      kMockV1LocationCentralHubMap,
    );
    expect(detail.processedLocationTree.renderRoots.map((node) => node.id), [
      'loc_hub',
      'loc_gate',
      'loc_market',
      'loc_canal',
    ]);
    final originRootsById = {
      for (final node in detail.processedLocationTree.renderRoots)
        node.id: node,
    };
    expect(originRootsById['loc_hub']!.children.map((node) => node.id), [
      'loc_clocktower',
      'loc_dispatch_hall',
      'loc_pressure_garden',
    ]);
    expect(originRootsById['loc_gate']!.children.map((node) => node.id), [
      'loc_airdock',
      'loc_switchyard',
      'loc_customs_house',
    ]);
    expect(originRootsById['loc_market']!.children.map((node) => node.id), [
      'loc_underworks',
      'loc_battery_exchange',
      'loc_parts_arcade',
    ]);
    expect(originRootsById['loc_canal']!.children.map((node) => node.id), [
      'loc_signal_workshop',
      'loc_pump_gallery',
      'loc_water_basin',
    ]);
    expect(
      detail.locationTree
          .expand((node) => node.children)
          .expand((node) => node.children)
          .map((node) => node.depth)
          .toSet(),
      {2},
    );
    for (final root in detail.processedLocationTree.renderRoots) {
      expect(root.children.length, inInclusiveRange(2, 3));
    }

    final world = await api.launchWorld(
      originId: firstOrigin.id,
      worldviewId: firstOrigin.oid,
      worldName: firstOrigin.name,
    );
    expect(world.wid.isNotEmpty, true);

    final worldDetail = await api.getWorld(world.wid);
    expect(worldDetail.definitionVersion, 2);
    expect(worldDetail.lastChatLocationId, 'loc_gate');
    expect(worldDetail.locations.isNotEmpty, true);
    final worldMap = await api.getWorldMap(
      worldId: world.wid,
      locationId: 'loc_hub',
    );
    expect(worldMap.isAvailable, true);
    expect(worldMap.tiles.single.type, 'mock_tile');
    expect(worldDetail.origin.worldMap, kMockV1SteamMapImage);
    expect(worldDetail.locationTree.map((node) => node.id), [
      worldSyntheticRootLocationId,
    ]);
    expect(worldDetail.locationTree.single.children.map((node) => node.id), [
      'loc_hub',
      'loc_gate',
      'loc_market',
      'loc_canal',
    ]);
    expect(
      worldDetail.processedLocationTree.renderRoots.first.value['map_url'],
      kMockV1LocationCentralHubMap,
    );
    expect(
      worldDetail.processedLocationTree.renderRoots.map((node) => node.id),
      ['loc_hub', 'loc_gate', 'loc_market', 'loc_canal'],
    );
    final worldRootsById = {
      for (final node in worldDetail.processedLocationTree.renderRoots)
        node.id: node,
    };
    expect(worldRootsById['loc_hub']!.children.map((node) => node.id), [
      'loc_clocktower',
      'loc_dispatch_hall',
      'loc_pressure_garden',
    ]);
    expect(worldRootsById['loc_gate']!.children.map((node) => node.id), [
      'loc_airdock',
      'loc_switchyard',
      'loc_customs_house',
    ]);
    expect(worldRootsById['loc_market']!.children.map((node) => node.id), [
      'loc_underworks',
      'loc_battery_exchange',
      'loc_parts_arcade',
    ]);
    expect(worldRootsById['loc_canal']!.children.map((node) => node.id), [
      'loc_signal_workshop',
      'loc_pump_gallery',
      'loc_water_basin',
    ]);
    expect(
      worldDetail.locationTree
          .expand((node) => node.children)
          .expand((node) => node.children)
          .map((node) => node.depth)
          .toSet(),
      {2},
    );
    for (final root in worldDetail.processedLocationTree.renderRoots) {
      expect(root.children.length, inInclusiveRange(2, 3));
    }

    final before = await api.getLocationMessages(
      wid: world.wid,
      pointId: 'pt_hub',
      locationId: 'loc_hub',
      limit: 50,
      offset: 0,
    );

    await api.sendMessage(
      wid: world.wid,
      pointId: 'pt_hub',
      locationId: 'loc_hub',
      content: 'hello from mock',
    );

    final after = await api.getLocationMessages(
      wid: world.wid,
      pointId: 'pt_hub',
      locationId: 'loc_hub',
      limit: 50,
      offset: 0,
    );

    expect(after.data.length >= before.data.length, true);
    expect(after.data.first.content.isNotEmpty, true);
  });

  test('local mock supports v1 debug API surface', () async {
    final api = GenesisApi(useMock: true);
    await api.loginWithGoogle(idToken: 'google-token');

    final user = await api.v1.user.info();
    expect((user['user'] as Map)['uid'], 'u_mock_001');
    expect(user['uuid'], '4b74ec68-7abc-4cce-a223-e997e31dc811');
    final peer = await api.v1.user.info(uid: 'u_mock_peer');
    expect((peer['user'] as Map)['uid'], 'u_mock_peer');
    expect(peer.containsKey('uuid'), isFalse);
    final dmPeer = await api.v1.user.info(uid: 'u_mock_dm_002');
    expect((dmPeer['user'] as Map)['uid'], 'u_mock_dm_002');
    expect((dmPeer['user'] as Map)['name'], 'DM Contact 2');
    await api.v1.user.googleAuth(idToken: 'google-token');
    await api.v1.user.appleAuth(idToken: 'apple-token', fullName: 'Mock User');
    await api.v1.user.update(name: 'Mock User');
    await api.v1.user.profile(uid: 'u_mock_peer');
    await api.v1.user.origins(uid: 'u_mock_001');
    await api.v1.user.worlds(uid: 'u_mock_001');
    await api.v1.user.deleteAccount();

    final hotTags = await api.v1.origin.hotTags();
    expect(hotTags, containsAll(<String>['校园', '恋爱', '玄幻', '都市', '冒险']));

    final popularOrigins = await api.v1.origin.list(pn: 1, rn: 10);
    final firstPopularOrigin = (popularOrigins['list'] as List).first as Map;
    expect(firstPopularOrigin['discusses'], isA<List>());
    expect(firstPopularOrigin['discusses'], hasLength(2));
    final firstPopularOriginInfo = firstPopularOrigin['info'] as Map;
    expect(firstPopularOriginInfo['definition_version'], 2);
    expect(firstPopularOriginInfo['default_map_location_id'], 'root');

    final originFeed = await api.v1.origin.feed(startScore: 0, rn: 10);
    final firstOriginFeedItem = (originFeed['list'] as List).first as Map;
    final firstOriginFeedInfo = firstOriginFeedItem['info'] as Map;
    expect(firstOriginFeedInfo['definition_version'], 2);
    expect(firstOriginFeedInfo['default_map_location_id'], 'root');

    final uidOrigins = await api.v1.origin.list(
      scene: 'uid',
      uid: 'u_mock_001',
      pn: 1,
      rn: 10,
    );
    final firstUidOrigin = (uidOrigins['list'] as List).first as Map;
    expect(firstUidOrigin.containsKey('discusses'), isFalse);

    final home = await api.v1.home.home();
    expect(((home['my_world'] as Map)['list'] as List).isNotEmpty, true);
    await api.v1.home.following(pn: 2, rn: 10);

    final gemWallet = await api.v1.gem.wallet();
    expect(gemWallet.balanceCent, 43000);
    final gemProducts = await api.v1.gem.products();
    expect(gemProducts.products.first.googlePurchaseOptionId, '500-gems-new');
    expect(gemProducts.products.first.googleOfferId, '500-gems-new-discount');
    final gemReport = await api.v1.gem.reportPurchase(
      const GemPurchaseReportRequest(
        provider: 'google',
        productId: 'gem_pack_500',
        storeProductId: 'worldo_gems_500',
        transactionId: 'GPA.mock.1',
        purchaseToken: 'mock-purchase-token-1',
      ),
    );
    expect(gemReport.status, GemPurchaseReportStatus.completed);
    expect(gemReport.grantedGemsCent, 55000);
    expect(gemReport.transactionId, 'GPA.mock.1');

    final gemDuplicate = await api.v1.gem.reportPurchase(
      const GemPurchaseReportRequest(
        provider: 'google',
        productId: 'gem_pack_500',
        storeProductId: 'worldo_gems_500',
        transactionId: 'GPA.mock.1',
        purchaseToken: 'mock-purchase-token-1',
      ),
    );
    expect(gemDuplicate.status, GemPurchaseReportStatus.completed);
    expect(gemDuplicate.grantedGemsCent, 55000);
    expect(gemDuplicate.transactionId, 'GPA.mock.1');

    final dailyCheckin = await api.v1.gem.reportTask('daily_checkin');
    expect(dailyCheckin.status, 'claimed');
    expect((await api.v1.gem.wallet()).balanceCent, 100000);

    final discordReport = await api.v1.gem.reportTask('discord_follow');
    expect(discordReport.status, 'claimable');
    final discordClaim = await api.v1.gem.claimTask('discord_follow');
    expect(discordClaim.status, 'claimed');
    expect((await api.v1.gem.wallet()).balanceCent, 102000);

    final refreshedGemTasks = await api.v1.gem.tasks();
    final tasks = refreshedGemTasks.groups
        .expand((group) => group.tasks)
        .toList(growable: false);
    expect(
      tasks.singleWhere((task) => task.taskCode == 'daily_checkin').status,
      'claimed',
    );
    expect(
      tasks.singleWhere((task) => task.taskCode == 'discord_follow').status,
      'claimed',
    );

    final spentRecords = await api.v1.gem.records(
      scene: 'spent',
      pn: 1,
      rn: 10,
    );
    expect(spentRecords.items, isNotEmpty);
    expect(spentRecords.items.every((record) => record.amountCent < 0), isTrue);

    final origins = await api.v1.origin.list(scene: 'foryou', pn: 1, rn: 10);
    expect(origins['total'], greaterThanOrEqualTo(100));
    expect((origins['list'] as List), hasLength(10));
    final firstOriginStats =
        (((origins['list'] as List).first as Map)['stats'] as Map);
    expect(firstOriginStats['copy_cnt'], greaterThanOrEqualTo(1000));
    expect(firstOriginStats['connect_cnt'], greaterThanOrEqualTo(1000000));
    final firstOriginName =
        ((((origins['list'] as List)[0] as Map)['info'] as Map)['origin_name']);
    final secondOriginName =
        ((((origins['list'] as List)[1] as Map)['info'] as Map)['origin_name']);
    final secondOriginId =
        ((((origins['list'] as List)[1] as Map)['info'] as Map)['origin_id'])
            as String;
    expect(firstOriginName, isNot(secondOriginName));
    final laterOrigins = await api.v1.origin.list(pn: 2, rn: 10);
    final laterOrigin =
        (((laterOrigins['list'] as List).last as Map)['info'] as Map);
    final laterOriginId = laterOrigin['origin_id'] as String;
    final laterOriginDiscussions = await api.v1.discuss.list(
      bizId: laterOriginId,
      rn: 2,
    );
    final laterDiscussionItems = laterOriginDiscussions['list'] as List;
    expect(laterDiscussionItems, hasLength(2));
    expect(
      ((laterDiscussionItems.first as Map)['comment'] as Map)['biz_id'],
      laterOriginId,
    );
    expect(
      ((laterDiscussionItems.first as Map)['comment'] as Map)['world_id'],
      isNotEmpty,
    );
    expect(
      ((laterDiscussionItems.first as Map)['latest_replies'] as List),
      isNotEmpty,
    );

    final origin =
        (((origins['list'] as List).first as Map)['info'] as Map)['origin_id']
            as String;
    await expectLater(
      api.v1.origin.detail(originId: 'o_missing'),
      throwsA(isA<ApiException>().having((error) => error.code, 'code', 20101)),
    );
    final detail = await api.v1.origin.detail(oid: origin);
    final secondDetail = await api.v1.origin.detail(originId: secondOriginId);
    expect(detail, isNot(contains('show_opening_sheet')));
    expect(secondDetail, isNot(contains('show_opening_sheet')));
    final detailInfo = detail['info'] as Map;
    expect(detailInfo['origin_id'], origin);
    expect(detailInfo['metric'], isA<Map>());
    expect(detailInfo['created_at'], isA<int>());
    expect(detailInfo['language'], isNotEmpty);
    expect(detailInfo['current_time'], isNotEmpty);
    expect(detailInfo['owner_user'], isA<Map>());
    expect(((detail['stats'] as Map)['copy_cnt']), greaterThanOrEqualTo(1000));
    expect(detail['init_location_group'], isNull);
    final detailCharacter = (detail['characters'] as List).first as Map;
    expect(detailCharacter['type'], 'ai');
    expect(detailCharacter['player_uid'], isEmpty);
    expect(detailCharacter['player_user'], isA<Map>());
    expect(detailCharacter['player_joined_at'], 0);
    expect(detailCharacter['is_recommend'], 1);
    expect(
      detailInfo,
      allOf(
        isNot(contains('setting')),
        isNot(contains('events')),
        isNot(contains('started_at')),
        isNot(contains('tick_duration_days')),
      ),
    );
    expect(
      ((detail['locations'] as List).first as Map),
      allOf(
        isNot(contains('location_description')),
        containsPair('x', isA<double>()),
        containsPair('y', isA<double>()),
      ),
    );
    final detailTick = (detail['ticks'] as List).first as Map;
    expect(detailTick, contains('tick_result'));
    expect(detailTick['sub_tick_no'], 1);
    final detailTickResult = detailTick['tick_result'] as Map;
    expect(detailTickResult['current_time'], isNotEmpty);
    expect(detailTickResult, isNot(contains('location_groups')));
    final detailParagraph =
        (detailTickResult['paragraphs'] as List).first as Map;
    expect(detailParagraph['visibility'], anyOf('public', 'char_only'));
    expect(detailParagraph['visible_to'], isA<List>());
    expect(detailParagraph['clue'], isA<String>());
    expect(detailParagraph['character_deltas'], isEmpty);
    final edit = await api.v2.origin.forEdit(originId: origin);
    expect((edit['info'] as Map)['origin_id'], origin);
    expect(edit, contains('characters'));
    expect(edit, contains('stats'));
    expect(edit, contains('ticks'));
    expect((edit['info'] as Map), isNot(contains('setting')));
    expect((edit['info'] as Map), isNot(contains('events')));
    final created = await api.v1.origin.create(
      originName: 'Created Mock Origin',
      brief: 'Created from a local mock test.',
      setting: 'Created from a local mock test.',
      cover: '',
      characters: const [],
    );
    final createdOrigin = (created['info'] as Map)['origin_id'] as String;
    await api.v1.origin.update(
      originId: createdOrigin,
      originName: 'Updated Mock Origin',
      cover: '',
      characters: const [],
    );
    final createdV2 = await api.v2.origin.create(
      originName: 'Created V2 Mock Origin',
      events: const ['The old event remains.'],
      characters: const [
        {
          'char_id': 'char_v2_recommended',
          'name': 'Recommended Guide',
          'is_recommend': 1,
        },
      ],
      locations: const [],
      initLocationGroup: const {
        'location_id': 'loc_1_1_1',
        'initial_dialogue': [
          {'char_id': 'nar', 'content': 'A new map appears.'},
          {
            'char_id': 'nar_pic',
            'content': 'https://cdn.example.com/opening.webp',
          },
        ],
      },
    );
    final createdV2Origin = createdV2['origin_id'] as String;
    expect(createdV2.keys.toSet(), {
      'origin_id',
      'origin_version',
      'origin_version_time',
      'origin_name',
    });
    final createdV2ForEdit = await api.v2.origin.forEdit(
      originId: createdV2Origin,
    );
    expect((createdV2ForEdit['info'] as Map)['definition_version'], 2);
    expect(
      ((createdV2ForEdit['characters'] as List).single as Map)['is_recommend'],
      1,
    );
    expect(createdV2ForEdit, isNot(contains('tile_types')));
    expect(createdV2ForEdit['init_location_group'], {
      'location_id': 'loc_1_1_1',
      'initial_dialogue': [
        {
          'char_id': 'nar',
          'char_name': 'Narrator',
          'content': 'A new map appears.',
        },
        {
          'char_id': 'nar_pic',
          'char_name': 'Narrator',
          'content': 'https://cdn.example.com/opening.webp',
        },
      ],
    });
    final createdV2Detail = await api.v1.origin.detail(
      originId: createdV2Origin,
    );
    expect(createdV2Detail['init_location_group'], {
      'location_id': 'loc_1_1_1',
      'initial_dialogue': [
        {
          'char_id': 'nar',
          'char_name': 'Narrator',
          'content': 'A new map appears.',
        },
        {
          'char_id': 'nar_pic',
          'char_name': 'Narrator',
          'content': 'https://cdn.example.com/opening.webp',
        },
      ],
    });
    final createdV2Ticks = createdV2Detail['ticks'] as List;
    final createdV2TickResult =
        (createdV2Ticks.first as Map)['tick_result'] as Map;
    expect(createdV2TickResult, isNot(contains('location_groups')));
    final updatedV2 = await api.v2.origin.update(
      originId: createdV2Origin,
      originName: 'Updated V2 Mock Origin',
      events: const [],
      characters: const [
        {
          'char_id': 'char_v2_recommended',
          'name': 'Recommended Guide',
          'is_recommend': 0,
        },
      ],
      locations: const [],
    );
    expect(updatedV2['origin_id'], createdV2Origin);
    expect(updatedV2['origin_version'], '2');
    final v2Detail = await api.v1.origin.detail(originId: createdV2Origin);
    expect((v2Detail['info'] as Map)['definition_version'], 2);
    expect((v2Detail['info'] as Map)['status'], 20);
    expect(v2Detail['init_location_group'], isNull);
    final firstV2Info = await api.v1.origin.info(originId: createdV2Origin);
    final secondV2Info = await api.v1.origin.info(originId: createdV2Origin);
    expect((firstV2Info['info'] as Map)['status'], 20);
    expect((secondV2Info['info'] as Map)['status'], 10);
    final updatedV2ForEdit = await api.v2.origin.forEdit(
      originId: createdV2Origin,
    );
    expect((updatedV2ForEdit['info'] as Map), isNot(contains('events')));
    expect(
      ((updatedV2ForEdit['characters'] as List).single as Map)['is_recommend'],
      0,
    );
    expect(updatedV2ForEdit['init_location_group'], isNull);
    await api.v1.origin.launch(
      oid: createdOrigin,
      presetCharacterId: 'char_mock_001',
    );
    await api.v1.origin.versionList(oid: createdOrigin);
    await api.v1.origin.publish(oid: createdOrigin, updateNotes: 'publish');

    final worlds = await api.v1.world.list(scene: 'popular', pn: 1, rn: 10);
    expect(worlds['total'], greaterThanOrEqualTo(100));
    expect((worlds['list'] as List), hasLength(10));
    final firstWorldStats =
        (((worlds['list'] as List).first as Map)['stats'] as Map);
    final firstWorldInfo =
        (((worlds['list'] as List).first as Map)['info'] as Map);
    expect(firstWorldStats['tick_cnt'], greaterThanOrEqualTo(1000));
    expect(firstWorldStats['connect_cnt'], greaterThanOrEqualTo(1000));
    expect(firstWorldInfo['last_active_at'], isA<int>());
    expect(firstWorldInfo['last_active_at'], greaterThan(0));
    expect(firstWorldInfo['definition_version'], 2);
    expect(firstWorldInfo['default_map_location_id'], 'root');
    final myWorlds = await api.v1.world.list(
      scene: 'uid',
      uid: 'u_mock_001',
      pn: 1,
      rn: 10,
    );
    expect(myWorlds['total'], greaterThan(0));
    for (final item in myWorlds['list'] as List) {
      expect(((item as Map)['info'] as Map)['owner_uid'], 'u_mock_001');
    }
    final originId =
        (((myWorlds['list'] as List).first as Map)['info'] as Map)['origin_id']
            as String;
    final originWorlds = await api.v1.world.list(
      scene: 'uid',
      uid: 'u_mock_001',
      originId: originId,
      pn: 1,
      rn: 10,
    );
    expect((originWorlds['list'] as List), isNotEmpty);
    for (final item in originWorlds['list'] as List) {
      expect(((item as Map)['info'] as Map)['origin_id'], originId);
    }
    final firstWorldName =
        ((((worlds['list'] as List)[0] as Map)['info'] as Map)['world_name']);
    final secondWorldName =
        ((((worlds['list'] as List)[1] as Map)['info'] as Map)['world_name']);
    expect(firstWorldName, isNot(secondWorldName));
    final world =
        (((worlds['list'] as List).first as Map)['info'] as Map)['world_id']
            as String;
    expect(
      (((worlds['list'] as List).first as Map)['info'] as Map).containsKey(
        'last_chat_location_id',
      ),
      isFalse,
    );
    final worldDetail = await api.v1.world.detail(worldId: world);
    expect(((worldDetail['info'] as Map)['last_chat_location_id']), 'loc_gate');
    final worldInfo = await api.v1.world.info(worldId: world);
    expect(
      (worldInfo['info'] as Map).containsKey('last_chat_location_id'),
      isFalse,
    );
    expect(
      ((worldDetail['stats'] as Map)['tick_cnt']),
      greaterThanOrEqualTo(1000),
    );
    final worldOrigin = ((worldDetail['info'] as Map)['origin_id']) as String;
    final summaryByOrigin = await api.v1.world.summaryLatest(
      originId: worldOrigin,
    );
    final summaryItems = summaryByOrigin['list'] as List;
    expect(summaryItems, isNotEmpty);
    expect(summaryItems.length, lessThanOrEqualTo(5));
    final summaryItem = summaryItems.first as Map;
    expect(summaryItem['origin_id'], worldOrigin);
    expect(summaryItem['world_id'], isNotEmpty);
    expect(summaryItem['summary'], isNotEmpty);
    expect(summaryItem['tick_no'], isA<int>());
    expect(summaryItem['tick_time'], isA<int>());
    expect(summaryItem['created_at'], isA<int>());
    final summaryByWorld = await api.v1.world.summaryLatest(worldId: world);
    for (final item in summaryByWorld['list'] as List) {
      expect((item as Map)['world_id'], isNot(world));
    }
    final facadeSummaries = await api.getLatestWorldSummaries(
      originId: worldOrigin,
    );
    expect(facadeSummaries.first.originId, worldOrigin);
    expect(facadeSummaries.first.summary, isNotEmpty);
    final originProgress = await api.v1.world.originProgress(
      uid: 'u_mock_001',
      originId: worldOrigin,
    );
    expect(originProgress['world_id'], isNotEmpty);
    expect(originProgress['tick_cnt'], greaterThanOrEqualTo(1000));
    final missingOriginProgress = await api.v1.world.originProgress(
      uid: 'u_missing',
      originId: worldOrigin,
    );
    expect(missingOriginProgress, {'world_id': '', 'tick_cnt': 0});
    final detailTicks = worldDetail['ticks'] as List;
    expect(detailTicks.length, greaterThanOrEqualTo(4));
    final detailLocations = worldDetail['locations'] as List;
    final firstDetailLocation = detailLocations.first as Map;
    expect(firstDetailLocation['map_url'], kMockV1LocationCentralHubMap);
    expect(firstDetailLocation.containsKey('map'), isFalse);
    expect([
      for (final tick in detailTicks) ((tick as Map)['tick_no'] as num).toInt(),
    ], List<int>.generate(detailTicks.length, (index) => index + 1));
    final tickList = await api.v1.world.tickList(worldId: world, pn: 1, rn: 2);
    expect(tickList['total'], detailTicks.length);
    expect(tickList['pn'], 1);
    expect(tickList['rn'], 2);
    final tickListItems = tickList['list'] as List;
    expect(tickListItems, hasLength(2));
    expect(
      tickListItems.every((tick) => (tick as Map)['status'] == 50),
      isTrue,
    );
    expect(
      [
        for (final tick in tickListItems)
          ((tick as Map)['tick_no'] as num).toInt(),
      ],
      [4, 3],
    );
    expect(
      ((tickListItems.first as Map)['tick_result'] as Map)['narrator'],
      isNotEmpty,
    );
    final firstTick = tickListItems.first as Map;
    expect(firstTick['sub_tick_no'], 1);
    final firstTickResult = firstTick['tick_result'] as Map;
    expect(firstTickResult['current_time'], isNotEmpty);
    final firstParagraph = (firstTickResult['paragraphs'] as List).first as Map;
    expect(firstParagraph['visibility'], 'public');
    expect(firstParagraph['visible_to'], isEmpty);
    expect(firstParagraph['clue'], isA<String>());
    expect(
      ((firstParagraph['character_deltas'] as List).first as Map)['delta'],
      isA<int>(),
    );
    await expectLater(
      api.v1.world.tickList(worldId: 'w_missing_tick_list'),
      throwsA(isA<ApiException>().having((error) => error.code, 'code', 20201)),
    );
    final apply = await api.v1.world.apply(worldId: world, message: '想加入这个世界');
    expect(apply['status'], 10);
    final applyId = apply['apply_id'] as String;
    final applyList = await api.v1.world.applyList(
      worldId: world,
      status: 10,
      pn: 1,
      rn: 20,
    );
    expect(applyList['total'], 1);
    expect(((applyList['list'] as List).single as Map)['apply_id'], applyId);
    final review = await api.v1.world.reviewApply(
      applyId: applyId,
      action: 'approve',
      reviewMsg: 'Welcome',
    );
    expect(review['status'], 20);
    final join = await api.v1.world.join(
      worldId: world,
      presetCharacterId: 'char_1',
    );
    expect(join, containsPair('world_id', world));
    expect(join, containsPair('char_id', 'char_1'));
    await api.v1.world.tick(worldId: world);
    await api.v1.world.syncLatestOrigin(wid: world);

    final worldMessages = await api.chatroomHttp.getWorldMessages(
      worldId: world,
    );
    expect(worldMessages.locations, isNotEmpty);
    final userLocations = await api.chatroomHttp.getUserLocations(
      worldId: world,
    );
    expect(userLocations.worldId, world);
    expect(userLocations.locations, isNotEmpty);
    final firstLocationUser = userLocations.locations.first.users.first;
    expect(firstLocationUser.userId, isNotEmpty);
    expect(firstLocationUser.userName, isNotEmpty);
    final history = await api.chatroomHttp.getMessages(
      worldId: world,
      locationId: worldMessages.locations.first.locationId,
      since: 0,
      limit: 20,
    );
    expect(history.messages, isNotEmpty);
    final historyMessage = history.messages.first;
    expect(historyMessage.globalMessageId, greaterThan(0));
    expect(historyMessage.messageId, greaterThan(0));
    expect(historyMessage.locationMessageId, greaterThan(0));
    expect(historyMessage.createdAt, isNotNull);
    var lockStatus = await api.chatroomHttp.tickLockStatus(worldId: world);
    expect(lockStatus.isLocked, false);
    expect(await api.chatroomHttp.lockWorld(worldId: world), true);
    lockStatus = await api.chatroomHttp.tickLockStatus(worldId: world);
    expect(lockStatus.isLocked, true);
    var tickProgress = await api.chatroomHttp.tickProgress(worldId: world);
    expect(tickProgress.progress, 0);
    expect(await api.chatroomHttp.unlockWorld(worldId: world), true);
    lockStatus = await api.chatroomHttp.tickLockStatus(worldId: world);
    expect(lockStatus.isLocked, false);
    tickProgress = await api.chatroomHttp.tickProgress(worldId: world);
    expect(tickProgress.progress, 1);
    final narratorMessageId = await api.chatroomHttp.writeNarrator(
      worldId: world,
      tickId: 'tick_mock_001',
      locationGroups: const [
        ChatroomNarratorLocationGroup(
          locationId: 'loc_hub',
          locationName: 'Central Hub',
          locationSummary: 'The hub quiets down.',
          characters: [
            ChatroomNarratorCharacter(charId: 'c_mock_iris', name: 'Iris Vale'),
          ],
          initialDialogue: [
            ChatroomNarratorDialogueLine(
              charId: 'c_mock_iris',
              charName: 'Iris Vale',
              content: 'The gears settle into a slower rhythm.',
            ),
          ],
        ),
      ],
    );
    expect(narratorMessageId, greaterThan(0));

    var unreadSummary = await api.v1.messages.unreadSummary();
    expect(unreadSummary.systemUnread, greaterThanOrEqualTo(1));
    final systemMessages = await api.v1.messages.notifications(
      block: 'world_apply',
      pn: 1,
      rn: 20,
    );
    final systemItems = systemMessages['list'] as List;
    expect(systemMessages['total'], systemItems.length);
    expect(systemItems, isNotEmpty);
    expect(
      systemItems.every(
        (item) => (item as Map)['notice_block'] == 'world_apply',
      ),
      isTrue,
    );
    final followerMessages = await api.v1.messages.notifications(
      block: 'follow',
      pn: 1,
      rn: 20,
    );
    expect(
      ((followerMessages['list'] as List).single as Map)['notice_block'],
      'follow',
    );
    final commentMessages = await api.v1.messages.notifications(
      block: 'interaction',
      pn: 1,
      rn: 20,
    );
    expect(
      ((commentMessages['list'] as List).single as Map)['notice_block'],
      'interaction',
    );
    expect(
      ((commentMessages['list'] as List).single as Map)['origin_name'],
      'Steam Kingdom',
    );
    await api.v1.messages.markNotificationsRead(block: 'world_apply');
    unreadSummary = await api.v1.messages.unreadSummary();
    expect(unreadSummary.systemUnread, 0);
    expect(unreadSummary.followerUnread, 1);
    expect(unreadSummary.commentUnread, 1);
    await api.v1.messages.followers(pn: 2, rn: 10);

    await api.v1.follow.follow(uid: 'u_mock_peer');
    await api.v1.follow.unfollow(uid: 'u_mock_peer');
    final following = await api.v1.follow.following(
      uid: 'u_mock_001',
      pn: 1,
      rn: 10,
    );
    final followingList = following['list'] as List;
    expect(following['total'], greaterThan(10));
    expect(followingList, hasLength(10));
    expect((followingList.first as Map)['user'], isA<Map>());

    final followers = await api.v1.follow.followers(
      uid: 'u_mock_001',
      pn: 1,
      rn: 10,
    );
    final followersList = followers['list'] as List;
    expect(followers['total'], greaterThan(10));
    expect(followersList, hasLength(10));
    expect((followersList.first as Map)['relation'], isA<Map>());
    await api.v1.follow.relations(type: 'followers', pn: 1, rn: 10);
    await api.v1.follow.status(uids: const ['u_mock_peer']);

    final dm = await api.v1.dm.send(
      peerUid: 'u_mock_peer',
      content: 'hello v1 mock',
    );
    expect(((dm['message'] as Map)['content']), 'hello v1 mock');
    final conversations = await api.v1.dm.conversations(pn: 1, rn: 10);
    expect(conversations['total'], greaterThan(20));
    final firstConversation = (conversations['list'] as List).first as Map;
    expect(firstConversation, contains('conv_id'));
    expect(firstConversation, contains('last_message_id'));
    expect(firstConversation['last_message_at'], isA<int>());
    final firstConversationPeer = firstConversation['peer'] as Map;
    expect(firstConversationPeer['last_login_at'], isA<int>());
    expect(firstConversationPeer['create_at'], isA<int>());
    expect(conversations['next_after_message_id'], isA<String>());
    final deltaConversations = await api.v1.dm.conversations(
      afterMessageId: '${conversations['next_after_message_id']}',
    );
    final deltaList = deltaConversations['list'] as List;
    expect(deltaList, isNotEmpty);
    expect(
      deltaConversations['next_after_message_id'],
      isNot(conversations['next_after_message_id']),
    );
    final defaultConversations = await api.v1.dm.conversations();
    expect(defaultConversations['rn'], 20);
    expect(defaultConversations['list'], hasLength(20));
    final cappedConversations = await api.v1.dm.conversations(pn: 1, rn: 500);
    expect(cappedConversations['rn'], 100);
    final secondPageConversations = await api.v1.dm.conversations(
      pn: 2,
      rn: 10,
    );
    expect(secondPageConversations['list'], isNotEmpty);
    final directMessages = await api.v1.dm.list(
      peerUid: 'u_mock_peer',
      pn: 1,
      rn: 20,
    );
    final firstMessage = (directMessages['list'] as List).first as Map;
    expect(firstMessage['created_at'], isA<int>());
    final otherPeerMessages = await api.v1.dm.list(
      peerUid: 'u_mock_dm_002',
      pn: 1,
      rn: 5,
    );
    expect(otherPeerMessages['list'], hasLength(1));
    expect(
      ((otherPeerMessages['list'] as List).first as Map)['sender_uid'],
      isNotEmpty,
    );
    final twoMessagePeerMessages = await api.v1.dm.list(
      peerUid: 'u_mock_dm_003',
      pn: 1,
      rn: 5,
    );
    expect(twoMessagePeerMessages['list'], hasLength(2));
    expect(
      ((twoMessagePeerMessages['list'] as List).first as Map)['content'],
      'Second short mock reply.',
    );
    final shortConversation = (defaultConversations['list'] as List)
        .cast<Map>()
        .firstWhere(
          (item) => ((item['peer'] as Map)['uid']) == 'u_mock_dm_002',
        );
    expect(
      shortConversation['last_message'],
      'One-message mock chat with DM Contact 2.',
    );
    var dmUnread = await api.v1.dm.unread();
    expect(dmUnread['unread_cnt'], greaterThanOrEqualTo(0));
    await api.v1.dm.markRead(peerUid: 'u_mock_peer');
    dmUnread = await api.v1.dm.unread();
    expect(dmUnread['unread_cnt'], 0);
    await api.v1.dm.block(targetUid: 'u_mock_peer');
    var blocks = await api.v1.dm.blocks(pn: 1, rn: 20);
    expect((blocks['list'] as List).single, containsPair('uid', 'u_mock_peer'));
    await api.v1.dm.unblock(targetUid: 'u_mock_peer');
    blocks = await api.v1.dm.blocks(pn: 1, rn: 20);
    expect(blocks['list'], isEmpty);

    final newPost = await api.v1.discuss.post(
      bizId: createdOrigin,
      content: 'mock post',
    );
    final postId = newPost['discuss_id'] as String;
    await api.v1.discuss.post(
      bizId: createdOrigin,
      content: 'mock reply',
      rootDiscussId: postId,
    );
    final discussions = await api.v1.discuss.list(bizId: createdOrigin);
    final discussionItems = discussions['list'] as List;
    expect(discussionItems.length, 1);
    final firstDiscussion = discussionItems.first as Map;
    expect((firstDiscussion['comment'] as Map)['discuss_id'], postId);
    expect((firstDiscussion['latest_replies'] as List).length, 1);
    expect(discussions['top_total'], 1);
    expect(discussions['total_all'], 2);
    final replies = await api.v1.discuss.replies(
      rootDiscussId: postId,
      pn: 1,
      rn: 20,
    );
    final replyItems = replies['list'] as List;
    expect(replyItems.length, 1);
    expect((replyItems.first as Map)['root_discuss_id'], postId);
    expect(replies['total'], 1);
    expect(replies['pn'], 1);
    expect(replies['rn'], 20);
    await api.v1.discuss.like(discussId: postId);
    await api.v1.discuss.unlike(discussId: postId);
    await api.v1.discuss.delete(discussId: postId);
    final report = await api.v1.report.create(
      targetType: 'origin',
      targetId: createdOrigin,
      content: '内容疑似违规',
    );
    expect(report['report_id'], startsWith('rpt_mock_'));
    final feedback = await api.v1.feedback.create(content: '希望增加夜间模式');
    expect(feedback['feedback_id'], startsWith('fbk_mock_'));

    final search = await api.v1.search.search(query: 'steam');
    expect(search.origins.items, isNotEmpty);
    expect(search.origins.items.first.originVersion, isNotEmpty);
    expect(
      search.origins.items.first.matches.whereType<SearchV2TagMatch>(),
      isNotEmpty,
    );
    expect(search.worlds.items.first.tags, isNotEmpty);
    expect(
      search.worlds.items.first.matches.whereType<SearchV2TagMatch>(),
      isNotEmpty,
    );
    await api.v1.search.suggest(query: 'steam', limit: 10);

    final rebornSearch = await api.v1.search.search(query: '重生', pn: 1, rn: 20);
    expect(rebornSearch.origins.total, greaterThan(0));
    expect(rebornSearch.origins.items, isNotEmpty);
    expect(rebornSearch.worlds.total, greaterThan(0));
    expect(rebornSearch.worlds.items, isNotEmpty);
    final rebornWorldStats = rebornSearch.worlds.items.first.stats;
    expect(rebornWorldStats.tickCount, greaterThan(0));
    expect(rebornWorldStats.connectCount, greaterThan(0));
    expect(rebornWorldStats.characterCount, greaterThan(0));
    expect(rebornWorldStats.playerCount, greaterThan(0));

    final userSearch = await api.v1.search.search(
      query: '老肖',
      type: 'user',
      pn: 1,
      rn: 20,
    );
    expect(userSearch.users.total, greaterThan(0));
    expect(userSearch.users.items, isNotEmpty);

    final searchAllPage1 = await api.v1.search.search(query: '', pn: 1, rn: 20);
    for (final group in [
      (
        total: searchAllPage1.origins.total,
        count: searchAllPage1.origins.items.length,
      ),
      (
        total: searchAllPage1.worlds.total,
        count: searchAllPage1.worlds.items.length,
      ),
      (
        total: searchAllPage1.users.total,
        count: searchAllPage1.users.items.length,
      ),
    ]) {
      expect(group.total, greaterThanOrEqualTo(50));
      expect(group.count, 20);
    }
    final searchUserPage2 = await api.v1.search.search(
      query: '',
      type: 'user',
      pn: 2,
      rn: 20,
    );
    expect(searchUserPage2.users.total, greaterThanOrEqualTo(50));
    expect(searchUserPage2.users.items, hasLength(20));
    expect(searchUserPage2.origins.total, 0);
    expect(searchUserPage2.origins.items, isEmpty);

    final upload = await api.v1.common.uploadFile(
      bytes: const [1, 2, 3],
      bizType: 'avatar',
    );
    expect(upload['file_url'], isNotEmpty);
    final imageUpload = await api.v1.upload.image(
      bytes: const [255, 216, 255, 224],
      filename: 'avatar.jpg',
      contentType: 'image/jpeg',
    );
    expect(imageUpload['sm_url'], startsWith('https://mock.local/uploads/'));
    expect(imageUpload['xl_url'], startsWith('https://mock.local/uploads/'));
    expect(imageUpload['object_key'], startsWith('uploads/'));
    final draft = await api.v1.common.saveDraft(
      draftType: 'origin_create',
      draftData: const {'name': 'draft'},
    );
    await api.v1.common.readDraft(draftType: 'origin_create');
    await api.v1.common.deleteDraft(draftId: draft['draft_id'] as String);
    await api.v1.common.registerDevice(
      deviceId: 'device_mock_1',
      platform: 'android',
    );
  });
}

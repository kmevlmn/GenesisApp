import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/ai_content_disclaimer.dart';
import 'package:genesis_flutter_android/components/chat/shared/chat_ui.dart';
import 'package:genesis_flutter_android/components/common/genesis_image_viewer_overlay.dart';
import 'package:genesis_flutter_android/components/gems/memory_model_entry_button.dart';
import 'package:genesis_flutter_android/app/config/genesis_image_config.dart';
import 'package:genesis_flutter_android/icons/custom_icon_assets.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_scroll_coordinator.dart';
import 'package:genesis_flutter_android/ui/components/genesis_avatar.dart';
import 'package:genesis_flutter_android/ui/components/genesis_static_network_image.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_typography.dart';
import 'package:genesis_flutter_android/utils/genesis_message_image.dart';

class _JumpRecordingScrollController extends ScrollController {
  int jumpToCallCount = 0;

  @override
  void jumpTo(double value) {
    jumpToCallCount += 1;
    super.jumpTo(value);
  }

  void resetJumpToCallCount() => jumpToCallCount = 0;
}

void main() {
  test('private chat keeps its legacy green send button', () {
    expect(kPrivateChatStyle.composerSendButtonColor, const Color(0xFF338960));
    expect(
      kPrivateChatStyle.composerSendButtonDisabledColor,
      const Color(0xFFBFD8CD),
    );
  });

  testWidgets('chat bubble avatars use the 2.4 DPR cap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatAvatar(
          label: 'P',
          colors: <Color>[Colors.black, Colors.white],
        ),
      ),
    );

    final avatar = tester.widget<GenesisAvatar>(find.byType(GenesisAvatar));
    expect(
      avatar.maxDevicePixelRatio,
      GenesisImageConfig.chatAvatarMaxDevicePixelRatio,
    );
  });

  testWidgets('plain chat avatars do not draw a default border', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatAvatar(
          label: 'P',
          colors: <Color>[Colors.black, Colors.white],
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(ChatAvatar),
        matching: find.byWidgetPredicate((widget) {
          if (widget is! DecoratedBox) return false;
          final decoration = widget.decoration;
          return decoration is BoxDecoration && decoration.border != null;
        }),
      ),
      findsNothing,
    );
  });

  test('private chat uses a transparent status bar with dark icons', () {
    expect(
      kChatTransparentLightSystemUiOverlayStyle.statusBarColor,
      Colors.transparent,
    );
    expect(
      kChatTransparentLightSystemUiOverlayStyle.statusBarIconBrightness,
      Brightness.dark,
    );
    expect(
      kChatTransparentLightSystemUiOverlayStyle.systemStatusBarContrastEnforced,
      isFalse,
    );
  });

  LocationChatScrollCoordinator locationChatCoordinator(
    ScrollController controller,
  ) {
    final coordinator = LocationChatScrollCoordinator(controller: controller);
    addTearDown(coordinator.dispose);
    return coordinator;
  }

  List<ChatMessageVm> chatMessages(int start, int end) {
    return [
      for (var id = start; id <= end; id += 1)
        ChatMessageVm(
          localId: 'm$id',
          senderId: 'peer',
          senderName: 'Peer',
          text: 'message $id',
          isMe: id.isEven,
          status: 'sent',
          createdAt: DateTime(2026, 5, 29, 10).add(Duration(minutes: id)),
        ),
    ];
  }

  testWidgets('chat message row uses a dedicated component per bubble type', (
    WidgetTester tester,
  ) async {
    final messages = [
      ChatMessageVm(
        localId: 'self',
        senderId: 'self',
        senderName: 'Self',
        text: 'Self message',
        isMe: true,
        status: 'sent',
      ),
      ChatMessageVm(
        localId: 'other',
        senderId: 'other',
        senderName: 'Other',
        text: 'Other message',
        isMe: false,
        status: 'sent',
      ),
      ChatMessageVm.system('System message'),
      ChatMessageVm.aiContentDisclaimer(),
      ChatMessageVm(
        localId: 'narrator',
        senderId: 'nar',
        senderName: 'Narrator',
        text: 'Narrator message',
        isMe: false,
        status: 'sent',
        senderType: 'narrator',
      ),
      ChatMessageVm(
        localId: 'tick',
        senderId: 'tick',
        senderName: 'Time',
        text: 'Day 1',
        isMe: false,
        status: 'sent',
        senderType: 'tick',
        tickNo: 1,
      ),
      ChatMessageVm(
        localId: 'image',
        senderId: 'nar_pic',
        senderName: 'Narrator',
        imageUrl: 'assets/images/default_list_image.png',
        text: '',
        isMe: false,
        status: 'sent',
        senderType: 'image',
      ),
      ChatMessageVm(
        localId: 'user-enter-location',
        senderId: 'sub_tick',
        senderName: 'sub_tick',
        text: 'Alice entered the cafe',
        isMe: false,
        status: 'sent',
        senderType: 'user_enter_location',
        timelinePayload: const ChatUserEnterLocationPayloadVm(
          characterId: 'char_alice',
          toLocationId: 'loc_cafe',
          text: 'Alice entered the cafe',
        ),
      ),
      ChatMessageVm(
        localId: 'story-events',
        senderId: 'sub_tick',
        senderName: 'sub_tick',
        text: 'Alice found a ticket.',
        isMe: false,
        status: 'sent',
        senderType: 'story_events',
        tickNo: 4,
        subTickNo: 1,
        currentTime: 'Day 2, 00:09:15',
        timelinePayload: const ChatStoryEventsPayloadVm(
          locationId: 'loc_station',
          locationName: 'Old Station',
          paragraphs: [
            ChatStoryEventParagraphVm(
              timestamp: 'Day 2, 10:15',
              text: 'Alice found a ticket.',
              clue: 'The date is three years ago.',
              visibilityLabel: 'public',
            ),
          ],
        ),
      ),
      ChatMessageVm(
        localId: 'characters-moved',
        senderId: 'sub_tick',
        senderName: 'sub_tick',
        text: 'Alice → Cafe',
        isMe: false,
        status: 'sent',
        senderType: 'characters_moved',
        timelinePayload: const ChatCharactersMovedPayloadVm(
          movements: [
            ChatCharacterMovementVm(
              characterId: 'char_alice',
              characterName: 'Alice',
              toLocationId: 'loc_cafe',
              toLocationName: 'Cafe',
              isDestinationCurrentLocation: true,
            ),
          ],
        ),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (final message in messages)
                  ChatMessageRow(message: message, showDateDivider: false),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ChatSelfMessageBubble), findsOneWidget);
    expect(find.byType(ChatOtherMessageBubble), findsOneWidget);
    expect(find.byType(ChatSystemMessage), findsNWidgets(3));
    expect(find.byType(ChatAiContentDisclaimerMessageBubble), findsOneWidget);
    expect(find.byType(ChatNarratorMessageBubble), findsOneWidget);
    expect(find.byType(ChatTickMessageBubble), findsOneWidget);
    expect(find.byType(ChatImageMessage), findsOneWidget);
    expect(find.byType(ChatUserEnterLocationMessageBubble), findsOneWidget);
    expect(find.byType(ChatStoryEventsMessageBubble), findsOneWidget);
    expect(find.byType(ChatCharactersMovedMessageBubble), findsOneWidget);
    expect(find.byType(ChatOtherMessageBubble), findsOneWidget);
  });

  testWidgets(
    'AI content disclaimer uses its dedicated non-interactive bubble',
    (WidgetTester tester) async {
      var longPressCount = 0;
      final message = ChatMessageVm.aiContentDisclaimer();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageRow(
              message: message,
              showDateDivider: false,
              onMessageLongPressStart: (_, _, _) => longPressCount += 1,
            ),
          ),
        ),
      );

      expect(message.isAiContentDisclaimer, isTrue);
      expect(message.isSystem, isTrue);
      expect(find.byType(ChatAiContentDisclaimerMessageBubble), findsOneWidget);
      expect(find.byType(AiContentDisclaimer), findsOneWidget);
      expect(find.byType(ChatSystemMessage), findsNothing);
      expect(find.text(kAiContentDisclaimerText), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>(
            'chat-ai-content-disclaimer-message-'
            'location-chat-ai-content-disclaimer',
          ),
        ),
        findsOneWidget,
      );

      await tester.longPress(find.text(kAiContentDisclaimerText));
      await tester.pump();
      expect(longPressCount, 0);
    },
  );

  testWidgets('timeline event bubbles render typed display fields', (
    WidgetTester tester,
  ) async {
    ChatCharacterMovementVm? tappedMovement;
    final messages = [
      ChatMessageVm(
        localId: 'enter',
        senderId: 'sub_tick',
        senderName: 'sub_tick',
        text: 'Alice entered the cafe',
        isMe: false,
        status: 'sent',
        senderType: 'user_enter_location',
        timelinePayload: const ChatUserEnterLocationPayloadVm(
          characterId: 'char_alice',
          toLocationId: 'loc_cafe',
          text: 'Alice entered the cafe',
        ),
      ),
      ChatMessageVm(
        localId: 'story',
        senderId: 'sub_tick',
        senderName: 'sub_tick',
        text: 'Alice found a ticket.',
        isMe: false,
        status: 'sent',
        senderType: 'story_events',
        tickNo: 4,
        subTickNo: 1,
        currentTime: 'Day 2, 00:09:15',
        timelinePayload: const ChatStoryEventsPayloadVm(
          locationId: 'loc_station',
          locationName: 'Old Station',
          paragraphs: [
            ChatStoryEventParagraphVm(
              timestamp: 'Day 2, 10:15',
              text: 'Alice found a ticket.',
              clue: 'The date is three years ago.',
              visibilityLabel: 'Mateo, Iris',
              visibleRoles: [
                ChatStoryEventVisibleRoleVm(
                  roleId: 'char_mateo',
                  name: 'Mateo',
                  isAi: true,
                ),
                ChatStoryEventVisibleRoleVm(
                  roleId: 'char_iris',
                  name: 'Iris',
                  isAi: false,
                ),
              ],
            ),
            ChatStoryEventParagraphVm(
              timestamp: 'Day 2, 10:20',
              text: 'The platform became quiet.',
              clue: '',
              visibilityLabel: 'public',
            ),
          ],
        ),
      ),
      ChatMessageVm(
        localId: 'moved',
        senderId: 'sub_tick',
        senderName: 'sub_tick',
        text: 'Alice → Cafe',
        isMe: false,
        status: 'sent',
        senderType: 'characters_moved',
        timelinePayload: const ChatCharactersMovedPayloadVm(
          movements: [
            ChatCharacterMovementVm(
              characterId: 'char_alice',
              characterName: 'Alice',
              toLocationId: 'loc_cafe',
              toLocationName: 'Cafe',
              isDestinationCurrentLocation: true,
            ),
            ChatCharacterMovementVm(
              characterId: 'char_bob',
              characterName: 'Bob',
              toLocationId: 'loc_harbor',
              toLocationName: 'Harbor',
            ),
          ],
        ),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (final message in messages)
                ChatMessageRow(
                  message: message,
                  showDateDivider: false,
                  style: kLocationChatStyle,
                  onCharactersMovedLocationTap: (movement) {
                    tappedMovement = movement;
                  },
                ),
            ],
          ),
        ),
      ),
    );

    final enterText = find.text('Alice came to the cafe', findRichText: true);
    final enterBubble = find.byKey(
      const ValueKey<String>('chat-user-enter-location-message-enter'),
    );
    expect(enterText, findsOneWidget);
    expect(find.byType(ChatSystemMessage), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('chat-user-enter-location-icon')),
      findsOneWidget,
    );
    final enterDecoration =
        tester.widget<Container>(enterBubble).decoration! as BoxDecoration;
    expect(enterDecoration.color, const Color(0x21FFFFFF));
    expect(enterDecoration.borderRadius, BorderRadius.circular(20));
    final enterBubbleRect = tester.getRect(enterBubble);
    final enterRowRect = tester.getRect(
      find.ancestor(of: enterBubble, matching: find.byType(ChatMessageRow)),
    );
    expect(enterBubbleRect.width, lessThan(enterRowRect.width));
    expect(enterBubbleRect.center.dx, closeTo(enterRowRect.center.dx, 1));
    expect(find.text('Tick 4-1 · Day 2, 00:09:15'), findsNothing);
    expect(find.text('Old Station'), findsNothing);
    expect(find.text('Event'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains(eventsIconAsset),
      ),
      findsNWidgets(2),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains(clueIconAsset),
      ),
      findsOneWidget,
    );
    expect(find.text('Day 2, 10:15'), findsOneWidget);
    expect(find.text('Mateo, Iris'), findsOneWidget);
    expect(find.text('Mateo'), findsNothing);
    expect(find.text('Iris'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains(characterStatIconAsset),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains(userStatIconAsset),
      ),
      findsNothing,
    );
    expect(find.text('Alice found a ticket.'), findsOneWidget);
    expect(find.text('The date is three years ago.'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.text('The date is three years ago.'))
          .textSpan
          ?.style
          ?.color,
      Colors.white.withValues(alpha: 0.72),
    );
    expect(find.text('Day 2, 10:20'), findsOneWidget);
    expect(find.text('public'), findsNothing);
    expect(find.text('The platform became quiet.'), findsOneWidget);
    expect(find.text('Day 2, 10:15 · Mateo, Iris'), findsNothing);
    expect(find.text('Day 2, 10:20 · public'), findsNothing);
    expect(
      find.byKey(const ValueKey('chat-story-event-paragraph-story-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-story-event-paragraph-story-1')),
      findsOneWidget,
    );
    final firstTimestamp = find.byKey(
      const ValueKey('chat-story-event-timestamp-story-0'),
    );
    final firstVisibility = find.byKey(
      const ValueKey('chat-story-event-visibility-story-0'),
    );
    final timestampText = tester.widget<Text>(firstTimestamp);
    expect(timestampText.style?.fontSize, 11);
    expect(timestampText.style?.color, Colors.white.withValues(alpha: 0.72));
    final visibleRolesText = tester.widget<Text>(find.text('Mateo, Iris'));
    expect(visibleRolesText.style?.fontSize, 13);
    expect(visibleRolesText.style?.height, 1.3);
    expect(
      tester.getCenter(firstVisibility).dx,
      greaterThan(tester.getCenter(firstTimestamp).dx),
    );
    expect(
      (tester.getCenter(firstVisibility).dy -
              tester.getCenter(firstTimestamp).dy)
          .abs(),
      lessThan(2),
    );
    expect(
      tester.getTopLeft(find.text('Alice found a ticket.')).dy,
      greaterThan(tester.getBottomLeft(firstTimestamp).dy),
    );
    expect(
      tester.getTopLeft(find.text('The date is three years ago.')).dy,
      greaterThan(tester.getBottomLeft(find.text('Alice found a ticket.')).dy),
    );
    final storyBubble = tester.widget<Container>(
      find.byKey(const ValueKey('chat-story-events-message-story')),
    );
    expect(
      (storyBubble.decoration as BoxDecoration).color,
      kLocationChatStyle.systemMessageBackgroundColor,
    );
    expect(find.text('Character destinations'), findsNothing);
    expect(find.byIcon(Icons.directions_walk_rounded), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains(routeIconAsset),
      ),
      findsNWidgets(2),
    );
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('has come to'), findsOneWidget);
    expect(find.text('has gone to'), findsOneWidget);
    expect(find.text('Cafe'), findsOneWidget);
    expect(find.text('Harbor'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Alice')).style?.fontWeight,
      FontWeight.w400,
    );
    expect(
      tester.widget<Text>(find.text('Cafe')).style?.fontWeight,
      FontWeight.w400,
    );
    final firstMovement = find.byKey(
      const ValueKey<String>('chat-character-movement-moved-0'),
    );
    final secondMovement = find.byKey(
      const ValueKey<String>('chat-character-movement-moved-1'),
    );
    expect(
      tester.getTopLeft(secondMovement).dy -
          tester.getBottomLeft(firstMovement).dy,
      closeTo(10, 0.01),
    );
    expect(
      tester
          .widget<Container>(
            find.byKey(
              const ValueKey<String>('chat-story-event-paragraph-story-1'),
            ),
          )
          .margin,
      const EdgeInsets.only(top: 10),
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('chat-story-events-message-story'),
        ),
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 5,
        ),
      ),
      findsNWidgets(3),
    );
    expect(find.text('Alice → Cafe'), findsNothing);
    final movedBubble = tester.widget<Container>(
      find.byKey(const ValueKey('chat-characters-moved-message-moved')),
    );
    expect(
      (movedBubble.decoration as BoxDecoration).color,
      kLocationChatStyle.systemMessageBackgroundColor,
    );
    final locationLabel = tester.widget<Text>(find.text('Harbor'));
    expect(
      locationLabel.style?.color,
      kLocationChatStyle.systemMessageTextStyle.color,
    );
    await tester.tap(
      find.byKey(const ValueKey('chat-character-movement-location-moved-1')),
    );
    expect(tappedMovement?.toLocationId, 'loc_harbor');
    expect(find.text('sub_tick'), findsNothing);
    expect(find.text('char_alice'), findsNothing);
    expect(find.byType(ChatAvatar), findsNothing);
  });

  testWidgets('tick event visibility uses available width when wrapping', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const roleNames =
        'Mateo Cruz, Iris, Marcus Aurelius, Alexandra Johnson, River Song, '
        'Theodore Roosevelt, Cassandra Nova';
    final message = ChatMessageVm(
      localId: 'wrapping-tick',
      senderId: 'tick',
      senderName: 'Tick',
      text: 'A narrow-screen event.',
      isMe: false,
      status: 'sent',
      senderType: 'tick',
      tickNo: 2,
      timelinePayload: const ChatTickPayloadVm(
        storyEvents: ChatStoryEventsPayloadVm(
          locationId: 'loc_station',
          locationName: 'Old Station',
          paragraphs: [
            ChatStoryEventParagraphVm(
              timestamp: 'Day 2, 10:15',
              text: 'A narrow-screen event.',
              clue: '',
              visibilityLabel: roleNames,
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: message,
            showDateDivider: false,
            style: kLocationChatStyle,
          ),
        ),
      ),
    );

    final visibility = find.byKey(
      const ValueKey('chat-story-event-visibility-wrapping-tick-tick-0'),
    );
    expect(visibility, findsOneWidget);
    expect(find.text(roleNames), findsOneWidget);
    expect(tester.getSize(find.text(roleNames)).width, greaterThan(224));
    expect(tester.getSize(find.text(roleNames)).height, greaterThan(20));
    expect(
      tester.getTopLeft(find.text('Day 2, 10:15')).dy,
      lessThan(tester.getTopLeft(find.text(roleNames)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat message list can render an oldest-edge notice', (
    WidgetTester tester,
  ) async {
    const notice = 'Oldest edge notice';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            controller: ScrollController(),
            topTitle: '',
            oldestEdgeNotice: notice,
            showDateDividers: false,
            messages: [
              ChatMessageVm(
                localId: 'tick-1',
                senderId: 'tick',
                senderName: 'Tick',
                senderType: 'tick',
                text: '',
                isMe: false,
                status: 'sent',
                tickNo: 1,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text(notice), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(notice)).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('chat-tick-message-bubble')))
            .dy,
      ),
    );
  });

  testWidgets('failed self message can be tapped to retry', (tester) async {
    var retryCount = 0;
    final message = ChatMessageVm(
      localId: 'failed-message',
      clientMsgId: 'failed-client-id',
      senderId: 'me',
      senderName: 'Me',
      text: 'Retry me',
      isMe: true,
      status: 'failed',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            controller: ScrollController(),
            messages: [message],
            topTitle: '',
            showDateDividers: false,
            onFailedMessageTap: (_) => retryCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('chat-message-retry-failed-message')),
    );
    await tester.pump();
    expect(retryCount, 1);

    await tester.tap(find.text('Retry me'));
    await tester.pump();
    expect(retryCount, 2);
  });

  testWidgets('chat header can show Memory & Model entry', (
    WidgetTester tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatHeader(
            title: 'Moonlit Market',
            subtitle: '2 characters',
            connected: true,
            connecting: false,
            onBack: () {},
            trailing: TextButton(
              key: const ValueKey('memory-model-entry'),
              onPressed: () => tapped = true,
              child: const Text('CC4.5'),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('memory-model-entry')), findsOneWidget);
    expect(find.text('CC4.5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('memory-model-entry')));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('chat header constrains long model entry beside title', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatHeader(
            title: 'The Wisteria Terrace (1)',
            subtitle: 'kitchen maid',
            connected: true,
            connecting: false,
            onBack: () {},
            showSubtitle: false,
            trailing: MemoryModelEntryButton(
              modelLabel: 'top_pick_v3_5',
              darkHeader: true,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    final titleRect = tester.getRect(find.text('The Wisteria Terrace (1)'));
    final modelRect = tester.getRect(
      find.byKey(const ValueKey('memory-model-entry')),
    );

    expect(modelRect.width, lessThanOrEqualTo(kMemoryModelEntryMaxWidth));
    expect(titleRect.right, lessThanOrEqualTo(modelRect.left + 1));
  });

  testWidgets('anchored message list keeps oldest notice while loading', (
    WidgetTester tester,
  ) async {
    const notice = 'Oldest edge notice';
    final coordinator = locationChatCoordinator(ScrollController());
    Widget build({required bool loading}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: LocationChatAnchoredMessageList(
              coordinator: coordinator,
              topTitle: '',
              oldestEdgeNotice: notice,
              oldestEdgeLoading: loading,
              showDateDividers: false,
              messages: chatMessages(1, 5),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(loading: false));
    await tester.pumpAndSettle();
    coordinator.controller.jumpTo(0);
    coordinator.deactivate();
    await tester.pump();
    final noticeSize = tester.getSize(find.byType(ChatOldestEdgeContent));
    final firstMessage = find.byKey(const ValueKey<String>('m1'));
    final firstMessageTop = tester.getTopLeft(firstMessage).dy;

    await tester.pumpWidget(build(loading: true));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(notice), findsOneWidget);
    expect(tester.getSize(find.byType(ChatOldestEdgeContent)), noticeSize);
    expect(tester.getTopLeft(firstMessage).dy, firstMessageTop);
  });

  testWidgets(
    'anchored message list stops at the oldest message before the notice',
    (WidgetTester tester) async {
      final coordinator = locationChatCoordinator(ScrollController());
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 640,
              child: NotificationListener<ScrollNotification>(
                onNotification: coordinator.handleScrollNotification,
                child: LocationChatAnchoredMessageList(
                  coordinator: coordinator,
                  topTitle: '',
                  oldestEdgeNotice: 'Oldest edge notice',
                  oldestEdgeNoticeRequiresSecondScroll: true,
                  showDateDividers: false,
                  messages: chatMessages(1, 30),
                  style: style,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final scrollableRect = tester.getRect(scrollable);
      final position = coordinator.controller.position;
      expect(position.maxScrollExtent, greaterThan(scrollableRect.height));
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));

      await tester.drag(scrollable, const Offset(0, 2000));
      await tester.pumpAndSettle();

      expect(position.pixels, greaterThan(0));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('m1'))).dy,
        closeTo(scrollableRect.top + 18, 1),
      );
      expect(
        tester.getBottomLeft(find.text('Oldest edge notice')).dy,
        lessThanOrEqualTo(scrollableRect.top + 18),
      );

      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(position.pixels, 0);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('m1'))).dy,
        closeTo(
          tester.getBottomLeft(find.text('Oldest edge notice')).dy + 16,
          1,
        ),
      );
    },
  );

  testWidgets('short messages start at their top with the notice just above', (
    WidgetTester tester,
  ) async {
    final coordinator = locationChatCoordinator(ScrollController());
    final style = ChatUiStyleConfig.standard.copyWith(
      messageListPadding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 640,
            child: NotificationListener<ScrollNotification>(
              onNotification: coordinator.handleScrollNotification,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                topTitle: '',
                oldestEdgeNotice: 'Oldest edge notice',
                oldestEdgeNoticeRequiresSecondScroll: true,
                showDateDividers: false,
                messages: chatMessages(1, 3),
                style: style,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final scrollableRect = tester.getRect(scrollable);
    final position = coordinator.controller.position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.maxScrollExtent, lessThan(scrollableRect.height / 2));
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('m1'))).dy,
      closeTo(scrollableRect.top + 18, 1),
    );

    await tester.drag(scrollable, const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(position.pixels, 0);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('m1'))).dy,
      closeTo(tester.getBottomLeft(find.text('Oldest edge notice')).dy + 16, 1),
    );
  });

  testWidgets('notice is shown directly when there are no messages', (
    WidgetTester tester,
  ) async {
    final coordinator = locationChatCoordinator(ScrollController());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationChatAnchoredMessageList(
            coordinator: coordinator,
            topTitle: '',
            oldestEdgeNotice: 'Oldest edge notice',
            oldestEdgeNoticeRequiresSecondScroll: true,
            showDateDividers: false,
            messages: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(coordinator.controller.position.maxScrollExtent, 0);
    expect(find.text('Oldest edge notice'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Oldest edge notice')).dy,
      greaterThanOrEqualTo(tester.getTopLeft(find.byType(Scrollable).first).dy),
    );
  });

  testWidgets(
    'anchored message list does not scroll short notice and message content',
    (WidgetTester tester) async {
      final controller = ScrollController();
      final coordinator = locationChatCoordinator(controller);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 640,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                topTitle: '',
                oldestEdgeNotice: 'Oldest edge notice',
                showDateDividers: false,
                messages: chatMessages(1, 3),
                style: style,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final firstMessageTop = tester
          .getTopLeft(find.byKey(const ValueKey('m1')))
          .dy;

      expect(position.minScrollExtent, 0);
      expect(position.maxScrollExtent, 0);

      await tester.drag(scrollable, const Offset(0, -80));
      await tester.pump();

      expect(position.pixels, 0);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('m1'))).dy,
        firstMessageTop,
      );
    },
  );

  testWidgets(
    'anchored message list stays linear when only system messages precede center',
    (WidgetTester tester) async {
      final controller = ScrollController();
      final coordinator = locationChatCoordinator(controller);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
      );

      final messages = [
        ChatMessageVm(
          localId: 'tick-1',
          senderId: 'tick',
          senderName: 'Tick',
          senderType: 'tick',
          text: '',
          isMe: false,
          status: 'sent',
          tickNo: 1,
          currentTime: 'Match Day, 14:00',
        ),
        ChatMessageVm(
          localId: 'm1',
          senderId: 'me',
          senderName: 'Me',
          text: 'first message',
          isMe: true,
          status: 'sent',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 640,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                topTitle: '',
                oldestEdgeNotice: 'Oldest edge notice',
                showDateDividers: false,
                messages: messages,
                style: style,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final noticeTop = tester.getTopLeft(find.text('Oldest edge notice')).dy;

      expect(position.minScrollExtent, 0);
      expect(position.maxScrollExtent, 0);

      await tester.drag(scrollable, const Offset(0, -80));
      await tester.pump();

      expect(position.pixels, 0);
      expect(tester.getTopLeft(find.text('Oldest edge notice')).dy, noticeTop);
    },
  );

  testWidgets(
    'anchored message list does not scroll short content before center',
    (WidgetTester tester) async {
      final controller = ScrollController();
      final coordinator = locationChatCoordinator(controller);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 640,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                topTitle: '',
                oldestEdgeNotice: 'Oldest edge notice',
                showDateDividers: false,
                messages: chatMessages(1, 3),
                style: style,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final firstMessageTop = tester
          .getTopLeft(find.byKey(const ValueKey('m1')))
          .dy;

      expect(position.minScrollExtent, 0);
      expect(position.maxScrollExtent, 0);

      await tester.drag(scrollable, const Offset(0, -80));
      await tester.pump();

      expect(position.pixels, 0);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('m1'))).dy,
        firstMessageTop,
      );
    },
  );

  testWidgets('anchored message list pins bottom while last bubble grows', (
    WidgetTester tester,
  ) async {
    final controller = ScrollController();
    final coordinator = locationChatCoordinator(controller);
    final messages = chatMessages(1, 24);
    final style = ChatUiStyleConfig.standard.copyWith(
      messageListPadding: EdgeInsets.zero,
    );

    Widget build() {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: LocationChatAnchoredMessageList(
              coordinator: coordinator,
              messages: messages,
              topTitle: '',
              showDateDividers: false,
              style: style,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    final lastMessage = find.byKey(const ValueKey<String>('m24'));
    final bottomBefore = tester.getBottomLeft(lastMessage).dy;

    messages.last.text = List.filled(
      16,
      'streaming content keeps growing',
    ).join('\n');
    await tester.pumpWidget(build());

    expect(
      controller.position.pixels,
      closeTo(controller.position.maxScrollExtent, 0.1),
    );
    expect(tester.getBottomLeft(lastMessage).dy, closeTo(bottomBefore, 1));
  });

  testWidgets(
    'anchored message list preserves position when last bubble grows away from bottom',
    (WidgetTester tester) async {
      final controller = ScrollController();
      final coordinator = locationChatCoordinator(controller);
      final messages = chatMessages(1, 24);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: EdgeInsets.zero,
      );

      Widget build() {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                messages: messages,
                topTitle: '',
                showDateDividers: false,
                style: style,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      controller.jumpTo(controller.position.maxScrollExtent - 120);
      coordinator.deactivate();
      await tester.pump();
      final pixelsBefore = controller.position.pixels;
      final observedOffsets = <double>[];
      void recordOffset() => observedOffsets.add(controller.position.pixels);
      controller.addListener(recordOffset);

      messages.last.text = List.filled(
        16,
        'streaming content keeps growing',
      ).join('\n');
      await tester.pumpWidget(build());
      controller.removeListener(recordOffset);

      expect(controller.position.pixels, closeTo(pixelsBefore, 0.1));
      expect(
        controller.position.pixels,
        lessThan(controller.position.maxScrollExtent),
      );
      expect(
        observedOffsets,
        everyElement(inInclusiveRange(pixelsBefore - 0.1, pixelsBefore + 0.1)),
      );
    },
  );

  testWidgets(
    'anchored message list skips geometry while a transform is unlaid out',
    (WidgetTester tester) async {
      final controller = ScrollController();
      final coordinator = locationChatCoordinator(controller);
      final listKey = GlobalKey();
      final messages = chatMessages(1, 24);
      var width = 360.0;

      Widget build() {
        return MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: 360,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Transform.scale(
                      key: ValueKey<double>(constraints.maxWidth),
                      alignment: Alignment.topLeft,
                      scale: 1,
                      child: LocationChatAnchoredMessageList(
                        key: listKey,
                        coordinator: coordinator,
                        messages: messages,
                        topTitle: '',
                        showDateDividers: false,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      controller.jumpTo(controller.position.maxScrollExtent - 120);
      await tester.pump();

      messages.last.text = List.filled(8, 'updated message').join('\n');
      width = 320;
      await tester.pumpWidget(build());

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('chat message list shows first divider and long gaps', (
    WidgetTester tester,
  ) async {
    final start = DateTime(2026, 5, 29, 10);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            controller: ScrollController(),
            topTitle: '',
            messages: [
              ChatMessageVm(
                localId: 'm1',
                senderId: 'peer',
                senderName: 'Peer',
                text: 'first',
                isMe: false,
                status: 'sent',
                createdAt: start,
              ),
              ChatMessageVm(
                localId: 'm2',
                senderId: 'peer',
                senderName: 'Peer',
                text: 'second',
                isMe: false,
                status: 'sent',
                createdAt: start.add(const Duration(minutes: 30)),
              ),
              ChatMessageVm(
                localId: 'm3',
                senderId: 'peer',
                senderName: 'Peer',
                text: 'third',
                isMe: false,
                status: 'sent',
                createdAt: start.add(const Duration(minutes: 61)),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(ChatDateDivider), findsNWidgets(2));
  });

  testWidgets('chat message list can hide date dividers', (
    WidgetTester tester,
  ) async {
    final start = DateTime(2026, 5, 29, 10);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            controller: ScrollController(),
            topTitle: '',
            showDateDividers: false,
            messages: [
              ChatMessageVm(
                localId: 'm1',
                senderId: 'peer',
                senderName: 'Peer',
                text: 'first',
                isMe: false,
                status: 'sent',
                createdAt: start,
              ),
              ChatMessageVm(
                localId: 'm2',
                senderId: 'peer',
                senderName: 'Peer',
                text: 'second',
                isMe: false,
                status: 'sent',
                createdAt: start.add(const Duration(hours: 1)),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(ChatDateDivider), findsNothing);
  });

  testWidgets(
    'anchored message list keeps center stable when history prepends',
    (WidgetTester tester) async {
      final controller = ScrollController();
      final coordinator = locationChatCoordinator(controller);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: EdgeInsets.zero,
      );

      Widget build(List<ChatMessageVm> messages) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                messages: messages,
                topTitle: '',
                showDateDividers: false,
                style: style,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(build(chatMessages(21, 80)));
      await tester.pumpAndSettle();
      controller.jumpTo(0);
      coordinator.deactivate();
      await tester.pumpAndSettle();

      final centerFinder = find.byKey(const ValueKey<String>('m21'));
      expect(centerFinder, findsOneWidget);
      final before = tester.getTopLeft(centerFinder).dy;

      await tester.pumpWidget(build(chatMessages(1, 80)));
      await tester.pumpAndSettle();

      expect(centerFinder, findsOneWidget);
      final after = tester.getTopLeft(centerFinder).dy;
      expect(after, closeTo(before, 1));
    },
  );

  testWidgets('anchored message list lazily builds the visible window', (
    WidgetTester tester,
  ) async {
    final coordinator = locationChatCoordinator(ScrollController());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: LocationChatAnchoredMessageList(
              coordinator: coordinator,
              messages: chatMessages(1, 200),
              topTitle: '',
              showDateDividers: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('m1')), findsNothing);
    expect(find.byKey(const ValueKey<String>('m200')), findsOneWidget);
    expect(
      find.byType(ChatMessageRow).evaluate().length,
      lessThanOrEqualTo(15),
    );

    final position = coordinator.controller.position;
    position.jumpTo(position.maxScrollExtent / 2);
    await tester.pumpAndSettle();
    final middleMountedMessageCount = find
        .byType(ChatMessageRow)
        .evaluate()
        .length;
    expect(middleMountedMessageCount, lessThanOrEqualTo(15));
  });

  testWidgets(
    'history waits for the loading collapse before prepending without a jump',
    (WidgetTester tester) async {
      final controller = _JumpRecordingScrollController();
      final coordinator = locationChatCoordinator(controller);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: EdgeInsets.zero,
      );
      var collapseCount = 0;

      Widget build({
        required List<ChatMessageVm> messages,
        required bool loading,
      }) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                messages: messages,
                topTitle: '',
                oldestEdgeLoading: loading,
                onOldestEdgeLoadingCollapsed: () => collapseCount += 1,
                showDateDividers: false,
                style: style,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(
        build(messages: chatMessages(21, 80), loading: false),
      );
      await tester.pumpAndSettle();
      controller.jumpTo(0);
      coordinator.deactivate();
      await tester.pump();
      controller.resetJumpToCallCount();

      final retainedMessage = find.byKey(const ValueKey<String>('m21'));
      final prependedMessage = find.byKey(const ValueKey<String>('m1'));
      final baselineTop = tester.getTopLeft(retainedMessage).dy;

      await tester.pumpWidget(
        build(messages: chatMessages(21, 80), loading: true),
      );
      await tester.pump(locationChatOldestEdgeLoadingAnimationDuration * 0.5);
      final expandingTop = tester.getTopLeft(retainedMessage).dy;
      expect(expandingTop, greaterThan(baselineTop));

      await tester.pump(locationChatOldestEdgeLoadingAnimationDuration * 0.5);
      final expandedTop = tester.getTopLeft(retainedMessage).dy;
      expect(expandedTop, greaterThan(expandingTop));

      await tester.pumpWidget(
        build(messages: chatMessages(1, 80), loading: false),
      );
      expect(prependedMessage, findsNothing);
      await tester.pump(locationChatOldestEdgeLoadingAnimationDuration * 0.5);
      expect(prependedMessage, findsNothing);
      final collapsingTop = tester.getTopLeft(retainedMessage).dy;
      expect(collapsingTop, lessThan(expandedTop));
      expect(collapsingTop, greaterThan(baselineTop));

      await tester.pump(locationChatOldestEdgeLoadingAnimationDuration * 0.5);
      await tester.pump(const Duration(milliseconds: 1));
      expect(prependedMessage, findsNothing);
      expect(tester.getTopLeft(retainedMessage).dy, closeTo(baselineTop, 1));

      await tester.pump();
      expect(prependedMessage, findsNothing);
      expect(tester.getTopLeft(retainedMessage).dy, closeTo(baselineTop, 1));
      expect(controller.jumpToCallCount, 0);
      expect(collapseCount, 1);

      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(prependedMessage, findsOneWidget);
    },
  );

  testWidgets(
    'AI disclaimer is a normal anchored first row without a second-scroll stop',
    (WidgetTester tester) async {
      final controller = _JumpRecordingScrollController();
      final coordinator = locationChatCoordinator(controller);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: EdgeInsets.zero,
      );

      Widget build(List<ChatMessageVm> messages) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              child: NotificationListener<ScrollNotification>(
                onNotification: coordinator.handleScrollNotification,
                child: LocationChatAnchoredMessageList(
                  coordinator: coordinator,
                  messages: messages,
                  topTitle: '',
                  showDateDividers: false,
                  style: style,
                ),
              ),
            ),
          ),
        );
      }

      final ordinaryMessages = chatMessages(1, 30);
      await tester.pumpWidget(build(ordinaryMessages));
      await tester.pumpAndSettle();
      controller.jumpTo(40);
      coordinator.deactivate();
      await tester.pump();
      controller.resetJumpToCallCount();

      final retainedMessage = find.byKey(const ValueKey<String>('m1'));
      final baselineTop = tester.getTopLeft(retainedMessage).dy;
      await tester.pumpWidget(
        build([ChatMessageVm.aiContentDisclaimer(), ...ordinaryMessages]),
      );

      expect(tester.getTopLeft(retainedMessage).dy, closeTo(baselineTop, 1));
      expect(controller.jumpToCallCount, 0);
      expect(coordinator.oldestMessageStopOffset, isNull);

      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, 2000));
      await tester.pumpAndSettle();

      expect(controller.position.pixels, 0);
      expect(find.text(kAiContentDisclaimerText), findsOneWidget);
    },
  );

  testWidgets(
    'history layout transaction ignores a simultaneous live tail append',
    (WidgetTester tester) async {
      final controller = _JumpRecordingScrollController();
      final coordinator = locationChatCoordinator(controller);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: EdgeInsets.zero,
      );

      Widget build({
        required List<ChatMessageVm> messages,
        required bool loading,
      }) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                messages: messages,
                topTitle: '',
                oldestEdgeLoading: loading,
                showDateDividers: false,
                style: style,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(
        build(messages: chatMessages(21, 80), loading: false),
      );
      await tester.pumpAndSettle();
      controller.jumpTo(0);
      coordinator.deactivate();
      await tester.pump();
      controller.resetJumpToCallCount();

      final retainedMessage = find.byKey(const ValueKey<String>('m21'));
      final baselineTop = tester.getTopLeft(retainedMessage).dy;

      await tester.pumpWidget(
        build(messages: chatMessages(21, 80), loading: true),
      );
      await tester.pump(locationChatOldestEdgeLoadingAnimationDuration);
      await tester.pumpWidget(
        build(messages: chatMessages(1, 81), loading: false),
      );
      await tester.pump(locationChatOldestEdgeLoadingAnimationDuration);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(const ValueKey<String>('m1')), findsNothing);

      await tester.pump();

      expect(find.byKey(const ValueKey<String>('m1')), findsNothing);
      expect(find.byKey(const ValueKey<String>('m81')), findsNothing);
      expect(tester.getTopLeft(retainedMessage).dy, closeTo(baselineTop, 1));
      expect(controller.jumpToCallCount, 0);

      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('m1')), findsOneWidget);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('m81')), findsOneWidget);
    },
  );

  testWidgets(
    'history layout transaction survives a replaced display boundary row',
    (WidgetTester tester) async {
      final controller = _JumpRecordingScrollController();
      final coordinator = locationChatCoordinator(controller);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: EdgeInsets.zero,
      );
      final initialMessages = <ChatMessageVm>[
        ChatMessageVm(
          localId: 'tick-old',
          senderId: 'tick',
          senderName: 'Time',
          text: 'Old Tick',
          isMe: false,
          status: 'sent',
          senderType: 'tick',
        ),
        ...chatMessages(22, 80),
      ];
      final nextMessages = <ChatMessageVm>[
        ...chatMessages(1, 20),
        ChatMessageVm(
          localId: 'tick-new',
          senderId: 'tick',
          senderName: 'Time',
          text: 'New Tick',
          isMe: false,
          status: 'sent',
          senderType: 'tick',
        ),
        ...chatMessages(22, 80),
      ];

      Widget build({
        required List<ChatMessageVm> messages,
        required bool loading,
      }) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                messages: messages,
                topTitle: '',
                oldestEdgeLoading: loading,
                showDateDividers: false,
                style: style,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(build(messages: initialMessages, loading: false));
      await tester.pumpAndSettle();
      controller.jumpTo(0);
      coordinator.deactivate();
      await tester.pump();
      controller.resetJumpToCallCount();

      final retainedMessage = find.byKey(const ValueKey<String>('m22'));
      final baselineTop = tester.getTopLeft(retainedMessage).dy;

      await tester.pumpWidget(build(messages: initialMessages, loading: true));
      await tester.pump(locationChatOldestEdgeLoadingAnimationDuration);
      await tester.pumpWidget(build(messages: nextMessages, loading: false));
      await tester.pump(locationChatOldestEdgeLoadingAnimationDuration);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('tick-old')), findsNothing);
      expect(find.byKey(const ValueKey<String>('tick-new')), findsOneWidget);
      expect(tester.getTopLeft(retainedMessage).dy, closeTo(baselineTop, 1));
      expect(controller.jumpToCallCount, 0);
    },
  );

  testWidgets(
    'later history prepend stays anchored after the loading transaction',
    (WidgetTester tester) async {
      final controller = _JumpRecordingScrollController();
      final coordinator = locationChatCoordinator(controller);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: EdgeInsets.zero,
      );

      Widget build({
        required List<ChatMessageVm> messages,
        required bool loading,
      }) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                messages: messages,
                topTitle: '',
                oldestEdgeLoading: loading,
                showDateDividers: false,
                style: style,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(
        build(messages: chatMessages(21, 80), loading: false),
      );
      await tester.pumpAndSettle();
      controller.jumpTo(0);
      coordinator.deactivate();
      await tester.pump();

      final retainedMessage = find.byKey(const ValueKey<String>('m21'));
      final baselineTop = tester.getTopLeft(retainedMessage).dy;

      await tester.pumpWidget(
        build(messages: chatMessages(21, 80), loading: true),
      );
      await tester.pump(locationChatOldestEdgeLoadingAnimationDuration);
      await tester.pumpWidget(
        build(messages: chatMessages(11, 80), loading: false),
      );
      await tester.pump(locationChatOldestEdgeLoadingAnimationDuration);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(tester.getTopLeft(retainedMessage).dy, closeTo(baselineTop, 1));
      controller.resetJumpToCallCount();

      await tester.pumpWidget(
        build(messages: chatMessages(1, 80), loading: false),
      );

      expect(find.byKey(const ValueKey<String>('m1')), findsNothing);
      expect(tester.getTopLeft(retainedMessage).dy, closeTo(baselineTop, 1));
      expect(controller.jumpToCallCount, 0);

      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('m1')), findsOneWidget);
    },
  );

  testWidgets(
    'history prepend without a painted loading state corrects before paint',
    (WidgetTester tester) async {
      final controller = _JumpRecordingScrollController();
      final coordinator = locationChatCoordinator(controller);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: EdgeInsets.zero,
      );

      Widget build(List<ChatMessageVm> messages) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                messages: messages,
                topTitle: '',
                showDateDividers: false,
                style: style,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(build(chatMessages(21, 80)));
      await tester.pumpAndSettle();
      controller.jumpTo(0);
      coordinator.deactivate();
      await tester.pump();
      controller.resetJumpToCallCount();

      final retainedMessage = find.byKey(const ValueKey<String>('m21'));
      final baselineTop = tester.getTopLeft(retainedMessage).dy;

      await tester.pumpWidget(build(chatMessages(1, 80)));

      expect(find.byKey(const ValueKey<String>('m1')), findsNothing);
      expect(tester.getTopLeft(retainedMessage).dy, closeTo(baselineTop, 1));
      expect(controller.jumpToCallCount, 0);

      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('m1')), findsOneWidget);
    },
  );

  testWidgets(
    'detached anchor survives a later height change above the viewport',
    (WidgetTester tester) async {
      final controller = _JumpRecordingScrollController();
      final coordinator = locationChatCoordinator(controller);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: EdgeInsets.zero,
      );

      Widget build(List<ChatMessageVm> messages) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                messages: messages,
                topTitle: '',
                showDateDividers: false,
                style: style,
              ),
            ),
          ),
        );
      }

      final shortHistory = <ChatMessageVm>[
        ChatMessageVm(
          localId: 'history-changing-height',
          senderId: 'peer',
          senderName: 'Peer',
          text: 'short history',
          isMe: false,
          status: 'sent',
        ),
        ...chatMessages(21, 80),
      ];
      final tallHistory = <ChatMessageVm>[
        ChatMessageVm(
          localId: 'history-changing-height',
          senderId: 'peer',
          senderName: 'Peer',
          text: List<String>.filled(20, 'history expanded').join('\n'),
          isMe: false,
          status: 'sent',
        ),
        ...chatMessages(21, 80),
      ];

      await tester.pumpWidget(build(shortHistory));
      await tester.pumpAndSettle();
      controller.jumpTo(80);
      coordinator.deactivate();
      await tester.pump();
      controller.resetJumpToCallCount();

      final retainedMessage = find.byKey(const ValueKey<String>('m21'));
      final baselineTop = tester.getTopLeft(retainedMessage).dy;

      await tester.pumpWidget(build(tallHistory));

      expect(tester.getTopLeft(retainedMessage).dy, closeTo(baselineTop, 1));
      expect(controller.jumpToCallCount, 0);
    },
  );

  testWidgets(
    'anchored message list keeps viewport stable when rolling window evicts head',
    (WidgetTester tester) async {
      final controller = ScrollController();
      final coordinator = locationChatCoordinator(controller);
      final style = ChatUiStyleConfig.standard.copyWith(
        messageListPadding: EdgeInsets.zero,
      );

      Widget build(List<ChatMessageVm> messages) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                messages: messages,
                topTitle: '',
                showDateDividers: false,
                style: style,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(build(chatMessages(1, 80)));
      await tester.pumpAndSettle();
      final retainedMessage = find.byKey(const ValueKey<String>('m30'));
      controller.jumpTo(controller.position.maxScrollExtent * 29 / 80);
      await tester.pumpAndSettle();
      await tester.ensureVisible(retainedMessage);
      await tester.pumpAndSettle();
      coordinator.deactivate();
      expect(
        controller.position.maxScrollExtent - controller.position.pixels,
        greaterThan(24),
      );
      final before = tester.getTopLeft(retainedMessage).dy;

      await tester.pumpWidget(build(chatMessages(2, 81)));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(retainedMessage).dy, closeTo(before, 1));
    },
  );

  test('chat date divider rule includes first message only plus long gaps', () {
    final start = DateTime(2026, 5, 29, 10);

    expect(shouldShowChatDateDivider(null, start), isTrue);
    expect(
      shouldShowChatDateDivider(start, start.add(const Duration(minutes: 30))),
      isFalse,
    );
    expect(
      shouldShowChatDateDivider(start, start.add(const Duration(minutes: 31))),
      isTrue,
    );
  });

  testWidgets(
    'chat header uses location title icon and character subtitle icon',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatHeader(
              title: 'Market',
              subtitle: 'Alice, Bob',
              connected: true,
              connecting: false,
              onBack: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.place_outlined), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SvgPicture &&
              widget.bytesLoader.toString().contains(characterStatIconAsset),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('location chat header uses white character subtitle icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatHeader(
            title: 'Market',
            subtitle: 'Alice, Bob',
            connected: true,
            connecting: false,
            onBack: () {},
            style: kLocationChatStyle,
            subtitleIconAsset: characterStatIconAsset,
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains(characterStatIconAsset),
      ),
      findsOneWidget,
    );
  });

  testWidgets('location chat header is transparent with blur four', (
    WidgetTester tester,
  ) async {
    final backdropGroupKey = BackdropKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatHeader(
            title: 'Market',
            subtitle: 'Alice, Bob',
            connected: true,
            connecting: false,
            onBack: () {},
            style: kLocationChatStyle,
            backdropGroupKey: backdropGroupKey,
          ),
        ),
      ),
    );

    expect(kLocationChatStyle.headerBackdropBlurSigma, 4);
    expect(kLocationChatStyle.headerBackgroundGradient, isNull);
    expect(kLocationChatStyle.headerBackgroundColor.a, 0);
    final headerBackdrop = tester.widget<BackdropFilter>(
      find.descendant(
        of: find.byType(ChatHeader),
        matching: find.byType(BackdropFilter),
      ),
    );
    expect(headerBackdrop.backdropGroupKey, same(backdropGroupKey));
    expect(headerBackdrop.filter, isNull);
    expect(
      headerBackdrop.filterConfig,
      const ImageFilterConfig.blur(sigmaX: 4, sigmaY: 4, bounded: false),
    );
  });

  testWidgets('location chat composer is transparent with blur four', (
    WidgetTester tester,
  ) async {
    final backdropGroupKey = BackdropKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: TextEditingController(),
            inputEnabled: true,
            sendEnabled: false,
            sending: false,
            onSend: () async {},
            style: kLocationChatStyle,
            backdropGroupKey: backdropGroupKey,
          ),
        ),
      ),
    );

    expect(kLocationChatStyle.composerBackdropBlurSigma, 4);
    expect(kLocationChatStyle.composerBackgroundGradient, isNull);
    expect(kLocationChatStyle.composerBackgroundColor.a, 0);
    expect(kLocationChatStyle.inputBorderRadius, 8);
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.cursorColor, kLocationChatStyle.inputTextStyle.color);
    expect(input.cursorColor, const Color(0xF2FFFFFF));
    expect(input.decoration?.hintStyle?.color, const Color(0x73FFFFFF));
    final composerBackdrops = tester
        .widgetList<BackdropFilter>(
          find.descendant(
            of: find.byType(ChatComposer),
            matching: find.byType(BackdropFilter),
          ),
        )
        .toList(growable: false);
    expect(composerBackdrops, hasLength(3));
    expect(
      composerBackdrops
          .where((backdrop) => backdrop.backdropGroupKey == backdropGroupKey)
          .length,
      1,
    );
    expect(
      composerBackdrops
          .where((backdrop) => backdrop.backdropGroupKey == null)
          .length,
      2,
    );
    expect(
      composerBackdrops.every((backdrop) => backdrop.filter == null),
      isTrue,
    );
    expect(
      composerBackdrops
          .where(
            (backdrop) =>
                backdrop.filterConfig ==
                const ImageFilterConfig.blur(
                  sigmaX: 4,
                  sigmaY: 4,
                  bounded: false,
                ),
          )
          .length,
      2,
    );
    expect(
      composerBackdrops
          .where(
            (backdrop) =>
                backdrop.filterConfig ==
                const ImageFilterConfig.blur(
                  sigmaX: 14,
                  sigmaY: 14,
                  bounded: false,
                ),
          )
          .length,
      1,
    );
  });

  test('location chat uses fourteen pixel message spacing', () {
    expect(kLocationChatStyle.rowBottomPadding, 14);
    expect(kLocationChatStyle.systemMessageMargin.bottom, 14);
  });

  test(
    'opening dialogue uses its light-surface palette without changing location chat',
    () {
      final openingStyle = kOpeningDialogueStyle;
      final locationStyle = kLocationChatStyle;

      expect(openingStyle.otherBubbleColor, Colors.white);
      expect(openingStyle.bubbleTextStyle.color, Colors.black);
      expect(openingStyle.selfBubbleColor, const Color(0xFFC41F2E));
      expect(
        openingStyle.systemMessageBackgroundColor,
        const Color(0xE6111111),
      );
      expect(
        openingStyle.systemMessageTextStyle.color,
        const Color(0xBAFFFFFF),
      );
      expect(openingStyle.bubbleBackdropBlurSigma, 0);
      expect(openingStyle.useConfiguredScenePlateSystemStyle, isTrue);

      expect(locationStyle.otherBubbleColor, const Color(0x993A3942));
      expect(locationStyle.selfBubbleColor, const Color(0x99C41F2E));
      expect(
        locationStyle.systemMessageBackgroundColor,
        const Color(0x14FFFFFF),
      );
      expect(locationStyle.bubbleBackdropBlurSigma, 14);
      expect(locationStyle.useConfiguredScenePlateSystemStyle, isFalse);
    },
  );

  testWidgets('opening narrator renders its configured dark surface', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'opening-narrator',
              senderId: 'narrator',
              senderName: 'Narrator',
              senderType: 'narrator',
              text: 'The story begins.',
              isMe: false,
              status: 'sent',
            ),
            showDateDivider: false,
            style: kOpeningDialogueStyle,
          ),
        ),
      ),
    );

    final bubble = tester.widget<Container>(
      find.byKey(const ValueKey('chat-system-message-bubble')),
    );
    expect((bubble.decoration as BoxDecoration).color, const Color(0xE6111111));
    final narratorIcon = tester.widget<SvgPicture>(
      find.descendant(
        of: find.byType(ChatSystemMessage),
        matching: find.byType(SvgPicture),
      ),
    );
    expect(
      narratorIcon.colorFilter,
      const ColorFilter.mode(Color(0xBAFFFFFF), BlendMode.srcIn),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('location chat uses the scene bubble palette and geometry', (
    WidgetTester tester,
  ) async {
    final style = kLocationChatStyle;
    expect(
      style.bubblePadding,
      const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    );
    expect(style.bubbleTextStyle.fontSize, 14);
    expect(style.bubbleTextStyle.height, 1.4);
    expect(style.senderNameTextStyle.fontSize, 11);
    expect(style.senderNameTextStyle.fontWeight, FontWeight.w600);
    expect(style.senderNameBottomGap, 6);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ChatMessageRow(
                message: ChatMessageVm(
                  localId: 'scene-self',
                  senderId: 'me',
                  senderName: 'Me',
                  text: 'Self message',
                  isMe: true,
                  status: 'sent',
                ),
                showDateDivider: false,
                style: style,
              ),
              ChatMessageRow(
                message: ChatMessageVm(
                  localId: 'scene-ai',
                  senderId: 'ai',
                  senderName: 'AI Role',
                  senderType: 'character',
                  currentTime: '12:34',
                  text: 'AI message',
                  isMe: false,
                  status: 'sent',
                ),
                showDateDivider: false,
                style: style,
              ),
              ChatMessageRow(
                message: ChatMessageVm(
                  localId: 'scene-player',
                  senderId: 'player',
                  senderName: 'Player Role',
                  senderType: 'character',
                  text: 'Player message',
                  isMe: false,
                  isPlayerControlledRole: true,
                  status: 'sent',
                ),
                showDateDivider: false,
                style: style,
              ),
            ],
          ),
        ),
      ),
    );

    BoxDecoration bubbleDecoration(String localId) {
      return tester
              .widget<Container>(
                find.byKey(ValueKey<String>('chat-message-bubble-$localId')),
              )
              .decoration!
          as BoxDecoration;
    }

    final self = bubbleDecoration('scene-self');
    expect(self.color, const Color(0x99C41F2E));
    expect(
      self.borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(14),
        topRight: Radius.circular(2),
        bottomRight: Radius.circular(14),
        bottomLeft: Radius.circular(14),
      ),
    );
    final ai = bubbleDecoration('scene-ai');
    expect(ai.color, const Color(0x993A3942));
    expect(
      ai.borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(2),
        topRight: Radius.circular(14),
        bottomRight: Radius.circular(14),
        bottomLeft: Radius.circular(14),
      ),
    );
    final player = bubbleDecoration('scene-player');
    expect(player.color, const Color(0x993A3942));
    expect(
      player.borderRadius,
      const BorderRadius.only(
        topLeft: Radius.zero,
        topRight: Radius.circular(14),
        bottomRight: Radius.circular(14),
        bottomLeft: Radius.circular(14),
      ),
    );
    final bubbleBackdrops = tester
        .widgetList<BackdropFilter>(find.byType(BackdropFilter))
        .toList(growable: false);
    expect(bubbleBackdrops, hasLength(2));
    for (final backdrop in bubbleBackdrops) {
      expect(backdrop.filter, isNull);
      expect(
        backdrop.filterConfig,
        const ImageFilterConfig.blur(sigmaX: 14, sigmaY: 14, bounded: false),
      );
      expect(backdrop.child, isA<Container>());
    }

    final aiName = tester.widget<Text>(
      find.byKey(const ValueKey<String>('chat-sender-name-scene-ai')),
    );
    final aiTime = tester.widget<Text>(
      find.byKey(const ValueKey<String>('chat-sender-time-scene-ai')),
    );
    final playerName = tester.widget<Text>(
      find.byKey(const ValueKey<String>('chat-sender-name-scene-player')),
    );
    expect(aiName.style?.color, const Color(0xFFF4F3F6));
    expect(
      find.byKey(const ValueKey<String>('chat-sender-name-scene-self')),
      findsNothing,
    );
    expect(aiTime.style?.fontSize, 10);
    expect(aiTime.style?.color?.a, closeTo(0.45, 0.001));
    expect(playerName.style?.color, aiName.style?.color);
  });

  testWidgets('ordinary bubble caps affect self and other but not system', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const longText =
        'This is a deliberately long message that needs the full available '
        'message column before it wraps onto additional lines.';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: Column(
              children: [
                ChatMessageRow(
                  message: ChatMessageVm(
                    localId: 'capped-self',
                    senderId: 'me',
                    senderName: 'Me',
                    text: longText,
                    isMe: true,
                    status: 'sent',
                  ),
                  showDateDivider: false,
                  selfMessageBubbleMaxWidthCap: 180,
                  otherMessageBubbleMaxWidthCap: 200,
                  style: kLocationChatStyle,
                ),
                ChatMessageRow(
                  message: ChatMessageVm(
                    localId: 'uncapped-other',
                    senderId: 'other',
                    senderName: 'Other',
                    text: longText,
                    isMe: false,
                    status: 'sent',
                  ),
                  showDateDivider: false,
                  selfMessageBubbleMaxWidthCap: 180,
                  otherMessageBubbleMaxWidthCap: 200,
                  style: kLocationChatStyle,
                ),
                ChatMessageRow(
                  message: ChatMessageVm.system(longText),
                  showDateDivider: false,
                  selfMessageBubbleMaxWidthCap: 180,
                  otherMessageBubbleMaxWidthCap: 200,
                  style: kLocationChatStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final selfBubble = tester.getSize(
      find.byKey(const ValueKey<String>('chat-message-bubble-capped-self')),
    );
    final otherBubble = tester.getSize(
      find.byKey(const ValueKey<String>('chat-message-bubble-uncapped-other')),
    );
    final systemBubble = tester.getSize(
      find.byKey(const ValueKey('chat-system-message-bubble')),
    );

    expect(selfBubble.width, closeTo(180, 0.01));
    expect(otherBubble.width, closeTo(200, 0.01));
    expect(systemBubble.width, greaterThan(200));
  });

  testWidgets('location chat header left aligns title and subtitle rows', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatHeader(
            title: 'Googleplex园区 (1)',
            subtitle:
                'Mark Zuckerberg, Ada Lovelace, Grace Hopper, Alan Turing',
            connected: true,
            connecting: false,
            onBack: () {},
            alignContentLeft: true,
            style: kLocationChatStyle,
            subtitleIconAsset: characterStatIconAsset,
            trailing: MemoryModelEntryButton(
              modelLabel: 'top_pick_v3_5',
              darkHeader: true,
              compact: true,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    final titleIconFinder = find.byIcon(Icons.place_outlined);
    final titleIcon = tester.widget<Icon>(titleIconFinder);
    final titleIconRect = tester.getRect(titleIconFinder);
    final subtitleIconRect = tester.getRect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains(characterStatIconAsset),
      ),
    );
    final titleRect = tester.getRect(find.text('Googleplex园区 (1)'));
    final subtitleRect = tester.getRect(
      find.text('Mark Zuckerberg, Ada Lovelace, Grace Hopper, Alan Turing'),
    );
    final modelRect = tester.getRect(
      find.byKey(const ValueKey('memory-model-entry')),
    );
    final headerRect = tester.getRect(find.byType(ChatHeader));
    expect(titleIconRect.left, closeTo(48, 1));
    expect(titleIcon.color, Colors.white.withValues(alpha: 0.45));
    expect(subtitleIconRect.left, closeTo(titleIconRect.left, 1));
    expect(modelRect.right, closeTo(headerRect.right, 1));
    expect(modelRect.center.dy, closeTo(titleRect.center.dy + 2, 1));
    expect(subtitleRect.right, greaterThan(modelRect.left));
  });

  testWidgets('location chat title uses the model entry intrinsic width', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatHeader(
            title: 'The Wisteria Terrace With A Long Name (1)',
            subtitle: '',
            connected: true,
            connecting: false,
            onBack: () {},
            showSubtitle: false,
            alignContentLeft: true,
            style: kLocationChatStyle,
            trailing: MemoryModelEntryButton(
              modelLabel: 'M',
              darkHeader: true,
              compact: true,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    final titleRect = tester.getRect(
      find.text('The Wisteria Terrace With A Long Name (1)'),
    );
    final modelRect = tester.getRect(
      find.byKey(const ValueKey('memory-model-entry')),
    );

    expect(modelRect.width, kMemoryModelEntryMinWidth);
    expect(titleRect.right, closeTo(modelRect.left, 0.01));
    expect(titleRect.width, closeTo(393 - 48 - 16 - 4 - 82, 0.01));
  });

  testWidgets(
    'location chat title icon centers in header and matches parent color',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatHeader(
              title: 'Current location',
              titleOverline: 'Parent location',
              subtitle: '',
              connected: true,
              connecting: false,
              onBack: () {},
              showSubtitle: false,
              showTitleIcon: true,
              alignContentLeft: true,
              style: kLocationChatStyle,
            ),
          ),
        ),
      );

      final titleRect = tester.getRect(find.text('Current location'));
      final parentRect = tester.getRect(find.text('Parent location'));
      final titleIcon = tester.widget<Icon>(find.byIcon(Icons.place_outlined));
      final titleIconRect = tester.getRect(find.byIcon(Icons.place_outlined));
      final backIconRect = tester.getRect(
        find.byIcon(Icons.arrow_back_ios_new),
      );
      final parentText = tester.widget<Text>(find.text('Parent location'));
      expect(parentRect.left, closeTo(titleRect.left, 0.01));
      expect(titleIconRect.center.dy, closeTo(backIconRect.center.dy, 0.01));
      expect(titleIcon.color, parentText.style?.color);
    },
  );

  testWidgets('private chat style hides peer name', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'peer',
              senderName: 'Peer Name',
              text: 'hello',
              isMe: false,
              status: 'sent',
            ),
            showDateDivider: false,
            style: kPrivateChatStyle,
          ),
        ),
      ),
    );

    expect(find.text('Peer Name'), findsNothing);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('chat row sanitizes malformed UTF-16 text before layout', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'bad-utf16',
              senderId: 'peer',
              senderName: 'bad \uD800 name',
              text: 'hello \uD800 world',
              currentTime: 'time \uDC00',
              isMe: false,
              status: 'sent',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('bad \uFFFD name'), findsOneWidget);
    expect(find.text('time \uFFFD'), findsOneWidget);
  });

  testWidgets('player controlled chat avatar uses highlighted border', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'peer',
              senderName: 'Peer Name',
              text: 'hello',
              isMe: false,
              isPlayerControlledRole: true,
              status: 'sent',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate((widget) {
        if (widget is! DecoratedBox) return false;
        final decoration = widget.decoration;
        if (decoration is! BoxDecoration) return false;
        final border = decoration.border;
        if (border is! Border) return false;
        return border.top.color == GenesisColors.brand;
      }),
      findsOneWidget,
    );
  });

  testWidgets('self player controlled chat avatar has no highlighted border', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'self-player-role',
              senderId: 'me',
              senderName: 'Me',
              text: 'hello',
              isMe: true,
              isPlayerControlledRole: true,
              status: 'sent',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(ChatAvatar),
        matching: find.byWidgetPredicate((widget) {
          if (widget is! DecoratedBox) return false;
          final decoration = widget.decoration;
          return decoration is BoxDecoration && decoration.border != null;
        }),
      ),
      findsNothing,
    );
  });

  testWidgets('player controlled chat sender name uses highlighted color', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'peer',
              senderName: 'Peer Name',
              text: 'hello',
              isMe: false,
              isPlayerControlledRole: true,
              status: 'sent',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    final name = tester.widget<Text>(find.text('Peer Name'));
    expect(name.style?.color, GenesisColors.brand);
  });

  testWidgets('self chat message places avatar on the right', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'me',
              senderName: 'Me',
              text: 'hello',
              isMe: true,
              status: 'sent',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    final bubbleRight = tester.getTopRight(find.byType(ChatMessageBubble)).dx;
    final avatarLeft = tester.getTopLeft(find.byType(ChatAvatar)).dx;
    expect(avatarLeft, greaterThan(bubbleRight));
  });

  testWidgets('chat message avatar renders image url before fallback', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'peer',
              senderName: 'Peer',
              avatarUrl: 'assets/images/default_list_image.png',
              text: 'hello',
              isMe: false,
              status: 'sent',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/default_list_image.png',
      ),
      findsOneWidget,
    );
  });

  testWidgets('chat message avatar renders generated fallback for empty url', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'peer',
              senderName: 'Peer Name',
              text: 'hello',
              isMe: false,
              status: 'sent',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    expect(find.text('PN'), findsOneWidget);
  });

  testWidgets('char npc message renders fixed NPC avatar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'char_npc',
              senderName: 'Village Guide',
              text: 'hello',
              isMe: false,
              status: 'sent',
            ),
            showDateDivider: false,
            style: kLocationChatStyle,
          ),
        ),
      ),
    );

    final avatarFinder = find.byKey(const ValueKey('chat-npc-avatar'));
    expect(avatarFinder, findsOneWidget);
    expect(tester.getSize(avatarFinder), const Size(40, 40));
    expect(find.text('NPC'), findsOneWidget);
    expect(find.text('VG'), findsNothing);

    final avatarBox = tester.widget<DecoratedBox>(
      find.descendant(of: avatarFinder, matching: find.byType(DecoratedBox)),
    );
    final decoration = avatarBox.decoration as BoxDecoration;
    expect(decoration.color, const Color(0x24FFFFFF));
    expect(decoration.shape, BoxShape.circle);
    expect(
      decoration.border,
      const Border.fromBorderSide(
        BorderSide(color: Color(0x2EFFFFFF), width: 1),
      ),
    );

    final label = tester.widget<Text>(find.text('NPC'));
    expect(label.style?.color, Colors.white);
    expect(label.style?.fontWeight, FontWeight.w800);
  });

  testWidgets('chat message bubble parses markdown italic text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'peer',
              senderName: 'Peer',
              text: 'hello *quietly*',
              isMe: false,
              status: 'sent',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    expect(find.text('hello quietly'), findsOneWidget);
    final bubbleText = tester.widget<Text>(
      find.descendant(
        of: find.byType(ChatMessageBubble),
        matching: find.byType(Text),
      ),
    );
    expect(_textHasItalicFragment(bubbleText, 'quietly'), isTrue);
    expect(_textFragmentColor(bubbleText, 'quietly'), const Color(0xFF888888));
  });

  testWidgets('self chat markdown uses the AI emphasis color', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'me',
              senderName: 'Me',
              text: '*historical role message*',
              isMe: true,
              status: 'sent',
              senderType: 'character',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    final bubbleText = tester.widget<Text>(
      find.descendant(
        of: find.byType(ChatMessageBubble),
        matching: find.byType(Text),
      ),
    );
    expect(
      _textFragmentColor(bubbleText, 'historical role message'),
      const Color(0xFF888888),
    );
  });

  testWidgets('chat markdown preserves backslash text', (
    WidgetTester tester,
  ) async {
    const raw = r'value\tend\\slash\u1234\*';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageBubble(
            message: ChatMessageVm(
              localId: 'escaped-message',
              senderId: 'me',
              senderName: 'Me',
              text: raw,
              isMe: true,
              status: 'sent',
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(ChatMessageBubble),
        matching: find.byType(Text),
      ),
    );
    expect(text.textSpan?.toPlainText(), raw);
  });

  testWidgets(
    'chat message bubble uses decorative unicode visual fallback text',
    (WidgetTester tester) async {
      const raw = '☛ ˙۵ও⃢♥︎ ━  𝙏ᶦⁿᶦᵗᵃ 🍓|🎀〬𓈒ֹ⁠꙳';
      const rendered = '☛ ˙۵▤▤▤♥︎ ━  𝙏ᶦⁿᶦᵗᵃ 🍓|🎀°ₒ✩';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: ChatMessageVm(
                localId: 'unicode-message',
                senderId: 'me',
                senderName: 'Me',
                text: raw,
                isMe: true,
                status: 'sent',
              ),
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(ChatMessageBubble),
          matching: find.byType(Text),
        ),
      );
      expect(text.textSpan?.toPlainText(), rendered);
      expect(text.textSpan?.style?.fontFamily, GenesisTypography.fontFamily);
      expect(
        text.textSpan?.style?.fontFamilyFallback,
        GenesisTypography.fontFamilyFallback,
      );
    },
  );

  testWidgets('chat message bubble uses Inter markdown emphasis on iOS', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'peer',
              senderName: 'Peer',
              text: 'hello *quietly*',
              isMe: false,
              status: 'sent',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    final style = _firstTextFragmentStyle(
      tester.widgetList<Text>(
        find.descendant(
          of: find.byType(ChatMessageBubble),
          matching: find.byType(Text),
        ),
      ),
      'quietly',
    );
    expect(style?.fontStyle, FontStyle.italic);
    expect(style?.color, const Color(0xFF888888));
    expect(
      find.descendant(
        of: find.byType(ChatMessageBubble),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('chat message bubble keeps iOS emphasis in one Inter span', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'peer',
              senderName: 'Peer',
              text: 'hello *quietly now*',
              isMe: false,
              status: 'sent',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    final style = _firstTextFragmentStyle(
      tester.widgetList<Text>(
        find.descendant(
          of: find.byType(ChatMessageBubble),
          matching: find.byType(Text),
        ),
      ),
      'quietly now',
    );

    expect(style?.fontStyle, FontStyle.italic);
    expect(
      find.descendant(
        of: find.byType(ChatMessageBubble),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('chat rows reserve matching avatar space on both sides', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: Column(
              children: [
                ChatMessageRow(
                  message: ChatMessageVm(
                    localId: 'other',
                    senderId: 'peer',
                    senderName: 'Peer',
                    text: 'left',
                    isMe: false,
                    status: 'sent',
                  ),
                  showDateDivider: false,
                ),
                ChatMessageRow(
                  message: ChatMessageVm(
                    localId: 'me',
                    senderId: 'me',
                    senderName: 'Me',
                    text: 'right',
                    isMe: true,
                    status: 'sent',
                  ),
                  showDateDivider: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final rows = find.byType(ChatMessageRow);
    final otherRow = tester.getRect(rows.at(0));
    final meRow = tester.getRect(rows.at(1));
    final bubbles = find.byType(ChatMessageBubble);
    final otherBubble = tester.getRect(bubbles.at(0));
    final meBubble = tester.getRect(bubbles.at(1));
    final reservedWidth =
        ChatUiStyleConfig.standard.avatarSize +
        ChatUiStyleConfig.standard.avatarBubbleGap;

    expect(
      otherBubble.right,
      lessThanOrEqualTo(otherRow.right - reservedWidth),
    );
    expect(meBubble.left, greaterThanOrEqualTo(meRow.left + reservedWidth));
  });

  testWidgets('character chat avatar omits redstar icon badge', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'character',
              senderName: 'Guide',
              text: 'hello',
              isMe: false,
              status: 'sent',
              senderType: 'character',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    expect(find.byType(ChatAiBadge), findsNothing);
  });

  testWidgets('system chat message uses normal bubble width and centers', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm.system(
              'A long narrator message that should be constrained like normal chat bubbles.',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    final systemBox = tester.getRect(find.byType(ChatSystemMessage));
    final bubbleBox = tester.getRect(
      find.byKey(const ValueKey('chat-system-message-bubble')),
    );
    final reservedWidth =
        ChatUiStyleConfig.standard.avatarSize +
        ChatUiStyleConfig.standard.avatarBubbleGap;
    expect(bubbleBox.width, lessThanOrEqualTo(400 - reservedWidth * 2 + 1));
    expect(bubbleBox.center.dx, closeTo(systemBox.center.dx, 1));
    final text = tester.widget<Text>(
      find.text(
        'A long narrator message that should be constrained like normal chat bubbles.',
      ),
    );
    expect(text.maxLines, isNull);
    expect(text.overflow, isNull);
  });

  testWidgets('narrator system message parses star markdown italic text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'narrator',
              senderName: 'Narrator',
              text: 'The room grows *cold*.',
              isMe: false,
              status: 'sent',
              senderType: 'narrator',
            ),
            showDateDivider: false,
            style: kLocationChatStyle,
          ),
        ),
      ),
    );

    expect(find.text('The room grows cold.'), findsOneWidget);
    final systemText = tester.widget<Text>(
      find.descendant(
        of: find.byType(ChatSystemMessage),
        matching: find.byType(Text),
      ),
    );
    expect(_textHasItalicFragment(systemText, 'cold'), isTrue);
    expect(
      _textFragmentColor(systemText, 'cold'),
      systemText.textSpan?.style?.color,
    );
    expect(
      _textFragmentColor(systemText, 'cold'),
      isNot(const Color(0xFF888888)),
    );
    expect(systemText.textSpan?.style?.fontSize, 14);
    expect(_textFragmentStyle(systemText, 'cold')?.fontSize, 14);
  });

  testWidgets('location chat keeps avatars aligned and bars one-third in', (
    WidgetTester tester,
  ) async {
    final style = kLocationChatStyle;
    final expectedOuterPadding = 10.0;
    final expectedInnerPadding = ChatUiStyleConfig.standard.avatarSize / 3;
    final expectedBubbleEdge = expectedOuterPadding + expectedInnerPadding;

    expect(style.conversationBackgroundColor, const Color(0xFF151517));
    expect(style.conversationBackgroundColor.a, 1);
    expect(style.messageListPadding.left, expectedOuterPadding);
    expect(style.messageListPadding.right, expectedOuterPadding);
    expect(style.avatarSideSpacerWidth, closeTo(expectedInnerPadding, 0.01));
    expect(style.systemMessageMargin.left, 0);
    expect(style.systemMessageMargin.right, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: Padding(
              padding: style.messageListPadding,
              child: Column(
                children: [
                  ChatMessageRow(
                    message: ChatMessageVm(
                      localId: 'me',
                      senderId: 'me',
                      senderName: 'Me',
                      text: List.filled(24, 'wide').join(' '),
                      isMe: true,
                      status: 'sent',
                    ),
                    showDateDivider: false,
                    style: style,
                  ),
                  ChatMessageRow(
                    message: ChatMessageVm(
                      localId: 'other',
                      senderId: 'peer',
                      senderName: 'Peer',
                      text: List.filled(24, 'wide').join(' '),
                      isMe: false,
                      status: 'sent',
                    ),
                    showDateDivider: false,
                    style: style,
                  ),
                  ChatMessageRow(
                    message: ChatMessageVm(
                      localId: 'narrator',
                      senderId: 'nar',
                      senderName: '旁白',
                      text: 'A full width narrator bar.',
                      isMe: false,
                      status: 'sent',
                      senderType: 'narrator',
                    ),
                    showDateDivider: false,
                    style: style,
                  ),
                  ChatMessageRow(
                    message: ChatMessageVm(
                      localId: 'tick',
                      senderId: 'tick',
                      senderName: 'Time',
                      text: 'Day 45, 19:34',
                      isMe: false,
                      status: 'sent',
                      senderType: 'tick',
                      tickNo: 7,
                    ),
                    showDateDivider: false,
                    style: style,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final avatars = find.byType(ChatAvatar);
    final bubbles = find.byType(ChatMessageBubble);
    final meAvatar = tester.getRect(avatars.at(0));
    final otherAvatar = tester.getRect(avatars.at(1));
    final meBubble = tester.getRect(bubbles.at(0));
    final otherBubble = tester.getRect(bubbles.at(1));
    final narratorBar = tester.getRect(
      find.byKey(const ValueKey('chat-system-message-bubble')),
    );
    final tickBar = tester.getRect(
      find.byKey(const ValueKey('chat-tick-message-bubble')),
    );
    final narratorText = tester.getRect(
      find.text('A full width narrator bar.'),
    );
    final tickText = tester.getRect(find.text('Tick 7 · Day 45, 19:34'));

    expect(meAvatar.right, closeTo(400 - expectedOuterPadding, 1));
    expect(otherAvatar.left, closeTo(expectedOuterPadding, 1));
    expect(meBubble.left, closeTo(expectedBubbleEdge, 1));
    expect(otherBubble.right, closeTo(400 - expectedBubbleEdge, 1));
    expect(narratorBar.left, closeTo(expectedOuterPadding, 1));
    expect(narratorBar.right, closeTo(400 - expectedOuterPadding, 1));
    final narratorDecoration =
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('chat-system-message-bubble')),
                )
                .decoration!
            as BoxDecoration;
    expect(narratorDecoration.color, const Color(0x80151517));
    expect(narratorDecoration.borderRadius, BorderRadius.circular(8));
    expect(tickBar.left, closeTo(expectedOuterPadding, 1));
    expect(tickBar.right, closeTo(400 - expectedOuterPadding, 1));
    expect(
      narratorText.left,
      closeTo(
        expectedOuterPadding + style.systemMessagePadding.left + 13 + 9,
        1,
      ),
    );
    expect(tickText.left, closeTo(expectedBubbleEdge + 14, 1));
  });

  testWidgets('underscore markdown remains plain text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'narrator',
              senderName: 'Narrator',
              text: 'The room grows _cold_.',
              isMe: false,
              status: 'sent',
              senderType: 'narrator',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    expect(find.text('The room grows _cold_.'), findsOneWidget);
  });

  testWidgets('narrator system message text is left aligned', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'nar-1',
              senderId: 'nar',
              senderName: '旁白',
              text: 'A narrator paragraph can wrap across multiple lines.',
              isMe: false,
              status: 'sent',
              senderType: 'narrator',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(
      find.text('A narrator paragraph can wrap across multiple lines.'),
    );
    expect(text.maxLines, isNull);
    expect(text.overflow, isNull);
    expect(text.textAlign, TextAlign.left);
  });

  testWidgets('real newlines render in user and narrator messages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ChatMessageRow(
                message: ChatMessageVm(
                  localId: 'peer-1',
                  senderId: 'peer',
                  senderName: 'Peer',
                  text: 'First\n\nSecond',
                  isMe: false,
                  status: 'sent',
                ),
                showDateDivider: false,
              ),
              ChatMessageRow(
                message: ChatMessageVm(
                  localId: 'nar-1',
                  senderId: 'narrator',
                  senderName: 'Narrator',
                  text: 'Aside\n\nContinues',
                  isMe: false,
                  status: 'sent',
                  senderType: 'narrator',
                ),
                showDateDivider: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('First\n\nSecond'), findsOneWidget);
    expect(find.text('Aside\n\nContinues'), findsOneWidget);
  });

  testWidgets('chat markdown does not restore escaped backslash layers', (
    WidgetTester tester,
  ) async {
    const raw = r'double\\n stays literal';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageBubble(
            message: ChatMessageVm(
              localId: 'double-backslash-message',
              senderId: 'me',
              senderName: 'Me',
              text: raw,
              isMe: true,
              status: 'sent',
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(ChatMessageBubble),
        matching: find.byType(Text),
      ),
    );
    expect(text.textSpan?.toPlainText(), raw);
  });

  testWidgets('message and narrator bubbles report long press starts', (
    WidgetTester tester,
  ) async {
    final pressed = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ChatMessageRow(
                message: ChatMessageVm(
                  localId: 'peer-1',
                  senderId: 'peer',
                  senderName: 'Peer',
                  text: 'Peer message',
                  isMe: false,
                  status: 'sent',
                ),
                showDateDivider: false,
                onMessageLongPressStart: (_, message, _) {
                  pressed.add(message.localId);
                },
              ),
              ChatMessageRow(
                message: ChatMessageVm(
                  localId: 'nar-1',
                  senderId: 'narrator',
                  senderName: 'Narrator',
                  text: 'Narrator message',
                  isMe: false,
                  status: 'sent',
                  senderType: 'narrator',
                ),
                showDateDivider: false,
                onMessageLongPressStart: (_, message, _) {
                  pressed.add(message.localId);
                },
              ),
            ],
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Peer message'));
    await tester.pump();
    await tester.longPress(find.text('Narrator message'));
    await tester.pump();

    expect(pressed, ['peer-1', 'nar-1']);
  });

  testWidgets('tick system message spans avatar-edge width with tick label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ChatMessageRow(
              message: ChatMessageVm(
                localId: 'tick-112',
                senderId: 'tick',
                senderName: 'Time',
                text: 'Day 45, 19:34',
                isMe: false,
                status: 'sent',
                senderType: 'tick',
                roundId: '1455',
                tickNo: 7,
                subTickNo: 1,
              ),
              showDateDivider: false,
            ),
          ),
        ),
      ),
    );

    final rowBox = tester.getRect(find.byType(ChatMessageRow));
    final bubbleBox = tester.getRect(
      find.byKey(const ValueKey('chat-tick-message-bubble')),
    );

    expect(find.text('Tick 7-1 · Day 45, 19:34'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Tick 7-1 · Day 45, 19:34'));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.textAlign, TextAlign.left);
    expect(bubbleBox.left, closeTo(rowBox.left, 1));
    expect(bubbleBox.right, closeTo(rowBox.right, 1));
  });

  testWidgets('tick system message includes zero tick number', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'tick-zero-one',
              senderId: 'tick',
              senderName: 'Time',
              text: 'Day 1, 20:25',
              isMe: false,
              status: 'sent',
              senderType: 'tick',
              tickNo: 0,
              subTickNo: 1,
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    expect(find.text('Tick 0-1 · Day 1, 20:25'), findsOneWidget);
  });

  testWidgets(
    'tick progress uses the tick surface with title and avatars only',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageRow(
              message: ChatMessageVm(
                localId: 'tick-progress',
                senderId: 'tick',
                senderName: 'Time',
                text: '',
                isMe: false,
                status: 'progressing',
                senderType: 'tick',
                timelinePayload: const ChatTickProgressPayloadVm(
                  title: 'Progressing the World',
                  avatars: [
                    ChatTickProgressAvatarVm(
                      name: 'Guide',
                      url: 'assets/images/default_list_image.png',
                    ),
                  ],
                ),
              ),
              showDateDivider: false,
              style: kLocationChatStyle,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('chat-tick-message-surface')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('chat-tick-message-accent')),
        findsNothing,
      );
      expect(find.textContaining('Progressing the World'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('chat-tick-progress-title')),
            )
            .style
            ?.fontSize,
        13,
      );
      expect(
        find.image(const AssetImage('assets/images/default_list_image.png')),
        findsOneWidget,
      );
      expect(find.textContaining('Compressing recent memories'), findsNothing);
      expect(find.textContaining('Advancing the world timeline'), findsNothing);
      expect(
        find.textContaining('Generating the next story beat'),
        findsNothing,
      );
      expect(find.textContaining('Updating character locations'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'composite tick renders every non-empty section in order and forwards actions',
    (WidgetTester tester) async {
      ChatCharacterMovementVm? tappedMovement;
      ChatMessageVm? longPressedMessage;
      final message = ChatMessageVm(
        localId: 'tick-composite',
        globalMessageId: 8702,
        messageId: 101,
        locationMessageId: 29,
        roundId: '7359',
        tickNo: 1,
        subTickNo: 2,
        senderId: 'tick',
        senderName: 'SubTick',
        text: '',
        currentTime: 'Day 1, 13:50',
        isMe: false,
        status: 'sent',
        senderType: 'tick',
        timelinePayload: const ChatTickPayloadVm(
          globalText: 'The promise-shaped key pulses.',
          storyEvents: ChatStoryEventsPayloadVm(
            locationId: 'loc_vault',
            locationName: 'Vault',
            paragraphs: [
              ChatStoryEventParagraphVm(
                timestamp: 'Day 1, 13:30',
                text: 'Frost creeps toward Room 0.',
                clue: 'It spells Elara.',
                visibilityLabel: 'public',
              ),
            ],
          ),
          charactersMoved: ChatCharactersMovedPayloadVm(
            movements: [
              ChatCharacterMovementVm(
                characterId: 'char_2',
                characterName: 'Elara',
                toLocationId: 'loc_room_0',
                toLocationName: 'Room 0',
              ),
              ChatCharacterMovementVm(
                characterId: 'char_3',
                characterName: 'Lyra',
                toLocationId: 'loc_room_0',
                toLocationName: 'Room 0',
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: ChatMessageRow(
                message: message,
                showDateDivider: false,
                style: kLocationChatStyle,
                onMessageLongPressStart: (_, pressedMessage, _) {
                  longPressedMessage = pressedMessage;
                },
                onCharactersMovedLocationTap: (movement) {
                  tappedMovement = movement;
                },
              ),
            ),
          ),
        ),
      );

      final header = find.text('Tick 1-2');
      final globalSection = find.byKey(
        const ValueKey<String>('chat-tick-global-section'),
      );
      final globalText = find.descendant(
        of: globalSection,
        matching: find.byWidgetPredicate(
          (widget) => widget is Text && widget.textSpan != null,
        ),
      );
      final eventText = find.text('Frost creeps toward Room 0.');
      final movementRow = find.byKey(
        const ValueKey<String>('chat-character-movement-tick-composite-tick-0'),
      );
      expect(
        find.byKey(const ValueKey<String>('chat-tick-message-bubble')),
        findsOneWidget,
      );
      expect(header, findsOneWidget);
      expect(find.text('Global'), findsNothing);
      expect(globalText, findsOneWidget);
      expect(
        tester.widget<Text>(globalText).textSpan?.style?.fontStyle,
        FontStyle.italic,
      );
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
      final tickBubble = tester.widget<Container>(
        find.byKey(const ValueKey<String>('chat-tick-message-surface')),
      );
      final tickDecoration = tickBubble.decoration! as BoxDecoration;
      expect(tickDecoration.color, const Color(0x99151517));
      expect(tickDecoration.borderRadius, BorderRadius.circular(10));
      expect(tickDecoration.border, Border.all(color: const Color(0x33FFFFFF)));
      final tickAccent = find.byKey(
        const ValueKey<String>('chat-tick-message-accent'),
      );
      expect(tickAccent, findsNothing);
      expect(
        tester
            .widget<Container>(
              find.byKey(const ValueKey<String>('chat-tick-header-dot')),
            )
            .decoration,
        const BoxDecoration(color: Color(0xFFFF2442), shape: BoxShape.circle),
      );
      expect(tester.widget<Text>(header).style?.color, const Color(0xFFF4F3F6));
      expect(
        find.descendant(
          of: globalSection,
          matching: find.byIcon(Icons.public_rounded),
        ),
        findsNothing,
      );
      expect(tester.widget<Text>(header).style?.fontWeight, FontWeight.w600);
      expect(
        find.descendant(
          of: globalSection,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SvgPicture &&
                widget.bytesLoader.toString().contains(paragraphIconAsset),
          ),
        ),
        findsNothing,
      );
      expect(
        tester.widget<Text>(globalText).textSpan?.style?.color,
        Colors.white.withValues(alpha: 0.73),
      );
      expect(
        find.descendant(of: globalSection, matching: find.byType(Transform)),
        findsNothing,
      );
      expect(find.text('Event'), findsNothing);
      expect(find.text('Vault'), findsNothing);
      expect(find.text('public'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SvgPicture &&
              widget.bytesLoader.toString().contains(eventsIconAsset),
        ),
        findsOneWidget,
      );
      final movementSection = tester.widget<Container>(
        find.byKey(const ValueKey<String>('chat-tick-movement-section')),
      );
      expect(
        (movementSection.decoration! as BoxDecoration).border,
        const Border(top: BorderSide(color: Color(0x29FFFFFF))),
      );
      expect(eventText, findsOneWidget);
      final clueText = find.text('It spells Elara.');
      expect(clueText, findsOneWidget);
      expect(
        tester.widget<Text>(clueText).textSpan?.style?.fontStyle,
        FontStyle.italic,
      );
      expect(
        find.ancestor(of: clueText, matching: find.byType(Transform)),
        findsNothing,
      );
      expect(find.text('Character destinations'), findsNothing);
      expect(movementRow, findsOneWidget);
      expect(find.text('Elara, Lyra'), findsOneWidget);
      expect(find.text('went to'), findsOneWidget);
      expect(find.text('Room 0'), findsOneWidget);
      expect(
        tester.getTopLeft(header).dy,
        lessThan(tester.getTopLeft(globalSection).dy),
      );
      expect(
        tester.getTopLeft(globalSection).dy,
        lessThan(tester.getTopLeft(eventText).dy),
      );
      expect(
        tester.getTopLeft(eventText).dy,
        lessThan(tester.getTopLeft(movementRow).dy),
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'chat-character-movement-location-tick-composite-tick-0',
          ),
        ),
      );
      expect(tappedMovement?.toLocationId, 'loc_room_0');

      await tester.longPress(
        find.byKey(const ValueKey<String>('chat-tick-message-bubble')),
      );
      await tester.pump();
      expect(longPressedMessage, same(message));
      expect(
        chatTickMessageCopyText(message),
        'Tick 1-2 · Day 1, 13:50\n'
        'Global\n'
        'The promise-shaped key pulses.\n'
        'Event\n'
        'Day 1, 13:30 · public\n'
        'Frost creeps toward Room 0.\n'
        'It spells Elara.\n'
        'Character destinations\n'
        'Elara, Lyra went to Room 0',
      );
    },
  );

  testWidgets(
    'composite tick omits empty sections and renders fallback content',
    (WidgetTester tester) async {
      final message = ChatMessageVm(
        localId: 'tick-fallback',
        senderId: 'tick',
        senderName: 'SubTick',
        text: 'Original tick content',
        isMe: false,
        status: 'sent',
        senderType: 'tick',
        timelinePayload: const ChatTickPayloadVm(
          fallbackContent: 'Original tick content',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageRow(message: message, showDateDivider: false),
          ),
        ),
      );

      expect(find.text('Tick 0'), findsOneWidget);
      expect(find.text('Original tick content'), findsOneWidget);
      expect(find.text('Global'), findsNothing);
      expect(find.text('Event'), findsNothing);
      expect(find.text('Character destinations'), findsNothing);
      expect(chatTickMessageCopyText(message), 'Tick 0\nOriginal tick content');
    },
  );

  testWidgets('tick global uses Inter italic for iOS multiline content', (
    WidgetTester tester,
  ) async {
    const globalValue =
        'First signal crosses the valley while the second signal follows.';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: ChatMessageRow(
              message: ChatMessageVm(
                localId: 'tick-global-multiline',
                senderId: 'tick',
                senderName: 'Tick',
                text: '',
                isMe: false,
                status: 'sent',
                senderType: 'tick',
                timelinePayload: const ChatTickPayloadVm(
                  globalText: globalValue,
                ),
              ),
              showDateDivider: false,
              style: kLocationChatStyle,
            ),
          ),
        ),
      ),
    );

    final globalSection = find.byKey(
      const ValueKey<String>('chat-tick-global-section'),
    );
    final richText = find.descendant(
      of: globalSection,
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan != null,
      ),
    );
    expect(richText, findsOneWidget);
    expect(tester.getSize(richText).height, greaterThan(30));
    expect(tester.widget<Text>(richText).semanticsLabel, isNull);
    expect(
      tester.widget<Text>(richText).textSpan?.style?.fontStyle,
      FontStyle.italic,
    );
    expect(
      find.ancestor(of: richText, matching: find.byType(Transform)),
      findsNothing,
    );
    expect(
      find.descendant(of: globalSection, matching: find.byType(Transform)),
      findsNothing,
    );
  });

  testWidgets('chat composer grows with text up to ten lines', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    final reportedHeights = <double>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              controller: controller,
              inputEnabled: true,
              sendEnabled: true,
              sending: false,
              onSend: () async {},
              onHeightChanged: reportedHeights.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final initialHeight = tester.getSize(find.byType(ChatComposer)).height;

    await tester.enterText(find.byType(TextField), 'one\ntwo\nthree');
    await tester.pump();
    await tester.pump();
    final threeLineHeight = tester.getSize(find.byType(ChatComposer)).height;

    await tester.enterText(
      find.byType(TextField),
      List.filled(10, 'x').join('\n'),
    );
    await tester.pump();
    await tester.pump();
    final tenLineHeight = tester.getSize(find.byType(ChatComposer)).height;

    await tester.enterText(
      find.byType(TextField),
      List.filled(12, 'x').join('\n'),
    );
    await tester.pump();
    await tester.pump();
    final twelveLineHeight = tester.getSize(find.byType(ChatComposer)).height;

    expect(threeLineHeight, greaterThan(initialHeight));
    expect(tenLineHeight, greaterThan(threeLineHeight));
    expect(twelveLineHeight, closeTo(tenLineHeight, 1));
    expect(reportedHeights.first, initialHeight);
    expect(reportedHeights, contains(threeLineHeight));
    expect(reportedHeights.last, closeTo(tenLineHeight, 1));
  });

  testWidgets('chat composer can keep send action pinned while input grows', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController(text: 'one');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              controller: controller,
              inputEnabled: true,
              sendEnabled: true,
              sending: false,
              onSend: () async {},
              leadingShortcutLabel: '*',
              onLeadingShortcutPressed: () {},
              sendIcon: ChatComposerSendIcon.arrowUp,
              pinActionsToBottom: true,
              style: kLocationChatStyle,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final sendButton = find.byKey(
      const ValueKey<String>('chat-composer-send-button'),
    );
    final initialBottom = tester.getBottomLeft(sendButton).dy;

    await tester.enterText(find.byType(TextField), 'one\ntwo\nthree\nfour');
    await tester.pump();

    expect(tester.getBottomLeft(sendButton).dy, closeTo(initialBottom, 0.01));
  });

  testWidgets('chat composer default only shows send action button', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController(text: 'hello');
    var sendCount = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            inputEnabled: true,
            sendEnabled: true,
            sending: false,
            onSend: () async {
              sendCount += 1;
            },
          ),
        ),
      ),
    );

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.keyboardType, TextInputType.multiline);
    expect(input.textInputAction, TextInputAction.newline);
    expect(input.onSubmitted, isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-composer-send-button'))),
      Size(
        ChatUiStyleConfig.standard.composerSendButtonWidth,
        ChatUiStyleConfig.standard.composerSendButtonHeight,
      ),
    );
    expect(
      find.byKey(const ValueKey('chat-composer-send-button')),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(
      ChatUiStyleConfig.standard.composerSendButtonColor,
      GenesisColors.brand,
    );
    expect(
      find.byWidgetPredicate((widget) {
        return widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                ChatUiStyleConfig.standard.composerSendButtonColor;
      }),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sendCount, 1);
  });

  testWidgets('chat composer preserves decorative unicode input', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    const raw = '☛ ˙۵ও⃢♥︎ ━  𝙏ᶦⁿᶦᵗᵃ 🍓|🎀〬𓈒ֹ⁠꙳';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            inputEnabled: true,
            sendEnabled: true,
            sending: false,
            onSend: () async {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), raw);
    await tester.pump();

    expect(controller.text, raw);
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.style?.fontFamily, GenesisTypography.fontFamily);
    expect(
      input.style?.fontFamilyFallback,
      GenesisTypography.fontFamilyFallback,
    );
  });

  testWidgets('chat composer send button keeps text field focused', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController(text: 'hello');
    var sendCount = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            inputEnabled: true,
            sendEnabled: true,
            sending: false,
            onSend: () async {
              sendCount += 1;
            },
          ),
        ),
      ),
    );

    await tester.showKeyboard(find.byType(TextField));
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sendCount, 1);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('chat composer keyboard sends when send button is hidden', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController(text: 'hello');
    final style = ChatUiStyleConfig.standard.copyWith(
      showComposerSendButton: false,
    );
    var sendCount = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            inputEnabled: true,
            sendEnabled: true,
            sending: false,
            onSend: () async {
              sendCount += 1;
            },
            style: style,
          ),
        ),
      ),
    );

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.keyboardType, TextInputType.text);
    expect(input.textInputAction, TextInputAction.send);
    expect(input.onSubmitted, isNotNull);
    expect(
      find.byKey(const ValueKey('chat-composer-send-button')),
      findsNothing,
    );

    input.onSubmitted?.call('hello');
    await tester.pump();

    expect(sendCount, 1);
  });

  testWidgets('chat composer disables send action without showing spinner', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController(text: 'hello');
    var sendCount = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            inputEnabled: true,
            sendEnabled: false,
            sending: false,
            onSend: () async {
              sendCount += 1;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sendCount, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.byWidgetPredicate((widget) {
        return widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                ChatUiStyleConfig.standard.composerSendButtonDisabledColor;
      }),
      findsOneWidget,
    );
  });

  testWidgets('chat composer send button shows spinner while sending', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            inputEnabled: true,
            sendEnabled: false,
            sending: true,
            onSend: () async {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.send), findsNothing);
    expect(find.byIcon(Icons.hourglass_top), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) {
        return widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                ChatUiStyleConfig.standard.composerSendButtonColor;
      }),
      findsOneWidget,
    );
  });

  testWidgets('sending self message shows centered loading badge', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'm1',
              senderId: 'me',
              senderName: 'Me',
              text: 'hello',
              isMe: true,
              status: 'sending',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    expect(find.text('sending'), findsNothing);
    expect(find.byType(ChatSendingBadge), findsOneWidget);
    expect(find.byType(ChatFailedBadge), findsNothing);

    final progressFinder = find.descendant(
      of: find.byType(ChatSendingBadge),
      matching: find.byType(CircularProgressIndicator),
    );
    final progress = tester.widget<CircularProgressIndicator>(progressFinder);
    expect(tester.getSize(progressFinder), const Size.square(12));
    expect(progress.strokeWidth, 2);

    final badgeCenter = tester.getCenter(find.byType(ChatSendingBadge));
    final bubbleCenter = tester.getCenter(find.byType(ChatMessageBubble));
    expect(badgeCenter.dy, closeTo(bubbleCenter.dy, 1));
  });

  testWidgets('nar_pic chat message renders as an image instead of URL text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'opening-image',
              senderId: 'nar_pic',
              senderName: 'Narrator',
              senderType: 'image',
              imageUrl: 'assets/images/default_list_image.png',
              text: 'assets/images/default_list_image.png',
              isMe: false,
              status: 'sent',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    expect(find.byType(ChatImageMessage), findsOneWidget);
    expect(find.byType(ChatMessageBubble), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('chat-image-message-opening-image')),
      findsOneWidget,
    );
    expect(find.text('assets/images/default_list_image.png'), findsNothing);
  });

  testWidgets('chat image thumbnail uses its layout width and OSS tier', (
    WidgetTester tester,
  ) async {
    const source = 'https://cdn-001.worldo.ai/chat/chat.png?old=true#fragment';
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() {
      debugGenesisMessageImageInfoLoader = null;
      clearGenesisMessageImageSizeCache();
    });
    debugGenesisMessageImageInfoLoader = (_) async => {
      'ImageWidth': {'value': '1600'},
      'ImageHeight': {'value': '800'},
    };

    for (final expectation in const <(double, int)>[
      (1, 1080),
      (2, 1440),
      (3, 1440),
      (4, 1440),
    ]) {
      clearGenesisMessageImageSizeCache();
      tester.view.devicePixelRatio = expectation.$1;
      tester.view.physicalSize = Size(
        800 * expectation.$1,
        600 * expectation.$1,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageRow(
              message: ChatMessageVm(
                localId: 'remote-image-${expectation.$1}',
                senderId: 'nar_pic',
                senderName: 'Narrator',
                senderType: 'image',
                imageUrl: source,
                text: source,
                isMe: false,
                status: 'sent',
              ),
              showDateDivider: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final image = tester.widget<ChatThumbnailImage>(
        find.byType(ChatThumbnailImage),
      );
      expect(image.maxWidth, 750);
      final provider = tester
          .widgetList<Image>(
            find.descendant(
              of: find.byType(ChatThumbnailImage),
              matching: find.byType(Image),
            ),
          )
          .map((image) => image.image)
          .whereType<GenesisStaticNetworkImageProvider>()
          .single;
      expect(
        provider.imageUrl,
        'https://cdn-001.worldo.ai/chat/chat.png'
        '?x-oss-process=image/resize,m_lfit,'
        'w_${expectation.$2},h_${expectation.$2 * 2}/format,webp',
      );
      expect(image.borderRadius, BorderRadius.circular(8));
    }
  });

  testWidgets('chat image loading placeholder matches narrator bubble color', (
    WidgetTester tester,
  ) async {
    const source = 'https://cdn-001.worldo.ai/chat/pending.webp';
    final pendingImageInfo = Completer<Object?>();
    addTearDown(() {
      debugGenesisMessageImageInfoLoader = null;
      clearGenesisMessageImageSizeCache();
    });
    debugGenesisMessageImageInfoLoader = (_) => pendingImageInfo.future;

    Future<Color> placeholderColor(ChatUiStyleConfig style) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageRow(
              message: ChatMessageVm(
                localId: 'pending-image',
                senderId: 'nar_pic',
                senderName: 'Narrator',
                senderType: 'image',
                imageUrl: source,
                text: source,
                isMe: false,
                status: 'sent',
              ),
              showDateDivider: false,
              style: style,
            ),
          ),
        ),
      );
      final placeholder = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(ChatThumbnailImage),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(ChatThumbnailImage),
          matching: find.image(
            const AssetImage('assets/images/default_list_image.png'),
          ),
        ),
        findsNothing,
      );
      return placeholder.color;
    }

    expect(
      await placeholderColor(kOpeningDialogueStyle),
      const Color(0xE6111111),
    );
    expect(await placeholderColor(kLocationChatStyle), const Color(0x80151517));
  });

  testWidgets('location chat image keeps only the avatar-side inset', (
    WidgetTester tester,
  ) async {
    final style = kLocationChatStyle;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: Padding(
              padding: style.messageListPadding,
              child: ChatMessageRow(
                message: ChatMessageVm(
                  localId: 'location-image-width',
                  senderId: 'nar_pic',
                  senderName: 'Narrator',
                  senderType: 'image',
                  imageUrl: 'assets/images/default_list_image.png',
                  text: 'assets/images/default_list_image.png',
                  isMe: false,
                  status: 'sent',
                ),
                showDateDivider: false,
                style: style,
              ),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<ChatThumbnailImage>(
      find.byType(ChatThumbnailImage),
    );
    final imageContentWidth =
        400 - style.messageListPadding.horizontal - style.avatarSideSpacerWidth;
    expect(image.maxWidth, closeTo(imageContentWidth, 0.01));
  });

  testWidgets('resolved remote image keeps its geometry when rebuilt', (
    WidgetTester tester,
  ) async {
    const source = 'https://cdn-001.worldo.ai/chat/rebuild.webp';
    addTearDown(() {
      debugGenesisMessageImageInfoLoader = null;
      clearGenesisMessageImageSizeCache();
    });
    debugGenesisMessageImageInfoLoader = (_) async => {
      'ImageWidth': {'value': '400'},
      'ImageHeight': {'value': '800'},
    };

    Widget image() => const MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: ChatThumbnailImage(imageUrl: source, maxWidth: 300),
          ),
        ),
      ),
    );

    await tester.pumpWidget(image());
    await tester.pump();
    await tester.pump();
    expect(
      tester.getSize(find.byType(ChatThumbnailImage)),
      const Size(300, 600),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(image());

    expect(
      tester.getSize(find.byType(ChatThumbnailImage)),
      const Size(300, 600),
    );
  });

  testWidgets('chat image keeps its ratio within the available layout width', (
    WidgetTester tester,
  ) async {
    Future<Size> pumpImage(String localId, String imageUrl) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: ChatMessageRow(
                  message: ChatMessageVm(
                    localId: localId,
                    senderId: 'nar_pic',
                    senderName: 'Narrator',
                    senderType: 'image',
                    imageUrl: imageUrl,
                    text: imageUrl,
                    isMe: false,
                    status: 'sent',
                  ),
                  showDateDivider: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          AssetImage(imageUrl),
          tester.element(find.byType(ChatThumbnailImage)),
        );
      });
      await tester.pump();
      return tester.getSize(
        find.byKey(ValueKey<String>('chat-image-message-$localId')),
      );
    }

    final square = await pumpImage(
      'square',
      'assets/images/default_list_image.png',
    );
    expect(square, const Size.square(250));

    final portrait = await pumpImage(
      'portrait',
      'assets/images/map_default/root_default.webp',
    );
    expect(portrait.width, closeTo(250, 0.01));
    expect(portrait.height, closeTo(250 * 1536 / 1024, 0.01));

    final small = await pumpImage(
      'small',
      'assets/custom-icons/png/discuss_like_outline.png',
    );
    expect(small, const Size.square(96));

    final renderedImage = tester.widget<Image>(
      find.descendant(
        of: find.byType(ChatThumbnailImage),
        matching: find.byType(Image),
      ),
    );
    expect(renderedImage.fit, BoxFit.contain);
  });

  testWidgets('chat image opens all loaded images at the tapped message', (
    WidgetTester tester,
  ) async {
    final start = DateTime(2026, 7, 29, 10);
    const firstImage = 'assets/images/map_default/root_default.webp';
    const secondImage = 'assets/images/map_default/l1_default.webp';
    final messages = <ChatMessageVm>[
      ChatMessageVm(
        localId: 'image-later',
        senderId: 'nar_pic',
        senderName: 'Narrator',
        senderType: 'image',
        imageUrl: secondImage,
        text: secondImage,
        isMe: false,
        status: 'sent',
        createdAt: start.add(const Duration(minutes: 2)),
      ),
      ChatMessageVm(
        localId: 'text-between',
        senderId: 'peer',
        senderName: 'Peer',
        text: 'not an image',
        isMe: false,
        status: 'sent',
        createdAt: start.add(const Duration(minutes: 1)),
      ),
      ChatMessageVm(
        localId: 'image-earlier',
        senderId: 'nar_pic',
        senderName: 'Narrator',
        senderType: 'image',
        imageUrl: firstImage,
        text: firstImage,
        isMe: false,
        status: 'sent',
        createdAt: start,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            controller: ScrollController(),
            messages: messages,
            topTitle: '',
            reverse: false,
            showDateDividers: false,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('chat-image-message-image-later')),
    );
    await tester.pumpAndSettle();

    final viewer = tester.widget<GenesisImageViewerOverlay>(
      find.byType(GenesisImageViewerOverlay),
    );
    expect(viewer.imageUrls, const <String>[firstImage, secondImage]);
    expect(viewer.initialIndex, 1);
    expect(
      find.byKey(const ValueKey('genesis-image-viewer-page-dots')),
      findsOneWidget,
    );
  });

  testWidgets('standalone chat image viewer falls back to current image', (
    WidgetTester tester,
  ) async {
    const image = 'assets/images/map_default/root_default.webp';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageRow(
            message: ChatMessageVm(
              localId: 'standalone-image',
              senderId: 'nar_pic',
              senderName: 'Narrator',
              senderType: 'image',
              imageUrl: image,
              text: image,
              isMe: false,
              status: 'sent',
            ),
            showDateDivider: false,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('chat-image-message-standalone-image')),
    );
    await tester.pumpAndSettle();

    final viewer = tester.widget<GenesisImageViewerOverlay>(
      find.byType(GenesisImageViewerOverlay),
    );
    expect(viewer.imageUrls, const <String>[image]);
    expect(viewer.initialIndex, 0);
  });
}

bool _textHasItalicFragment(Text text, String value) {
  final span = text.textSpan;
  if (span == null) return false;
  var found = false;
  span.visitChildren((child) {
    if (child is TextSpan &&
        child.text == value &&
        child.style?.fontStyle == FontStyle.italic) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Color? _textFragmentColor(Text text, String value) {
  return _textFragmentStyle(text, value)?.color;
}

TextStyle? _textFragmentStyle(Text text, String value) {
  final span = text.textSpan;
  if (span == null) return null;
  TextStyle? style;
  span.visitChildren((child) {
    if (child is TextSpan && child.text == value) {
      style = child.style;
      return false;
    }
    return true;
  });
  return style;
}

TextStyle? _firstTextFragmentStyle(Iterable<Text> texts, String value) {
  for (final text in texts) {
    final style = _textFragmentStyle(text, value);
    if (style != null) return style;
  }
  return null;
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/chat/shared/chat_ui.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_reply_actions.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_scroll_coordinator.dart';
import 'package:genesis_flutter_android/components/gems/purchase_options_sheet.dart';
import 'package:genesis_flutter_android/components/common/genesis_bottom_sheet_panel.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

void main() {
  testWidgets(
    'inspiration swipes through three previews matching the user bubble',
    (tester) async {
      final style = kLocationChatStyle;
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const GenesisScrollBehavior(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 390,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: style.messageListPadding,
                    child: Column(
                      children: [
                        ChatSelfMessageBubble(
                          message: ChatMessageVm(
                            localId: 'reference-user',
                            senderId: 'user',
                            senderName: 'User',
                            text:
                                'A long reference reply that fills the maximum '
                                'available width of the user message bubble.',
                            isMe: true,
                            status: 'sent',
                          ),
                          style: style,
                          maxWidthCap: 230,
                        ),
                        LocationChatReplyActions(
                          style: style,
                          selfMessageBubbleMaxWidthCap: 230,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final inspiration = find.bySemanticsLabel('Inspiration');
      final first = find.byKey(const ValueKey('inspiration-reply-card-0'));
      expect(first, findsNothing);
      await tester.tap(inspiration);
      await tester.pumpAndSettle();

      final reference = tester.getRect(
        find.byKey(const ValueKey('chat-message-bubble-reference-user')),
      );
      final carousel = find.byKey(
        const ValueKey('inspiration-replies-carousel'),
      );
      for (var index = 0; index < 3; index++) {
        if (index > 0) {
          await tester.drag(carousel, const Offset(-230, 0));
          await tester.pumpAndSettle();
        }
        final card = find.byKey(ValueKey('inspiration-reply-card-$index'));
        expect(card, findsOneWidget);
        final bounds = tester.getRect(card);
        expect(bounds.width, closeTo(reference.width, 0.01));
        final viewport = tester.getRect(carousel);
        expect(bounds.right, closeTo(reference.right, 0.01));
        final neighborIndex = index < 2 ? index + 1 : index - 1;
        final neighbor = tester.getRect(
          find.byKey(ValueKey('inspiration-reply-card-$neighborIndex')),
        );
        expect(
          neighbor.overlaps(viewport),
          isTrue,
          reason: 'The adjacent card must peek into the viewport.',
        );
        expect(viewport.contains(neighbor.center), isFalse);
        expect(bounds.top, closeTo(tester.getTopLeft(carousel).dy, 0.01));
        final bubble = tester.widget<ChatMessageBubble>(
          find.descendant(of: card, matching: find.byType(ChatMessageBubble)),
        );
        expect(
          bubble.style!.selfBubbleColor,
          chatNarratorMessageBackgroundColor(style),
        );
        expect(bubble.onTap, isNotNull);
      }
      await tester.tap(inspiration);
      await tester.pumpAndSettle();
      expect(first, findsNothing);
      await tester.tap(inspiration);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inspiration-reply-card-2')),
        findsOneWidget,
      );
      await tester.drag(carousel, const Offset(230, 0));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inspiration-reply-card-1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('inspiration sends the card or edits from the full right strip', (
    tester,
  ) async {
    final sent = <String>[];
    final edited = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const GenesisScrollBehavior(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 390,
              child: LocationChatReplyActions(
                style: kLocationChatStyle,
                onInspirationSend: sent.add,
                onInspirationEdit: edited.add,
              ),
            ),
          ),
        ),
      ),
    );
    final toggle = find.bySemanticsLabel('Inspiration');
    final carousel = find.byKey(const ValueKey('inspiration-replies-carousel'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inspiration-reply-card-0')));
    await tester.pumpAndSettle();
    expect(sent, ['Good job!']);
    expect(edited, isEmpty);
    expect(carousel, findsNothing);

    // Both ends of the strip respond, even far away from the centered icon.
    for (final nearTop in [true, false]) {
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final strip = tester.getRect(
        find.byKey(const ValueKey('inspiration-edit-0')),
      );
      await tester.tapAt(
        Offset(strip.center.dx, nearTop ? strip.top + 4 : strip.bottom - 4),
      );
      await tester.pumpAndSettle();
      expect(carousel, findsNothing);
    }
    expect(edited, ['Good job!', 'Good job!']);
    expect(sent, ['Good job!']);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.drag(carousel, const Offset(-230, 0));
    await tester.pumpAndSettle();
    expect(sent, ['Good job!'], reason: 'Swiping must not send.');
    await tester.tap(find.byKey(const ValueKey('inspiration-reply-card-1')));
    await tester.pumpAndSettle();
    expect(sent.last, startsWith("You're right to ask for a plan."));
    expect(carousel, findsNothing);
  });
  testWidgets('inspiration survives recycling its message row', (tester) async {
    final coordinator = LocationChatScrollCoordinator();
    addTearDown(coordinator.dispose);
    final messages = List.generate(
      45,
      (index) => ChatMessageVm(
        localId: 'reply-$index',
        senderId: 'character',
        senderName: 'Character',
        text:
            'This is a long reply with enough content to fill several lines in the chat history. '
            'Scrolling away should not discard the inspiration selection.',
        isMe: false,
        status: 'sent',
        senderType: 'character',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const GenesisScrollBehavior(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 390,
              height: 600,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                messages: messages,
                topTitle: '',
                replyActionsMessageId: 'reply-44',
                style: kLocationChatStyle,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Inspiration'));
    await tester.pumpAndSettle();
    final carousel = find.byKey(const ValueKey('inspiration-replies-carousel'));
    await tester.ensureVisible(carousel);
    await tester.drag(carousel, const Offset(-300, 0));
    await tester.pumpAndSettle();
    coordinator.controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.byType(LocationChatReplyActions), findsNothing);
    coordinator.controller.jumpTo(
      coordinator.controller.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('inspiration-reply-card-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Get more opens Subscription and tabs switch without eager gems loading',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const GenesisScrollBehavior(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LocationChatReplyActions(style: kLocationChatStyle),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Inspiration'));
      await tester.pumpAndSettle();
      final getMore = find.byKey(const ValueKey('inspiration-get-more'));
      await tester.ensureVisible(getMore);
      await tester.tap(getMore);
      await tester.pumpAndSettle();
      expect(find.text('Subscription'), findsOneWidget);
      expect(find.text('Buy Gems'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('subscription-placeholder')),
        findsOneWidget,
      );
      await tester.tap(find.text('Buy Gems'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('subscription-placeholder')),
        findsNothing,
      );
      await tester.tap(find.text('Subscription'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('subscription-placeholder')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('gem-purchase-sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byType(PurchaseOptionsSheet), findsNothing);
    },
  );
  testWidgets('purchase tabs preserve the original header and close position', (
    tester,
  ) async {
    Widget host(Widget child) => MaterialApp(
      scrollBehavior: const GenesisScrollBehavior(),
      home: Scaffold(body: SizedBox(width: 390, height: 500, child: child)),
    );
    const contentKey = ValueKey('purchase-content-position');
    const closeKey = ValueKey('gem-purchase-sheet-close');
    await tester.pumpWidget(
      host(
        GenesisBottomSheetPanel(
          title: 'Low Gems',
          height: 500,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          trailing: GenesisBottomSheetCloseButton(
            buttonKey: closeKey,
            onPressed: () {},
          ),
          child: const SizedBox.expand(key: contentKey),
        ),
      ),
    );
    final closeRect = tester.getRect(find.byKey(closeKey));
    final contentTop = tester.getTopLeft(find.byKey(contentKey)).dy;
    await tester.pumpWidget(
      host(
        PurchaseOptionsSheet(
          gemsBuilder: (_) => const SizedBox.expand(key: contentKey),
        ),
      ),
    );
    expect(tester.getRect(find.byKey(closeKey)), closeRect);
    expect(tester.getTopLeft(find.byKey(contentKey)).dy, contentTop);
  });
  testWidgets('reopening inspiration follows the bottom after horizontal swipes', (
    tester,
  ) async {
    final coordinator = LocationChatScrollCoordinator();
    addTearDown(coordinator.dispose);
    final messages = List.generate(
      25,
      (index) => ChatMessageVm(
        localId: 'cycle-$index',
        senderId: 'character',
        senderName: 'Character',
        text:
            'A reply long enough to fill several lines, keeping the conversation scrollable while testing inspiration expansion.',
        isMe: false,
        status: 'sent',
        senderType: 'character',
      ),
    );
    const viewportKey = ValueKey('cycle-viewport');
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const GenesisScrollBehavior(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: viewportKey,
              width: 390,
              height: 650,
              child: NotificationListener<ScrollNotification>(
                onNotification: coordinator.handleScrollNotification,
                child: LocationChatAnchoredMessageList(
                  coordinator: coordinator,
                  messages: messages,
                  topTitle: '',
                  replyActionsMessageId: 'cycle-24',
                  style: kLocationChatStyle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final collapsedOffset = coordinator.controller.offset;
    for (var cycle = 0; cycle < 3; cycle++) {
      await tester.tap(find.bySemanticsLabel('Inspiration'));
      await tester.pumpAndSettle();
      expect(coordinator.isAtBottom, isTrue);
      final viewport = tester.getRect(find.byKey(viewportKey));
      final footer = tester.getRect(
        find.byKey(const ValueKey('inspiration-get-more')),
      );
      expect(footer.bottom, lessThanOrEqualTo(viewport.bottom));
      await tester.drag(
        find.byKey(const ValueKey('inspiration-replies-carousel')),
        Offset(cycle.isEven ? -230 : 230, 0),
      );
      await tester.pumpAndSettle();
      expect(
        coordinator.mode,
        LocationChatViewportMode.followingLatest,
        reason:
            'Horizontal card swipes must not detach the vertical conversation.',
      );
      await tester.tap(find.bySemanticsLabel('Inspiration'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inspiration-get-more')), findsNothing);
      expect(coordinator.controller.offset, closeTo(collapsedOffset, 1));
    }
  });
}

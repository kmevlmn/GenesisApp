import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/chat/shared/chat_ui.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_reply_actions.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_scroll_coordinator.dart';
import 'package:genesis_flutter_android/components/gems/purchase_options_sheet.dart';
import 'package:genesis_flutter_android/components/common/genesis_bottom_sheet_panel.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

void main() {
  testWidgets('all four non-member actions only show the subscription prompt', (
    tester,
  ) async {
    var actionCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const GenesisScrollBehavior(),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: LocationChatReplyActions(
              style: kLocationChatStyle,
              isMember: false,
              onRegenerate: () => actionCalls++,
              onGoOn: () => actionCalls++,
              onEditReply: () => actionCalls++,
            ),
          ),
        ),
      ),
    );
    final prompt = find.byKey(const ValueKey('edit-subscription-prompt'));
    expect(prompt, findsNothing);
    for (final action in ['Regenerate', 'Go on', 'Edit', 'Inspiration']) {
      await tester.tap(find.bySemanticsLabel(action));
      await tester.pumpAndSettle();
      expect(actionCalls, 0);
      expect(prompt, findsOneWidget);
      expect(
        find.byKey(const ValueKey('inspiration-replies-carousel')),
        findsNothing,
      );
    }
    final label = tester.widget<Text>(
      find.descendant(of: prompt, matching: find.byType(Text)),
    );
    expect(label.textSpan!.toPlainText(), 'Members only. Subscribe >');
    expect(label.maxLines, 1);
    expect(label.softWrap, isFalse);
    expect(label.style!.fontSize, 13);
    final icons = find.byKey(
      const ValueKey('location-chat-reply-actions-four-icons'),
    );
    expect(
      tester.getTopLeft(prompt).dy,
      greaterThan(tester.getBottomRight(icons).dy),
    );
    await tester.tap(prompt);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('subscription-placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('default members invoke actions with independent availability', (
    tester,
  ) async {
    final calls = <String>[];
    Widget host({bool busy = false}) => MaterialApp(
      home: Scaffold(
        body: LocationChatReplyActions(
          style: kLocationChatStyle,
          onRegenerate: () => calls.add('regenerate'),
          onGoOn: () => calls.add('goOn'),
          onEditReply: () => calls.add('edit'),
          regenerateBusy: busy,
          goOnEnabled: !busy,
        ),
      ),
    );
    await tester.pumpWidget(host());
    for (final action in ['Regenerate', 'Go on', 'Edit', 'Inspiration']) {
      expect(find.byTooltip(action), findsOneWidget);
      expect(tester.getSize(find.bySemanticsLabel(action)), const Size(32, 32));
    }
    for (final action in ['Regenerate', 'Go on', 'Edit']) {
      await tester.tap(find.bySemanticsLabel(action));
      await tester.pump();
    }
    expect(calls, ['regenerate', 'goOn', 'edit']);
    expect(
      find.byKey(const ValueKey('edit-subscription-prompt')),
      findsNothing,
    );
    await tester.pumpWidget(host(busy: true));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(find.bySemanticsLabel('Regenerate'))
          .properties
          .value,
      'In progress',
    );
    for (final action in ['Regenerate', 'Go on', 'Edit']) {
      await tester.tap(find.bySemanticsLabel(action));
      await tester.pump();
    }
    expect(calls, ['regenerate', 'goOn', 'edit', 'edit']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reply pagination exposes actual positions and boundary actions',
    (tester) async {
      var page = 0;
      late StateSetter setHostState;
      var confirmed = false;
      var count = 3;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                return LocationChatReplyActions(
                  style: kLocationChatStyle,
                  cardIndex: page,
                  cardCount: count,
                  cardsConfirmed: confirmed,
                  onPreviousCard: () => setState(() => page--),
                  onNextCard: () => setState(() => page++),
                );
              },
            ),
          ),
        ),
      );
      final previous = find.byKey(
        const ValueKey('location-chat-reply-previous-card'),
      );
      final next = find.byKey(const ValueKey('location-chat-reply-next-card'));
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Reply 1 of 3'), findsOneWidget);
      expect(tester.widget<IconButton>(previous).onPressed, isNull);
      await tester.tap(next);
      await tester.pump();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(next);
      await tester.pump();
      expect(find.text('3 / 3'), findsOneWidget);
      expect(tester.widget<IconButton>(next).onPressed, isNull);
      await tester.tap(previous);
      await tester.pump();
      expect(find.text('2 / 3'), findsOneWidget);
      setHostState(() => confirmed = true);
      await tester.pump();
      expect(previous, findsNothing);
      setHostState(() {
        confirmed = false;
        count = 1;
        page = 0;
      });
      await tester.pump();
      expect(previous, findsNothing);
      setHostState(() => count = 0);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('location-chat-reply-page-indicator')),
        findsNothing,
      );
    },
  );

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
      final footer = find.byKey(const ValueKey('inspiration-get-more'));
      final footerSurface = tester.widget<ChatStableBackdropSurface>(
        find.descendant(
          of: footer,
          matching: find.byType(ChatStableBackdropSurface),
        ),
      );
      expect(footerSurface.sigma, style.bubbleBackdropBlurSigma);
      final footerContainer = tester.widget<Container>(
        find.descendant(of: footer, matching: find.byType(Container)),
      );
      expect(
        (footerContainer.decoration! as BoxDecoration).color,
        chatNarratorMessageBackgroundColor(
          style,
        ).withValues(alpha: style.selfBubbleColor.a),
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
          chatNarratorMessageBackgroundColor(
            style,
          ).withValues(alpha: style.selfBubbleColor.a),
        );
        expect(bubble.onTap, isNotNull);
        final surface = tester.widget<ChatStableBackdropSurface>(
          find.descendant(
            of: card,
            matching: find.byType(ChatStableBackdropSurface),
          ),
        );
        expect(surface.sigma, style.bubbleBackdropBlurSigma);
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
    final activeRight = tester
        .getRect(find.byKey(const ValueKey('inspiration-reply-card-0')))
        .right;
    var current = 0;
    for (final target in [1, 0, 1, 2, 1, 0]) {
      // The left preview exposes its edit strip; that must only select it.
      final tapTarget = find.byKey(
        ValueKey(
          target < current
              ? 'inspiration-edit-$target'
              : 'inspiration-reply-card-$target',
        ),
      );
      final visible = tester
          .getRect(tapTarget)
          .intersect(tester.getRect(carousel));
      expect(visible.isEmpty, isFalse);
      await tester.tapAt(visible.center);
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(edited, isEmpty);
      expect(carousel, findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(ValueKey('inspiration-reply-card-$target')))
            .right,
        closeTo(activeRight, 0.01),
      );
      current = target;
    }
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
  testWidgets('inspiration collapses when a retained chat page is reentered', (
    tester,
  ) async {
    final coordinator = LocationChatScrollCoordinator();
    addTearDown(coordinator.dispose);
    final messages = [
      ChatMessageVm(
        localId: 'reply',
        senderId: 'character',
        senderName: 'Character',
        text: 'A completed reply.',
        isMe: false,
        status: 'sent',
        senderType: 'character',
      ),
    ];
    Widget host(bool active) => MaterialApp(
      scrollBehavior: const GenesisScrollBehavior(),
      home: Scaffold(
        body: SizedBox(
          width: 390,
          height: 600,
          child: LocationChatAnchoredMessageList(
            coordinator: coordinator,
            active: active,
            messages: messages,
            topTitle: '',
            replyActionsMessageId: 'reply',
            style: kLocationChatStyle,
          ),
        ),
      ),
    );
    final carousel = find.byKey(const ValueKey('inspiration-replies-carousel'));
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    final retainedState = tester.state(
      find.byType(LocationChatAnchoredMessageList),
    );
    for (var visit = 0; visit < 2; visit++) {
      expect(carousel, findsNothing);
      await tester.tap(find.bySemanticsLabel('Inspiration'));
      await tester.pumpAndSettle();
      expect(carousel, findsOneWidget);
      await tester.pumpWidget(host(true));
      await tester.pumpAndSettle();
      expect(
        carousel,
        findsOneWidget,
        reason: 'An ordinary rebuild must keep it expanded.',
      );
      await tester.pumpWidget(host(false));
      await tester.pumpAndSettle();
      expect(carousel, findsNothing);
      await tester.pumpWidget(host(true));
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(LocationChatAnchoredMessageList)),
        same(retainedState),
      );
      expect(carousel, findsNothing);
    }
    expect(tester.takeException(), isNull);
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
  testWidgets(
    'round controls exist without candidate messages and retain state',
    (tester) async {
      final coordinator = LocationChatScrollCoordinator();
      addTearDown(coordinator.dispose);
      final user = ChatMessageVm(
        localId: 'user',
        senderId: 'user',
        senderName: 'User',
        text: 'Hello',
        isMe: true,
        status: 'sent',
      );
      Widget host(
        List<ChatMessageVm> messages, {
        String status = 'Generating…',
      }) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 600,
            child: LocationChatAnchoredMessageList(
              coordinator: coordinator,
              messages: messages,
              topTitle: '',
              replyActionsIdentity: 'world/location/round',
              replyActionsAnchorIndex: messages.length,
              replyStatus: Text(status),
              replyCardIndex: 1,
              replyCardCount: 2,
              regenerateEnabled: false,
              goOnEnabled: false,
              editEnabled: false,
            ),
          ),
        ),
      );
      await tester.pumpWidget(host([user]));
      await tester.pumpAndSettle();
      final controls = find.byKey(
        const ValueKey('reply-actions-world/location/round'),
      );
      expect(controls, findsOneWidget);
      expect(find.text('Generating…'), findsOneWidget);
      final state = tester.state(controls);
      final candidate = ChatMessageVm(
        localId: 'candidate-100',
        senderId: 'role',
        senderName: 'Role',
        text: 'A candidate reply',
        isMe: false,
        status: 'streaming',
      );
      await tester.pumpWidget(host([user, candidate]));
      await tester.pumpAndSettle();
      expect(tester.state(controls), same(state));
      await tester.pumpWidget(host([user], status: 'Generation failed'));
      await tester.pumpAndSettle();
      expect(tester.state(controls), same(state));
      expect(find.text('Generation failed'), findsOneWidget);
      final list = tester.widget<LocationChatAnchoredMessageList>(
        find.byType(LocationChatAnchoredMessageList),
      );
      expect(list.messages, [user]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit card switches keep the round controls in the viewport',
    (tester) async {
      final coordinator = LocationChatScrollCoordinator();
      addTearDown(coordinator.dispose);
      final messages = List.generate(
        15,
        (index) => ChatMessageVm(
          localId: 'history-$index',
          senderId: 'role',
          senderName: 'Role',
          text: 'Previous history. ' * 10,
          isMe: false,
          status: 'sent',
        ),
      );
      Widget host(int revision, int lines, {bool loading = false}) =>
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 390,
                height: 500,
                child: NotificationListener<ScrollNotification>(
                  onNotification: coordinator.handleScrollNotification,
                  child: LocationChatAnchoredMessageList(
                    coordinator: coordinator,
                    topTitle: '',
                    oldestEdgeLoading: loading,
                    messages: [
                      ...messages,
                      ChatMessageVm(
                        localId: 'candidate-$revision',
                        senderId: 'role',
                        senderName: 'Role',
                        text: List.filled(
                          lines,
                          'Candidate reply line',
                        ).join('\n'),
                        isMe: false,
                        status: 'sent',
                      ),
                    ],
                    replyActionsIdentity: 'world/location/round',
                    replyActionsAnchorIndex: messages.length + 1,
                    replyPresentationRevision: revision,
                    replyCardIndex: revision,
                    replyCardCount: 3,
                  ),
                ),
              ),
            ),
          );
      final controls = find.byKey(
        const ValueKey('reply-actions-world/location/round'),
      );
      await tester.pumpWidget(host(0, 5));
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(controls).dy;
      await tester.pumpWidget(host(1, 20));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(controls).dy, closeTo(top, 1));
      expect(coordinator.shouldFollowLatest, isTrue);
      // A concurrent history request must not hold a user-selected candidate.
      await tester.pumpWidget(host(1, 20, loading: true));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpWidget(host(2, 3, loading: true));
      await tester.pump();
      expect(find.text('3 / 3'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-message-bubble-candidate-2')),
        findsOneWidget,
      );
      await tester.pumpWidget(host(2, 3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'candidate chunks follow only while the reader is at the bottom',
    (tester) async {
      final coordinator = LocationChatScrollCoordinator();
      addTearDown(coordinator.dispose);
      final history = List.generate(
        20,
        (index) => ChatMessageVm(
          localId: 'past-$index',
          senderId: 'role',
          senderName: 'Role',
          text: 'Earlier messages in this conversation. ' * 5,
          isMe: false,
          status: 'sent',
        ),
      );
      Widget host(int lines, {bool loading = false}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 500,
            child: NotificationListener<ScrollNotification>(
              onNotification: coordinator.handleScrollNotification,
              child: LocationChatAnchoredMessageList(
                coordinator: coordinator,
                topTitle: '',
                oldestEdgeLoading: loading,
                messages: [
                  ...history,
                  ChatMessageVm(
                    localId: 'live-candidate',
                    senderId: 'role',
                    senderName: 'Role',
                    text: List.filled(lines, 'Streaming line').join('\n'),
                    isMe: false,
                    status: 'streaming',
                  ),
                ],
                replyActionsIdentity: 'world/location/round',
                replyActionsAnchorIndex: history.length + 1,
                replyPresentationRevision: 1,
                replyCardIndex: 1,
                replyCardCount: 2,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(2));
      await tester.pumpAndSettle();
      final previousOffset = coordinator.controller.offset;
      await tester.pumpWidget(host(8));
      await tester.pumpAndSettle();
      expect(coordinator.controller.offset, greaterThan(previousOffset));
      expect(coordinator.isAtBottom, isTrue);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(coordinator.isDetached, isTrue);
      final detachedOffset = coordinator.controller.offset;
      await tester.pumpWidget(host(18));
      await tester.pumpAndSettle();
      expect(coordinator.controller.offset, closeTo(detachedOffset, 0.1));
      // A history loader does not buffer new candidate text.
      await tester.pumpWidget(host(18, loading: true));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpWidget(host(20, loading: true));
      await tester.pump();
      final candidateRow = tester.widget<ChatMessageRow>(
        find.byKey(const ValueKey('live-candidate')),
      );
      expect(candidateRow.message.text.split('\n'), hasLength(20));
      await tester.pumpWidget(host(20));
      await tester.pumpAndSettle();
      expect(coordinator.isDetached, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

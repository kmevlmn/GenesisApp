import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_reply_card_switcher.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_scroll_coordinator.dart';
import 'package:genesis_flutter_android/components/chat/shared/chat_ui.dart';

void main() {
  testWidgets(
    'a short fast swipe advances and ordinary vertical scrolling and long press remain available',
    (tester) async {
      final key = GlobalKey<LocationChatReplyCardSwitcherState>();
      final commits = <int>[];
      var longPresses = 0;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    LocationChatReplyCardSwitcher(
                      key: key,
                      identity: 'r',
                      currentCardId: 1,
                      cards: const [
                        LocationChatReplyCard(id: 1, messages: []),
                        LocationChatReplyCard(id: 2, messages: []),
                      ],
                      cardBuilder: (card) => GestureDetector(
                        onLongPress: () => longPresses++,
                        child: SizedBox(
                          height: 300,
                          child: Center(child: Text('Card ${card.id}')),
                        ),
                      ),
                      onCommit: (id) {
                        commits.add(id);
                        return true;
                      },
                      onBusyChanged: (_) {},
                      onWillChangeLayout: () {},
                    ),
                    const SizedBox(height: 700),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('Card 1'));
      expect(longPresses, 1);
      await tester.drag(find.text('Card 1'), const Offset(0, -90));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(commits, isEmpty);
      scroll.jumpTo(0);
      await tester.pump();
      await tester.fling(find.text('Card 1'), const Offset(-80, 0), 1000);
      await tester.pumpAndSettle();
      expect(commits, [2]);
    },
  );

  testWidgets(
    'arrows move whole pages in both directions and commit only once on settle',
    (tester) async {
      final key = GlobalKey<LocationChatReplyCardSwitcherState>();
      final commits = <int>[];
      final busy = <bool>[];
      await tester.pumpWidget(_host(key, commits, busy));
      final first = find.byKey(const ValueKey('body-1'));
      final origin = tester.getTopLeft(first).dx;
      key.currentState!.switchBy(1);
      key.currentState!.switchBy(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(commits, isEmpty);
      expect(tester.getTopLeft(first).dx, lessThan(origin));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('body-2'))).dx,
        greaterThan(origin),
      );
      await tester.pumpAndSettle();
      expect(commits, [2]);
      expect(busy, [true, false]);
      expect(first, findsNothing);
      key.currentState!.switchBy(-1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('body-2'))).dx,
        greaterThan(origin),
      );
      await tester.pumpAndSettle();
      expect(commits, [2, 1]);
      expect(find.byKey(const ValueKey('body-2')), findsNothing);
    },
  );

  testWidgets(
    'drag follows the finger, cancels below threshold and commits beyond threshold',
    (tester) async {
      final key = GlobalKey<LocationChatReplyCardSwitcherState>();
      final commits = <int>[];
      final busy = <bool>[];
      await tester.pumpWidget(_host(key, commits, busy));
      final area = find.byKey(const ValueKey('reply-card-gesture'));
      var gesture = await tester.startGesture(tester.getCenter(area));
      await gesture.moveBy(const Offset(-30, 0));
      await gesture.moveBy(const Offset(-35, 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('body-2')), findsOneWidget);
      expect(commits, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(commits, isEmpty);
      expect(find.byKey(const ValueKey('body-2')), findsNothing);
      gesture = await tester.startGesture(tester.getCenter(area));
      await gesture.moveBy(const Offset(-30, 0));
      await gesture.moveBy(const Offset(-130, 0));
      await tester.pump();
      expect(commits, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(commits, [2]);
    },
  );

  testWidgets(
    'outward drags and pointer cancellation rebound without a commit',
    (tester) async {
      final key = GlobalKey<LocationChatReplyCardSwitcherState>();
      final commits = <int>[];
      await tester.pumpWidget(_host(key, commits, []));
      final area = find.byKey(const ValueKey('reply-card-gesture'));
      var gesture = await tester.startGesture(tester.getCenter(area));
      await gesture.moveBy(const Offset(180, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(commits, isEmpty);
      gesture = await tester.startGesture(tester.getCenter(area));
      await gesture.moveBy(const Offset(-30, 0));
      await gesture.moveBy(const Offset(-140, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(commits, isEmpty);
    },
  );

  testWidgets(
    'changing round or disabling the deck cancels an in-flight switch',
    (tester) async {
      for (final disable in [true, false]) {
        final key = GlobalKey<LocationChatReplyCardSwitcherState>();
        final commits = <int>[];
        final busy = <bool>[];
        await tester.pumpWidget(_host(key, commits, busy));
        key.currentState!.switchBy(1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        await tester.pumpWidget(
          _host(
            key,
            commits,
            busy,
            enabled: !disable,
            identity: disable ? 'round' : 'next-round',
          ),
        );
        await tester.pumpAndSettle();
        expect(commits, isEmpty);
        expect(busy.last, false);
        expect(find.byKey(const ValueKey('body-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('body-2')), findsNothing);
      }
    },
  );

  testWidgets('disabled animations commit immediately', (tester) async {
    final key = GlobalKey<LocationChatReplyCardSwitcherState>();
    final commits = <int>[];
    await tester.pumpWidget(_host(key, commits, [], reducedMotion: true));
    key.currentState!.switchBy(1);
    await tester.pump();
    expect(commits, [2]);
    expect(find.byKey(const ValueKey('body-1')), findsNothing);
  });

  for (final secondScroll in [false, true]) {
    testWidgets(
      'variable height keeps the toolbar anchored through every frame (secondScroll=$secondScroll)',
      (tester) async {
        final coordinator = LocationChatScrollCoordinator();
        addTearDown(coordinator.dispose);
        final history = List.generate(12, (i) => _message('history-$i', 3));
        final cards = [
          LocationChatReplyCard(id: 1, messages: [_message('short', 3)]),
          LocationChatReplyCard(
            id: 2,
            messages: [_message('long', 18), _message('second', 2)],
          ),
        ];
        var current = 1;
        var revision = 0;
        final commits = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 390,
                height: 500,
                child: StatefulBuilder(
                  builder: (context, update) {
                    final selected = cards.firstWhere(
                      (card) => card.id == current,
                    );
                    return NotificationListener<ScrollNotification>(
                      onNotification: coordinator.handleScrollNotification,
                      child: LocationChatAnchoredMessageList(
                        coordinator: coordinator,
                        topTitle: secondScroll ? 'History' : '',
                        oldestEdgeNoticeRequiresSecondScroll: secondScroll,
                        messages: [...history, ...selected.messages],
                        replyCards: cards,
                        replyCurrentCardId: current,
                        replyActionsIdentity: 'round',
                        replyActionsAnchorIndex:
                            history.length + selected.messages.length,
                        replyPresentationRevision: revision,
                        replyCardCount: 2,
                        replyCardIndex: current - 1,
                        onReplyCardSelected: (id) {
                          commits.add(id);
                          update(() {
                            current = id;
                            revision++;
                          });
                          return true;
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final controls = find.byKey(const ValueKey('reply-actions-round'));
        final y = tester.getTopLeft(controls).dy;
        for (final direction in ['next', 'previous']) {
          await tester.tap(
            find.byKey(ValueKey('location-chat-reply-$direction-card')),
          );
          await tester.pump();
          for (var frame = 0; frame < 16; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              tester.getTopLeft(controls).dy,
              closeTo(y, 1),
              reason: 'frame $frame',
            );
            expect(tester.takeException(), isNull);
          }
          await tester.pumpAndSettle();
        }
        expect(commits, [2, 1]);
        expect(find.byKey(const ValueKey('reply-card-page-2')), findsNothing);
      },
    );
  }
}

ChatMessageVm _message(String id, int lines) => ChatMessageVm(
  localId: id,
  senderId: 'role',
  senderName: 'Role',
  text: List.filled(lines, 'Reply line').join('\n'),
  isMe: false,
  status: 'sent',
);

Widget _host(
  GlobalKey<LocationChatReplyCardSwitcherState> key,
  List<int> commits,
  List<bool> busy, {
  bool enabled = true,
  String identity = 'round',
  bool reducedMotion = false,
}) => MaterialApp(
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: LocationChatReplyCardSwitcher(
            key: key,
            identity: identity,
            currentCardId: 1,
            enabled: enabled,
            cards: const [
              LocationChatReplyCard(id: 1, messages: []),
              LocationChatReplyCard(id: 2, messages: []),
            ],
            cardBuilder: (card) => SizedBox(
              key: ValueKey('body-${card.id}'),
              height: card.id == 1 ? 160 : 280,
              child: Text('card ${card.id}'),
            ),
            onCommit: (id) {
              commits.add(id);
              return true;
            },
            onBusyChanged: busy.add,
            onWillChangeLayout: () {},
          ),
        ),
      ),
    ),
  ),
);

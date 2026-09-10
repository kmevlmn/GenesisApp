import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/chat/shared/chat_ui.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_scroll_coordinator.dart';

void main() {
  List<ChatMessageVm> messages(int count) {
    return [
      for (var id = 1; id <= count; id += 1)
        ChatMessageVm(
          localId: 'message-$id',
          senderId: 'peer',
          senderName: 'Peer',
          text: 'message $id',
          isMe: false,
          status: 'sent',
        ),
    ];
  }

  Widget viewport(LocationChatScrollCoordinator coordinator) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 360,
          child: AnimatedBuilder(
            animation: coordinator,
            builder: (context, _) {
              return NotificationListener<ScrollNotification>(
                onNotification: coordinator.handleScrollNotification,
                child: LocationChatAnchoredMessageList(
                  coordinator: coordinator,
                  messages: messages(30),
                  topTitle: '',
                  showDateDividers: false,
                  style: ChatUiStyleConfig.standard.copyWith(
                    messageListPadding: EdgeInsets.zero,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget asyncViewport(
    LocationChatScrollCoordinator coordinator,
    ValueListenable<int> messageCount, {
    FocusNode? composerFocusNode,
  }) {
    return MaterialApp(
      home: Scaffold(
        resizeToAvoidBottomInset: composerFocusNode != null,
        body: Column(
          children: [
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: messageCount,
                builder: (context, count, _) {
                  return NotificationListener<ScrollNotification>(
                    onNotification: coordinator.handleScrollNotification,
                    child: LocationChatAnchoredMessageList(
                      key: const ValueKey('async-location-chat-list'),
                      coordinator: coordinator,
                      messages: messages(count),
                      topTitle: '',
                      showDateDividers: false,
                      style: ChatUiStyleConfig.standard.copyWith(
                        messageListPadding: EdgeInsets.zero,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (composerFocusNode != null)
              TextField(focusNode: composerFocusNode),
          ],
        ),
      ),
    );
  }

  testWidgets('location chat disables overscroll indicators', (tester) async {
    final coordinator = LocationChatScrollCoordinator();
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(viewport(coordinator));
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey<String>('location-chat-message-scroll-configuration'),
      ),
      findsOneWidget,
    );
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
  });

  testWidgets(
    'reply generation scrolls over 500ms and respects a user interruption',
    (tester) async {
      final coordinator = LocationChatScrollCoordinator();
      addTearDown(coordinator.dispose);
      await tester.pumpWidget(viewport(coordinator));
      await tester.pumpAndSettle();
      coordinator.controller.jumpTo(0);
      coordinator.requestBottom(
        reason: LocationChatBottomReason.replyGeneration,
        behavior: LocationChatBottomBehavior.animate,
        duration: const Duration(milliseconds: 500),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final position = coordinator.controller.position;
      expect(position.pixels, greaterThan(0));
      expect(position.pixels, lessThan(position.maxScrollExtent - 24));
      await tester.pump(const Duration(milliseconds: 250));
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));

      coordinator.controller.jumpTo(0);
      coordinator.requestBottom(
        reason: LocationChatBottomReason.replyGeneration,
        behavior: LocationChatBottomBehavior.animate,
        duration: const Duration(milliseconds: 500),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(coordinator.isDetached, isTrue);
      expect(position.pixels, lessThan(position.maxScrollExtent - 24));
    },
  );

  testWidgets('async long content accepts the first user drag', (tester) async {
    final coordinator = LocationChatScrollCoordinator();
    final messageCount = ValueNotifier<int>(0);
    addTearDown(coordinator.dispose);
    addTearDown(messageCount.dispose);

    await tester.pumpWidget(asyncViewport(coordinator, messageCount));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('async-location-chat-list')),
      matching: find.byType(Scrollable),
    );
    final position = coordinator.controller.position;
    expect(position.maxScrollExtent, 0);
    expect(position.physics.shouldAcceptUserOffset(position), isTrue);

    messageCount.value = 30;
    await tester.pumpAndSettle();
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));
    final pixelsBeforeDrag = position.pixels;

    await tester.drag(scrollable, const Offset(0, 240));
    await tester.pumpAndSettle();

    expect(position.pixels, lessThan(pixelsBeforeDrag));
    expect(coordinator.mode, LocationChatViewportMode.detached);
  });

  testWidgets('async long content stays draggable across keyboard resize', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);
    final coordinator = LocationChatScrollCoordinator();
    final messageCount = ValueNotifier<int>(0);
    final composerFocusNode = FocusNode();
    void followLatestOnFocus() {
      if (!composerFocusNode.hasFocus) return;
      coordinator.requestBottom(
        reason: LocationChatBottomReason.composerFocus,
        behavior: LocationChatBottomBehavior.jump,
      );
    }

    composerFocusNode.addListener(followLatestOnFocus);
    addTearDown(coordinator.dispose);
    addTearDown(messageCount.dispose);
    addTearDown(() {
      composerFocusNode.removeListener(followLatestOnFocus);
      composerFocusNode.dispose();
    });

    await tester.pumpWidget(
      asyncViewport(
        coordinator,
        messageCount,
        composerFocusNode: composerFocusNode,
      ),
    );
    await tester.pumpAndSettle();
    messageCount.value = 30;
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('async-location-chat-list')),
      matching: find.byType(Scrollable),
    );
    final position = coordinator.controller.position;

    await tester.tap(find.byType(TextField));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(composerFocusNode.hasFocus, isTrue);
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));
    final keyboardPixelsBeforeDrag = position.pixels;

    await tester.drag(scrollable, const Offset(0, 240));
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(keyboardPixelsBeforeDrag));
    expect(coordinator.mode, LocationChatViewportMode.detached);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    final pixelsBeforePostKeyboardDrag = position.pixels;
    await tester.drag(scrollable, const Offset(0, 120));
    await tester.pumpAndSettle();

    expect(position.pixels, lessThan(pixelsBeforePostKeyboardDrag));
    expect(coordinator.mode, LocationChatViewportMode.detached);
  });

  testWidgets('every enter positions the viewport at the latest message', (
    tester,
  ) async {
    final coordinator = LocationChatScrollCoordinator();
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(viewport(coordinator));
    await tester.pumpAndSettle();
    expect(coordinator.mode, LocationChatViewportMode.followingLatest);
    expect(
      coordinator.controller.position.pixels,
      closeTo(coordinator.controller.position.maxScrollExtent, 0.1),
    );

    coordinator.controller.jumpTo(
      coordinator.controller.position.maxScrollExtent - 240,
    );
    coordinator.deactivate();
    await tester.pump();
    expect(coordinator.mode, LocationChatViewportMode.detached);

    coordinator.enter();
    await tester.pumpAndSettle();
    expect(coordinator.mode, LocationChatViewportMode.followingLatest);
    expect(
      coordinator.controller.position.pixels,
      closeTo(coordinator.controller.position.maxScrollExtent, 0.1),
    );
  });

  testWidgets('detaching cancels a queued explicit bottom request', (
    tester,
  ) async {
    final coordinator = LocationChatScrollCoordinator();
    addTearDown(coordinator.dispose);
    await tester.pumpWidget(viewport(coordinator));
    await tester.pumpAndSettle();

    coordinator.controller.jumpTo(
      coordinator.controller.position.maxScrollExtent - 240,
    );
    coordinator.deactivate();
    await tester.pump();
    final pixelsBefore = coordinator.controller.position.pixels;

    coordinator.requestBottom(
      reason: LocationChatBottomReason.unseenMessageNotice,
      behavior: LocationChatBottomBehavior.jump,
    );
    coordinator.deactivate();
    await tester.pump();

    expect(coordinator.mode, LocationChatViewportMode.detached);
    expect(coordinator.controller.position.pixels, closeTo(pixelsBefore, 0.1));
  });

  testWidgets('real user scrolling owns detached and following transitions', (
    tester,
  ) async {
    final coordinator = LocationChatScrollCoordinator();
    addTearDown(coordinator.dispose);
    await tester.pumpWidget(viewport(coordinator));
    await tester.pumpAndSettle();
    final notificationContext = tester.element(find.byType(Scrollable));

    coordinator.controller.jumpTo(
      coordinator.controller.position.maxScrollExtent - 240,
    );
    coordinator.handleScrollNotification(
      UserScrollNotification(
        metrics: coordinator.controller.position,
        context: notificationContext,
        direction: ScrollDirection.forward,
      ),
    );
    expect(coordinator.mode, LocationChatViewportMode.detached);

    coordinator.controller.jumpTo(
      coordinator.controller.position.maxScrollExtent,
    );
    coordinator.handleScrollNotification(
      UserScrollNotification(
        metrics: coordinator.controller.position,
        context: notificationContext,
        direction: ScrollDirection.reverse,
      ),
    );
    expect(coordinator.mode, LocationChatViewportMode.followingLatest);
  });

  testWidgets('a newer enter invalidates the previous entry callback', (
    tester,
  ) async {
    final coordinator = LocationChatScrollCoordinator();
    addTearDown(coordinator.dispose);
    await tester.pumpWidget(viewport(coordinator));
    await tester.pumpAndSettle();
    coordinator.controller.jumpTo(
      coordinator.controller.position.maxScrollExtent - 240,
    );
    coordinator.deactivate();
    await tester.pump();
    final generationBefore = coordinator.commandGeneration;
    final observedOffsets = <double>[];
    void recordOffset() {
      observedOffsets.add(coordinator.controller.position.pixels);
    }

    coordinator.controller.addListener(recordOffset);
    coordinator.enter();
    coordinator.enter();
    expect(coordinator.commandGeneration, generationBefore + 2);
    await tester.pump();
    coordinator.controller.removeListener(recordOffset);

    expect(observedOffsets, hasLength(1));
    expect(coordinator.mode, LocationChatViewportMode.followingLatest);
  });

  testWidgets(
    'dispose invalidates an entry callback without owning controller',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final coordinator = LocationChatScrollCoordinator(controller: controller);
      await tester.pumpWidget(viewport(coordinator));
      await tester.pumpAndSettle();
      controller.jumpTo(controller.position.maxScrollExtent - 240);
      coordinator.deactivate();
      await tester.pump();
      final pixelsBefore = controller.position.pixels;

      coordinator.enter();
      coordinator.dispose();
      await tester.pump();

      expect(controller.position.pixels, closeTo(pixelsBefore, 0.1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('one explicit request produces one bottom position change', (
    tester,
  ) async {
    final coordinator = LocationChatScrollCoordinator();
    addTearDown(coordinator.dispose);
    await tester.pumpWidget(viewport(coordinator));
    await tester.pumpAndSettle();

    coordinator.controller.jumpTo(
      coordinator.controller.position.maxScrollExtent - 240,
    );
    coordinator.deactivate();
    await tester.pump();
    final observedOffsets = <double>[];
    void recordOffset() {
      observedOffsets.add(coordinator.controller.position.pixels);
    }

    coordinator.controller.addListener(recordOffset);
    coordinator.requestBottom(
      reason: LocationChatBottomReason.unseenMessageNotice,
      behavior: LocationChatBottomBehavior.jump,
    );
    await tester.pump();
    coordinator.controller.removeListener(recordOffset);

    expect(observedOffsets, hasLength(1));
    expect(
      observedOffsets.single,
      closeTo(coordinator.controller.position.maxScrollExtent, 0.1),
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/chat/shared/chat_ui.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_page.dart';
import 'package:genesis_flutter_android/routers/app_router.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

ChatMessageVm message(
  String id, {
  String round = '',
  bool self = false,
  String type = 'character',
  String? text,
}) => ChatMessageVm(
  localId: id,
  roundId: round,
  senderId: self ? 'user' : 'alice',
  senderName: self ? 'You' : 'Alice',
  text: text ?? id,
  isMe: self,
  status: 'sent',
  senderType: type,
);

void main() {
  test(
    'latest round selection keeps AI replies and narrator but excludes users',
    () {
      final messages = [
        message('old', round: 'round-1'),
        message('user', round: 'round-2', self: true),
        message('other-user', round: 'round-2', type: 'user'),
        message('player-role', round: 'round-2')..isPlayerControlledRole = true,
        message('reply', round: 'round-2'),
        message('narrator', round: 'round-2', type: 'narrator'),
        ChatMessageVm.system('status'),
      ];
      expect(locationChatLatestEditableRound(messages).map((m) => m.localId), [
        'reply',
        'narrator',
      ]);
    },
  );

  test('missing round IDs stop at the last user or timeline boundary', () {
    expect(
      locationChatLatestEditableRound([
        message('old'),
        message('user', self: true),
        message('reply'),
        message('narrator', type: 'narrator'),
      ]).map((m) => m.localId),
      ['reply', 'narrator'],
    );
    expect(
      locationChatLatestEditableRound([
        message('old'),
        ChatMessageVm.system('time changes'),
        message('new'),
      ]).map((m) => m.localId),
      ['new'],
    );
  });

  test(
    'local edits survive rebuilds without changing the canonical message',
    () {
      final source = message('reply', text: 'Original');
      final edits = LocationChatLocalMessageEdits();
      edits.save([source], {'reply': 'Edited'});
      expect(source.text, 'Original');
      expect(edits.apply(source).text, 'Edited');
      expect(edits.apply(source).text, 'Edited');
      edits.save([source], {'reply': 'Edited again'});
      expect(edits.apply(source).text, 'Edited again');
      source.text = 'A new server version';
      expect(edits.apply(source).text, 'A new server version');
    },
  );

  test(
    'saved deletions hide messages locally without deleting canonical data',
    () {
      final source = message('reply', text: 'Original');
      final edits = LocationChatLocalMessageEdits();
      edits.save([source], {}, deletedMessageIds: {'reply'});
      expect(edits.isDeleted(source), isTrue);
      expect(source.text, 'Original');
      edits.clear();
      expect(edits.isDeleted(source), isFalse);
    },
  );

  for (final longBubble in [false, true]) {
    testWidgets(
      'editor puts caret at end and reveals ${longBubble ? "the end of a tall bubble" : "the full bubble"} above the keyboard',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetViewInsets();
          tester.view.resetDevicePixelRatio();
          return tester.binding.setSurfaceSize(null);
        });
        final targetText = List.filled(
          longBubble ? 35 : 7,
          'A line of editable dialogue.',
        ).join('\n');
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const GenesisScrollBehavior(),
            home: LocationChatEditPage(
              args: LocationChatEditPageArgs(
                style: kLocationChatStyle,
                messages: [
                  message(
                    'before',
                    round: 'latest',
                    text: List.filled(12, 'Earlier dialogue.').join('\n'),
                  ),
                  message('target', round: 'latest', text: targetText),
                  message('after', round: 'latest', text: 'Another reply.'),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('chat-message-editor-target'));
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        final fieldRect = tester.getRect(field);
        final list = find.byKey(const ValueKey('location-chat-edit-messages'));
        final visible = fieldRect.intersect(tester.getRect(list));
        await tester.tapAt(visible.topLeft + const Offset(10, 8));
        await tester.pump();
        final controller = tester.widget<TextField>(field).controller!;
        expect(
          controller.selection,
          TextSelection.collapsed(offset: targetText.length),
        );
        for (final inset in [100.0, 220.0, 320.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final bubble = tester.getRect(
          find.byKey(const ValueKey('chat-message-bubble-target')),
        );
        final viewport = tester.getRect(list);
        expect(bubble.bottom, lessThanOrEqualTo(viewport.bottom));
        if (!longBubble) {
          expect(bubble.top, greaterThanOrEqualTo(viewport.top));
          // Once focused, tapping the first line should still reposition the caret.
          await tester.tapAt(tester.getTopLeft(field) + const Offset(2, 5));
          await tester.pumpAndSettle();
          expect(controller.selection.baseOffset, lessThan(targetText.length));
        } else {
          expect(bubble.bottom, greaterThan(viewport.bottom - 60));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'edit route preserves chat surfaces, saves on Done, and cancels on back',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = [
        message('old', round: '1'),
        message('user', round: '2', self: true, text: 'Hello'),
        message('reply', round: '2', text: 'Welcome back.'),
        message(
          'narrator',
          round: '2',
          type: 'narrator',
          text: 'The room falls silent.',
        ),
      ];
      LocationChatEditResult? result;
      final args = LocationChatEditPageArgs(
        messages: source,
        style: kLocationChatStyle,
        selfMessageBubbleMaxWidthCap: 230,
        otherMessageBubbleMaxWidthCap: 230,
      );
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const GenesisScrollBehavior(),
          onGenerateRoute: AppRouter.onGenerateRoute,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.of(context)
                      .pushNamed<LocationChatEditResult>(
                        RouteNames.locationChatEdit,
                        arguments: args,
                      );
                },
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('chat-message-editor-old')),
        findsNothing,
      );
      expect(find.byType(ChatComposer), findsNothing);
      expect(
        find.byKey(const ValueKey('edit-subscription-prompt')),
        findsNothing,
      );
      final deleteDecoration =
          tester
                  .widget<Container>(
                    find.byKey(
                      const ValueKey(
                        'location-chat-edit-delete-decoration-reply',
                      ),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(
        deleteDecoration.color,
        kLocationChatStyle.composerSendButtonDisabledColor,
      );
      expect(
        deleteDecoration.borderRadius,
        BorderRadius.circular(
          kLocationChatStyle.composerSendButtonBorderRadius,
        ),
      );
      final deleteSurface = tester.widget<ChatStableBackdropSurface>(
        find.ancestor(
          of: find.byKey(const ValueKey('location-chat-edit-delete-reply')),
          matching: find.byType(ChatStableBackdropSurface),
        ),
      );
      expect(
        deleteSurface.sigma,
        kLocationChatStyle.composerSendButtonBackdropBlurSigma,
      );
      expect(
        find.byKey(const ValueKey('location-chat-background-overlay')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byType(ChatHeader)).height,
        kLocationChatStyle.headerHeight,
      );
      expect(
        tester
            .getBottomRight(
              find.byKey(const ValueKey('location-chat-edit-messages')),
            )
            .dy,
        844,
      );
      expect(
        find.byKey(const ValueKey('chat-message-editor-user')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('location-chat-edit-row-user')),
        findsNothing,
      );
      final replyBubble = tester.widget<Container>(
        find.byKey(const ValueKey('chat-message-bubble-reply')),
      );
      expect(
        (replyBubble.decoration! as BoxDecoration).color,
        kLocationChatStyle.otherBubbleColor,
      );
      final narratorBubble = tester.widget<Container>(
        find.byKey(const ValueKey('chat-system-message-bubble')),
      );
      expect(
        (narratorBubble.decoration! as BoxDecoration).color,
        chatNarratorMessageBackgroundColor(kLocationChatStyle),
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat-message-editor-reply')),
        'An edited reply.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-message-editor-narrator')),
        'A new narration.',
      );
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        source[2].text,
        'Welcome back.',
        reason: 'Edits stay in a draft until Done.',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('location-chat-edit-done')));
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      expect(result!.texts, {
        'reply': 'An edited reply.',
        'narrator': 'A new narration.',
      });
      expect(find.byType(LocationChatEditPage), findsNothing);
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chat-message-editor-reply')),
        'Discard me',
      );
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(source[2].text, 'Welcome back.');
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      for (final id in ['reply', 'narrator']) {
        final row = tester.getRect(
          find.byKey(ValueKey('location-chat-edit-row-$id')),
        );
        final button = find.byKey(ValueKey('location-chat-edit-delete-$id'));
        final buttonRect = tester.getRect(button);
        expect(buttonRect.size, const Size(24, 24));
        expect(buttonRect.top, closeTo(row.top - 8, 0.01));
        expect(buttonRect.right, closeTo(row.right, 0.01));
        // The protruding top of the button must also respond to taps.
        await tester.tapAt(Offset(buttonRect.center.dx, buttonRect.top + 2));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('location-chat-edit-row-$id')),
          findsNothing,
        );
      }
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      expect(result, isNull, reason: 'Back cancels draft deletions.');
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      await tester.tap(
        find.byKey(const ValueKey('location-chat-edit-delete-reply')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('location-chat-edit-done')));
      await tester.pumpAndSettle();
      expect(result!.deletedMessageIds, {'reply'});
      expect(result!.texts, {'narrator': 'The room falls silent.'});
      expect(source[2].text, 'Welcome back.');
      expect(tester.takeException(), isNull);
    },
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/common/genesis_center_toast.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
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

Future<void> openEditor(
  WidgetTester tester, {
  required Future<void> Function(LocationChatEditResult) onSave,
  List<ChatMessageVm>? messages,
  int? cardId,
  bool canEdit = true,
  bool canDelete = true,
  ValueNotifier<LocationChatEditExternalState>? externalState,
  ValueChanged<LocationChatEditResult>? onDraftChanged,
  VoidCallback? onCancel,
  LocationChatEditResult? initialDraft,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      scrollBehavior: const GenesisScrollBehavior(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<LocationChatEditResult>(
                builder: (_) => LocationChatEditPage(
                  args: LocationChatEditPageArgs(
                    worldId: 'world',
                    locationId: 'location',
                    roundId: 2,
                    cardId: cardId,
                    canEdit: canEdit,
                    canDelete: canDelete,
                    messages:
                        messages ??
                        [
                          message('reply', round: '2', text: 'Original reply.'),
                          message(
                            'narrator',
                            round: '2',
                            type: 'narrator',
                            text: 'Original narration.',
                          ),
                        ],
                    style: kLocationChatStyle,
                    onSave: onSave,
                    externalState: externalState,
                    onDraftChanged: onDraftChanged,
                    onCancel: onCancel,
                    initialDraft: initialDraft,
                  ),
                ),
              ),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

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

  test('missing round identities do not guess a contiguous reply block', () {
    expect(
      locationChatLatestEditableRound([
        message('old'),
        message('user', self: true),
        message('reply'),
        message('narrator', type: 'narrator'),
      ]),
      isEmpty,
    );
  });

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
                worldId: 'world',
                locationId: 'location',
                roundId: 2,
                onSave: (_) async {},
                style: kLocationChatStyle,
                messages: [
                  message(
                    'before',
                    round: '2',
                    text: List.filled(12, 'Earlier dialogue.').join('\n'),
                  ),
                  message('target', round: '2', text: targetText),
                  message('after', round: '2', text: 'Another reply.'),
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
        worldId: 'world',
        locationId: 'location',
        roundId: 2,
        onSave: (_) async {},
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

  testWidgets(
    'business save failure only shows the global toast and retains the draft',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await openEditor(
        tester,
        navigatorKey: navigatorKey,
        onSave: (_) async {
          showGenesisToastInOverlay(
            navigatorKey.currentState!.overlay!,
            '服务端编辑失败提示',
          );
          throw ApiException(
            message: '服务端编辑失败提示',
            code: 2012,
            kind: ApiExceptionKind.business,
          );
        },
      );
      final field = find.byKey(const ValueKey('chat-message-editor-reply'));
      await tester.enterText(field, 'Keep this draft.');
      await tester.tap(find.byKey(const ValueKey('location-chat-edit-done')));
      await tester.pumpAndSettle();
      expect(find.text('服务端编辑失败提示'), findsOneWidget);
      expect(find.textContaining('ApiException'), findsNothing);
      expect(find.byType(LocationChatEditPage), findsOneWidget);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Keep this draft.',
      );
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('服务端编辑失败提示'), findsNothing);
      expect(find.textContaining('2012'), findsNothing);
    },
  );

  testWidgets('Save awaits persistence and blocks repeat submission and back', (
    tester,
  ) async {
    final completion = Completer<void>();
    var saves = 0;
    var cancels = 0;
    final navigatorKey = GlobalKey<NavigatorState>();
    await openEditor(
      tester,
      navigatorKey: navigatorKey,
      onCancel: () => cancels++,
      onSave: (_) {
        saves++;
        return completion.future;
      },
    );
    await tester.enterText(
      find.byKey(const ValueKey('chat-message-editor-reply')),
      'Saved reply.',
    );
    final save = find.byKey(const ValueKey('location-chat-edit-done'));
    await tester.tap(save);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(save);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await navigatorKey.currentState!.maybePop();
    await tester.pump();
    expect(saves, 1);
    expect(cancels, 0);
    expect(find.byType(LocationChatEditPage), findsOneWidget);
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LocationChatEditPage), findsNothing);
    expect(cancels, 0);
  });

  testWidgets(
    'save failure retains text and deletions for a deliberate retry',
    (tester) async {
      final drafts = <LocationChatEditResult>[];
      final saved = <LocationChatEditResult>[];
      await openEditor(
        tester,
        onDraftChanged: drafts.add,
        onSave: (result) async {
          saved.add(result);
          if (saved.length == 1) {
            throw Exception('The reply could not be saved.');
          }
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-message-editor-reply')),
        'Edited line.\nAnother line.',
      );
      await tester.tap(
        find.byKey(const ValueKey('location-chat-edit-delete-narrator')),
      );
      await tester.pump();
      expect(drafts.last.texts, {'reply': 'Edited line.\nAnother line.'});
      expect(drafts.last.deletedMessageIds, {'narrator'});
      await tester.tap(find.byKey(const ValueKey('location-chat-edit-done')));
      await tester.pumpAndSettle();
      expect(find.byType(LocationChatEditPage), findsOneWidget);
      expect(
        find.text('Exception: The reply could not be saved.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('chat-message-editor-reply')),
            )
            .controller!
            .text,
        'Edited line.\nAnother line.',
      );
      expect(
        find.byKey(const ValueKey('location-chat-edit-row-narrator')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('location-chat-edit-done')));
      await tester.pumpAndSettle();
      expect(saved.length, 2);
      expect(saved.last.texts, saved.first.texts);
      expect(saved.last.deletedMessageIds, saved.first.deletedMessageIds);
      expect(find.byType(LocationChatEditPage), findsNothing);
    },
  );

  testWidgets(
    'candidate deletes stop at one while formal replies may be empty',
    (tester) async {
      await openEditor(tester, cardId: 20, onSave: (_) async {});
      await tester.tap(
        find.byKey(const ValueKey('location-chat-edit-delete-narrator')),
      );
      await tester.pumpAndSettle();
      final lastDelete = find.byKey(
        const ValueKey('location-chat-edit-delete-reply'),
      );
      expect(tester.widget<IconButton>(lastDelete).onPressed, isNull);
      await tester.tap(lastDelete);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('location-chat-edit-row-reply')),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      LocationChatEditResult? saved;
      await openEditor(tester, onSave: (result) async => saved = result);
      for (final id in ['reply', 'narrator']) {
        await tester.tap(find.byKey(ValueKey('location-chat-edit-delete-$id')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('location-chat-edit-done')));
      await tester.pumpAndSettle();
      expect(saved!.texts, isEmpty);
      expect(saved!.deletedMessageIds, {'reply', 'narrator'});
    },
  );

  testWidgets(
    'external freeze disables input and save, then closes after confirmation',
    (tester) async {
      final external = ValueNotifier(const LocationChatEditExternalState());
      addTearDown(external.dispose);
      var saves = 0;
      var cancels = 0;
      final drafts = <LocationChatEditResult>[];
      await openEditor(
        tester,
        externalState: external,
        onSave: (_) async {
          saves++;
        },
        onCancel: () => cancels++,
        onDraftChanged: drafts.add,
      );
      final field = find.byKey(const ValueKey('chat-message-editor-reply'));
      await tester.enterText(field, 'Draft to confirm.');
      expect(drafts.last.texts['reply'], 'Draft to confirm.');
      external.value = const LocationChatEditExternalState(
        frozen: true,
        saving: true,
      );
      await tester.pump();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('location-chat-edit-delete-reply')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('location-chat-edit-done')));
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pump();
      expect(saves, 0);
      expect(cancels, 0);
      expect(find.byType(LocationChatEditPage), findsOneWidget);
      external.value = const LocationChatEditExternalState(
        frozen: true,
        error: 'Confirmation needs recovery.',
      );
      await tester.pumpAndSettle();
      expect(find.text('Confirmation needs recovery.'), findsOneWidget);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Draft to confirm.',
      );
      external.value = const LocationChatEditExternalState(
        frozen: true,
        saved: true,
      );
      await tester.pumpAndSettle();
      expect(find.byType(LocationChatEditPage), findsNothing);
      expect(cancels, 0);
    },
  );

  testWidgets(
    'external completion only removes its own route under a later page',
    (tester) async {
      final external = ValueNotifier(const LocationChatEditExternalState());
      addTearDown(external.dispose);
      final navigatorKey = GlobalKey<NavigatorState>();
      await openEditor(
        tester,
        navigatorKey: navigatorKey,
        externalState: external,
        onSave: (_) async {},
      );
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Later page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      external.value = const LocationChatEditExternalState(
        frozen: true,
        saved: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Later page'), findsOneWidget);
      expect(
        find.byType(LocationChatEditPage, skipOffstage: false),
        findsNothing,
      );
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Open editor'), findsOneWidget);
    },
  );

  testWidgets(
    'unchanged Save avoids requests and read-only permissions are enforced',
    (tester) async {
      var saves = 0;
      await openEditor(
        tester,
        canEdit: false,
        canDelete: false,
        onSave: (_) async {
          saves++;
        },
      );
      expect(find.byType(TextField), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('location-chat-edit-delete-reply')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('location-chat-edit-done')));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.byType(LocationChatEditPage), findsNothing);
    },
  );

  testWidgets(
    'restores draft by message identity and cancel discards it once',
    (tester) async {
      var cancels = 0;
      await openEditor(
        tester,
        onSave: (_) async {},
        onCancel: () => cancels++,
        initialDraft: const LocationChatEditResult(
          texts: {'reply': 'Restored text.'},
          deletedMessageIds: {'narrator'},
        ),
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('chat-message-editor-reply')),
            )
            .controller!
            .text,
        'Restored text.',
      );
      expect(
        find.byKey(const ValueKey('location-chat-edit-row-narrator')),
        findsNothing,
      );
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      expect(cancels, 1);
    },
  );
}

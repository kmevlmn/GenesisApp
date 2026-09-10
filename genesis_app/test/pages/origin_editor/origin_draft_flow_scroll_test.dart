import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genesis_flutter_android/pages/create/create_origin_draft_store.dart';
import 'package:genesis_flutter_android/pages/origin_editor/origin_draft_repository.dart';
import 'package:genesis_flutter_android/pages/origin_editor/origin_editor_pages.dart';

void main() {
  for (final (dismissWithDone, safeBottom) in [
    (true, 0.0),
    (false, 0.0),
    (true, 34.0),
    (false, 34.0),
  ]) {
    testWidgets(
      'Update notes keeps its gap after ${dismissWithDone ? 'Done' : 'keyboard back'} with safe area $safeBottom',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 600);
        tester.view.viewPadding = FakeViewPadding(bottom: safeBottom);
        tester.view.padding = FakeViewPadding(bottom: safeBottom);
        addTearDown(tester.view.reset);
        final notes = TextEditingController();
        addTearDown(notes.dispose);
        final repository = MemoryOriginDraftRepository(
          initialDraft: CreateOriginDraft.empty(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: OriginDraftFlowPage(
              title: 'Edit Worldo',
              repository: repository,
              basicsPageBuilder: (_) => const SizedBox.shrink(),
              charactersPageBuilder: (_) => const SizedBox.shrink(),
              locationsPageBuilder: (_) => const SizedBox.shrink(),
              openingPageBuilder: (_) => const SizedBox.shrink(),
              storyEventsPageBuilder: (_) => const SizedBox.shrink(),
              submitLabel: 'Publish',
              updateNotesController: notes,
              onSubmit: (_, _, _) async =>
                  const OriginSubmitResult(message: ''),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final restingPublish = find.widgetWithText(FilledButton, 'Publish');
        expect(tester.getSize(restingPublish).height, 42);
        expect(
          tester.getRect(restingPublish).bottom,
          closeTo(600 - safeBottom - 14, 1),
        );
        final initialListBottom = tester.getRect(find.byType(ListView)).bottom;
        expect(
          tester.getRect(restingPublish).top - initialListBottom,
          closeTo(8, 1),
        );
        final field = find.widgetWithText(
          TextField,
          'What changed in this version?',
        );
        await tester.drag(find.byType(ListView), const Offset(0, -700));
        await tester.pumpAndSettle();
        await tester.tap(field);
        tester.view.padding = FakeViewPadding.zero;
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        await tester.enterText(field, 'Updated the opening scene.');
        await tester.pump();
        final inputBox = find
            .ancestor(of: field, matching: find.byType(Container))
            .first;
        expect(600 - 280 - tester.getRect(inputBox).bottom, closeTo(24, 1));
        expect(find.widgetWithText(FilledButton, 'Publish'), findsNothing);
        if (dismissWithDone) {
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();
        }
        for (final inset in [180.0, 80.0, 0.0]) {
          tester.view.padding = FakeViewPadding(
            bottom: inset == 0 ? safeBottom : 0,
          );
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pump(const Duration(milliseconds: 50));
          final firstFrameBottom = tester.getRect(inputBox).bottom;
          await tester.pump();
          expect(
            tester.getRect(inputBox).bottom,
            closeTo(firstFrameBottom, 1),
            reason: 'No post-layout scroll jump while closing the keyboard',
          );
          final restingFooterHeight = 8 + 42 + 14 + safeBottom;
          final obstruction = inset > restingFooterHeight
              ? inset
              : restingFooterHeight;
          expect(
            600 - obstruction - tester.getRect(inputBox).bottom,
            closeTo(24, 1),
          );
        }
        await tester.pumpAndSettle();
        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        expect(position.maxScrollExtent, greaterThan(0));
        expect(position.pixels, closeTo(position.maxScrollExtent, 1));
        final publish = find.widgetWithText(FilledButton, 'Publish');
        expect(publish, findsOneWidget);
        expect(tester.getSize(publish).height, 42);
        expect(
          tester.getRect(find.byType(ListView)).bottom,
          closeTo(initialListBottom, 1),
        );
        expect(
          tester.getRect(publish).top - tester.getRect(inputBox).bottom,
          closeTo(24 + 8, 1),
        );
        expect(notes.text, 'Updated the opening scene.');
        // Once the keyboard is closed, manual scrolling must remain possible.
        await tester.drag(find.byType(ListView), const Offset(0, 700));
        await tester.pumpAndSettle();
        expect(position.pixels, closeTo(0, 1));
      },
    );
  }
}

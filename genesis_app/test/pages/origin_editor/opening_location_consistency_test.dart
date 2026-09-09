import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/pages/create/create_origin_draft_store.dart';
import 'package:genesis_flutter_android/pages/origin_editor/origin_draft_repository.dart';
import 'package:genesis_flutter_android/pages/origin_editor/origin_editor_pages.dart';

const speaker = OpeningDialogueDraft(
  type: 'character',
  characterId: 'ari',
  content: 'Hello',
);
const otherSpeaker = OpeningDialogueDraft(
  type: 'character',
  characterId: 'bex',
  content: 'Hi',
);
const narration = OpeningDialogueDraft(
  type: 'narrator',
  content: 'The story begins.',
);
const room = LocationDraft(
  locationId: 'room',
  level: 3,
  name: 'Room',
  initialCharacterIds: ['ari', 'bex'],
);
CreateOriginDraft draftWith(List<OpeningDialogueDraft> dialogue) =>
    CreateOriginDraft(
      basics: const BasicsDraft(),
      basicsSaved: false,
      storyEventsSaved: false,
      characters: const [
        CharacterDraft(charId: 'ari', name: 'Ari'),
        CharacterDraft(charId: 'bex', name: 'Bex'),
      ],
      locations: const [room],
      storyEvents: const [],
      charactersSaved: true,
      locationsSaved: true,
      openingSaved: true,
      opening: OpeningDraft(
        locationId: 'room',
        locationName: 'Room',
        dialogue: dialogue,
      ),
    );

void main() {
  test(
    'saving locations removes only newly unbound speakers, preserving order',
    () {
      final draft = draftWith([speaker, narration, otherSpeaker, speaker]);
      final result = draft.withSavedLocations([
        room.copyWith(initialCharacterIds: ['bex']),
      ]);
      expect(result.opening.dialogue, [narration, otherSpeaker]);
      expect(result.openingSaved, isTrue);
      expect(result.characters, draft.characters);
      expect(
        MemoryOriginDraftRepository(initialDraft: draft).openingChanged(result),
        isTrue,
      );
    },
  );
  test(
    'removing all bubbles keeps location but requires Opening completion',
    () {
      final result = draftWith([speaker]).withSavedLocations([
        room.copyWith(initialCharacterIds: ['bex']),
      ]);
      expect(result.opening.dialogue, isEmpty);
      expect(result.opening.locationId, 'room');
      expect(result.openingSaved, isFalse);
      expect(result.validateForSubmit().join(), contains('Opening'));
    },
  );
  test(
    're-adding before saving preserves bubbles and deleting location clears Opening',
    () {
      final draft = draftWith([speaker]);
      expect(draft.withSavedLocations([room]).opening, same(draft.opening));
      final removed = draft.withSavedLocations([]);
      expect(removed.opening.locationId, isEmpty);
      expect(removed.openingSaved, isFalse);
    },
  );
  test('old invalid bindings are retained for repair and block submission', () {
    final invalid = draftWith([speaker]).copyWith(
      locations: [
        room.copyWith(initialCharacterIds: ['bex']),
      ],
    );
    final result = invalid.withSavedLocations(invalid.locations);
    expect(result.opening.dialogue, [speaker]);
    expect(
      result.validateForSubmit(),
      contains(contains('not in the selected location')),
    );
    expect(
      draftWith([speaker]).validateForSubmit(),
      isNot(contains(contains('not in the selected location'))),
    );
  });
  testWidgets(
    'cancel preserves character; confirm changes only editor until Locations Save',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = MemoryOriginDraftRepository(
        initialDraft: draftWith([
          speaker,
          narration,
        ]).copyWith(locations: [room.copyWith(level: 0)]),
      );
      await tester.pumpWidget(
        MaterialApp(home: OriginLocationsEditorPage(repository: repository)),
      );
      await tester.pumpAndSettle();
      final remove = find.byKey(
        const ValueKey('initial-character-chip-remove-ari'),
      );
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('delete 1 Opening dialogue bubble'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(remove, findsOneWidget);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(remove, findsNothing);
      expect((await repository.loadDraft()).opening.dialogue, [
        speaker,
        narration,
      ]);
      expect(
        (await repository.loadDraft()).locations.first.initialCharacterIds,
        contains('ari'),
      );
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect((await repository.loadDraft()).opening.dialogue, [narration]);
      expect(
        (await repository.loadDraft()).locations.first.initialCharacterIds,
        isNot(contains('ari')),
      );
    },
  );
  testWidgets(
    'L3 sheet stages cleanup until page Save and empty Opening keeps its location',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = MemoryOriginDraftRepository(
        initialDraft: draftWith([speaker]).copyWith(
          locations: [
            const LocationDraft(locationId: 'region', level: 1, name: 'Region'),
            const LocationDraft(
              locationId: 'building',
              parentLocationId: 'region',
              level: 2,
              name: 'Building',
            ),
            room.copyWith(parentLocationId: 'building'),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OriginLocationsEditorPage(
            repository: repository,
            useLocationTree: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('world-location-card-room'));
      await tester.tap(card);
      await tester.pumpAndSettle();
      if (find
          .byKey(const ValueKey('locations-l3-editor-sheet'))
          .evaluate()
          .isEmpty) {
        await tester.tap(card);
        await tester.pumpAndSettle();
      }
      final remove = find.byKey(
        const ValueKey('initial-character-chip-remove-ari'),
      );
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('locations-l3-editor-save')));
      await tester.pumpAndSettle();
      expect((await repository.loadDraft()).opening.dialogue, [speaker]);
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      final saved = await repository.loadDraft();
      expect(saved.opening.dialogue, isEmpty);
      expect(saved.openingSaved, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('opening-reopened'),
          home: OriginOpeningEditorPage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Room'), findsWidgets);
      expect(
        find.text('Select a location first, then edit the dialogue.'),
        findsNothing,
      );
    },
  );
}

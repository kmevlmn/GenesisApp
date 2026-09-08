import 'package:flutter/material.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/models/world.dart';
import 'package:genesis_flutter_android/pages/world/world_constants.dart';
import 'package:genesis_flutter_android/pages/world/world_header.dart';
import 'package:genesis_flutter_android/pages/world/world_sections.dart';
import 'package:genesis_flutter_android/ui/components/genesis_character_avatar.dart';

void main() {
  test('world map time label includes the current sub-tick number', () {
    expect(
      worldTimeLabel(tickIndex: 7, subTickNo: 3, worldTime: 'Day 45, 19:30'),
      'Tick 7-3 · Day 45, 19:30',
    );
  });

  test('world map time label keeps sub-tick when tick number is zero', () {
    expect(
      worldTimeLabel(tickIndex: 0, subTickNo: 3, worldTime: 'Day 1, 20:25'),
      'Tick 0-3 · Day 1, 20:25',
    );
  });

  test('world detail reads an explicit sub-tick for tick number zero', () {
    final world = WorldDetail.fromJson(const {
      'world_id': 'world-0',
      'tick_count': 0,
      'sub_tick_no': 3,
    });

    expect(world.subTickNo, 3);
  });

  test('world detail does not derive a missing sub-tick from ticks', () {
    final world = WorldDetail.fromJson(const {
      'world_id': 'world-1',
      'tick_count': 7,
      'ticks': [
        {'tick_no': 7, 'sub_tick_no': 3},
      ],
    });

    expect(world.subTickNo, 0);
  });

  test('launched loading hint uses the launched footer height', () {
    expect(
      worldInfoHeaderHeightFor(null, assumeLaunched: true),
      worldLaunchedInfoHeaderHeight,
    );
    expect(worldInfoHeaderHeightFor(null), worldInfoHeaderHeight);
  });

  testWidgets('launched footer skeleton uses the compact action size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorldInfoHeaderLoadingSkeleton(
            height: worldLaunchedInfoHeaderHeight,
            useCompactAction: true,
          ),
        ),
      ),
    );

    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('world-loading-action')),
      ),
      const Size(92, 34),
    );
  });

  testWidgets(
    'launched world footer shows the current user role and messages',
    (tester) async {
      final world = WorldDetail.fromJson(const {
        'world_id': 'world-launched',
        'tick_count': 7,
        'sub_tick_no': 3,
        'connect_count': 1280,
        'relation_status': 'owner',
        'characters': [
          {
            'char_id': 'character-other',
            'player_uid': 'user-other',
            'name': 'Other Role',
            'avatar': '',
          },
          {
            'char_id': 'character-self',
            'player_uid': 'user-self',
            'name': 'My Role',
            'avatar': '',
          },
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorldInfoHeader(
              world: world,
              currentUid: 'user-self',
              worldActionRunning: false,
              onWorldAction: (_) async {},
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('world-launched-character-summary')),
        findsOneWidget,
      );
      expect(find.text('My Role'), findsOneWidget);
      expect(find.text('Tick 7-3 · 1.3K Messages'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Tick now'), findsOneWidget);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('world-info-header-content')),
            )
            .height,
        worldLaunchedInfoHeaderHeight,
      );

      final characterName = tester.widget<Text>(
        find.byKey(const ValueKey<String>('world-current-character-name')),
      );
      expect(characterName.style?.fontSize, 14);
      expect(characterName.style?.color, GenesisColors.darkTextPrimary);
      expect(characterName.style?.fontWeight, FontWeight.w600);

      final avatar = tester.widget<GenesisCharacterAvatar>(
        find.byKey(const ValueKey<String>('world-current-character-avatar')),
      );
      final avatarPlaceholder = tester.widget<DecoratedBox>(
        find.byKey(
          const ValueKey<String>('world-current-character-avatar-placeholder'),
        ),
      );
      final avatarPlaceholderDecoration =
          avatarPlaceholder.decoration as BoxDecoration;
      expect(avatarPlaceholderDecoration.color, GenesisColors.darkFaintFill);
      expect(
        avatarPlaceholderDecoration.borderRadius,
        BorderRadius.circular(12),
      );
      expect(avatar.size, worldCharacterAvatarLogicalSize);
      expect(
        tester.getSize(
          find.byKey(const ValueKey<String>('world-current-character-avatar')),
        ),
        const Size.square(worldCharacterAvatarLogicalSize),
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(
                const ValueKey<String>('world-current-character-name'),
              ),
            )
            .dy,
        moreOrLessEquals(
          tester
              .getTopLeft(
                find.byKey(
                  const ValueKey<String>('world-current-character-avatar'),
                ),
              )
              .dy,
        ),
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Tick now'),
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey<String>('world-header-action-button')),
        ),
        const Size(92, 34),
      );
      expect(button.style?.textStyle?.resolve(<WidgetState>{})?.fontSize, 14);
      expect(
        button.style?.backgroundColor?.resolve(<WidgetState>{}),
        const Color(0xFFFF2442),
      );
    },
  );

  testWidgets('unlaunched world footer shows tick and messages', (
    tester,
  ) async {
    final world = WorldDetail.fromJson(const {
      'world_id': 'world-unlaunched',
      'tick_count': 0,
      'sub_tick_no': 1,
      'connect_count': 4,
      'relation_status': 'none',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldInfoHeader(
            world: world,
            currentUid: 'user-self',
            worldActionRunning: false,
            onWorldAction: (_) async {},
          ),
        ),
      ),
    );

    final summary = tester.widget<Text>(find.text('Tick 0-1 · 4 Messages'));
    expect(summary.style?.color, GenesisColors.darkTextSecondary);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('world-info-header-content')),
          )
          .height,
      worldInfoHeaderHeight,
    );
    expect(
      find.byKey(const ValueKey<String>('world-launched-character-summary')),
      findsNothing,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Request'),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('world-header-action-button')),
      ),
      const Size(140, 35),
    );
    expect(button.style?.textStyle?.resolve(<WidgetState>{})?.fontSize, 16);
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      const Color(0xFFFF2442),
    );
    expect(
      find.byKey(const ValueKey<String>('world-progress-button-icon')),
      findsNothing,
    );
  });
}

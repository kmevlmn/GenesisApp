import 'package:flutter/material.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/debug/world_new_content_debug_settings.dart';
import 'package:genesis_flutter_android/components/world_new_badge.dart';
import 'package:genesis_flutter_android/pages/world/world_sections.dart';
import 'package:genesis_flutter_android/ui/components/genesis_character_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    worldNewContentDebugSettings.resetForTesting();
  });

  tearDown(worldNewContentDebugSettings.resetForTesting);

  testWidgets('World Detail and Status use role ownership avatar styling', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              WorldCharacterRow(
                character: {'name': 'AI Guide', 'player_uid': '', 'avatar': ''},
                currentUid: 'user-self',
                subtitle: 'AI status',
                subtitleColor: Color(0xFF666666),
                showCharacterDetails: false,
              ),
              WorldCharacterRow(
                character: {
                  'name': 'My Role',
                  'player_uid': 'user-self',
                  'player_username': 'Owner',
                  'avatar': '',
                },
                currentUid: 'user-self',
                subtitle: 'Player status',
                subtitleColor: Color(0xFF666666),
                showCharacterDetails: false,
              ),
            ],
          ),
        ),
      ),
    );

    final avatars = tester
        .widgetList<GenesisCharacterAvatar>(find.byType(GenesisCharacterAvatar))
        .toList(growable: false);
    expect(avatars, hasLength(2));

    expect(avatars[0].border, isNull);

    final playerBorder = avatars[1].border! as Border;
    expect(playerBorder.top.color, const Color(0xFFFF2442));
    expect(playerBorder.top.width, 2);
    expect(find.textContaining('(Me)'), findsNothing);
    expect(find.text('My Role'), findsOneWidget);
  });

  test('current user character has no name suffix', () {
    expect(
      worldCharacterNameSuffix(
        currentUid: 'user-self',
        playerUid: 'user-self',
        username: 'Owner',
        playerDeleted: false,
      ),
      isEmpty,
    );
  });

  testWidgets('Player Cast rows show brief with character brief styling', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorldCharacterRow(
            character: {
              'name': 'My Role',
              'player_uid': 'user-self',
              'identity': 'Visitor',
              'brief': 'Travels between unfinished worlds',
              'goal': 'Player goals remain hidden',
              'avatar': '',
            },
            currentUid: 'user-self',
            subtitle: 'Visitor\nTravels between unfinished worlds',
            subtitleColor: Color(0xFF666666),
            showCharacterDetails: true,
          ),
        ),
      ),
    );

    final identity = tester.widget<Text>(find.text('Visitor'));
    final brief = tester.widget<Text>(
      find.text('Travels between unfinished worlds'),
    );
    expect(identity.style?.color, GenesisColors.darkTextPrimary);
    expect(brief.style?.color, GenesisColors.redSecondary);
    expect(find.text('Goal: Player goals remain hidden'), findsNothing);
    expect(find.text('No character details yet.'), findsNothing);
  });

  testWidgets('WorldCharacterRow robustly shows New beside the name', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                WorldCharacterRow(
                  character: {
                    'char_id': 'bool-new',
                    'name': 'Bool New',
                    'player_uid': '',
                    'avatar': '',
                    'is_new': true,
                  },
                  currentUid: 'user-self',
                  subtitle: '',
                  subtitleColor: Color(0xFF666666),
                  showCharacterDetails: false,
                ),
                WorldCharacterRow(
                  character: {
                    'char_id': 'number-new',
                    'name': 'Number New',
                    'player_uid': '',
                    'avatar': '',
                    'is_new': 1,
                  },
                  currentUid: 'user-self',
                  subtitle: '',
                  subtitleColor: Color(0xFF666666),
                  showCharacterDetails: false,
                ),
                WorldCharacterRow(
                  character: {
                    'char_id': 'string-new',
                    'name': 'String New',
                    'player_uid': '',
                    'avatar': '',
                    'is_new': 'true',
                  },
                  currentUid: 'user-self',
                  subtitle: '',
                  subtitleColor: Color(0xFF666666),
                  showCharacterDetails: false,
                ),
                WorldCharacterRow(
                  character: {
                    'char_id': 'old',
                    'name': 'Old Character',
                    'player_uid': '',
                    'avatar': '',
                    'is_new': false,
                  },
                  currentUid: 'user-self',
                  subtitle: '',
                  subtitleColor: Color(0xFF666666),
                  showCharacterDetails: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('world-character-new-badge-bool-new')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('world-character-new-badge-bool-new')),
      ),
      const Size(WorldNewBadge.width, WorldNewBadge.height),
    );
    expect(
      find.byKey(const ValueKey('world-character-new-badge-number-new')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('world-character-new-badge-string-new')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('world-character-new-badge-old')),
      findsNothing,
    );
    expect(
      tester.getRect(find.text('Bool New')).center.dy,
      closeTo(
        tester
            .getRect(
              find.byKey(const ValueKey('world-character-new-badge-bool-new')),
            )
            .center
            .dy,
        0.01,
      ),
    );
  });

  testWidgets('WorldCharacterRow honors the force-new debug override', (
    tester,
  ) async {
    await worldNewContentDebugSettings.setForceNewBadges(true);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorldCharacterRow(
            character: {
              'char_id': 'server-old',
              'name': 'Server Old',
              'is_new': false,
            },
            currentUid: 'user-self',
            subtitle: '',
            subtitleColor: Color(0xFF666666),
            showCharacterDetails: false,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('world-character-new-badge-server-old')),
      findsOneWidget,
    );
  });
}

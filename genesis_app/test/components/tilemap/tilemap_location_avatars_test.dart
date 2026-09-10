import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/tilemap/tilemap_location_avatars.dart';
import 'package:genesis_flutter_android/components/world_point.dart';
import 'package:genesis_flutter_android/ui/components/genesis_character_avatar.dart';

void main() {
  testWidgets('map avatars omit new while preserving role ownership styling', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: TilemapLocationAvatars(
            avatars: [
              UserAvatar('AI', id: 'ai', name: 'AI Role', isNew: true),
              UserAvatar(
                'PR',
                id: 'player',
                name: 'Player Role',
                isPlayerControlledRole: true,
              ),
            ],
          ),
        ),
      ),
    );

    GenesisCharacterAvatar avatarFor(String id) {
      return tester.widget<GenesisCharacterAvatar>(
        find.descendant(
          of: find.byKey(ValueKey<String>('tilemap-location-avatar-$id')),
          matching: find.byType(GenesisCharacterAvatar),
        ),
      );
    }

    final aiAvatar = avatarFor('ai');
    final playerAvatar = avatarFor('player');
    expect(aiAvatar.size, 36);
    expect(playerAvatar.size, 36);

    expect(aiAvatar.border, isNull);

    final playerBorder = playerAvatar.border! as Border;
    expect(playerBorder.top.color, const Color(0xFFFF2442));
    expect(playerBorder.top.width, 2);
    expect(
      find.byKey(const ValueKey<String>('tilemap-avatar-new-badge-ai')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('tilemap-avatar-new-badge-player')),
      findsNothing,
    );
  });
}

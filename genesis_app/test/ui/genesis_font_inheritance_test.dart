import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/models/world.dart';
import 'package:genesis_flutter_android/pages/world/world_bottom_sheet.dart';
import 'package:genesis_flutter_android/pages/world/world_models.dart';
import 'package:genesis_flutter_android/pages/world/world_sections.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_dark_theme.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';
import 'package:genesis_flutter_android/ui/components/genesis_primary_button.dart';

import '../support/font_expectations.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('primary and secondary button styles keep Inter on $platform', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GenesisTheme.light().copyWith(platform: platform),
          home: GenesisDarkTheme(
            child: Scaffold(
              body: Column(
                children: [
                  GenesisPrimaryButton(label: 'Save', onPressed: () {}),
                  const GenesisPrimaryButton(label: 'Create', onPressed: null),
                  GenesisSecondaryButton(label: 'Cancel', onPressed: () {}),
                  const GenesisSecondaryButton(
                    label: 'Disabled',
                    onPressed: null,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expectInterText(tester, find.byType(Scaffold));
    });

    testWidgets('World labels and join notice keep Inter on $platform', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GenesisTheme.light().copyWith(platform: platform),
          home: GenesisDarkTheme(
            child: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    WorldBottomTags(onTap: (_) {}),
                    WorldDetailSection(
                      world: WorldDetail.fromJson({'name': 'Font audit world'}),
                      currentUid: '',
                      showCharacters: false,
                      newUserJoinNotice: const WorldNewUserJoinNotice(
                        characterId: 'character',
                        characterType: 'user',
                        characterName: 'Mira',
                        playerUid: 'player',
                        playerUsername: 'Alex',
                        ts: null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectInterText(tester, find.byType(WorldBottomTags));
      final notice = find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('Alex playing as Mira'),
      );
      expect(notice, findsOneWidget);
      expectInterText(tester, notice);
    });
  }
}

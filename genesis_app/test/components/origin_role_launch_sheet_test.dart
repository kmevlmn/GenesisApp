import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/origin/origin_role_launch_sheet.dart';
import 'package:genesis_flutter_android/network/models/origin.dart';
import 'package:genesis_flutter_android/ui/components/genesis_character_avatar.dart';
import 'package:genesis_flutter_android/ui/components/genesis_primary_button.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/components/common/genesis_bottom_sheet_panel.dart';

void main() {
  testWidgets('role sheet has two dark tabs and a text-only custom launch', (
    tester,
  ) async {
    OriginRoleLaunchSelection? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OriginRoleLaunchSheet(
            characters: const [],
            onLaunch: (value) async {
              selection = value;
              return OriginRoleLaunchHandlerResult.failed;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Preset'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Playing'), findsNothing);
    expect(find.text('Enter'), findsNothing);
    final panel = find.byType(GenesisBottomSheetPanel);
    final material = tester.widget<Material>(
      find.descendant(of: panel, matching: find.byType(Material)).first,
    );
    expect(material.color, GenesisColors.darkRaisedBackground);
    var launch = tester.widget<GenesisPrimaryButton>(
      find.byKey(const ValueKey('origin-role-launch')),
    );
    expect(launch.leadingIcon, isNull);
    expect(launch.onPressed, isNull);
    expect(launch.onDisabledPressed, isNotNull);
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    final name = tester.widget<TextField>(fields.at(0));
    expect(name.style?.color, GenesisColors.darkTextPrimary);
    expect(name.cursorColor, GenesisColors.darkTextPrimary);
    expect(
      tester
          .widgetList<Container>(
            find.ancestor(of: fields.at(0), matching: find.byType(Container)),
          )
          .map((widget) => widget.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.color),
      contains(GenesisColors.darkFaintFill),
    );
    await tester.enterText(fields.at(0), 'Mira');
    await tester.enterText(fields.at(1), 'Navigator');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    launch = tester.widget<GenesisPrimaryButton>(
      find.byKey(const ValueKey('origin-role-launch')),
    );
    expect(launch.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('origin-role-launch')));
    await tester.pumpAndSettle();
    expect(selection?.customRole?.name, 'Mira');
    expect(selection?.customRole?.identity, 'Navigator');
  });

  testWidgets('recommended preset roles are first and show an indicator', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OriginRoleLaunchSheet(
            characters: [
              OriginCharacter(
                id: 1,
                characterId: 'preset_regular_1',
                originId: 1,
                name: 'Regular one',
                avatar: '',
                tags: '',
                currentLocationId: 0,
                initialLocationId: 0,
                createdAt: null,
                updatedAt: null,
              ),
              OriginCharacter(
                id: 2,
                characterId: 'preset_recommended',
                originId: 1,
                name: 'Recommended',
                avatar: '',
                tags: '',
                currentLocationId: 0,
                initialLocationId: 0,
                isRecommend: 1,
                createdAt: null,
                updatedAt: null,
              ),
              OriginCharacter(
                id: 3,
                characterId: 'preset_regular_2',
                originId: 1,
                name: 'Regular two',
                avatar: '',
                tags: '',
                currentLocationId: 0,
                initialLocationId: 0,
                createdAt: null,
                updatedAt: null,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final recommendedTile = find.byKey(
      const ValueKey('origin-role-preset-preset_recommended'),
    );
    final regularOneTile = find.byKey(
      const ValueKey('origin-role-preset-preset_regular_1'),
    );
    final regularTwoTile = find.byKey(
      const ValueKey('origin-role-preset-preset_regular_2'),
    );

    expect(
      tester.getTopLeft(recommendedTile).dx,
      lessThan(tester.getTopLeft(regularOneTile).dx),
    );
    expect(
      tester.getTopLeft(regularOneTile).dx,
      lessThan(tester.getTopLeft(regularTwoTile).dx),
    );
    final recommendedMark = find.byKey(
      const ValueKey('origin-role-preset-recommended-preset_recommended'),
    );
    expect(recommendedMark, findsOneWidget);
    expect(tester.getSize(recommendedMark), const Size.square(22));
    expect(
      find.descendant(
        of: recommendedMark,
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsOneWidget,
    );
    final markBackground = tester.widget<DecoratedBox>(
      find.descendant(of: recommendedMark, matching: find.byType(DecoratedBox)),
    );
    final markDecoration = markBackground.decoration as BoxDecoration;
    expect(markDecoration.color, const Color(0xCCFFFFFF));
    expect(markDecoration.borderRadius, BorderRadius.circular(8));
    final recommendedAvatar = find.descendant(
      of: recommendedTile,
      matching: find.byType(GenesisCharacterAvatar),
    );
    final avatarRect = tester.getRect(recommendedAvatar);
    final markRect = tester.getRect(recommendedMark);
    expect(markRect.left, avatarRect.left + 4);
    expect(markRect.bottom, avatarRect.bottom - 4);
    expect(avatarRect.contains(markRect.topLeft), isTrue);
    expect(
      avatarRect.contains(markRect.bottomRight - const Offset(1, 1)),
      isTrue,
    );
    expect(
      find.byKey(
        const ValueKey('origin-role-preset-recommended-preset_regular_1'),
      ),
      findsNothing,
    );
  });

  testWidgets('route keeps the requested transparent status bar style', (
    WidgetTester tester,
  ) async {
    const style = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showOriginRoleLaunchSheet(
                  context: context,
                  characters: const <OriginCharacter>[],
                  systemUiOverlayStyle: style,
                ),
              ),
              child: const Text('Show setup'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show setup'));
    await tester.pump();

    expect(
      tester
          .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .any((region) => region.value == style),
      isTrue,
    );
  });

  testWidgets('launch stays in the sheet and shows button loading', (
    WidgetTester tester,
  ) async {
    var launchCompleter = Completer<OriginRoleLaunchHandlerResult>();
    OriginRoleLaunchSelection? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showOriginRoleLaunchSheet(
                  context: context,
                  characters: const [
                    OriginCharacter(
                      id: 1,
                      characterId: 'preset_1',
                      originId: 1,
                      name: 'Preset role',
                      avatar: '',
                      tags: '',
                      currentLocationId: 0,
                      initialLocationId: 0,
                      createdAt: null,
                      updatedAt: null,
                    ),
                  ],
                  onLaunch: (_) => launchCompleter.future,
                );
              },
              child: const Text('Show setup'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show setup'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('origin-role-preset-preset_1')));
    await tester.tap(find.byKey(const ValueKey('origin-role-launch')));
    await tester.pump();

    expect(find.byKey(const ValueKey('origin-role-sheet')), findsOneWidget);
    expect(
      tester
          .widget<GenesisPrimaryButton>(
            find.byKey(const ValueKey('origin-role-launch')),
          )
          .isLoading,
      isTrue,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: find.byKey(const ValueKey('origin-role-cancel')),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const ValueKey('origin-role-sheet-close')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    launchCompleter.complete(OriginRoleLaunchHandlerResult.failed);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('origin-role-sheet')), findsOneWidget);
    expect(
      tester
          .widget<GenesisPrimaryButton>(
            find.byKey(const ValueKey('origin-role-launch')),
          )
          .isLoading,
      isFalse,
    );

    launchCompleter = Completer<OriginRoleLaunchHandlerResult>();
    await tester.tap(find.byKey(const ValueKey('origin-role-launch')));
    await tester.pump();
    launchCompleter.complete(OriginRoleLaunchHandlerResult.closeSheet);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('origin-role-sheet')), findsNothing);
    expect(result?.presetCharacterId, 'preset_1');
  });
}

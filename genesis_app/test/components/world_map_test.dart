import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/legacy_world_map/legacy_world_map.dart';
import 'package:genesis_flutter_android/components/legacy_world_map/legacy_world_map_gesture.dart';
import 'package:genesis_flutter_android/components/world_details_shell.dart';
import 'package:genesis_flutter_android/components/world_map.dart';
import 'package:genesis_flutter_android/components/world_map_exit_location_button.dart';
import 'package:genesis_flutter_android/components/world_map_interaction_notification.dart';
import 'package:genesis_flutter_android/icons/custom_icon_assets.dart';
import 'package:genesis_flutter_android/icons/my_flutter_app_icons.dart';
import 'package:genesis_flutter_android/network/mock_data/mock_v1_data.dart';
import 'package:genesis_flutter_android/ui/components/genesis_character_avatar.dart';
import 'package:genesis_flutter_android/ui/components/recent_chat_marker.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('initial zoom focus uses location with the most avatars', () {
    final focus = worldMapInitialZoomFocusForTesting([
      const WorldPoint(
        id: 'empty',
        name: 'Empty',
        type: WorldPointType.castle,
        position: Offset(0.1, 0.2),
        users: <UserAvatar>[],
      ),
      const WorldPoint(
        id: 'one',
        name: 'One',
        type: WorldPointType.castle,
        position: Offset(0.3, 0.4),
        users: <UserAvatar>[UserAvatar('A')],
      ),
      const WorldPoint(
        id: 'three',
        name: 'Three',
        type: WorldPointType.castle,
        position: Offset(0.7, 0.8),
        users: <UserAvatar>[UserAvatar('A'), UserAvatar('B'), UserAvatar('C')],
      ),
    ]);

    expect(focus, const Offset(0.7, 0.8));
  });

  test('mock world data includes dense map points and default map asset', () {
    expect(kMockV1Locations.length, greaterThanOrEqualTo(9));

    final countsByLocation = <String, int>{};
    for (final character in kMockV1Characters) {
      final locationId = '${character['location_id']}';
      countsByLocation[locationId] = (countsByLocation[locationId] ?? 0) + 1;
    }

    expect(countsByLocation['loc_hub'], 3);
    expect(countsByLocation['loc_gate'], greaterThanOrEqualTo(4));
    expect(countsByLocation['loc_market'], greaterThanOrEqualTo(5));
    expect(
      File('assets/images/map_default/root_default.webp').existsSync(),
      isTrue,
      reason: 'assets/images/map_default/root_default.webp',
    );
    for (final origin in kMockV1Origins) {
      expect(origin['cover'], isEmpty);
    }
    for (final world in kMockV1Worlds) {
      expect(world['cover'], isEmpty);
    }

    final avatarPaths = kMockV1Characters
        .map((character) => '${character['avatar']}')
        .where((path) => path.startsWith('assets/images/mock_avatars/'))
        .toSet();
    expect(avatarPaths, isEmpty);

    final locationCoverPaths = kMockV1Locations
        .map((location) => '${location['image']}')
        .where((path) => path.startsWith('assets/images/mock_locations/'))
        .toSet();
    expect(locationCoverPaths, isEmpty);

    final locationMapPaths = kMockV1Locations
        .map((location) => '${location['map_url']}')
        .where((path) => path.startsWith('assets/images/map_default/'))
        .toSet();
    expect(locationMapPaths, isEmpty);
  });

  testWidgets('world map lays out fewer than four avatars in one row', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      mapImageUrl: kMockV1SteamMapImage,
      users: const [
        UserAvatar(
          'AA',
          name: 'Ada',
          avatarUrl: 'assets/images/default_list_image.png',
        ),
        UserAvatar(
          'BB',
          name: 'Bert',
          avatarUrl: 'assets/images/default_list_image.png',
        ),
        UserAvatar(
          'CC',
          name: 'Cy',
          avatarUrl: 'assets/images/default_list_image.png',
        ),
      ],
    );

    final avatars = find.byType(GenesisCharacterAvatar);
    expect(avatars, findsNWidgets(3));
    expect(tester.getSize(avatars.first), const Size(36, 36));
    expect(
      tester.widget<GenesisCharacterAvatar>(avatars.first).boxShadow,
      isNotEmpty,
    );
    expect(find.byIcon(MyFlutterApp.redstarCharIcon), findsNothing);

    final first = tester.getTopLeft(avatars.at(0));
    final second = tester.getTopLeft(avatars.at(1));
    final third = tester.getTopLeft(avatars.at(2));
    expect(second.dy, first.dy);
    expect(third.dy, first.dy);
    expect(second.dx, greaterThan(first.dx));
    expect(third.dx, greaterThan(second.dx));
  });

  testWidgets('world map wraps Chinese labels after six characters', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [
        WorldPoint(
          id: 'silicon-valley',
          name: '中国',
          type: WorldPointType.portal,
          position: Offset(0.35, 0.35),
          users: [],
        ),
        WorldPoint(
          id: 'seattle',
          name: '西雅图',
          type: WorldPointType.camp,
          position: Offset(0.65, 0.35),
          users: [],
        ),
        WorldPoint(
          id: 'startup-street',
          name: '中关村创业大街中心',
          type: WorldPointType.shop,
          position: Offset(0.5, 0.55),
          users: [],
        ),
      ],
    );

    final china = tester.renderObject<RenderParagraph>(find.text('中国'));
    final seattle = tester.renderObject<RenderParagraph>(find.text('西雅图'));
    final startupStreet = tester.renderObject<RenderParagraph>(
      find.text('中关村创业大街中心'),
    );

    expect(china.didExceedMaxLines, isFalse);
    expect(seattle.didExceedMaxLines, isFalse);
    expect(startupStreet.didExceedMaxLines, isFalse);
    expect(china.size.height, lessThanOrEqualTo(12.0));
    expect(seattle.size.height, lessThanOrEqualTo(12.0));
    expect(startupStreet.size.width, lessThanOrEqualTo(90.0));
    expect(startupStreet.size.height, greaterThan(12.0));
  });

  testWidgets(
    'legacy world map sizes wrapped labels to their longest line and clears dot',
    (tester) async {
      const name = 'Sala Común De Slytherin';
      await _pumpWorldMap(
        tester,
        users: const [],
        inheritedTextMaxLines: 1,
        points: const <WorldPoint>[
          WorldPoint(
            id: 'wrapped-label',
            name: name,
            type: WorldPointType.portal,
            position: _pointPosition,
            users: <UserAvatar>[],
          ),
        ],
      );

      final painter = TextPainter(
        text: const TextSpan(
          text: name,
          style: TextStyle(
            fontSize: 12,
            height: 1.2,
            leadingDistribution: TextLeadingDistribution.even,
            fontWeight: FontWeight.w600,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 135);
      final longestLine = painter.computeLineMetrics().fold<double>(
        0,
        (width, line) => math.max(width, line.width),
      );
      final expectedLabelWidth = longestLine.ceilToDouble() + 6;

      final labelRect = tester.getRect(
        find.byKey(
          const ValueKey<String>('world-map-location-label-wrapped-label'),
        ),
      );
      final dotRect = tester.getRect(
        find.byKey(const ValueKey<String>('world-map-location-dot')),
      );
      final paragraph = tester.renderObject<RenderParagraph>(find.text(name));

      final expectedLineCount = painter.computeLineMetrics().length;
      expect(expectedLineCount, greaterThan(1));
      expect(paragraph.maxLines, expectedLineCount);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(labelRect.width, closeTo(expectedLabelWidth, 0.01));
      expect(labelRect.width, lessThan(141));
      expect(labelRect.height, closeTo(painter.height + 8, 0.01));
      expect(dotRect.top - labelRect.bottom, closeTo(6, 0.01));
    },
  );

  testWidgets('world map renders recent chat icon outside centered label', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const <WorldPoint>[
        WorldPoint(
          id: 'point-1',
          sceneId: 'location-1',
          name: 'Gate',
          type: WorldPointType.portal,
          position: _pointPosition,
          users: <UserAvatar>[],
        ),
      ],
      recentChatMapLocationIds: const <String>{'location-1'},
    );

    final labelRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-map-location-label-point-1')),
    );
    final iconRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-map-recent-chat-icon')),
    );
    final dotRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-map-location-dot')),
    );

    expect(iconRect.right, closeTo(labelRect.left - 3, 0.01));
    expect(iconRect.center.dy, closeTo(labelRect.center.dy, 0.01));
    expect(labelRect.center.dx, closeTo(dotRect.center.dx, 0.01));
    expect(iconRect.size, const Size.square(16));
    final iconBadge = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('world-map-recent-chat-icon')),
    );
    expect(
      (iconBadge.decoration as BoxDecoration).color,
      kRecentChatMapBadgeBackgroundColor,
    );
  });

  testWidgets('world map renders event count on the location name', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const <WorldPoint>[
        WorldPoint(
          id: 'point-1',
          sceneId: 'location-1',
          name: 'Gate',
          type: WorldPointType.portal,
          position: _pointPosition,
          users: <UserAvatar>[],
        ),
      ],
      eventMapLocationIds: const <String>{'location-1'},
      recentChatMapLocationIds: const <String>{'location-1'},
    );

    final labelRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-map-location-label-point-1')),
    );
    final eventRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-map-location-event-count')),
    );
    final recentRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-map-recent-chat-icon')),
    );
    final dotRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-map-location-dot')),
    );

    expect(eventRect.size, const Size(14, 14));
    expect(eventRect.left, closeTo(labelRect.right + 3, 0.01));
    expect(eventRect.center.dy, closeTo(labelRect.center.dy, 0.01));
    expect(recentRect.right, closeTo(labelRect.left - 3, 0.01));
    expect(recentRect.center.dy, closeTo(labelRect.center.dy, 0.01));
    expect(labelRect.center.dx, closeTo(dotRect.center.dx, 0.01));
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('world-map-location-event-count'),
        ),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('world map renders new for locations but not character avatars', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const <WorldPoint>[
        WorldPoint(
          id: 'new-point',
          name: 'New Gate',
          type: WorldPointType.portal,
          position: _pointPosition,
          isNew: true,
          users: <UserAvatar>[
            UserAvatar('AA', id: 'new-character', name: 'Ada', isNew: true),
          ],
        ),
      ],
    );

    final labelRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-map-location-label-new-point')),
    );
    final badgeRect = tester.getRect(
      find.byKey(
        const ValueKey<String>('world-map-location-new-badge-new-point'),
      ),
    );
    final dotRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-map-location-dot')),
    );
    expect(badgeRect.left, closeTo(labelRect.right + 3, 0.01));
    expect(badgeRect.center.dy, closeTo(labelRect.center.dy, 0.01));
    expect(labelRect.center.dx, closeTo(dotRect.center.dx, 0.01));
    expect(
      find.byKey(
        const ValueKey<String>('world-map-avatar-new-badge-new-character'),
      ),
      findsNothing,
    );
  });

  testWidgets('world map renders generated avatar when avatar URL is empty', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('LP', id: 'larry-page', name: 'Larry Page')],
    );

    expect(find.byType(GenesisCharacterAvatar), findsOneWidget);
    expect(find.text('LP'), findsOneWidget);
  });

  testWidgets('world map shows bubble for matching visible avatar', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('AA', id: 'char_a', name: 'Ava')],
      activeBubble: const WorldMapMessageBubble(
        characterId: 'char_a',
        content: 'Ava checks the storefront.',
      ),
    );

    expect(find.text('Ava checks the storefront.'), findsOneWidget);
  });

  testWidgets('tapping a message bubble opens its location', (tester) async {
    final tappedIds = <String>[];
    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('AA', id: 'char_a', name: 'Ava')],
      activeBubble: const WorldMapMessageBubble(
        characterId: 'char_a',
        content: 'Ava checks the storefront.',
      ),
      onPointTap: (point) => tappedIds.add(point.id),
    );

    await tester.tap(find.text('Ava checks the storefront.'));

    expect(tappedIds, ['point-1']);
  });

  testWidgets('world map bubble uses the shared map bubble style', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('AA', id: 'char_a', name: 'Ava')],
      activeBubble: const WorldMapMessageBubble(
        characterId: 'char_a',
        content: 'Ava checks the storefront.',
      ),
    );

    final surface = find.byType(WorldMapMessageBubbleSurface);
    expect(surface, findsOneWidget);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: surface,
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, const Color(0xCC3A3942));
    expect(decoration.borderRadius, BorderRadius.circular(8));
    expect(
      find.descendant(of: surface, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    final text = tester.widget<Text>(find.text('Ava checks the storefront.'));
    expect(text.style?.fontSize, 12);
    expect(text.style?.height, 1.2);
    expect(text.style?.color, const Color(0xFFF4F3F6));
  });

  testWidgets('world map bubble adapts width up to the maximum', (
    tester,
  ) async {
    const bubbleBodyKey = ValueKey<String>('world-map-message-bubble-body');
    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('AA', id: 'char_a', name: 'Ava')],
      activeBubble: const WorldMapMessageBubble(
        characterId: 'char_a',
        content: 'who are you',
      ),
    );

    final shortSize = tester.getSize(find.byKey(bubbleBodyKey));
    final shortTextSize = tester.getSize(find.text('who are you'));

    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('AA', id: 'char_a', name: 'Ava')],
      activeBubble: const WorldMapMessageBubble(
        characterId: 'char_a',
        content:
            'Ava checks the storefront, counts every crate, and writes down '
            'the route before the market opens.',
      ),
    );

    final longSize = tester.getSize(find.byKey(bubbleBodyKey));
    expect(shortSize.width, lessThan(longSize.width));
    expect(shortTextSize.height, closeTo(14, 0.01));
    expect(longSize.width, worldMapMessageBubbleMaxWidth);
    expect(shortSize.height, lessThan(longSize.height));
  });

  testWidgets('world map hides bubble when avatar is not visible', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('AA', id: 'char_a', name: 'Ava')],
      activeBubble: const WorldMapMessageBubble(
        characterId: 'char_b',
        content: 'Ben is elsewhere.',
      ),
    );

    expect(find.text('Ben is elsewhere.'), findsNothing);
  });

  testWidgets('world map paints message bubbles above all point markers', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [
        WorldPoint(
          id: 'point-a',
          name: 'Gate',
          type: WorldPointType.portal,
          position: Offset(0.5, 0.35),
          users: [UserAvatar('AA', id: 'char_a', name: 'Ava')],
        ),
        WorldPoint(
          id: 'point-b',
          name: 'Market',
          type: WorldPointType.shop,
          position: Offset(0.5, 0.35),
          users: [],
        ),
      ],
      activeBubble: const WorldMapMessageBubble(
        characterId: 'char_a',
        content: 'Ava checks the storefront.',
      ),
    );

    final widgets = tester.allWidgets.toList(growable: false);
    final lastPointMarkerLayer = widgets.lastIndexWhere(
      (widget) =>
          widget.runtimeType.toString() == 'LegacyWorldMapPointPositioned',
    );
    final bubbleOverlayLayer = widgets.indexWhere(
      (widget) =>
          widget.runtimeType.toString() ==
          'LegacyWorldMapPointMessageBubblePositioned',
    );

    expect(find.text('Ava checks the storefront.'), findsOneWidget);
    expect(lastPointMarkerLayer, greaterThanOrEqualTo(0));
    expect(bubbleOverlayLayer, greaterThan(lastPointMarkerLayer));
  });

  testWidgets('world map loops a single queued bubble with a gap', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('AA', id: 'char_a', name: 'Ava')],
      messageBubbles: const [
        WorldMapMessageBubble(
          characterId: 'char_a',
          content: 'Ava checks the storefront.',
        ),
      ],
    );

    expect(find.text('Ava checks the storefront.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Ava checks the storefront.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Ava checks the storefront.'), findsOneWidget);
  });

  testWidgets('world map paginates a long bubble before the playback gap', (
    tester,
  ) async {
    const longText =
        'Ava counts every crate in the storefront twice before sunrise, '
        'then writes a sharper plan for the delivery route that keeps the '
        'whole block supplied before noon while the market trucks idle at '
        'the corner and the night manager waits for one clean answer.';
    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('AA', id: 'char_a', name: 'Ava')],
      messageBubbles: const [
        WorldMapMessageBubble(characterId: 'char_a', content: longText),
      ],
    );
    final pages = resolveWorldMapMessageBubblePages(
      tester.element(
        find.byKey(const ValueKey<String>('world-map-message-bubble-body')),
      ),
      longText,
    );

    expect(pages, hasLength(greaterThan(1)));
    expect(find.text(pages.first), findsOneWidget);
    for (final page in pages.skip(1)) {
      await tester.pump(const Duration(seconds: 4));
      expect(find.text(page), findsOneWidget);
    }

    await tester.pump(const Duration(seconds: 4));
    expect(find.text(pages.last), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(pages.first), findsOneWidget);
  });

  testWidgets('world map keeps the first-page width for a short remainder', (
    tester,
  ) async {
    final longText = '${List<String>.filled(29, 'word').join(' ')} tail';
    const bubbleBodyKey = ValueKey<String>('world-map-message-bubble-body');
    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('AA', id: 'char_a', name: 'Ava')],
      messageBubbles: [
        WorldMapMessageBubble(characterId: 'char_a', content: longText),
      ],
    );
    final pages = resolveWorldMapMessageBubblePages(
      tester.element(find.byKey(bubbleBodyKey)),
      longText,
    );

    final firstPageWidth = tester.getSize(find.byKey(bubbleBodyKey)).width;

    await tester.pump(const Duration(seconds: 4));
    expect(find.text(pages[1]), findsOneWidget);
    final remainderWidth = tester.getSize(find.byKey(bubbleBodyKey)).width;

    expect(firstPageWidth, worldMapMessageBubbleMaxWidth);
    expect(remainderWidth, firstPageWidth);
  });

  testWidgets('world map pauses bubble playback while location chat is open', (
    tester,
  ) async {
    const longText =
        'Ava counts every crate in the storefront twice before sunrise, '
        'then writes a sharper plan for the delivery route that keeps the '
        'whole block supplied before noon while the market trucks idle at '
        'the corner and the night manager waits for one clean answer.';
    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('AA', id: 'char_a', name: 'Ava')],
      messageBubbles: const [
        WorldMapMessageBubble(characterId: 'char_a', content: longText),
      ],
    );
    final pages = resolveWorldMapMessageBubblePages(
      tester.element(
        find.byKey(const ValueKey<String>('world-map-message-bubble-body')),
      ),
      longText,
    );

    await tester.pump(const Duration(seconds: 4));
    expect(find.text(pages[1]), findsOneWidget);

    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('AA', id: 'char_a', name: 'Ava')],
      messageBubbles: const [
        WorldMapMessageBubble(characterId: 'char_a', content: longText),
      ],
      messageBubblePlaybackPaused: true,
    );
    expect(find.text(pages[1]), findsNothing);

    await tester.pump(const Duration(seconds: 10));
    expect(find.text(pages[1]), findsNothing);

    await _pumpWorldMap(
      tester,
      users: const [UserAvatar('AA', id: 'char_a', name: 'Ava')],
      messageBubbles: const [
        WorldMapMessageBubble(characterId: 'char_a', content: longText),
      ],
    );
    expect(find.text(pages[1]), findsOneWidget);
  });

  test('player controlled map avatar uses highlighted border', () {
    expect(
      worldMapAvatarBorderColorForTesting(isPlayerControlledRole: true),
      const Color(0xFFFF2442),
    );
    expect(
      worldMapAvatarBorderColorForTesting(isPlayerControlledRole: false),
      isNull,
    );
  });

  testWidgets('world map AI avatar is plain and player role has a red border', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [
        UserAvatar('AI', id: 'ai', name: 'AI Role'),
        UserAvatar(
          'PR',
          id: 'player',
          name: 'Player Role',
          isPlayerControlledRole: true,
        ),
      ],
    );

    final avatars = tester
        .widgetList<GenesisCharacterAvatar>(find.byType(GenesisCharacterAvatar))
        .toList(growable: false);
    expect(avatars, hasLength(2));

    expect(avatars[0].border, isNull);

    final playerBorder = avatars[1].border! as Border;
    expect(playerBorder.top.color, const Color(0xFFFF2442));
    expect(playerBorder.top.width, 2);
  });

  testWidgets(
    'world map moves point anchors with zoom without scaling markers',
    (tester) async {
      await _pumpWorldMap(
        tester,
        mapImageUrl: kMockV1SteamMapImage,
        users: const [
          UserAvatar(
            'AA',
            name: 'Ada',
            avatarUrl: 'assets/images/default_list_image.png',
          ),
        ],
      );

      final interactiveViewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );

      expect(interactiveViewer.minScale, 1);
      expect(interactiveViewer.maxScale, 2);
      expect(interactiveViewer.panEnabled, isTrue);
      expect(
        find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.byType(GenesisCharacterAvatar),
        ),
        findsNothing,
      );
      final avatar = find.byType(GenesisCharacterAvatar);
      expect(avatar, findsOneWidget);

      final initialAvatarTopLeft = tester.getTopLeft(avatar);
      final initialAvatarSize = tester.getSize(avatar);
      final first = await tester.createGesture(pointer: 1);
      final second = await tester.createGesture(pointer: 2);

      await first.down(const Offset(110, 520));
      await second.down(const Offset(250, 520));
      await tester.pump();
      await first.moveTo(const Offset(70, 560));
      await second.moveTo(const Offset(290, 480));
      await tester.pump();
      await second.up();
      await first.up();
      await tester.pump();

      expect(tester.getSize(avatar), initialAvatarSize);
      expect(tester.getTopLeft(avatar), isNot(initialAvatarTopLeft));
    },
  );

  testWidgets('world map pinches when both pointers start on map markers', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      mapImageUrl: kMockV1SteamMapImage,
      users: const [
        UserAvatar(
          'AA',
          name: 'Ada',
          avatarUrl: 'assets/images/default_list_image.png',
        ),
      ],
    );

    final avatar = find.byType(GenesisCharacterAvatar);
    expect(avatar, findsOneWidget);
    final initialAvatarTopLeft = tester.getTopLeft(avatar);
    final initialAvatarSize = tester.getSize(avatar);
    final avatarCenter = tester.getCenter(avatar);
    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);

    await first.down(avatarCenter - const Offset(8, 0));
    await second.down(avatarCenter + const Offset(8, 0));
    await tester.pump();
    await first.moveTo(avatarCenter - const Offset(44, 34));
    await second.moveTo(avatarCenter + const Offset(44, 34));
    await tester.pump();
    await second.up();
    await first.up();
    await tester.pump();

    expect(tester.getSize(avatar), initialAvatarSize);
    expect(tester.getTopLeft(avatar), isNot(initialAvatarTopLeft));
  });

  testWidgets('world map double tap toggles zoom around tap position', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      mapImageUrl: kMockV1SteamMapImage,
      users: const [
        UserAvatar(
          'AA',
          name: 'Ada',
          avatarUrl: 'assets/images/default_list_image.png',
        ),
      ],
    );

    final avatar = find.byType(GenesisCharacterAvatar);
    final initialAvatarTopLeft = tester.getTopLeft(avatar);
    final initialAvatarSize = tester.getSize(avatar);

    await tester.tapAt(const Offset(150, 520));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(150, 520));
    await tester.pump();

    expect(tester.getSize(avatar), initialAvatarSize);
    expect(tester.getTopLeft(avatar), isNot(initialAvatarTopLeft));

    await tester.tapAt(const Offset(150, 520));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(150, 520));
    await tester.pump();

    expect(tester.getSize(avatar), initialAvatarSize);
    expect(tester.getTopLeft(avatar), initialAvatarTopLeft);
  });

  testWidgets('world map zoom control changes scale and disables at limits', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      mapImageUrl: kMockV1SteamMapImage,
      users: const [
        UserAvatar(
          'AA',
          name: 'Ada',
          avatarUrl: 'assets/images/default_list_image.png',
        ),
      ],
    );

    final zoomControl = find.byKey(
      const ValueKey<String>('world-map-zoom-control'),
    );
    final zoomDragArea = find.byKey(
      const ValueKey<String>('world-map-zoom-drag-area'),
    );
    final zoomIn = find.byKey(const ValueKey<String>('world-map-zoom-in'));
    final zoomOut = find.byKey(const ValueKey<String>('world-map-zoom-out'));
    final dragIndicator = find.byKey(
      const ValueKey<String>('world-map-zoom-drag-indicator'),
    );
    final avatar = find.byType(GenesisCharacterAvatar);
    final initialAvatarTopLeft = tester.getTopLeft(avatar);

    SvgPicture zoomInIcon() {
      return tester.widget<SvgPicture>(
        find.descendant(
          of: zoomIn,
          matching: _assetSvgFinder('assets/custom-icons/svg/map_zoom_in.svg'),
        ),
      );
    }

    SvgPicture zoomOutIcon() {
      return tester.widget<SvgPicture>(
        find.descendant(
          of: zoomOut,
          matching: _assetSvgFinder('assets/custom-icons/svg/map_zoom_out.svg'),
        ),
      );
    }

    expect(tester.getSize(zoomControl), const Size(30, 68));
    expect(tester.getSize(zoomDragArea), const Size(48, 88));
    expect(
      tester.getTopLeft(zoomControl).dx,
      closeTo(_mapSize.width - 42, 0.1),
    );
    expect(
      tester.getBottomRight(zoomControl).dy,
      closeTo(_mapSize.height - 30, 0.1),
    );
    expect(
      tester.getBottomRight(zoomDragArea),
      tester.getBottomRight(zoomControl),
    );
    final zoomControlBox = tester.widget<DecoratedBox>(zoomControl);
    final zoomDecoration = zoomControlBox.decoration as BoxDecoration;
    expect(zoomDecoration.color, legacyWorldMapZoomControlBackgroundColor);
    expect(zoomDecoration.borderRadius, BorderRadius.circular(8));
    expect(zoomDecoration.boxShadow, isNotEmpty);
    expect(
      zoomInIcon().colorFilter,
      const ColorFilter.mode(
        legacyWorldMapZoomControlEnabledColor,
        BlendMode.srcIn,
      ),
    );
    expect(
      zoomOutIcon().colorFilter,
      const ColorFilter.mode(
        legacyWorldMapZoomControlDisabledColor,
        BlendMode.srcIn,
      ),
    );
    expect(dragIndicator, findsOneWidget);

    await tester.tap(zoomIn);
    await tester.pump();

    expect(tester.getTopLeft(avatar), isNot(initialAvatarTopLeft));
    expect(zoomOutIcon().colorFilter, isNotNull);

    final clickedScale = tester
        .widget<LegacyWorldMapZoomControl>(
          find.byType(LegacyWorldMapZoomControl),
        )
        .value;
    await tester.drag(zoomDragArea, const Offset(0, -24));
    await tester.pump();
    final draggedScale = tester
        .widget<LegacyWorldMapZoomControl>(
          find.byType(LegacyWorldMapZoomControl),
        )
        .value;
    expect(draggedScale, greaterThan(clickedScale));
    expect(draggedScale, lessThan(clickedScale + 0.25));

    await tester.tap(zoomIn);
    await tester.pump();
    await tester.tap(zoomIn);
    await tester.pump();
    await tester.tap(zoomIn);
    await tester.pump();

    final maxZoomAvatarTopLeft = tester.getTopLeft(avatar);
    expect(zoomInIcon().colorFilter, isNotNull);

    await tester.tap(zoomIn);
    await tester.pump();

    expect(tester.getTopLeft(avatar), maxZoomAvatarTopLeft);
  });

  testWidgets('world map notifies parent scrolling on second pointer down', (
    tester,
  ) async {
    final states = <bool>[];
    await _pumpWorldMap(
      tester,
      users: const [],
      onMapInteractionChanged: states.add,
    );

    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);
    await first.down(const Offset(100, 100));
    await second.down(const Offset(140, 140));
    await tester.pump();

    expect(states, contains(true));

    await second.up();
    await first.up();
    await tester.pump();

    expect(states.last, isFalse);
  });

  testWidgets('world map ignores stale pointer events after unmounting', (
    tester,
  ) async {
    var showMap = true;
    late StateSetter setHarnessState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setHarnessState = setState;
              return showMap
                  ? const SizedBox(
                      width: 375,
                      height: 670,
                      child: LegacyWorldMap(
                        common: WorldMapCommonConfig(),
                        config: LegacyWorldMapConfig(points: <WorldPoint>[]),
                      ),
                    )
                  : const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(pointer: 1);
    await gesture.down(const Offset(100, 100));
    await tester.pump();

    setHarnessState(() => showMap = false);
    await tester.pump();

    await gesture.moveTo(const Offset(130, 130));
    await gesture.up();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('world map renders local asset map background', (tester) async {
    await _pumpWorldMap(
      tester,
      mapImageUrl: kWorldMapFallbackBackgroundAsset,
      users: const [],
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                kWorldMapFallbackBackgroundAsset,
      ),
      findsOneWidget,
    );
  });

  test('world map defers image dimension rebuilds during build', () {
    final source = File(
      'lib/components/legacy_world_map/legacy_world_map.dart',
    ).readAsStringSync();

    expect(source, contains('SchedulerPhase.persistentCallbacks'));
    expect(source, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(source, isNot(contains('GlobalKey<_ZoomableMapContentState>')));
    expect(
      source,
      isNot(contains('setState(() => _mapImageDimensionsByUrl[url] = size)')),
    );
  });

  testWidgets('world map defers zoom scale rebuilds during widget update', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      mapImageUrl: kMockV1SteamMapImage,
      users: const [],
      initialZoomScale: 1,
    );

    await _pumpWorldMap(
      tester,
      mapImageUrl: kMockV1SteamMapImage,
      users: const [],
      initialZoomScale: 1.5,
    );

    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('world map uses fallback background when map URL is empty', (
    tester,
  ) async {
    await _pumpWorldMap(tester, users: const []);

    expect(_assetImageFinder(kWorldMapFallbackBackgroundAsset), findsOneWidget);
  });

  testWidgets('world map can keep empty URL in loading placeholder state', (
    tester,
  ) async {
    await _pumpWorldMap(tester, users: const [], fallbackOnEmptyMapUrl: false);

    expect(_assetImageFinder(kWorldMapFallbackBackgroundAsset), findsNothing);
    expect(_mapPlaceholderFinder(), findsOneWidget);
  });

  testWidgets('world map uses fallback background when map asset fails', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      mapImageUrl: 'assets/images/map_default/missing_map.webp',
      users: const [],
    );
    await tester.pump();

    expect(_assetImageFinder(kWorldMapFallbackBackgroundAsset), findsOneWidget);
  });

  testWidgets(
    'world map scales to fill tall screens with horizontal overflow',
    (tester) async {
      const viewportSize = Size(375, 812);
      await _pumpWorldMap(
        tester,
        size: viewportSize,
        mapImageUrl: kMockV1SteamMapImage,
        users: const [],
      );
      await tester.pump();

      final scaledContent = find.byKey(
        const ValueKey<String>('world-map-scaled-content'),
      );
      final contentSize = tester.getSize(scaledContent);
      final contentTopLeft = tester.getTopLeft(scaledContent);

      expect(contentSize.height, viewportSize.height);
      expect(contentSize.width, greaterThan(viewportSize.width));
      expect(
        contentTopLeft.dx,
        closeTo((viewportSize.width - contentSize.width) / 2, 0.01),
      );
      expect(contentTopLeft.dy, 0);
      expect(find.byType(SingleChildScrollView), findsNothing);
    },
  );

  testWidgets('unzoomed world map pans within the cover-sized canvas', (
    tester,
  ) async {
    const viewportSize = Size(375, 812);
    await _pumpWorldMap(
      tester,
      size: viewportSize,
      mapImageUrl: kMockV1SteamMapImage,
      users: const [],
      points: const [],
    );
    await tester.pump();

    final interactiveViewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final controller = interactiveViewer.transformationController!;
    final contentSize = tester.getSize(
      find.byKey(const ValueKey<String>('world-map-scaled-content')),
    );

    expect(
      controller.value.storage[12],
      closeTo((viewportSize.width - contentSize.width) / 2, 0.01),
    );

    await tester.drag(find.byType(InteractiveViewer), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(
      controller.value.storage[12],
      closeTo(viewportSize.width - contentSize.width, 0.5),
    );
  });

  testWidgets(
    'world map reports horizontal pan boundaries from one transform',
    (tester) async {
      const viewportSize = Size(375, 812);
      final panStates = <WorldMapHorizontalPanState>[];
      await _pumpWorldMap(
        tester,
        size: viewportSize,
        mapImageUrl: kMockV1SteamMapImage,
        users: const [],
        points: const [],
        onHorizontalPanStateChanged: panStates.add,
      );
      await tester.pump();

      expect(panStates.last.canScrollLeft, isTrue);
      expect(panStates.last.canScrollRight, isTrue);

      await tester.drag(find.byType(InteractiveViewer), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(panStates.last.canScrollLeft, isTrue);
      expect(panStates.last.canScrollRight, isFalse);
    },
  );

  testWidgets(
    'zoomed world map can pan across cover-cropped horizontal edges',
    (tester) async {
      const viewportSize = Size(375, 812);
      const initialScale = 1.2;
      await _pumpWorldMap(
        tester,
        size: viewportSize,
        mapImageUrl: kMockV1SteamMapImage,
        users: const [],
        points: const [],
        initialZoomScale: initialScale,
      );
      await tester.pump();

      final interactiveViewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final controller = interactiveViewer.transformationController!;
      final contentSize = tester.getSize(
        find.byKey(const ValueKey<String>('world-map-scaled-content')),
      );
      final expectedMinTranslation =
          viewportSize.width - contentSize.width * initialScale;

      await tester.drag(find.byType(InteractiveViewer), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(
        controller.value.storage[12],
        closeTo(expectedMinTranslation, 0.5),
      );
    },
  );

  testWidgets('world map lays out four avatars in a two by two grid', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [
        UserAvatar(
          'AA',
          name: 'Ada',
          avatarUrl: 'assets/images/default_list_image.png',
        ),
        UserAvatar(
          'BB',
          name: 'Bert',
          avatarUrl: 'assets/images/default_list_image.png',
        ),
        UserAvatar(
          'CC',
          name: 'Cy',
          avatarUrl: 'assets/images/default_list_image.png',
        ),
        UserAvatar(
          'DD',
          name: 'Dee',
          avatarUrl: 'assets/images/default_list_image.png',
        ),
      ],
    );

    final avatars = find.byType(GenesisCharacterAvatar);
    expect(avatars, findsNWidgets(4));

    final topLeftAvatar = tester.getTopLeft(avatars.at(0));
    final topRightAvatar = tester.getTopLeft(avatars.at(1));
    final bottomLeftAvatar = tester.getTopLeft(avatars.at(2));
    final bottomRightAvatar = tester.getTopLeft(avatars.at(3));
    final pointY = _mapSize.height * _pointPosition.dy;

    expect(topLeftAvatar.dy, closeTo(pointY + 10, 0.01));
    expect(topRightAvatar.dy, topLeftAvatar.dy);
    expect(bottomLeftAvatar.dy, greaterThan(topLeftAvatar.dy));
    expect(bottomRightAvatar.dy, bottomLeftAvatar.dy);
    expect(topRightAvatar.dx, greaterThan(topLeftAvatar.dx));
    expect(bottomLeftAvatar.dx, topLeftAvatar.dx);
    expect(bottomRightAvatar.dx, topRightAvatar.dx);
  });

  testWidgets('world map allows slight avatar overlap for dense rings', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [
        UserAvatar('AA', name: 'Ada'),
        UserAvatar('BB', name: 'Bert'),
        UserAvatar('CC', name: 'Cy'),
        UserAvatar('DD', name: 'Dee'),
        UserAvatar('EE', name: 'Eli'),
        UserAvatar('FF', name: 'Flo'),
      ],
    );

    final avatars = find.byType(GenesisCharacterAvatar);
    expect(avatars, findsNWidgets(6));

    final firstCenter = tester.getCenter(avatars.at(0));
    final secondCenter = tester.getCenter(avatars.at(1));
    expect((firstCenter - secondCenter).distance, lessThan(36));
  });

  testWidgets('points list shows all locations and indents by hierarchy', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      showPointsList: true,
      points: const [
        WorldPoint(
          id: 'root',
          name: 'Root Gate',
          type: WorldPointType.portal,
          position: _pointPosition,
          users: [],
          iconUrl: kMockV1SteamMapImage,
        ),
        WorldPoint(
          id: 'level-1',
          name: 'Rail Gate',
          type: WorldPointType.shop,
          position: _pointPosition,
          users: [
            UserAvatar('AA', name: 'Ada'),
            UserAvatar('BB', name: 'Bert'),
            UserAvatar('CC', name: 'Cara'),
            UserAvatar('DD', name: 'Drew'),
          ],
          iconUrl: kMockV1SteamMapImage,
          description: 'Gate checkpoint summary.',
          locationDescription: 'Gate checkpoint description.',
          depth: 1,
        ),
        WorldPoint(
          id: 'level-2',
          name: 'Airdock Nine',
          type: WorldPointType.camp,
          position: _pointPosition,
          users: [],
          iconUrl: kMockV1SteamMapImage,
          depth: 2,
        ),
      ],
    );

    final list = find.byType(ListView);
    expect(find.byType(WorldLocationList), findsOneWidget);
    final rootTitle = find.descendant(
      of: list,
      matching: find.text('Root Gate'),
    );
    final levelOneTitle = find.descendant(
      of: list,
      matching: find.text('Rail Gate'),
    );
    final levelTwoTitle = find.descendant(
      of: list,
      matching: find.text('Airdock Nine'),
    );

    expect(rootTitle, findsOneWidget);
    expect(levelOneTitle, findsOneWidget);
    expect(levelTwoTitle, findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
    expect(find.byIcon(Icons.place_outlined), findsNWidgets(3));
    expect(_assetSvgFinder(characterStatIconAsset), findsOneWidget);
    expect(_assetSvgFinder(userStatIconAsset), findsNothing);
    expect(find.byIcon(Icons.schedule), findsNothing);
    expect(find.text('Ada, Bert, Cara, Drew'), findsOneWidget);
    expect(find.text('Gate checkpoint description.'), findsOneWidget);
    expect(find.text('Gate checkpoint summary.'), findsNothing);
    expect(
      tester.getTopLeft(levelOneTitle).dx - tester.getTopLeft(rootTitle).dx,
      closeTo(15, 0.01),
    );
    expect(
      tester.getTopLeft(levelTwoTitle).dx - tester.getTopLeft(levelOneTitle).dx,
      closeTo(15, 0.01),
    );
  });

  testWidgets('location tree uses the typography for each hierarchy level', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      showPointsList: true,
      points: const [],
      locationNodes: const [
        WorldMapLocationNode(
          id: 'synthetic-root',
          point: WorldPoint(
            id: 'synthetic-root',
            name: '',
            type: WorldPointType.portal,
            position: _pointPosition,
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'level-1',
              point: WorldPoint(
                id: 'level-1',
                name: 'Level One',
                type: WorldPointType.portal,
                position: _pointPosition,
                users: [],
                isLeafLocation: false,
              ),
              children: [
                WorldMapLocationNode(
                  id: 'level-2',
                  point: WorldPoint(
                    id: 'level-2',
                    name: 'Level Two',
                    type: WorldPointType.shop,
                    position: _pointPosition,
                    users: [],
                    isLeafLocation: false,
                  ),
                  children: [
                    WorldMapLocationNode(
                      id: 'level-3',
                      point: WorldPoint(
                        id: 'level-3',
                        name: 'Level Three',
                        type: WorldPointType.camp,
                        position: _pointPosition,
                        users: [UserAvatar('AA', name: 'Ari')],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final levelOne = find.text('- Level One');
    final levelTwo = find.text('- Level Two');
    final levelThree = find.text('Level Three');
    final character = find.text('Ari');
    final levelOneStyle = tester.widget<Text>(levelOne).style!;
    final levelTwoStyle = tester.widget<Text>(levelTwo).style!;
    final levelThreeStyle = tester.widget<Text>(levelThree).style!;

    expect(levelOneStyle.fontSize, 16);
    expect(levelOneStyle.fontWeight, FontWeight.w600);
    expect(levelTwoStyle.fontSize, 14);
    expect(levelTwoStyle.fontWeight, FontWeight.w600);
    expect(levelTwoStyle.height, 1.2);
    expect(levelThreeStyle.fontSize, 14);
    expect(levelThreeStyle.fontWeight, FontWeight.w400);
    expect(levelThreeStyle.height, 1.2);
    expect(
      tester.getTopLeft(character).dy - tester.getBottomLeft(levelThree).dy,
      closeTo(8, 0.01),
    );
  });

  testWidgets(
    'points list uses location description and hides empty summary row',
    (tester) async {
      await _pumpWorldMap(
        tester,
        users: const [],
        showPointsList: true,
        points: const [
          WorldPoint(
            id: 'summary',
            name: 'Summary Point',
            type: WorldPointType.portal,
            position: _pointPosition,
            users: [],
            description: 'Preferred current summary.',
            locationDescription: 'Older location description.',
          ),
          WorldPoint(
            id: 'empty-location-description',
            name: 'Empty Location Description Point',
            type: WorldPointType.shop,
            position: _pointPosition,
            users: [],
            description: 'Unused summary description.',
          ),
        ],
      );

      expect(find.text('Older location description.'), findsOneWidget);
      expect(find.text('Preferred current summary.'), findsNothing);
      expect(find.text('Unused summary description.'), findsNothing);
      expect(find.byIcon(Icons.schedule), findsNothing);
    },
  );

  testWidgets('points list hands bottom overscroll to details page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final points = List<WorldPoint>.generate(
      18,
      (index) => WorldPoint(
        id: 'point-$index',
        name: 'Location $index',
        type: WorldPointType.portal,
        position: _pointPosition,
        users: const [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorldDetailsPageScaffold(
          panelTopGap: 50,
          panelCollapsedHeightOffset: 100,
          map: LegacyWorldMap(
            common: const WorldMapCommonConfig(),
            config: LegacyWorldMapConfig(points: points, showPointsList: true),
          ),
          slivers: const [
            SliverToBoxAdapter(
              child: SizedBox(key: ValueKey('details-content'), height: 900),
            ),
          ],
        ),
      ),
    );

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.padding, const EdgeInsets.fromLTRB(12, 8, 12, 12));

    final detailsTopBefore = tester
        .getTopLeft(find.byKey(const ValueKey('details-content')))
        .dy;

    await tester.drag(find.byType(ListView), const Offset(0, -940));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pump();

    final detailsTopAfter = tester
        .getTopLeft(find.byKey(const ValueKey('details-content')))
        .dy;
    expect(detailsTopAfter, lessThan(detailsTopBefore));

    final listFinder = find.byType(ListView, skipOffstage: false);
    final listOffsetBefore = tester
        .widget<ListView>(listFinder)
        .controller!
        .offset;

    await tester.drag(listFinder, const Offset(0, 140));
    await tester.pump();

    final listOffsetAfter = tester
        .widget<ListView>(listFinder)
        .controller!
        .offset;
    final detailsTopAfterReturn = tester
        .getTopLeft(find.byKey(const ValueKey('details-content')))
        .dy;
    expect(listOffsetAfter, closeTo(listOffsetBefore, 0.5));
    expect(detailsTopAfterReturn, greaterThan(detailsTopAfter));
  });

  testWidgets('world map preloads next-level location maps', (tester) async {
    await _pumpWorldMap(
      tester,
      mapImageUrl: kMockV1SteamMapImage,
      preloadMapImageUrls: const [
        kMockV1LocationCentralHubMap,
        kMockV1LocationRailGateMap,
      ],
      users: const [],
    );

    expect(
      _assetImageFinder(kMockV1SteamMapImage, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      _assetImageFinder(kMockV1LocationCentralHubMap, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      _assetImageFinder(kMockV1LocationRailGateMap, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('map taps report branch and leaf locations', (tester) async {
    final tappedIds = <String>[];
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [
        WorldPoint(
          id: 'root',
          name: 'Root Hub',
          type: WorldPointType.portal,
          position: Offset(0.3, 0.35),
          users: [],
          isLeafLocation: false,
        ),
        WorldPoint(
          id: 'leaf',
          name: 'Leaf Dock',
          type: WorldPointType.shop,
          position: Offset(0.7, 0.35),
          users: [],
        ),
      ],
      onPointTap: (point) => tappedIds.add(point.id),
    );

    await tester.tap(find.text('Root Hub'), warnIfMissed: false);
    expect(tappedIds, ['root']);

    await tester.tap(find.text('Leaf Dock'));
    expect(tappedIds, ['root', 'leaf']);
  });

  testWidgets('map background taps report map tap', (tester) async {
    var mapTapCount = 0;
    await _pumpWorldMap(
      tester,
      users: const [],
      onMapTap: () => mapTapCount += 1,
    );

    await tester.tapAt(const Offset(20, 20));

    expect(mapTapCount, 1);
  });

  testWidgets('map point taps report map tap and point tap', (tester) async {
    var mapTapCount = 0;
    final tappedIds = <String>[];
    await _pumpWorldMap(
      tester,
      users: const [],
      onMapTap: () => mapTapCount += 1,
      onPointTap: (point) => tappedIds.add(point.id),
    );

    await tester.tap(find.text('Gate'));

    expect(mapTapCount, 1);
    expect(tappedIds, ['point-1']);
  });

  testWidgets('map point leaves empty marker space untappable', (tester) async {
    final tappedIds = <String>[];
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const <WorldPoint>[
        WorldPoint(
          id: 'point-1',
          sceneId: 'location-1',
          name: 'Gate',
          type: WorldPointType.portal,
          position: _pointPosition,
          users: <UserAvatar>[],
        ),
      ],
      onPointTap: (point) => tappedIds.add(point.id),
    );

    final labelRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-map-location-label-point-1')),
    );
    await tester.tapAt(Offset(labelRect.right + 10, labelRect.center.dy));

    expect(tappedIds, isEmpty);
  });

  testWidgets('drillable map tap does not show a location ripple', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [],
      locationNodes: const [
        WorldMapLocationNode(
          id: 'district',
          point: WorldPoint(
            id: 'district',
            sceneId: 'district',
            name: 'Rail District',
            type: WorldPointType.shop,
            position: Offset(0.5, 0.35),
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'leaf',
              point: WorldPoint(
                id: 'leaf',
                sceneId: 'leaf',
                name: 'Leaf Dock',
                type: WorldPointType.shop,
                position: Offset(0.7, 0.35),
                users: [],
              ),
            ),
            WorldMapLocationNode(
              id: 'leaf-2',
              point: WorldPoint(
                id: 'leaf-2',
                sceneId: 'leaf-2',
                name: 'Signal Room',
                type: WorldPointType.camp,
                position: Offset(0.45, 0.55),
                users: [],
              ),
            ),
          ],
        ),
      ],
      onPointTap: (_) {},
    );

    await tester.tap(find.text('Rail District'), warnIfMissed: false);
    await tester.pump();

    expect(find.text('Leaf Dock'), findsOneWidget);
    expect(find.text('Signal Room'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('world_map_location_tap_ripple')),
      findsNothing,
    );
  });

  testWidgets('world map drills into branch locations internally', (
    tester,
  ) async {
    final tappedIds = <String>[];
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [],
      locationNodes: const [
        WorldMapLocationNode(
          id: 'root',
          isRoot: true,
          point: WorldPoint(
            id: 'root',
            sceneId: 'root',
            name: 'Root Hub',
            type: WorldPointType.portal,
            position: Offset(0.3, 0.35),
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'district',
              mapImageUrl: kMockV1LocationCentralHubMap,
              point: WorldPoint(
                id: 'district',
                sceneId: 'district',
                name: 'Rail District',
                type: WorldPointType.shop,
                position: Offset(0.5, 0.35),
                users: [],
                isLeafLocation: false,
              ),
              children: [
                WorldMapLocationNode(
                  id: 'leaf',
                  point: WorldPoint(
                    id: 'leaf',
                    sceneId: 'leaf',
                    name: 'Leaf Dock',
                    type: WorldPointType.shop,
                    position: Offset(0.7, 0.35),
                    users: [],
                  ),
                ),
                WorldMapLocationNode(
                  id: 'leaf-2',
                  point: WorldPoint(
                    id: 'leaf-2',
                    sceneId: 'leaf-2',
                    name: 'Signal Room',
                    type: WorldPointType.camp,
                    position: Offset(0.45, 0.55),
                    users: [],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
      onPointTap: (point) => tappedIds.add(point.id),
    );

    expect(find.text('Root Hub'), findsNothing);
    expect(find.text('Rail District'), findsOneWidget);
    expect(find.byIcon(Icons.subdirectory_arrow_left), findsNothing);

    await tester.tap(find.text('Rail District'), warnIfMissed: false);
    await tester.pump();
    expect(tappedIds, isEmpty);
    expect(find.text('Leaf Dock'), findsOneWidget);
    expect(find.text('Signal Room'), findsOneWidget);
    expect(find.byIcon(Icons.subdirectory_arrow_left), findsOneWidget);
    expect(
      _assetImageFinder(kMockV1LocationCentralHubMap, skipOffstage: false),
      findsWidgets,
    );

    await tester.tap(find.byIcon(Icons.subdirectory_arrow_left));
    await tester.pumpAndSettle();
    expect(find.text('Rail District'), findsOneWidget);
    expect(find.byIcon(Icons.subdirectory_arrow_left), findsNothing);

    await tester.tap(find.text('Rail District'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leaf Dock'));
    expect(tappedIds, ['leaf']);
  });

  testWidgets('world map places drill exit above the bottom center', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [],
      locationNodes: const [
        WorldMapLocationNode(
          id: 'root',
          isRoot: true,
          point: WorldPoint(
            id: 'root',
            name: 'Root',
            type: WorldPointType.portal,
            position: _pointPosition,
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'branch',
              point: WorldPoint(
                id: 'branch',
                name: 'Branch',
                type: WorldPointType.shop,
                position: _pointPosition,
                users: [],
                isLeafLocation: false,
              ),
              children: [
                WorldMapLocationNode(
                  id: 'leaf',
                  point: WorldPoint(
                    id: 'leaf',
                    name: 'Leaf',
                    type: WorldPointType.shop,
                    position: _pointPosition,
                    users: [],
                  ),
                ),
                WorldMapLocationNode(
                  id: 'leaf-2',
                  point: WorldPoint(
                    id: 'leaf-2',
                    name: 'Leaf 2',
                    type: WorldPointType.camp,
                    position: Offset(0.6, 0.45),
                    users: [],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.tap(find.text('Branch'), warnIfMissed: false);
    await tester.pump();

    final mapRect = tester.getRect(find.byType(LegacyWorldMap));
    final drillExitRect = tester.getRect(
      find.byKey(const ValueKey<String>('legacy-world-map-exit-location')),
    );
    final drillExitButtonRect = tester.getRect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('legacy-world-map-exit-location'),
        ),
        matching: find.byKey(
          const ValueKey<String>(worldMapExitLocationIconFrameKey),
        ),
      ),
    );
    final labelRect = tester.getRect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('legacy-world-map-exit-location'),
        ),
        matching: find.text('Branch'),
      ),
    );
    expect(drillExitRect.center.dx, closeTo(mapRect.center.dx, 0.001));
    expect(
      labelRect.left - drillExitButtonRect.right,
      closeTo(worldMapExitLocationLabelGap, 0.001),
    );
    expect(
      mapRect.bottom - drillExitRect.bottom,
      closeTo(worldMapDrillExitBottom, 0.001),
    );
  });

  testWidgets('world map hides drill exit when showing location list', (
    tester,
  ) async {
    var showPointsList = false;
    late StateSetter setHarnessState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setHarnessState = setState;
              return SizedBox(
                width: _mapSize.width,
                height: _mapSize.height,
                child: LegacyWorldMap(
                  common: WorldMapCommonConfig(
                    locationNodes: const [
                      WorldMapLocationNode(
                        id: 'root',
                        isRoot: true,
                        point: WorldPoint(
                          id: 'root',
                          sceneId: 'root',
                          name: 'Root Hub',
                          type: WorldPointType.portal,
                          position: Offset(0.3, 0.35),
                          users: [],
                          isLeafLocation: false,
                        ),
                        children: [
                          WorldMapLocationNode(
                            id: 'district',
                            point: WorldPoint(
                              id: 'district',
                              sceneId: 'district',
                              name: 'Rail District',
                              type: WorldPointType.shop,
                              position: Offset(0.5, 0.35),
                              users: [],
                              isLeafLocation: false,
                            ),
                            children: [
                              WorldMapLocationNode(
                                id: 'leaf',
                                point: WorldPoint(
                                  id: 'leaf',
                                  sceneId: 'leaf',
                                  name: 'Leaf Dock',
                                  type: WorldPointType.shop,
                                  position: Offset(0.7, 0.35),
                                  users: [],
                                ),
                              ),
                              WorldMapLocationNode(
                                id: 'leaf-2',
                                point: WorldPoint(
                                  id: 'leaf-2',
                                  sceneId: 'leaf-2',
                                  name: 'Signal Room',
                                  type: WorldPointType.camp,
                                  position: Offset(0.45, 0.55),
                                  users: [],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                    onPointTap: (_) {},
                  ),
                  config: LegacyWorldMapConfig(
                    showPointsList: showPointsList,
                    points: const [],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Rail District'), warnIfMissed: false);
    await tester.pump();
    expect(find.byIcon(Icons.subdirectory_arrow_left), findsOneWidget);

    setHarnessState(() {
      showPointsList = true;
    });
    await tester.pump();

    expect(find.byIcon(Icons.subdirectory_arrow_left), findsNothing);
    expect(find.text('Leaf Dock'), findsWidgets);
    expect(find.text('Signal Room'), findsWidgets);
  });

  testWidgets('world map hides root and starts from level two locations', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [],
      locationNodes: const [
        WorldMapLocationNode(
          id: 'root',
          isRoot: true,
          point: WorldPoint(
            id: 'root',
            sceneId: 'root',
            name: 'World Root',
            type: WorldPointType.portal,
            position: Offset(0.3, 0.35),
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'level-2',
              point: WorldPoint(
                id: 'level-2',
                sceneId: 'level-2',
                name: 'Visible District',
                type: WorldPointType.shop,
                position: Offset(0.7, 0.35),
                users: [],
              ),
            ),
          ],
        ),
      ],
    );

    expect(find.text('World Root'), findsNothing);
    expect(find.text('Visible District'), findsOneWidget);
    expect(find.byIcon(Icons.subdirectory_arrow_left), findsNothing);
  });

  testWidgets('world map uses detail map as initial background', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [],
      mapImageUrl: kMockV1SteamMapImage,
      locationNodes: const [
        WorldMapLocationNode(
          id: 'root',
          isRoot: true,
          mapImageUrl: kMockV1LocationCentralHubMap,
          point: WorldPoint(
            id: 'root',
            sceneId: 'root',
            name: 'World Root',
            type: WorldPointType.portal,
            position: Offset(0.3, 0.35),
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'level-2',
              point: WorldPoint(
                id: 'level-2',
                sceneId: 'level-2',
                name: 'Visible District',
                type: WorldPointType.shop,
                position: Offset(0.7, 0.35),
                users: [],
              ),
            ),
          ],
        ),
      ],
    );

    expect(find.text('World Root'), findsNothing);
    expect(find.text('Visible District'), findsOneWidget);
    expect(_assetImageFinder(kMockV1SteamMapImage), findsOneWidget);
    expect(_assetImageFinder(kMockV1LocationCentralHubMap), findsNothing);
  });

  testWidgets('world map opens the only leaf child instead of drilling', (
    tester,
  ) async {
    final tappedIds = <String>[];
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [],
      locationNodes: const [
        WorldMapLocationNode(
          id: 'root',
          isRoot: true,
          point: WorldPoint(
            id: 'root',
            sceneId: 'root',
            name: 'World Root',
            type: WorldPointType.portal,
            position: Offset(0.3, 0.35),
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'district',
              point: WorldPoint(
                id: 'district',
                sceneId: 'district',
                name: 'District',
                type: WorldPointType.shop,
                position: Offset(0.5, 0.35),
                users: [],
                isLeafLocation: false,
              ),
              children: [
                WorldMapLocationNode(
                  id: 'room',
                  point: WorldPoint(
                    id: 'room',
                    sceneId: 'room',
                    name: 'Only Room',
                    type: WorldPointType.camp,
                    position: Offset(0.6, 0.45),
                    users: [],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
      onPointTap: (point) => tappedIds.add(point.id),
    );

    await tester.tap(find.text('District'));
    expect(tappedIds, ['room']);
    expect(find.byIcon(Icons.subdirectory_arrow_left), findsNothing);
  });

  testWidgets('world map opens level two leaf directly on two-level tree', (
    tester,
  ) async {
    final tappedIds = <String>[];
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [],
      locationNodes: const [
        WorldMapLocationNode(
          id: 'root',
          isRoot: true,
          point: WorldPoint(
            id: 'root',
            sceneId: 'root',
            name: 'World Root',
            type: WorldPointType.portal,
            position: Offset(0.3, 0.35),
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'level-2-leaf',
              point: WorldPoint(
                id: 'level-2-leaf',
                sceneId: 'level-2-leaf',
                name: 'Leaf District',
                type: WorldPointType.shop,
                position: Offset(0.5, 0.35),
                users: [],
              ),
            ),
          ],
        ),
      ],
      onPointTap: (point) => tappedIds.add(point.id),
    );

    expect(find.text('World Root'), findsNothing);
    expect(find.text('Leaf District'), findsOneWidget);
    expect(find.byIcon(Icons.subdirectory_arrow_left), findsNothing);

    await tester.tap(find.text('Leaf District'));
    expect(tappedIds, ['level-2-leaf']);
    expect(find.byIcon(Icons.subdirectory_arrow_left), findsNothing);
  });

  testWidgets('world map renders already rootless leaf nodes', (tester) async {
    final tappedIds = <String>[];
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [],
      locationNodes: const [
        WorldMapLocationNode(
          id: 'level-2-leaf',
          point: WorldPoint(
            id: 'level-2-leaf',
            sceneId: 'level-2-leaf',
            name: 'Rootless Leaf',
            type: WorldPointType.shop,
            position: Offset(0.5, 0.35),
            users: [],
          ),
        ),
      ],
      onPointTap: (point) => tappedIds.add(point.id),
    );

    expect(find.text('Rootless Leaf'), findsOneWidget);
    expect(find.byIcon(Icons.subdirectory_arrow_left), findsNothing);

    await tester.tap(find.text('Rootless Leaf'));
    expect(tappedIds, ['level-2-leaf']);
  });

  testWidgets('world map does not hide unmarked top-level branch nodes', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [],
      locationNodes: const [
        WorldMapLocationNode(
          id: 'district',
          point: WorldPoint(
            id: 'district',
            sceneId: 'district',
            name: 'Top District',
            type: WorldPointType.shop,
            position: Offset(0.5, 0.35),
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'room',
              point: WorldPoint(
                id: 'room',
                sceneId: 'room',
                name: 'Hidden Room',
                type: WorldPointType.camp,
                position: Offset(0.6, 0.45),
                users: [],
              ),
            ),
          ],
        ),
        WorldMapLocationNode(
          id: 'market',
          point: WorldPoint(
            id: 'market',
            sceneId: 'market',
            name: 'Top Market',
            type: WorldPointType.portal,
            position: Offset(0.3, 0.55),
            users: [],
          ),
        ),
      ],
    );

    expect(find.text('Top District'), findsOneWidget);
    expect(find.text('Top Market'), findsOneWidget);
    expect(find.text('Hidden Room'), findsNothing);
    expect(find.byIcon(Icons.subdirectory_arrow_left), findsNothing);
  });

  testWidgets('points list taps report branch and leaf locations', (
    tester,
  ) async {
    final tappedIds = <String>[];
    await _pumpWorldMap(
      tester,
      users: const [],
      showPointsList: true,
      points: const [
        WorldPoint(
          id: 'root',
          name: 'Root Hub',
          type: WorldPointType.portal,
          position: _pointPosition,
          users: [],
          isLeafLocation: false,
        ),
        WorldPoint(
          id: 'leaf',
          name: 'Leaf Dock',
          type: WorldPointType.shop,
          position: _pointPosition,
          users: [],
          depth: 1,
        ),
      ],
      onPointTap: (point) => tappedIds.add(point.id),
    );

    final rootTitle = find.text('Root Hub').last;
    final leafTitle = find.text('Leaf Dock').last;

    await tester.tap(rootTitle, warnIfMissed: false);
    expect(tappedIds, ['root']);

    await tester.tap(leafTitle);
    expect(tappedIds, ['root', 'leaf']);
  });

  testWidgets('tree location list renders level headers and leaf cards', (
    tester,
  ) async {
    final tappedIds = <String>[];
    await _pumpWorldMap(
      tester,
      users: const [],
      showPointsList: true,
      points: const [],
      locationNodes: const [
        WorldMapLocationNode(
          id: 'root',
          isRoot: true,
          point: WorldPoint(
            id: 'root',
            name: 'Blackspire Arcane Academy',
            type: WorldPointType.portal,
            position: _pointPosition,
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'fortress',
              point: WorldPoint(
                id: 'fortress',
                name: 'Main Fortress',
                type: WorldPointType.shop,
                position: _pointPosition,
                users: [],
                isLeafLocation: false,
              ),
              children: [
                WorldMapLocationNode(
                  id: 'hall',
                  point: WorldPoint(
                    id: 'hall',
                    name: 'Grand Hall',
                    type: WorldPointType.camp,
                    position: _pointPosition,
                    users: [],
                    locationDescription: 'The stained glass hall.',
                  ),
                ),
                WorldMapLocationNode(
                  id: 'classroom',
                  point: WorldPoint(
                    id: 'classroom',
                    name: 'Sorting Classroom',
                    type: WorldPointType.tavern,
                    position: _pointPosition,
                    users: [],
                    locationDescription: 'The classroom waits.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
      onPointTap: (point) => tappedIds.add(point.id),
    );

    expect(find.text('- Blackspire Arcane Academy'), findsOneWidget);
    expect(find.text('- Main Fortress'), findsOneWidget);
    expect(find.text('Grand Hall'), findsOneWidget);
    expect(find.text('Sorting Classroom'), findsOneWidget);

    await tester.tap(find.text('Grand Hall'));
    expect(tappedIds, ['hall']);
  });

  testWidgets('single child level three is opened from level two card', (
    tester,
  ) async {
    final tappedIds = <String>[];
    await _pumpWorldMap(
      tester,
      users: const [],
      showPointsList: true,
      points: const [],
      locationNodes: const [
        WorldMapLocationNode(
          id: 'root',
          isRoot: true,
          point: WorldPoint(
            id: 'root',
            name: 'Academy',
            type: WorldPointType.portal,
            position: _pointPosition,
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'fortress',
              point: WorldPoint(
                id: 'fortress',
                name: 'Main Fortress',
                type: WorldPointType.shop,
                position: _pointPosition,
                users: [],
                isLeafLocation: false,
              ),
              children: [
                WorldMapLocationNode(
                  id: 'hall',
                  point: WorldPoint(
                    id: 'hall',
                    name: 'Grand Hall',
                    type: WorldPointType.camp,
                    position: _pointPosition,
                    users: [],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
      onPointTap: (point) => tappedIds.add(point.id),
    );

    final list = find.byType(ListView);
    expect(
      find.descendant(of: list, matching: find.text('- Academy')),
      findsOneWidget,
    );
    final mainFortressCard = find.descendant(
      of: list,
      matching: find.text('Main Fortress'),
    );
    expect(mainFortressCard, findsOneWidget);
    expect(
      find.descendant(of: list, matching: find.text('Grand Hall')),
      findsNothing,
    );

    await tester.tap(mainFortressCard);
    expect(tappedIds, ['hall']);
  });

  testWidgets('world map ignores duplicate taps while point tap is pending', (
    tester,
  ) async {
    final tappedIds = <String>[];
    final completer = Completer<void>();
    await _pumpWorldMap(
      tester,
      users: const [],
      onPointTap: (point) {
        tappedIds.add(point.id);
        return completer.future;
      },
    );

    await tester.tap(find.text('Gate'));
    await tester.tap(find.text('Gate'));
    expect(tappedIds, ['point-1']);

    completer.complete();
    await tester.pump();
    await tester.tap(find.text('Gate'));
    expect(tappedIds, ['point-1', 'point-1']);
  });

  testWidgets('world map ignores duplicate taps while drilling into location', (
    tester,
  ) async {
    var drillCount = 0;
    await _pumpWorldMap(
      tester,
      users: const [],
      points: const [],
      onDrillIntoLocation: () {
        drillCount += 1;
      },
      locationNodes: const [
        WorldMapLocationNode(
          id: 'district',
          point: WorldPoint(
            id: 'district',
            sceneId: 'district',
            name: 'District',
            type: WorldPointType.shop,
            position: _pointPosition,
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'room-a',
              point: WorldPoint(
                id: 'room-a',
                sceneId: 'room-a',
                name: 'Room A',
                type: WorldPointType.camp,
                position: Offset(0.45, 0.4),
                users: [],
              ),
            ),
            WorldMapLocationNode(
              id: 'room-b',
              point: WorldPoint(
                id: 'room-b',
                sceneId: 'room-b',
                name: 'Room B',
                type: WorldPointType.camp,
                position: Offset(0.55, 0.5),
                users: [],
              ),
            ),
          ],
        ),
      ],
    );

    await tester.tap(find.text('District'));
    await tester.tap(find.text('District'), warnIfMissed: false);
    expect(drillCount, 1);

    await tester.pump();
    expect(find.text('Room A'), findsOneWidget);
  });

  testWidgets(
    'points list can show full hierarchy while map points stay scoped',
    (tester) async {
      await _pumpWorldMap(
        tester,
        users: const [],
        showPointsList: true,
        points: const [
          WorldPoint(
            id: 'root',
            name: 'Root Gate',
            type: WorldPointType.portal,
            position: _pointPosition,
            users: [],
          ),
        ],
        listPoints: const [
          WorldPoint(
            id: 'root',
            name: 'Root Gate',
            type: WorldPointType.portal,
            position: _pointPosition,
            users: [],
          ),
          WorldPoint(
            id: 'child',
            name: 'Hidden Child',
            type: WorldPointType.shop,
            position: _pointPosition,
            users: [],
            depth: 1,
          ),
        ],
      );

      final list = find.byType(ListView);
      expect(
        find.descendant(of: list, matching: find.text('Root Gate')),
        findsWidgets,
      );
      expect(
        find.descendant(of: list, matching: find.text('Hidden Child')),
        findsWidgets,
      );
    },
  );

  testWidgets('points list includes root when map uses location tree', (
    tester,
  ) async {
    await _pumpWorldMap(
      tester,
      users: const [],
      showPointsList: true,
      points: const [],
      locationNodes: const [
        WorldMapLocationNode(
          id: 'root',
          isRoot: true,
          point: WorldPoint(
            id: 'root',
            name: 'Root Location',
            type: WorldPointType.portal,
            position: _pointPosition,
            users: [],
            isLeafLocation: false,
          ),
          children: [
            WorldMapLocationNode(
              id: 'child',
              point: WorldPoint(
                id: 'child',
                name: 'Child Location',
                type: WorldPointType.shop,
                position: _pointPosition,
                users: [],
                depth: 1,
              ),
            ),
          ],
        ),
      ],
    );

    final list = find.byType(ListView);
    expect(
      find.descendant(of: list, matching: find.text('- Root Location')),
      findsWidgets,
    );
    expect(
      find.descendant(of: list, matching: find.text('Child Location')),
      findsWidgets,
    );
  });
}

const _mapSize = Size(375, 670);
const _pointPosition = Offset(0.5, 0.35);

Future<void> _pumpWorldMap(
  WidgetTester tester, {
  required List<UserAvatar> users,
  Size size = _mapSize,
  String mapImageUrl = '',
  List<String> preloadMapImageUrls = const <String>[],
  bool showPointsList = false,
  List<WorldPoint>? points,
  List<WorldPoint>? listPoints,
  List<WorldMapLocationNode> locationNodes = const <WorldMapLocationNode>[],
  bool fallbackOnEmptyMapUrl = true,
  VoidCallback? onMapTap,
  WorldPointTapCallback? onPointTap,
  VoidCallback? onDrillIntoLocation,
  ValueChanged<bool>? onMapInteractionChanged,
  ValueChanged<WorldMapHorizontalPanState>? onHorizontalPanStateChanged,
  WorldMapMessageBubble? activeBubble,
  List<WorldMapMessageBubble> messageBubbles = const <WorldMapMessageBubble>[],
  bool messageBubblePlaybackPaused = false,
  double initialZoomScale = 1,
  Set<String> recentChatMapLocationIds = const <String>{},
  Set<String> eventMapLocationIds = const <String>{},
  int? inheritedTextMaxLines,
}) async {
  tester.view.physicalSize = const Size(430, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final worldMap = LegacyWorldMap(
    common: WorldMapCommonConfig(
      locationNodes: locationNodes,
      messageBubbles: messageBubbles,
      messageBubblePlaybackPaused: messageBubblePlaybackPaused,
      onDrillIntoLocation: onDrillIntoLocation,
      onMapTap: onMapTap,
      onPointTap: onPointTap,
    ),
    config: LegacyWorldMapConfig(
      mapImageUrl: mapImageUrl,
      preloadMapImageUrls: preloadMapImageUrls,
      fallbackOnEmptyMapUrl: fallbackOnEmptyMapUrl,
      showPointsList: showPointsList,
      listPoints: listPoints,
      activeBubble: activeBubble,
      initialZoomScale: initialZoomScale,
      recentChatMapLocationIds: recentChatMapLocationIds,
      eventMapLocationIds: eventMapLocationIds,
      onHorizontalPanStateChanged: onHorizontalPanStateChanged,
      points:
          points ??
          [
            WorldPoint(
              id: 'point-1',
              name: 'Gate',
              type: WorldPointType.portal,
              position: _pointPosition,
              users: users,
            ),
          ],
    ),
  );
  final mapChild = inheritedTextMaxLines == null
      ? worldMap
      : DefaultTextStyle(
          style: const TextStyle(letterSpacing: 4),
          maxLines: inheritedTextMaxLines,
          overflow: TextOverflow.ellipsis,
          child: worldMap,
        );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: NotificationListener<WorldMapInteractionNotification>(
            onNotification: (notification) {
              onMapInteractionChanged?.call(notification.active);
              return onMapInteractionChanged != null;
            },
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: mapChild,
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _assetImageFinder(String path, {bool skipOffstage = true}) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == path,
    skipOffstage: skipOffstage,
  );
}

Finder _assetSvgFinder(String path, {bool skipOffstage = true}) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is SvgPicture &&
        widget.bytesLoader is SvgAssetLoader &&
        (widget.bytesLoader as SvgAssetLoader).assetName == path,
    skipOffstage: skipOffstage,
  );
}

Finder _mapPlaceholderFinder({bool skipOffstage = true}) {
  return find.byWidgetPredicate(
    (widget) => widget is ColoredBox && widget.color == const Color(0xFFF3F4F6),
    skipOffstage: skipOffstage,
  );
}

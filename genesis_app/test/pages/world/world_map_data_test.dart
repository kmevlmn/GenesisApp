import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/debug/world_new_content_debug_settings.dart';
import 'package:genesis_flutter_android/network/models/location_tree.dart';
import 'package:genesis_flutter_android/network/models/world.dart';
import 'package:genesis_flutter_android/pages/world/world_map_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    worldNewContentDebugSettings.resetForTesting();
  });

  tearDown(worldNewContentDebugSettings.resetForTesting);

  test('uses first root location map image', () {
    final roots = [
      const LocationTreeNode<Map<String, dynamic>>(
        id: 'root-1',
        parentId: '',
        depth: 0,
        value: {'map_url': 'assets/maps/root.webp'},
        children: [],
      ),
    ];

    expect(worldRootMapImageUrl(roots), 'assets/maps/root.webp');
  });

  test('filters current user avatars from map occupants', () {
    final avatars = worldAvatarsByLocationFromCharacterPositions([
      {
        'location_id': 'loc-1',
        'character': {
          'character_id': 'char-self',
          'name': 'Self',
          'player_uid': 'uid-self',
          'avatar': 'assets/self.webp',
        },
      },
      {
        'location_id': 'loc-1',
        'character': {
          'character_id': 'char-other',
          'name': 'Other',
          'player_uid': 'uid-other',
          'avatar': 'assets/other.webp',
          'is_new': 1,
        },
      },
    ], currentUid: 'uid-self');

    expect(avatars['loc-1'], hasLength(1));
    expect(avatars['loc-1']?.single.name, 'Other');

    expect(avatars['loc-1']?.single.isPlayerControlledRole, isTrue);
    expect(avatars['loc-1']?.single.isNew, isTrue);
  });

  test('builds fallback map points from location ids', () {
    final points = worldPointsFromLocationIds(['b', 'a', 'a', ''], const {});

    expect(points.map((point) => point.id), ['a', 'b']);
    expect(points.every((point) => point.sceneId == point.id), isTrue);
    expect(points.every((point) => point.isLeafLocation), isTrue);
  });

  test('builds location sheet data from the current world hierarchy', () {
    final world = WorldDetail.fromJson({
      'world_id': 'w-1',
      'locations': [
        {
          'location_id': 'root',
          'level': 1,
          'location_name': 'Root',
          'image': {
            'sm_url': 'https://cdn.example.com/root-sm.webp',
            'xl_url': 'https://cdn.example.com/root-xl.webp',
          },
          'is_new': 'true',
        },
        {
          'location_id': 'child',
          'location_pid': 'root',
          'level': 2,
          'location_name': 'Child',
          'image': '',
          'icon': 'https://cdn.example.com/child-legacy.webp',
        },
      ],
    });

    final data = worldLocationListDataFor(world, currentUid: '');

    expect(data.points.map((point) => point.sceneId), [
      '__world_root__',
      'root',
      'child',
    ]);
    final rootPoint = data.points.singleWhere(
      (point) => point.sceneId == 'root',
    );
    final childPoint = data.points.singleWhere(
      (point) => point.sceneId == 'child',
    );
    expect(rootPoint.iconUrl, 'https://cdn.example.com/root-xl.webp');
    expect(rootPoint.isNew, isFalse);
    expect(childPoint.iconUrl, 'https://cdn.example.com/child-legacy.webp');
    expect(childPoint.isNew, isFalse);
    expect(data.locationNodes, hasLength(1));
    expect(data.locationNodes.single.id, '__world_root__');
    final rootNode = data.locationNodes.single.children.single;
    expect(rootNode.id, 'root');
    expect(rootNode.children.single.id, 'child');
  });

  test('keeps the location sheet empty without location data', () {
    final data = worldLocationListDataFor(
      WorldDetail.fromJson({'world_id': 'w-empty'}),
      currentUid: '',
    );

    expect(data.points, isEmpty);
    expect(data.locationNodes, isEmpty);
  });

  test(
    'debug override marks every map location and character as new',
    () async {
      await worldNewContentDebugSettings.setForceNewBadges(true);
      final avatars = worldAvatarsByLocationFromCharacterPositions([
        {
          'location_id': 'location-1',
          'character': {'id': 'character-1', 'name': 'Ada', 'is_new': false},
        },
      ], currentUid: 'current-user');
      final points = worldPointsFromLocations([
        {
          'location_id': 'location-1',
          'level': 3,
          'location_name': 'Library',
          'is_new': false,
        },
      ], avatars);
      final fallbackPoints = worldPointsFromLocationIds([
        'fallback-location',
      ], const {});

      expect(avatars['location-1']!.single.isNew, isTrue);
      expect(points.single.isNew, isTrue);
      expect(fallbackPoints.single.isNew, isTrue);
    },
  );

  test('map new state comes from L3 and propagates to its direct parent', () {
    final world = WorldDetail.fromJson({
      'world_id': 'w-new-l3',
      'locations': [
        {
          'location_id': 'l1',
          'level': 1,
          'location_name': 'L1',
          'is_new': true,
        },
        {
          'location_id': 'l2',
          'location_pid': 'l1',
          'level': 2,
          'location_name': 'L2',
          'is_new': false,
        },
        {
          'location_id': 'l3',
          'location_pid': 'l2',
          'level': 3,
          'location_name': 'L3',
          'is_new': true,
        },
      ],
    });

    final data = worldLocationListDataFor(world, currentUid: '');
    final l1Point = data.points.singleWhere((point) => point.sceneId == 'l1');
    final l2Point = data.points.singleWhere((point) => point.sceneId == 'l2');
    final l3Point = data.points.singleWhere((point) => point.sceneId == 'l3');

    expect(l1Point.isNew, isFalse);
    expect(l2Point.isNew, isTrue);
    expect(l3Point.isNew, isTrue);
  });
}

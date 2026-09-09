import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/chat/shared/chat_scene_plate_tokens.dart';
import 'package:genesis_flutter_android/network/chatroom/world_chatroom_service.dart';
import 'package:genesis_flutter_android/pages/world/world_update_push_banner.dart';
import 'package:genesis_flutter_android/ui/components/genesis_avatar.dart';
import 'package:genesis_flutter_android/ui/components/genesis_character_avatar.dart';
import 'package:genesis_flutter_android/ui/components/genesis_static_network_image.dart';

const _characterAvatarUrl =
    'https://cdn-001.worldo.ai/app/uploads/20260702/'
    '2072507310906806272_356_356.jpg?x-oss-process=image/format,webp';
const _locationImageUrl =
    'https://cdn-001.worldo.ai/app/uploads/20260705/'
    '2073569582257278976_800_1200.jpg?x-oss-process=image/format,webp';

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    debugGenesisStaticNetworkImageCompleter = null;
  });

  tearDown(() {
    debugGenesisStaticNetworkImageCompleter = null;
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets('world update push notices are shown sequentially', (
    WidgetTester tester,
  ) async {
    final avatarImage = (await tester.runAsync(
      () => _createTestImage(const Color(0xFF336699)),
    ))!;
    addTearDown(avatarImage.dispose);
    var characterAvatarLoadCount = 0;
    debugGenesisStaticNetworkImageCompleter = (_) {
      characterAvatarLoadCount += 1;
      return OneFrameImageStreamCompleter(
        SynchronousFuture<ImageInfo>(ImageInfo(image: avatarImage.clone())),
      );
    };
    const notices = <WorldContentUpdateNotice>[
      WorldContentUpdateNotice(
        kind: WorldContentUpdateKind.location,
        entityId: 'loc-new',
        name: 'New Harbor',
        targetLocationId: 'loc-new',
        avatarUrl: _locationImageUrl,
        tickCount: 3,
        contextLabel: 'Azure Coast',
      ),
      WorldContentUpdateNotice(
        kind: WorldContentUpdateKind.character,
        entityId: 'char-new',
        name: 'New Wanderer',
        targetLocationId: 'loc-new',
        avatarUrl: _characterAvatarUrl,
        tickCount: 3,
        contextLabel: 'Wandering swordsman',
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              WorldUpdatePushBannerQueue(
                top: 12,
                revision: 1,
                notices: notices,
                displayDuration: Duration(milliseconds: 50),
                transitionDuration: Duration(milliseconds: 20),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('New Place Emerged'), findsOneWidget);
    expect(find.text('New Harbor · Azure Coast'), findsOneWidget);
    expect(find.text('New Wanderer · Wandering swordsman'), findsNothing);
    expect(characterAvatarLoadCount, 0);
    expect(find.byType(GenesisStaticNetworkImage), findsNothing);
    final locationNameIcon = tester.widget<Icon>(
      find.byKey(
        const ValueKey<String>('world-update-push-location-name-icon'),
      ),
    );
    expect(locationNameIcon.icon, Icons.place_outlined);
    expect(locationNameIcon.size, 14);
    expect(locationNameIcon.color, const Color(0xF2FFFFFF));
    expect(
      find.byKey(const ValueKey<String>('world-update-push-location-image')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('world-update-push-location-icon')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('world-update-push-character-avatar')),
      findsNothing,
    );
    final locationBannerRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-update-push-banner')),
    );
    final shadow = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('world-update-push-shadow')),
    );
    final shadowDecoration = shadow.decoration as BoxDecoration;
    expect(shadowDecoration.borderRadius, BorderRadius.circular(12));
    expect(shadowDecoration.boxShadow, hasLength(1));
    expect(shadowDecoration.boxShadow!.single.color, const Color(0x99000000));
    expect(shadowDecoration.boxShadow!.single.blurRadius, 24);
    expect(shadowDecoration.boxShadow!.single.offset, const Offset(0, 8));
    expect(
      find.byKey(const ValueKey<String>('world-update-push-outline')),
      findsNothing,
    );
    final backdropBlur = tester.widget<BackdropFilter>(
      find.byKey(const ValueKey<String>('world-update-push-backdrop-blur')),
    );
    expect(
      backdropBlur.filterConfig,
      const ImageFilterConfig.blur(sigmaX: 14, sigmaY: 14, bounded: false),
    );
    final bannerMaterial = tester.widget<Material>(
      find.byKey(const ValueKey<String>('world-update-push-banner')),
    );
    expect(bannerMaterial.color, const Color(0x33FFFFFF));
    expect(bannerMaterial.shape, isNull);
    expect(bannerMaterial.borderRadius, BorderRadius.circular(12));
    final viewportWidth = tester.getSize(find.byType(Scaffold)).width;
    final locationDetailRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-update-push-detail')),
    );
    final locationIconRect = tester.getRect(
      find.byKey(
        const ValueKey<String>('world-update-push-location-name-icon'),
      ),
    );
    expect(locationBannerRect.height, 64);
    expect(locationBannerRect.left, kLocationChatOuterPadding);
    expect(viewportWidth - locationBannerRect.right, kLocationChatOuterPadding);
    expect(
      locationBannerRect.width,
      viewportWidth - (kLocationChatOuterPadding * 2),
    );
    expect(locationIconRect.left - locationBannerRect.left, 16);
    expect(locationDetailRect.left - locationIconRect.right, 2);

    await tester.pump(const Duration(milliseconds: 30));

    expect(find.text('New Harbor · Azure Coast'), findsOneWidget);
    expect(find.text('New Wanderer · Wandering swordsman'), findsNothing);

    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('New Harbor · Azure Coast'), findsOneWidget);
    expect(find.text('New Wanderer · Wandering swordsman'), findsNothing);

    await tester.pump(const Duration(milliseconds: 11));

    expect(find.text('New Wanderer · Wandering swordsman'), findsNothing);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('New Harbor · Azure Coast'), findsNothing);
    expect(find.text('New Character Appeared'), findsOneWidget);
    expect(find.text('New Wanderer · Wandering swordsman'), findsOneWidget);
    expect(characterAvatarLoadCount, 1);
    expect(
      find.byKey(
        const ValueKey<String>('world-update-push-location-name-icon'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('world-update-push-location-icon')),
      findsNothing,
    );
    final characterAvatar = tester.widget<GenesisCharacterAvatar>(
      find.byKey(const ValueKey<String>('world-update-push-character-avatar')),
    );
    expect(characterAvatar.url, _characterAvatarUrl);
    expect(characterAvatar.name, 'New Wanderer');
    expect(characterAvatar.size, 48);
    expect(characterAvatar.borderRadius, 8);
    expect(characterAvatar.showFallbackWhileLoading, isFalse);
    final detailText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('world-update-push-detail')),
    );
    expect(detailText.style?.fontSize, 14);
    expect(detailText.style?.color, const Color(0xF2FFFFFF));
    expect(detailText.maxLines, 1);
    expect(detailText.overflow, TextOverflow.ellipsis);
    final detailSpan = detailText.textSpan! as TextSpan;
    expect(detailSpan.text, 'New Wanderer');
    final identitySpan = detailSpan.children!.single as TextSpan;
    expect(identitySpan.text, ' · Wandering swordsman');
    expect(identitySpan.style?.fontSize, 11);
    expect(identitySpan.style?.fontWeight, FontWeight.w500);
    expect(identitySpan.style?.color, const Color(0xB8FFFFFF));
    final bannerRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-update-push-banner')),
    );
    final avatarRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-update-push-character-avatar')),
    );
    expect(avatarRect.size, const Size.square(48));
    expect(avatarRect.left - bannerRect.left, 8);
    expect(avatarRect.top - bannerRect.top, 8);
    expect(bannerRect.bottom - avatarRect.bottom, 8);
    expect(bannerRect.height, 64);
    expect(bannerRect.width, locationBannerRect.width);
    expect(locationBannerRect.height, bannerRect.height);
    final detailRect = tester.getRect(
      find.byKey(const ValueKey<String>('world-update-push-detail')),
    );
    final categoryRect = tester.getRect(find.text('New Character Appeared'));
    expect(detailRect.top - categoryRect.bottom, closeTo(5, 0.01));
    expect(detailRect.left - avatarRect.right, 10);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('world-update-push-banner')),
      findsNothing,
    );
  });

  testWidgets('world update push omits separator without context', (
    WidgetTester tester,
  ) async {
    Future<void> pumpNotice(WorldContentUpdateNotice notice) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                WorldUpdatePushBannerQueue(
                  key: ValueKey<String>(notice.entityId),
                  top: 12,
                  revision: 1,
                  notices: [notice],
                  displayDuration: const Duration(hours: 1),
                  transitionDuration: Duration.zero,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpNotice(
      const WorldContentUpdateNotice(
        kind: WorldContentUpdateKind.location,
        entityId: 'location-without-parent',
        name: 'Root Harbor',
        targetLocationId: 'location-without-parent',
        avatarUrl: '',
        tickCount: 1,
      ),
    );

    expect(find.text('New Place Emerged'), findsOneWidget);
    expect(find.text('Root Harbor'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
    expect(find.byType(GenesisStaticNetworkImage), findsNothing);
    expect(
      find.byKey(
        const ValueKey<String>('world-update-push-location-name-icon'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('world-update-push-location-icon')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('world-update-push-location-image')),
      findsNothing,
    );

    await pumpNotice(
      const WorldContentUpdateNotice(
        kind: WorldContentUpdateKind.character,
        entityId: 'character-without-identity',
        name: 'Nameless Wanderer',
        targetLocationId: 'location-without-parent',
        avatarUrl: '',
        tickCount: 1,
        contextLabel: '   ',
      ),
    );

    expect(find.text('New Character Appeared'), findsOneWidget);
    expect(find.text('Nameless Wanderer'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
    expect(
      find.byKey(
        const ValueKey<String>('world-update-push-location-name-icon'),
      ),
      findsNothing,
    );
    final characterAvatar = tester.widget<GenesisCharacterAvatar>(
      find.byKey(const ValueKey<String>('world-update-push-character-avatar')),
    );
    expect(characterAvatar.borderRadius, 8);
  });

  testWidgets('location push builds only the inline icon', (
    WidgetTester tester,
  ) async {
    var imageLoadCount = 0;
    debugGenesisStaticNetworkImageCompleter = (_) {
      imageLoadCount += 1;
      return OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
    };
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              WorldUpdatePushBannerQueue(
                top: 12,
                revision: 1,
                notices: [
                  WorldContentUpdateNotice(
                    kind: WorldContentUpdateKind.location,
                    entityId: 'location-with-image',
                    name: 'Storm Harbor',
                    targetLocationId: 'location-with-image',
                    avatarUrl: _locationImageUrl,
                    tickCount: 1,
                  ),
                ],
                displayDuration: Duration(hours: 1),
                transitionDuration: Duration.zero,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(GenesisStaticNetworkImage), findsNothing);
    expect(
      find.byKey(
        const ValueKey<String>('world-update-push-location-name-icon'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('world-update-push-location-icon')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('world-update-push-location-image')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('world-update-push-character-avatar')),
      findsNothing,
    );
    expect(imageLoadCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('character push waits for its avatar before becoming visible', (
    WidgetTester tester,
  ) async {
    final avatarImage = (await tester.runAsync(
      () => _createTestImage(const Color(0xFF663399)),
    ))!;
    addTearDown(avatarImage.dispose);
    final firstFrame = Completer<ImageInfo>();
    var imageLoadCount = 0;
    debugGenesisStaticNetworkImageCompleter = (_) {
      imageLoadCount += 1;
      return OneFrameImageStreamCompleter(firstFrame.future);
    };

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              WorldUpdatePushBannerQueue(
                top: 12,
                revision: 1,
                notices: [
                  WorldContentUpdateNotice(
                    kind: WorldContentUpdateKind.character,
                    entityId: 'waiting-character',
                    name: 'Waiting Character',
                    targetLocationId: 'leaf-location',
                    avatarUrl: 'https://cache.test/waiting-character.webp',
                    tickCount: 1,
                  ),
                ],
                displayDuration: Duration(milliseconds: 50),
                transitionDuration: Duration.zero,
                avatarPreloadTimeout: Duration(hours: 1),
              ),
            ],
          ),
        ),
      ),
    );

    expect(imageLoadCount, 1);
    expect(find.text('New Character Appeared'), findsNothing);
    expect(find.text('Waiting Character'), findsNothing);
    expect(find.byType(GenesisAvatarFallback), findsNothing);

    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Waiting Character'), findsNothing);

    firstFrame.complete(ImageInfo(image: avatarImage.clone()));
    await tester.pump();
    await tester.pump();

    expect(find.text('New Character Appeared'), findsOneWidget);
    expect(find.text('Waiting Character'), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.byType(GenesisAvatarFallback), findsNothing);
    expect(imageLoadCount, 1);

    await tester.pump(const Duration(milliseconds: 49));
    expect(find.text('Waiting Character'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(find.text('Waiting Character'), findsNothing);
  });

  testWidgets('failed character avatar falls back and queue continues', (
    WidgetTester tester,
  ) async {
    debugGenesisStaticNetworkImageCompleter = (_) =>
        OneFrameImageStreamCompleter(
          Future<ImageInfo>.error(StateError('avatar load failed')),
        );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              WorldUpdatePushBannerQueue(
                top: 12,
                revision: 1,
                notices: [
                  WorldContentUpdateNotice(
                    kind: WorldContentUpdateKind.character,
                    entityId: 'failed-character',
                    name: 'Failed Character',
                    targetLocationId: 'leaf-location',
                    avatarUrl: 'https://cache.test/failed-character.webp',
                    tickCount: 1,
                  ),
                  WorldContentUpdateNotice(
                    kind: WorldContentUpdateKind.location,
                    entityId: 'next-location',
                    name: 'Next Location',
                    targetLocationId: 'next-location',
                    avatarUrl: '',
                    tickCount: 1,
                  ),
                ],
                displayDuration: Duration(milliseconds: 30),
                transitionDuration: Duration.zero,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Failed Character'), findsOneWidget);
    expect(find.byType(GenesisAvatarFallback), findsOneWidget);
    final failedAvatar = tester.widget<GenesisCharacterAvatar>(
      find.byKey(const ValueKey<String>('world-update-push-character-avatar')),
    );
    expect(failedAvatar.url, isEmpty);

    await tester.pump(const Duration(milliseconds: 31));
    await tester.pump();

    expect(find.text('Failed Character'), findsNothing);
    expect(find.text('Next Location'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('character avatar timeout uses a stable fallback', (
    WidgetTester tester,
  ) async {
    final avatarImage = (await tester.runAsync(
      () => _createTestImage(const Color(0xFF996633)),
    ))!;
    addTearDown(avatarImage.dispose);
    final delayedFrame = Completer<ImageInfo>();
    debugGenesisStaticNetworkImageCompleter = (_) =>
        OneFrameImageStreamCompleter(delayedFrame.future);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              WorldUpdatePushBannerQueue(
                top: 12,
                revision: 1,
                notices: [
                  WorldContentUpdateNotice(
                    kind: WorldContentUpdateKind.character,
                    entityId: 'slow-character',
                    name: 'Slow Character',
                    targetLocationId: 'leaf-location',
                    avatarUrl: 'https://cache.test/slow-character.webp',
                    tickCount: 1,
                  ),
                ],
                displayDuration: Duration(hours: 1),
                transitionDuration: Duration.zero,
                avatarPreloadTimeout: Duration(milliseconds: 40),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Slow Character'), findsNothing);
    await tester.pump(const Duration(milliseconds: 39));
    expect(find.text('Slow Character'), findsNothing);

    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();

    expect(find.text('Slow Character'), findsOneWidget);
    expect(find.byType(GenesisAvatarFallback), findsOneWidget);
    final slowAvatar = tester.widget<GenesisCharacterAvatar>(
      find.byKey(const ValueKey<String>('world-update-push-character-avatar')),
    );
    expect(slowAvatar.url, isEmpty);

    delayedFrame.complete(ImageInfo(image: avatarImage.clone()));
    await tester.pump();

    expect(find.text('Slow Character'), findsOneWidget);
    expect(find.byType(GenesisAvatarFallback), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('world update push enters from above', (
    WidgetTester tester,
  ) async {
    const bannerKey = ValueKey<String>('world-update-push-banner');
    const transitionDuration = Duration(milliseconds: 200);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              WorldUpdatePushBannerQueue(
                top: 60,
                revision: 1,
                notices: [
                  WorldContentUpdateNotice(
                    kind: WorldContentUpdateKind.location,
                    entityId: 'loc-new',
                    name: 'New Harbor',
                    targetLocationId: 'loc-new',
                    avatarUrl: '',
                    tickCount: 3,
                  ),
                ],
                displayDuration: Duration(hours: 1),
                transitionDuration: transitionDuration,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(bannerKey), findsNothing);

    await tester.pump();
    final startingTop = tester.getTopLeft(find.byKey(bannerKey)).dy;

    await tester.pump(transitionDuration ~/ 2);
    final middleTop = tester.getTopLeft(find.byKey(bannerKey)).dy;

    await tester.pump(transitionDuration ~/ 2);
    final settledTop = tester.getTopLeft(find.byKey(bannerKey)).dy;

    expect(startingTop, lessThan(middleTop));
    expect(middleTop, lessThan(settledTop));
    expect(settledTop, closeTo(60, 0.01));
  });

  testWidgets('tapping a world update push opens it only once', (
    WidgetTester tester,
  ) async {
    const notice = WorldContentUpdateNotice(
      kind: WorldContentUpdateKind.location,
      entityId: 'loc-new',
      name: 'New Harbor',
      targetLocationId: 'loc-new',
      avatarUrl: '',
      tickCount: 3,
    );
    final tappedNotices = <WorldContentUpdateNotice>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              WorldUpdatePushBannerQueue(
                top: 12,
                revision: 1,
                notices: const [notice],
                onNoticeTap: tappedNotices.add,
                displayDuration: const Duration(hours: 1),
                transitionDuration: const Duration(milliseconds: 20),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final tapTarget = find.byKey(
      const ValueKey<String>('world-update-push-tap-target'),
    );
    expect(tapTarget, findsOneWidget);

    await tester.tap(tapTarget);
    await tester.tap(tapTarget);

    expect(tappedNotices, [same(notice)]);

    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('world-update-push-banner')),
      findsNothing,
    );
  });

  testWidgets('queued notices are rechecked before they are displayed', (
    WidgetTester tester,
  ) async {
    const notices = <WorldContentUpdateNotice>[
      WorldContentUpdateNotice(
        kind: WorldContentUpdateKind.location,
        entityId: 'first',
        name: 'First Location',
        targetLocationId: 'first',
        avatarUrl: '',
        tickCount: 1,
      ),
      WorldContentUpdateNotice(
        kind: WorldContentUpdateKind.character,
        entityId: 'second',
        name: 'Second Character',
        targetLocationId: 'second',
        avatarUrl: '',
        tickCount: 1,
      ),
    ];
    var eligibleIds = <String>{'first', 'second'};
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return Stack(
                children: [
                  WorldUpdatePushBannerQueue(
                    top: 12,
                    revision: 1,
                    notices: notices,
                    canShowNotice: (notice) =>
                        eligibleIds.contains(notice.entityId),
                    displayDuration: const Duration(milliseconds: 50),
                    transitionDuration: const Duration(milliseconds: 10),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('First Location'), findsOneWidget);

    updateHost(() => eligibleIds = <String>{'first'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();

    expect(find.text('First Location'), findsNothing);
    expect(find.text('Second Character'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('world-update-push-banner')),
      findsNothing,
    );
  });

  testWidgets('an active notice is dismissed when it becomes ineligible', (
    WidgetTester tester,
  ) async {
    const notice = WorldContentUpdateNotice(
      kind: WorldContentUpdateKind.character,
      entityId: 'moving-character',
      name: 'Moving Character',
      targetLocationId: 'current-location',
      avatarUrl: '',
      tickCount: 1,
    );
    var eligible = true;
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return Stack(
                children: [
                  WorldUpdatePushBannerQueue(
                    top: 12,
                    revision: 1,
                    notices: const [notice],
                    canShowNotice: (_) => eligible,
                    displayDuration: const Duration(hours: 1),
                    transitionDuration: const Duration(milliseconds: 10),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Moving Character'), findsOneWidget);

    updateHost(() => eligible = false);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Moving Character'), findsNothing);
  });

  testWidgets('notices received during exit wait for the prior banner', (
    WidgetTester tester,
  ) async {
    var revision = 0;
    var notices = const <WorldContentUpdateNotice>[];
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return Stack(
                children: [
                  WorldUpdatePushBannerQueue(
                    top: 12,
                    revision: revision,
                    notices: notices,
                    displayDuration: const Duration(milliseconds: 50),
                    transitionDuration: const Duration(milliseconds: 20),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    updateHost(() {
      revision = 1;
      notices = const [
        WorldContentUpdateNotice(
          kind: WorldContentUpdateKind.location,
          entityId: 'loc-new',
          name: 'New Harbor',
          targetLocationId: 'loc-new',
          avatarUrl: '',
          tickCount: 3,
        ),
      ];
    });
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('New Harbor'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 10));

    updateHost(() {
      revision = 2;
      notices = const [
        WorldContentUpdateNotice(
          kind: WorldContentUpdateKind.character,
          entityId: 'char-new',
          name: 'New Wanderer',
          targetLocationId: 'loc-new',
          avatarUrl: '',
          tickCount: 3,
        ),
      ];
    });
    await tester.pump();

    expect(find.text('New Harbor'), findsOneWidget);
    expect(find.text('New Wanderer'), findsNothing);

    await tester.pump(const Duration(milliseconds: 11));

    expect(find.text('New Wanderer'), findsNothing);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('New Harbor'), findsNothing);
    expect(find.text('New Wanderer'), findsOneWidget);
  });
}

Future<ui.Image> _createTestImage(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = color);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(2, 2);
  } finally {
    picture.dispose();
  }
}

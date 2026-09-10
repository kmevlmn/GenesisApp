import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_dark_theme.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/components/common/list_loading_skeleton.dart';
import 'package:genesis_flutter_android/components/origin/origin_item_card.dart';
import 'package:genesis_flutter_android/components/origin/origin_item_cover_gradient_painter.dart';
import 'package:genesis_flutter_android/components/origin/origin_item_cover_throttled_image_provider.dart';
import 'package:genesis_flutter_android/icons/custom_icon_assets.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_origin_card_geometry.dart';

void main() {
  setUp(() {
    debugOriginItemCoverImageProvider = null;
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  tearDown(() {
    debugOriginItemCoverImageProvider = null;
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  test('parses default Tilemap metadata from origin list or feed info', () {
    final item = OriginListItem.fromJson({
      'info': {
        'origin_id': 'o_map',
        'definition_version': 2,
        'default_map_location_id': 'loc_origin_map',
      },
    });

    expect(item.definitionVersion, 2);
    expect(item.defaultMapLocationId, 'loc_origin_map');
  });

  test('preserves returned UGC backslashes for origin cards', () {
    final item = OriginListItem.fromJson({
      'info': {
        'oid': 'o_alpha',
        'name': r'Name\nvalue',
        'display_subtitle': r'Subtitle\nvalue',
        'world_view': r'View\nvalue',
      },
    });

    expect(item.name, r'Name\nvalue');
    expect(item.displaySubtitle, r'Subtitle\nvalue');
    expect(item.worldView, r'View\nvalue');
  });

  test('parses tick count for shared origin tick chip', () {
    final item = OriginListItem.fromJson({
      'info': {'oid': 'o_alpha', 'name': 'Alpha', 'version_num': 3},
      'stats': {'tick_cnt': 8, 'max_tick_cnt': 11},
    });

    expect(item.versionNum, 3);
    expect(item.tickCount, 8);
  });

  test('falls back to max tick count when tick count is absent', () {
    final item = OriginListItem.fromJson({
      'info': {'oid': 'o_alpha', 'name': 'Alpha', 'version_num': 3},
      'stats': {'max_tick_cnt': 11},
    });

    expect(item.tickCount, 11);
  });

  testWidgets('renders image stats on the cover overlay', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);

    const item = OriginListItem(
      oid: 'o_alpha',
      status: 1,
      versionNum: 3,
      name: 'Alpha Empire',
      cover: '',
      displaySubtitle: 'Tycoon idols',
      worldView: '',
      createdUid: 'u_1',
      createdUserName: 'Shawn',
      createdAt: '2026-05-01T00:00:00Z',
      updatedAt: '2026-05-02T00:00:00Z',
      tags: <String>[],
      copyCnt: 99900,
      connectCnt: 99900000,
      discussCnt: 0,
      characterCnt: 8,
      locationCnt: 0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 220, child: OriginItemCard(item: item)),
        ),
      ),
    );
    await _pumpUntilOriginCardReady(tester);

    expect(_assetSvgFinder(copyStatIconAsset), findsOneWidget);
    expect(_assetSvgFinder(characterStatIconAsset), findsOneWidget);
    final characterIcon = tester.widget<SvgPicture>(
      _assetSvgFinder(characterStatIconAsset),
    );
    final characterColorMapper =
        (characterIcon.bytesLoader as SvgAssetLoader).colorMapper;
    expect(characterColorMapper, isNotNull);
    expect(
      characterColorMapper!.substitute(
        null,
        'path',
        'fill',
        const Color(0xFF111111),
      ),
      Colors.white,
    );
    expect(
      characterColorMapper.substitute(
        null,
        'path',
        'fill',
        const Color(0xFFFF2442),
      ),
      const Color(0xFFFF2442),
    );
    final coverFinder = find.byKey(
      const ValueKey<String>('origin-item-card-rendered-cover'),
    );
    expect(tester.getSize(coverFinder), const Size(220, 330));
    expect(
      tester.getSize(find.byType(OriginItemCard)),
      const Size(220, 330 + genesisOriginCardBottomExtension),
    );
    final footerFinder = find.byKey(
      const ValueKey<String>('origin-item-card-footer-extension'),
    );
    expect(
      tester.getSize(footerFinder),
      const Size(220, genesisOriginCardBottomExtension),
    );
    expect(
      tester.widget<ColoredBox>(footerFinder).color,
      const Color(0xFF111111),
    );
    final coverImage = tester.widget<Image>(
      find.byKey(const ValueKey<String>('origin-item-card-cover-loader')),
    );
    expect(coverImage.image, isA<AssetImage>());
    final paintedCover = tester.widget<CustomPaint>(
      find.byKey(const ValueKey<String>('origin-item-card-painted-cover')),
    );
    expect(
      paintedCover.foregroundPainter,
      isA<OriginItemCoverGradientPainter>(),
    );
    expect(
      (paintedCover.foregroundPainter! as OriginItemCoverGradientPainter)
          .transitionHeight,
      50,
    );
    expect(
      find.byKey(const ValueKey<String>('origin-item-card-cover-transition')),
      findsNothing,
    );
    final details = tester.widget<Container>(
      find.byKey(const ValueKey<String>('origin-item-card-details')),
    );
    expect(details.decoration, isNull);
    final statsFinder = find.byKey(
      const ValueKey<String>('origin-item-card-stats'),
    );
    final statsPadding =
        tester.widget<Padding>(statsFinder).padding as EdgeInsets;
    expect(statsPadding.top, 8);
    expect(statsPadding.bottom, 6);
    final connectIcon = tester.widget<SvgPicture>(
      _assetSvgFinder(connectStatIconAsset),
    );
    expect(connectIcon.width, 10);
    expect(connectIcon.height, 10);
    final copyIcon = tester.widget<SvgPicture>(
      _assetSvgFinder(copyStatIconAsset),
    );
    expect(copyIcon.width, 10);
    expect(copyIcon.height, 10);
    expect(find.text('99.9K'), findsOneWidget);
    expect(find.text('99.9M'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(tester.widget<Text>(find.text('99.9K')).style?.fontSize, 11);
    expect(tester.widget<Text>(find.text('99.9M')).style?.fontSize, 11);
    expect(tester.widget<Text>(find.text('99.9K')).style?.height, 1.2);
    final nameRect = tester.getRect(find.text('#Alpha Empire'));
    final briefRect = tester.getRect(find.text('Tycoon idols'));
    final statsTextRect = tester.getRect(find.text('99.9K'));
    final cardRect = tester.getRect(find.byType(OriginItemCard));
    expect(briefRect.top - nameRect.bottom, 4);
    expect(statsTextRect.top - briefRect.bottom, 8);
    expect(cardRect.bottom - statsTextRect.bottom, 6);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is FittedBox && widget.fit == BoxFit.scaleDown,
      ),
      findsNothing,
    );
    expect(find.text('v3'), findsNothing);

    final subtitle = tester.widget<Text>(find.text('Tycoon idols'));
    expect(subtitle.style?.color, Colors.white.withValues(alpha: 0.75));
    expect(subtitle.style?.fontSize, 11);
    expect(subtitle.style?.height, 1.2);
    expect(subtitle.maxLines, 3);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'keeps the whole item hidden until its cover is ready (${dark ? 'dark' : 'light'})',
      (WidgetTester tester) async {
        final frame = Completer<ImageInfo>();
        final sourceImage = await _solidImage(const Color(0xFFFF0000));
        addTearDown(sourceImage.dispose);
        debugOriginItemCoverImageProvider = (_) =>
            _CompletingTestImageProvider(frame.future);

        const item = OriginListItem(
          oid: 'o_delayed',
          status: 1,
          versionNum: 1,
          name: 'Delayed Origin',
          cover: '',
          displaySubtitle: 'Wait for the cover',
          worldView: '',
          createdUid: 'u_1',
          createdUserName: 'Shawn',
          createdAt: '2026-05-01T00:00:00Z',
          updatedAt: '2026-05-02T00:00:00Z',
          tags: <String>[],
          copyCnt: 3,
          connectCnt: 4,
          discussCnt: 0,
          characterCnt: 5,
          locationCnt: 0,
        );
        var coverLoaded = false;

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) =>
                dark ? GenesisDarkTheme(child: child!) : child!,
            home: Scaffold(
              body: SizedBox(
                width: 220,
                child: OriginItemCard(
                  item: item,
                  onCoverLoaded: () => coverLoaded = true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final loadingFinder = find.byKey(
          const ValueKey<String>('origin-item-card-loading'),
        );
        expect(loadingFinder, findsOneWidget);
        expect(
          tester.getSize(loadingFinder),
          const Size(220, 330 + genesisOriginCardBottomExtension),
        );
        final placeholderFinder = find.descendant(
          of: loadingFinder,
          matching: find.byType(DecoratedBox),
        );
        expect(placeholderFinder, findsOneWidget);
        final initialDecoration =
            tester.widget<DecoratedBox>(placeholderFinder).decoration
                as BoxDecoration;
        final initialGradient = initialDecoration.gradient! as LinearGradient;
        expect(
          initialGradient.colors,
          dark
              ? const [
                  GenesisColors.darkRaisedBackground,
                  GenesisColors.darkFaintSurface,
                ]
              : const [Color(0xFFE8EBF0), Color(0xFFF3F4F6)],
        );
        await tester.pump(const Duration(milliseconds: 350));
        final movedDecoration =
            tester.widget<DecoratedBox>(placeholderFinder).decoration
                as BoxDecoration;
        final movedGradient = movedDecoration.gradient! as LinearGradient;
        expect(movedGradient, initialGradient);
        expect(
          find.descendant(
            of: loadingFinder,
            matching: find.byType(AnimatedBuilder),
          ),
          findsNothing,
        );
        expect(find.text('#Delayed Origin'), findsNothing);
        expect(
          find.byKey(
            const ValueKey<String>('origin-item-card-footer-extension'),
          ),
          findsNothing,
        );
        expect(coverLoaded, isFalse);

        frame.complete(ImageInfo(image: sourceImage.clone()));
        await _pumpUntilOriginCardReady(tester);

        expect(loadingFinder, findsNothing);
        expect(
          find.byKey(const ValueKey<String>('origin-item-card-ready')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(OriginItemCard),
            matching: find.byType(AnimatedOpacity),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(OriginItemCard),
            matching: find.byType(FadeTransition),
          ),
          findsNothing,
        );
        expect(find.text('#Delayed Origin'), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey<String>('origin-item-card-footer-extension'),
          ),
          findsOneWidget,
        );
        expect(coverLoaded, isTrue);
      },
    );
  }

  testWidgets('retries a queued cover superseded before loading', (
    WidgetTester tester,
  ) async {
    final sourceImage = await _solidImage(const Color(0xFF00AAFF));
    addTearDown(sourceImage.dispose);
    final retriedFrame = Completer<ImageInfo>();
    var attempts = 0;
    debugOriginItemCoverImageProvider = (_) {
      attempts += 1;
      return _CompletingTestImageProvider(
        attempts == 1
            ? Future<ImageInfo>.error(
                const OriginItemCoverLoadCancelledException(),
              )
            : retriedFrame.future,
      );
    };

    const item = OriginListItem(
      oid: 'o_retried',
      status: 1,
      versionNum: 1,
      name: 'Retried Origin',
      cover: '',
      displaySubtitle: 'Retry the cover',
      worldView: '',
      createdUid: 'u_1',
      createdUserName: 'Shawn',
      createdAt: '2026-05-01T00:00:00Z',
      updatedAt: '2026-05-02T00:00:00Z',
      tags: <String>[],
      copyCnt: 0,
      connectCnt: 0,
      discussCnt: 0,
      characterCnt: 0,
      locationCnt: 0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 220, child: OriginItemCard(item: item)),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('origin-item-card-loading-cancelled')),
      findsOneWidget,
    );
    final loadingBoneElement = find
        .byType(GenesisOriginCardLoadingBone)
        .evaluate()
        .single;

    await tester.pump(const Duration(milliseconds: 150));
    expect(attempts, greaterThanOrEqualTo(2));
    expect(
      identical(
        find.byType(GenesisOriginCardLoadingBone).evaluate().single,
        loadingBoneElement,
      ),
      isTrue,
      reason: 'The static placeholder must remain stable across a cover retry.',
    );

    retriedFrame.complete(ImageInfo(image: sourceImage.clone()));
    await _pumpUntilOriginCardReady(tester);

    expect(attempts, greaterThanOrEqualTo(2));
    expect(find.text('#Retried Origin'), findsOneWidget);
  });

  testWidgets('does not render origin tags', (WidgetTester tester) async {
    const item = OriginListItem(
      oid: 'o_alpha',
      status: 1,
      versionNum: 3,
      name: 'Alpha Empire',
      cover: '',
      displaySubtitle: 'Tycoon idols',
      worldView: '',
      createdUid: 'u_1',
      createdUserName: 'Shawn',
      createdAt: '2026-05-01T00:00:00Z',
      updatedAt: '2026-05-02T00:00:00Z',
      tags: <String>['one', 'two', 'three', 'four', 'five'],
      copyCnt: 2300,
      connectCnt: 4400000,
      discussCnt: 0,
      characterCnt: 0,
      locationCnt: 0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, child: OriginItemCard(item: item)),
        ),
      ),
    );
    await _pumpUntilOriginCardReady(tester);

    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsNothing);
    expect(find.text('three'), findsNothing);
    expect(find.text('four'), findsNothing);
    expect(find.text('five'), findsNothing);
  });

  testWidgets('limits a long cover title to two lines', (
    WidgetTester tester,
  ) async {
    const longTitle =
        'The Floating City Where Every District Changes at Sunrise';
    const item = OriginListItem(
      oid: 'o_alpha',
      status: 1,
      versionNum: 3,
      name: longTitle,
      cover: '',
      displaySubtitle: 'Tycoon idols',
      worldView: '',
      createdUid: 'u_1',
      createdUserName: 'Shawn',
      createdAt: '2026-05-01T00:00:00Z',
      updatedAt: '2026-05-02T00:00:00Z',
      tags: <String>[],
      copyCnt: 0,
      connectCnt: 0,
      discussCnt: 0,
      characterCnt: 0,
      locationCnt: 0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 180, child: OriginItemCard(item: item)),
        ),
      ),
    );
    await _pumpUntilOriginCardReady(tester);

    final titleFinder = find.text('#$longTitle');
    final title = tester.widget<Text>(titleFinder);
    expect(title.style?.color, Colors.white);
    expect(title.style?.fontSize, 13);
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(title.style?.height, 1.2);
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(
      tester.getSize(titleFinder).height,
      lessThanOrEqualTo((13 * 1.2 * 2).ceilToDouble()),
    );
  });
}

Finder _assetSvgFinder(String assetName) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is SvgPicture &&
        widget.bytesLoader is SvgAssetLoader &&
        (widget.bytesLoader as SvgAssetLoader).assetName == assetName,
  );
}

Future<ui.Image> _solidImage(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 8, 12), Paint()..color = color);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(8, 12);
  } finally {
    picture.dispose();
  }
}

Future<void> _pumpUntilOriginCardReady(WidgetTester tester) async {
  final readyFinder = find.byKey(
    const ValueKey<String>('origin-item-card-ready'),
  );
  for (var attempt = 0; attempt < 20; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump();
    if (readyFinder.evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
  }
  fail('Origin item cover image did not become ready.');
}

@immutable
class _CompletingTestImageProvider
    extends ImageProvider<_CompletingTestImageProvider> {
  const _CompletingTestImageProvider(this.frame);

  final Future<ImageInfo> frame;

  @override
  Future<_CompletingTestImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<_CompletingTestImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CompletingTestImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(frame);
  }

  @override
  bool operator ==(Object other) {
    return other is _CompletingTestImageProvider &&
        identical(other.frame, frame);
  }

  @override
  int get hashCode => identityHashCode(frame);
}

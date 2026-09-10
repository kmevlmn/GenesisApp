import 'dart:async';

import 'package:flutter/material.dart';

import '../../support/font_expectations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/telemetry/genesis_telemetry.dart';
import 'package:genesis_flutter_android/network/models/gem_model.dart';
import 'package:genesis_flutter_android/pages/gems/memory_model_page.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';

void main() {
  tearDown(GenesisTelemetry.resetForTesting);

  testWidgets('initial loading indicator uses the Gem red color', (
    tester,
  ) async {
    final catalogCompleter = Completer<GemModelCatalog>();

    await tester.pumpWidget(
      MaterialApp(
        home: MemoryModelPage(
          worldId: 'W_LOADING',
          catalogLoader: (_) => catalogCompleter.future,
        ),
      ),
    );
    await tester.pump();

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('gem-model-page-loading')),
    );
    expect(indicator.color, const Color(0xFFFF2442));

    catalogCompleter.complete(_catalog());
    await tester.pumpAndSettle();
  });

  testWidgets('renders backend model catalog and selected state', (
    tester,
  ) async {
    final requestedWorldIds = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: MemoryModelPage(
          worldId: 'W_000001',
          catalogLoader: (worldId) async {
            requestedWorldIds.add(worldId);
            return _catalog();
          },
          selectionHandler: (_, modelCode) async =>
              GemModelSelection(selectedModelCode: modelCode),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedWorldIds, ['W_000001']);
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expectInterText(tester, find.text('Save'));
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Top Pick V3'), findsOneWidget);
    expect(find.text('Hot'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Estimated next message: 4.0 gems'), findsOneWidget);

    final pageTitleStyle = tester.widget<Text>(find.text('Model')).style;
    expect(pageTitleStyle?.fontSize, 20);
    expect(pageTitleStyle?.height, 1.4);
    expect(pageTitleStyle?.fontWeight, FontWeight.w600);
    expect(pageTitleStyle?.color, const Color(0xFF111111));
    expect(
      tester.getTopLeft(find.text('Recommended')).dy -
          tester.getRect(find.text('Model')).bottom,
      closeTo(23, 0.1),
    );
    expect(tester.getTopLeft(find.byIcon(Icons.arrow_back_ios_new)).dx, 16);
    expect(
      tester.getRect(find.byType(Scaffold)).right -
          tester.getRect(find.text('Save')).right,
      16,
    );

    final saveButton = tester.widget<TextButton>(
      find.byKey(const ValueKey('gem-model-save')),
    );
    expect(saveButton.onPressed, isNull);
    expect(
      find.byKey(const ValueKey('gem-model-current-top_pick_v3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gem-model-current-sake_pro')),
      findsNothing,
    );
    final currentModelMarker = tester.widget<Container>(
      find.byKey(const ValueKey('gem-model-current-top_pick_v3')),
    );
    expect(
      (currentModelMarker.decoration as BoxDecoration).color,
      GenesisColors.brand,
    );
    final saveStyle = saveButton.style?.textStyle?.resolve(<WidgetState>{});
    expect(saveStyle?.fontSize, 14);
    expect(saveStyle?.height, 18 / 14);
    expect(saveStyle?.fontWeight, FontWeight.w600);
    expect(
      saveButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      const Color(0xFF111111),
    );

    final groupTitleStyle = tester.widget<Text>(find.text('Recommended')).style;
    expect(groupTitleStyle?.fontSize, 16);
    expect(groupTitleStyle?.height, 20 / 16);
    expect(groupTitleStyle?.fontWeight, FontWeight.w600);

    final modelTitleStyle = tester.widget<Text>(find.text('Top Pick V3')).style;
    expect(modelTitleStyle?.fontSize, 14);
    expect(modelTitleStyle?.height, 16 / 14);
    expect(modelTitleStyle?.fontWeight, FontWeight.w600);
    expect(modelTitleStyle?.color, const Color(0xFF111111));

    final estimateStyle = tester
        .widget<Text>(find.text('Estimated next message: 4.0 gems'))
        .style;
    expect(estimateStyle?.fontSize, 12);
    expect(estimateStyle?.height, 12 / 12);
    expect(estimateStyle?.fontWeight, FontWeight.w400);
    expect(estimateStyle?.color, const Color(0xFF666666));
    final estimateText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('gem-model-estimate-top_pick_v3')),
    );
    final estimateSpan = estimateText.textSpan! as TextSpan;
    final gemsSpan = estimateSpan.children!.single as TextSpan;
    expect(gemsSpan.text, '4.0 gems');
    expect(gemsSpan.style?.color, const Color(0xFFFF2442));

    final descriptionStyle = tester
        .widget<Text>(find.text('Balanced storytelling.'))
        .style;
    expect(descriptionStyle?.fontSize, 12);
    expect(descriptionStyle?.height, 14 / 12);
    expect(descriptionStyle?.fontWeight, FontWeight.w400);
    expect(descriptionStyle?.color, const Color(0xFF666666));

    expect(find.text('4-320 gems (memory from 2K to 156K)'), findsNothing);

    final hotStyle = tester.widget<Text>(find.text('Hot')).style;
    expect(hotStyle?.fontSize, 10);
    expect(hotStyle?.height, 14 / 10);
    expect(hotStyle?.fontWeight, FontWeight.w600);
    expect(_tileBorder(tester, 'top_pick_v3').color, const Color(0xFFFF2442));
    expect(_tileBorder(tester, 'sake_pro').color, const Color(0xFFE1E1E1));
    expect(_tileColor(tester, 'top_pick_v3'), const Color(0xFFFFF4F6));
    expect(_tileColor(tester, 'sake_pro'), Colors.white);
    final selectedTileInkWell = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('gem-model-top_pick_v3')),
        matching: find.byType(InkWell),
      ),
    );
    expect(selectedTileInkWell.splashFactory, NoSplash.splashFactory);
    expect(
      selectedTileInkWell.overlayColor?.resolve(<WidgetState>{}),
      Colors.transparent,
    );
    expect(_tagContainer(tester, 'hot').color, const Color(0xFFFF7A1A));
    expect(_tagContainer(tester, 'hot').height, 20);
    expect(_tagContainer(tester, 'new').color, const Color(0xFFFF2442));
    expect(_tagContainer(tester, 'new').height, 20);
    expect(
      tester.getCenter(find.text('Top Pick V3')).dy,
      closeTo(tester.getCenter(find.text('Hot')).dy, 0.5),
    );
    final estimateSize = tester.getSize(
      find.byKey(const ValueKey<String>('gem-model-estimate-top_pick_v3')),
    );
    final tileSize = tester.getSize(
      find.byKey(const ValueKey<String>('gem-model-top_pick_v3')),
    );
    expect(estimateSize.width, lessThan(tileSize.width));
    expect(estimateSize.height, 12);
    expect(_tagContainer(tester, 'hot').radius, 8);
    expect(_tagContainer(tester, 'new').radius, 8);
  });

  testWidgets('reports model page view once with the world id', (tester) async {
    final telemetry = _CapturingTelemetrySink();
    GenesisTelemetry.setSinkForTesting(telemetry);

    await tester.pumpWidget(
      MaterialApp(
        home: MemoryModelPage(
          worldId: 'W_000004',
          catalogLoader: (_) async => _catalog(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final events = telemetry.events
        .where((event) => event.name == 'switch_model_page')
        .toList();
    expect(events, hasLength(1));
    expect(events.single.data, <String, Object?>{
      'action_type': 'pay_event',
      'action': 'switch_model_page',
      'object1': 'W_000004',
    });
  });

  testWidgets('save submits the pending model for the current world', (
    tester,
  ) async {
    final telemetry = _CapturingTelemetrySink();
    GenesisTelemetry.setSinkForTesting(telemetry);
    final selections = <(String, String)>[];
    final cachedModelCodes = <String>[];
    final selectionCompleter = Completer<GemModelSelection>();

    await tester.pumpWidget(
      MaterialApp(
        home: MemoryModelPage(
          worldId: 'W_000002',
          catalogLoader: (_) async => _catalog(),
          selectionHandler: (worldId, modelCode) async {
            selections.add((worldId, modelCode));
            return selectionCompleter.future;
          },
          selectedModelCodeCacheWriter: (modelCode) async {
            cachedModelCodes.add(modelCode);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('gem-model-sake_pro')));
    await tester.pump();

    expect(selections, isEmpty);
    expect(cachedModelCodes, isEmpty);
    expect(_tileBorder(tester, 'top_pick_v3').color, const Color(0xFFE1E1E1));
    expect(_tileBorder(tester, 'sake_pro').color, const Color(0xFFFF2442));
    expect(_tileColor(tester, 'top_pick_v3'), Colors.white);
    expect(_tileColor(tester, 'sake_pro'), const Color(0xFFFFF4F6));
    expect(
      find.byKey(const ValueKey('gem-model-current-top_pick_v3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gem-model-current-sake_pro')),
      findsNothing,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('gem-model-save')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('gem-model-save')));
    await tester.pump();

    expect(selections, [('W_000002', 'sake_pro')]);
    final saveEvents = telemetry.events
        .where((event) => event.name == 'switch_model_save')
        .toList();
    expect(saveEvents, hasLength(1));
    expect(saveEvents.single.data, <String, Object?>{
      'action_type': 'pay_event',
      'action': 'switch_model_save',
      'object1': 'W_000002',
      'object2': 'sake_pro',
    });
    expect(
      find.byKey(const ValueKey('gem-model-save-loading')),
      findsOneWidget,
    );
    expect(find.text('Save'), findsNothing);

    selectionCompleter.complete(
      const GemModelSelection(selectedModelCode: 'sake_pro'),
    );
    await tester.pump();
    await tester.pump();

    expect(cachedModelCodes, ['sake_pro']);
    expect(_tileBorder(tester, 'top_pick_v3').color, const Color(0xFFE1E1E1));
    expect(_tileBorder(tester, 'sake_pro').color, const Color(0xFFFF2442));
    expect(find.text('Switched successfully'), findsOneWidget);
    expect(find.byKey(const ValueKey('gem-model-save-loading')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('failed save restores the server-selected model', (tester) async {
    final telemetry = _CapturingTelemetrySink();
    GenesisTelemetry.setSinkForTesting(telemetry);
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryModelPage(
          worldId: 'W_000003',
          catalogLoader: (_) async => _catalog(),
          selectionHandler: (_, _) async => throw StateError('save failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('gem-model-sake_pro')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('gem-model-save')));
    await tester.pump();
    await tester.pump();

    expect(_tileBorder(tester, 'top_pick_v3').color, const Color(0xFFFF2442));
    expect(_tileBorder(tester, 'sake_pro').color, const Color(0xFFE1E1E1));
    expect(find.text('Switched failed'), findsOneWidget);
    expect(
      telemetry.events.where((event) => event.name == 'switch_model_save'),
      hasLength(1),
    );
    await tester.pump(const Duration(seconds: 2));
  });
}

class _CapturingTelemetrySink implements GenesisTelemetrySink {
  final events = <GenesisTelemetryEvent>[];

  @override
  Future<void> captureException(Object error, StackTrace stackTrace) async {}

  @override
  Future<void> record(GenesisTelemetryEvent event) async {
    events.add(event);
  }

  @override
  Future<void> setContext(GenesisTelemetryContext context) async {}

  @override
  Future<void> setUserId(String? uid) async {}
}

BorderSide _tileBorder(WidgetTester tester, String modelCode) {
  final material = tester.widget<Material>(
    find.byKey(ValueKey<String>('gem-model-$modelCode')),
  );
  return (material.shape! as RoundedRectangleBorder).side;
}

Color _tileColor(WidgetTester tester, String modelCode) {
  return tester
      .widget<Material>(find.byKey(ValueKey<String>('gem-model-$modelCode')))
      .color!;
}

({Color? color, double? height, double? radius}) _tagContainer(
  WidgetTester tester,
  String tag,
) {
  final container = tester.widget<Container>(
    find.byKey(ValueKey<String>('gem-model-tag-$tag')),
  );
  final decoration = container.decoration! as BoxDecoration;
  return (
    color: decoration.color,
    height: container.constraints?.maxHeight,
    radius: decoration.borderRadius?.resolve(TextDirection.ltr).topLeft.x,
  );
}

GemModelCatalog _catalog() {
  return const GemModelCatalog(
    selectedModelCode: 'top_pick_v3',
    groups: [
      GemModelGroup(
        groupCode: 'recommended',
        groupTitle: 'Recommended',
        models: [
          GemModel(
            modelCode: 'top_pick_v3',
            title: 'Top Pick V3',
            tags: ['hot'],
            estimatedNextMessageGemsCent: 400,
            estimatedNextTickGemsCent: 400,
            description: 'Balanced storytelling.',
            rangeText: '4-320 gems (memory from 2K to 156K)',
          ),
          GemModel(
            modelCode: 'sake_pro',
            title: 'Sake Pro',
            tags: ['new'],
            estimatedNextMessageGemsCent: 300,
            estimatedNextTickGemsCent: 300,
            description: 'Flexible storytelling.',
            rangeText: '3-160 gems (memory from 2K to 156K)',
          ),
        ],
      ),
    ],
  );
}

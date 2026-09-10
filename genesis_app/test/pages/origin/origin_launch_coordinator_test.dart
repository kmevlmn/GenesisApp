import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/genesis_navigator.dart';
import 'package:genesis_flutter_android/network/models/origin.dart';
import 'package:genesis_flutter_android/network/models/world.dart';
import 'package:genesis_flutter_android/pages/origin/origin_launch_coordinator.dart';
import 'package:genesis_flutter_android/pages/origin/origin_launch_pending_store.dart';
import 'package:genesis_flutter_android/pages/world/world_page_result.dart';
import 'package:genesis_flutter_android/routers/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/font_expectations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OriginLaunchCoordinator.instance.resetForTesting();
  });

  tearDown(() async {
    OriginLaunchCoordinator.instance.resetForTesting();
    await OriginLaunchPendingStore.clear();
  });

  test('start saves pending launch until tick1 is ready', () async {
    var loadCount = 0;

    await OriginLaunchCoordinator.instance.start(
      originId: 'o_launching_1',
      worldId: 'w_launching_1',
      loadWorld: (worldId) async {
        loadCount += 1;
        return _worldDetail(worldId: worldId, tickCount: 0);
      },
    );
    await Future<void>.delayed(Duration.zero);

    final pending = await OriginLaunchPendingStore.load();
    expect(pending?.originId, 'o_launching_1');
    expect(pending?.worldId, 'w_launching_1');
    expect(
      OriginLaunchCoordinator.instance.state.value?.originId,
      'o_launching_1',
    );
    expect(loadCount, 1);
  });

  test('poll success clears pending launch and reports completion', () async {
    final outcomes = <OriginLaunchOutcome>[];
    final removeListener = OriginLaunchCoordinator.instance.addOutcomeListener(
      outcomes.add,
    );

    await OriginLaunchCoordinator.instance.start(
      originId: 'o_ready_1',
      worldId: 'w_ready_1',
      loadWorld: (worldId) async =>
          _worldDetail(worldId: worldId, tickCount: 1),
    );
    await Future<void>.delayed(Duration.zero);

    expect(await OriginLaunchPendingStore.load(), isNull);
    expect(OriginLaunchCoordinator.instance.state.value, isNull);
    expect(outcomes, hasLength(1));
    expect(outcomes.single.completed, isTrue);
    expect(outcomes.single.originId, 'o_ready_1');
    expect(outcomes.single.world?.tickCount, 1);

    removeListener();
  });

  test('expired pending launch uses launched exit without polling', () async {
    final outcomes = <OriginLaunchOutcome>[];
    final removeListener = OriginLaunchCoordinator.instance.addOutcomeListener(
      outcomes.add,
    );
    addTearDown(removeListener);
    await OriginLaunchPendingStore.save(
      originId: 'o_timeout_1',
      worldId: 'w_timeout_1',
      initialLocationId: 'l_opening_1',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pending_origin_launch_started_at',
      DateTime.now()
          .toUtc()
          .subtract(OriginLaunchPendingStore.timeout)
          .subtract(const Duration(seconds: 1))
          .toIso8601String(),
    );

    await OriginLaunchCoordinator.instance.ensurePolling(
      originId: 'o_timeout_1',
      loadWorld: (_) => fail('Expired launch should not poll world detail'),
    );

    expect(await OriginLaunchPendingStore.load(), isNull);
    expect(OriginLaunchCoordinator.instance.state.value, isNull);
    expect(outcomes, hasLength(1));
    expect(outcomes.single.completed, isTrue);
    expect(outcomes.single.originId, 'o_timeout_1');
    expect(outcomes.single.worldId, 'w_timeout_1');
    expect(outcomes.single.world, isNull);
  });

  testWidgets('expired pending launch shows launched exit and opens world', (
    WidgetTester tester,
  ) async {
    await OriginLaunchPendingStore.save(
      originId: 'o_timeout_1',
      worldId: 'w_timeout_1',
      initialLocationId: 'l_opening_1',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pending_origin_launch_started_at',
      DateTime.now()
          .toUtc()
          .subtract(OriginLaunchPendingStore.timeout)
          .subtract(const Duration(seconds: 1))
          .toIso8601String(),
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: genesisNavigatorKey,
        onGenerateRoute: (settings) {
          if (settings.name == RouteNames.home) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('home')),
            );
          }
          if (settings.name == RouteNames.world) {
            final args = settings.arguments as Map?;
            return MaterialPageRoute<WorldPageResult>(
              settings: settings,
              builder: (_) => Scaffold(
                body: Text(
                  'world_wid=${args?['wid']} '
                  'location=${args?['initial_location_id']}',
                ),
              ),
            );
          }
          return null;
        },
        home: const Scaffold(body: Text('start')),
      ),
    );

    final polling = OriginLaunchCoordinator.instance.ensurePolling(
      originId: 'o_timeout_1',
      loadWorld: (_) => fail('Expired launch should not poll world detail'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Launch timed out'), findsNothing);
    expect(
      _richTextWithPlainText('Worldo #w_timeout_1 launched!'),
      findsOneWidget,
    );
    expectInterText(
      tester,
      _richTextWithPlainText('Worldo #w_timeout_1 launched!'),
    );

    await tester.tap(find.text('Enter'));
    await tester.pump();
    await tester.pump();
    await polling;
    await tester.pump();
    await tester.pump();
    expect(
      find.text('world_wid=w_timeout_1 location=l_opening_1'),
      findsOneWidget,
    );
  });
}

Finder _richTextWithPlainText(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText() == text,
  );
}

WorldDetail _worldDetail({required String worldId, required int tickCount}) {
  return WorldDetail(
    id: 1,
    worldId: worldId,
    originId: 1,
    ownerUid: 'u_owner',
    name: 'World $worldId',
    tickCount: tickCount,
    connectCount: 0,
    characterCount: 0,
    playerCount: 0,
    currentTime: '',
    latestTickAt: null,
    latestNarrator: '',
    isProgressing: false,
    relationStatus: 'owner',
    metric: const <String, dynamic>{},
    inviteToken: worldId,
    createdAt: null,
    updatedAt: null,
    origin: const OriginSummary(
      id: 1,
      oid: 'o_test',
      name: 'Origin',
      description: '',
      mapImage: '',
      worldMap: '',
      worldView: '',
      copyCount: 0,
      interactCount: 0,
      tags: <String>[],
      createdAt: null,
      updatedAt: null,
      characters: <OriginCharacter>[],
      locations: <OriginLocation>[],
    ),
    characters: const <Map<String, dynamic>>[],
    ticks: const <Map<String, dynamic>>[],
    locations: const <Map<String, dynamic>>[],
    characterPositions: const <Map<String, dynamic>>[],
    userPositions: const <Map<String, dynamic>>[],
  );
}

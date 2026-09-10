import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/bootstrap/app_services_scope.dart';
import 'package:genesis_flutter_android/app/bootstrap/service_registry.dart';
import 'package:genesis_flutter_android/app/config/app_config.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_message_storage.dart';
import 'package:genesis_flutter_android/network/direct_message_conversation_store.dart';
import 'package:genesis_flutter_android/network/direct_message_message_store.dart';
import 'package:genesis_flutter_android/network/genesis_api.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/pages/search/search_page.dart';
import 'package:genesis_flutter_android/pages/world/world_page_result.dart';
import 'package:genesis_flutter_android/platform/session/memory_user_session_store.dart';
import 'package:genesis_flutter_android/routers/app_router.dart';
import 'package:genesis_flutter_android/ui/components/genesis_avatar.dart';
import 'package:genesis_flutter_android/ui/components/genesis_search_field.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';
import 'package:genesis_flutter_android/ui/components/genesis_list_image.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_avatar_radii.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_origin_card_geometry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('search push and pop keep dark pixels on $platform', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final boundaryKey = GlobalKey();
      // Build the fixture without native billing; the route platform below
      // still exercises the real Android/iOS transition implementations.
      final previousPlatform = debugDefaultTargetPlatformOverride;
      late final AppServices services;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        services = await _servicesWithTransport(_SearchPageTransport());
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: MaterialApp(
            theme: GenesisTheme.light().copyWith(platform: platform),
            onGenerateRoute: AppRouter.onGenerateRoute,
            builder: (context, child) =>
                RepaintBoundary(key: boundaryKey, child: child!),
            home: Scaffold(
              backgroundColor: GenesisColors.darkBackground,
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(RouteNames.search),
                  child: const Text('Open search'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> checkFrames() async {
        for (final milliseconds in [0, 16, 32, 64, 100, 120, 200]) {
          await tester.pump(Duration(milliseconds: milliseconds));
          final channels = await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              return [
                for (final x in [24, 195, 366])
                  for (var channel = 0; channel < 3; channel++)
                    bytes.getUint8((400 * image.width + x) * 4 + channel),
              ];
            } finally {
              image.dispose();
            }
          });
          expect(
            channels,
            everyElement(lessThan(64)),
            reason:
                'Empty page regions must stay dark throughout the transition.',
          );
        }
      }

      await tester.tap(find.text('Open search'));
      await checkFrames();
      expect(find.byType(SearchPage), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await checkFrames();
      await tester.pumpAndSettle();
      expect(find.byType(SearchPage), findsNothing);
    });
  }

  testWidgets('does not request search before three letters or chinese chars', (
    tester,
  ) async {
    final transport = _SearchPageTransport();
    await _pumpSearchPage(tester, transport);

    // The editable search entrance must match Home from its first frame.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, GenesisColors.darkBackground);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style?.color, GenesisColors.darkTextPrimary);
    expect(field.cursorColor, GenesisColors.darkTextPrimary);
    expect(field.decoration?.hintText, genesisSearchHintText);
    expect(
      field.decoration?.hintStyle?.color,
      GenesisColors.darkInputPlaceholder,
    );

    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 700));

    expect(transport.searchRequests, isEmpty);

    await tester.enterText(find.byType(TextField), '1你');
    await tester.pump(const Duration(milliseconds: 700));

    expect(transport.searchRequests, isEmpty);

    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump(const Duration(milliseconds: 700));

    expect(transport.searchRequests, isEmpty);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(
      tester.widget<Icon>(find.byIcon(Icons.close)).color,
      GenesisColors.darkTextTertiary,
    );
    expect(transport.searchRequests, hasLength(1));
    expect(
      transport.searchRequests.single.uri.queryParameters['keyword'],
      'abc',
    );
    expect(
      transport.searchRequests.single.uri.queryParameters['type'],
      'origin',
    );
  });

  testWidgets('uses the compact Search History capsule style', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'search_recent_queries_v1': <String>['history query'],
    });
    final transport = _SearchPageTransport();
    await _pumpSearchPage(tester, transport);
    await tester.pumpAndSettle();

    expect(find.text('Search history'), findsOneWidget);
    final historyText = tester.widget<Text>(find.text('history query'));
    expect(historyText.style?.color, GenesisColors.darkTextSecondary);
    final capsule = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.text('history query'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = capsule.decoration as BoxDecoration;
    expect(decoration.color, GenesisColors.darkFaintFill);
    expect(decoration.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('uses card skeletons instead of progress rings while loading', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1400);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport(
      searchDelay: const Duration(seconds: 1),
    );
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('genesis-search-result-list-skeleton')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'genesis-search-result-origin-thumbnail-skeleton',
        ),
      ),
      findsWidgets,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('#Origin 1'), findsOneWidget);
  });

  testWidgets('shows no results only after a successful empty response', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1400);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport(
      singleWorldResult: true,
      searchDelay: const Duration(seconds: 1),
    );
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(find.text('No results.'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('genesis-search-result-list-skeleton')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('No results.'), findsOneWidget);
  });

  testWidgets('switches directly from results to the next tab skeleton', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1400);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport(
      searchDelay: const Duration(seconds: 1),
    );
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('#Origin 1'), findsOneWidget);

    await tester.tap(find.text('World'));
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      if (transport.searchRequests.any(
        (request) => request.uri.queryParameters['type'] == 'world',
      )) {
        break;
      }
    }
    expect(transport.searchRequests.last.uri.queryParameters['type'], 'world');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No results.'), findsNothing);
    expect(
      find.byKey(
        const ValueKey<String>(
          'genesis-search-result-world-thumbnail-skeleton',
        ),
      ),
      findsWidgets,
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('World 1'), findsOneWidget);
    expect(find.text('Tick 11-2 · 21 Messages · 41 Players'), findsOneWidget);
  });

  testWidgets('uses the shared list progress style while loading next page', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport(
      paginated: true,
      loadMoreDelay: const Duration(seconds: 1),
    );
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final resultsList = find.byType(ListView).hitTestable().first;
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: resultsList, matching: find.byType(Scrollable)),
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('search-result-load-more')),
      findsOneWidget,
    );
    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.strokeWidth, 2);
    expect(progress.color, GenesisColors.darkTextSecondary);
    expect(
      tester.getSize(find.byType(CircularProgressIndicator)),
      const Size.square(20),
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('#Origin 21'), findsOneWidget);
  });

  testWidgets('updates all tab totals from every typed response', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1800);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport(
      sectionTotals: const {'origin': 114, 'world': 99, 'user': 34},
    );
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    final tabRectsBeforeTotals = {
      for (final tab in const ['origin', 'world', 'user'])
        tab: tester.getRect(find.byKey(ValueKey<String>('search-tab-$tab'))),
    };
    expect(tabRectsBeforeTotals['origin']?.left, 16);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    for (final entry in tabRectsBeforeTotals.entries) {
      expect(
        tester.getRect(find.byKey(ValueKey<String>('search-tab-${entry.key}'))),
        entry.value,
      );
    }
    expect(_searchTabCount('origin', '99+'), findsOneWidget);
    expect(_searchTabCount('world', '99'), findsOneWidget);
    expect(_searchTabCount('user', '34'), findsOneWidget);
    final originCount = tester.widget<Text>(_searchTabCount('origin', '99+'));
    final originLabel = find.descendant(
      of: find.byKey(const ValueKey<String>('search-tab-origin')),
      matching: find.text('Worldo'),
    );
    final originLabelStyle = DefaultTextStyle.of(
      tester.element(originLabel),
    ).style;
    expect(originCount.style?.fontSize, originLabelStyle.fontSize);
    expect(originCount.style?.color, originLabelStyle.color);
    expect(originCount.style?.fontWeight, FontWeight.w400);
    expect(find.text('All'), findsNothing);
    expect(find.text('#Origin 4'), findsOneWidget);
    expect(
      transport.searchRequests.single.uri.queryParameters['type'],
      'origin',
    );

    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    expect(_searchTabCount('origin', '99+'), findsOneWidget);
    expect(_searchTabCount('world', '99'), findsOneWidget);
    expect(_searchTabCount('user', '34'), findsOneWidget);
    final worldCount = tester.widget<Text>(_searchTabCount('world', '99'));
    final worldLabel = find.descendant(
      of: find.byKey(const ValueKey<String>('search-tab-world')),
      matching: find.text('World'),
    );
    final worldLabelStyle = DefaultTextStyle.of(
      tester.element(worldLabel),
    ).style;
    expect(worldCount.style?.fontSize, worldLabelStyle.fontSize);
    expect(worldCount.style?.color, worldLabelStyle.color);
    expect(worldCount.style?.fontWeight, FontWeight.w400);
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.labelPadding, const EdgeInsets.only(right: 42));
    expect(transport.searchRequests.last.uri.queryParameters['type'], 'world');

    await tester.tap(find.text('User'));
    await tester.pumpAndSettle();
    expect(_searchTabCount('origin', '99+'), findsOneWidget);
    expect(_searchTabCount('world', '99'), findsOneWidget);
    expect(_searchTabCount('user', '34'), findsOneWidget);
    expect(transport.searchRequests.last.uri.queryParameters['type'], 'user');
    expect(transport.searchRequests, hasLength(3));
  });

  testWidgets('selects a typed tab only for a complete six-character id', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1800);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport();
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'U_a1B2c3');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('User 1'), findsOneWidget);
    expect(find.text('#Origin 1'), findsNothing);
    expect(transport.searchRequests.last.uri.queryParameters['type'], 'user');

    await tester.enterText(find.byType(TextField), 'w_1A2b3C');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('World 1'), findsOneWidget);
    expect(find.text('User 1'), findsNothing);
    expect(transport.searchRequests.last.uri.queryParameters['type'], 'world');

    await tester.enterText(find.byType(TextField), 'u_ab12');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('#Origin 1'), findsOneWidget);
    expect(find.text('User 1'), findsNothing);
    expect(transport.searchRequests.last.uri.queryParameters['type'], 'origin');

    await tester.enterText(find.byType(TextField), 'w_abcdefg');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('#Origin 1'), findsOneWidget);
    expect(find.text('World 1'), findsNothing);
    expect(transport.searchRequests.last.uri.queryParameters['type'], 'origin');

    await tester.enterText(find.byType(TextField), 'anything');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('#Origin 1'), findsOneWidget);
    expect(find.text('World 1'), findsNothing);
    expect(transport.searchRequests.last.uri.queryParameters['type'], 'origin');
  });

  testWidgets('loads the next page independently for all three typed tabs', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport(paginated: true);
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    for (final entry in const [
      (tabLabel: 'Worldo', type: 'origin', lastItem: '#Origin 21'),
      (tabLabel: 'World', type: 'world', lastItem: 'World 21'),
      (tabLabel: 'User', type: 'user', lastItem: 'User 21'),
    ]) {
      if (entry.type != 'origin') {
        await tester.tap(find.text(entry.tabLabel));
        await tester.pumpAndSettle();
      }

      await tester.drag(
        find.byType(ListView).hitTestable().first,
        const Offset(0, -5000),
      );
      await tester.pumpAndSettle();

      final requests = transport.searchRequests
          .where((request) => request.uri.queryParameters['type'] == entry.type)
          .toList(growable: false);
      expect(requests, hasLength(2));
      expect(requests.last.uri.queryParameters['pn'], '2');
      expect(requests.last.uri.queryParameters['rn'], '20');
      expect(find.text(entry.lastItem), findsOneWidget);
    }
  });

  testWidgets('shows default Worldo brief when no summary field matches', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport(originNameMatchOnly: true);
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('#Origin 1'), findsOneWidget);
    expect(find.text('OID: origin_1'), findsOneWidget);
    expect(find.text('Originator: Deleted User'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Originator: Deleted User')).dy,
      greaterThan(tester.getTopLeft(find.text('OID: origin_1')).dy),
    );
    expect(find.textContaining('Brief:'), findsNothing);
    expect(find.textContaining('Characters:'), findsNothing);
    expect(find.textContaining('Latest Version:'), findsNothing);
    final brief = tester.widget<Text>(
      find.byKey(const ValueKey<String>('origin-summary-brief')).first,
    );
    expect(brief.textSpan?.toPlainText(), 'Origin brief 1');
    expect(brief.maxLines, 2);
    expect(brief.style?.color, GenesisColors.darkTextSecondary);
  });

  testWidgets('renders world fields from the v2 search contract', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1800);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport();
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();

    expect(find.text('World 1'), findsOneWidget);
    expect(find.text('WID: world_1'), findsOneWidget);
    expect(find.text('Owner: Owner 1'), findsOneWidget);
    expect(find.text('Tick 11-2 · 21 Messages · 41 Players'), findsOneWidget);
  });

  testWidgets('shows matched Tags only for Worldo and never for World', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1800);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport(
      originNameMatchOnly: true,
      includeTagMatches: true,
    );
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'tag');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final originTags = tester.widget<Text>(find.text('tag-1'));
    expect(_highlightedTextParts(originTags), ['tag']);
    final tagsBox = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('origin-summary-tags')).first,
    );
    final tagsDecoration = tagsBox.decoration as BoxDecoration;
    expect(tagsDecoration.color, GenesisColors.darkFaintFill);
    expect(tagsDecoration.borderRadius, BorderRadius.circular(4));
    expect(originTags.style?.color, GenesisColors.darkTextSecondary);
    final tagsPadding = tester.widget<Padding>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('origin-summary-tags')).first,
        matching: find.byType(Padding),
      ),
    );
    expect(tagsPadding.padding, const EdgeInsets.symmetric(horizontal: 8));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('origin-summary-tags')).first,
          )
          .height,
      20,
    );

    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tags:'), findsNothing);
  });

  testWidgets('does not show a Tags row without a tag match', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1800);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport();
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tags:'), findsNothing);

    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tags:'), findsNothing);
  });

  testWidgets('orders Worldo summaries as character then brief', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport(includeTagMatches: true);
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final briefFinder = find.byKey(
      const ValueKey<String>('origin-summary-brief'),
    );
    final brief = tester.widget<Text>(briefFinder.first);
    expect(brief.textSpan?.toPlainText(), 'Origin brief 1');
    expect(brief.maxLines, 2);
    expect(brief.textSpan?.toPlainText(), isNot(contains('…')));
    final charactersFinder = find.byKey(
      const ValueKey<String>('origin-summary-characters'),
    );
    final charactersText = tester.widget<Text>(
      find.descendant(
        of: charactersFinder.first,
        matching: find.text('Character 1, Supporting 1'),
      ),
    );
    expect(charactersText.style?.color, GenesisColors.darkTextSecondary);
    expect(
      tester.getTopLeft(charactersFinder.first).dy,
      lessThan(tester.getTopLeft(briefFinder.first).dy),
    );
    expect(
      find.byKey(const ValueKey<String>('origin-summary-tags')),
      findsNothing,
    );
    expect(find.textContaining('Latest Version:'), findsNothing);
  });

  testWidgets('keeps a prefix before a complete trailing Brief match', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport(trailingBriefMatch: true);
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'rooftop');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final briefFinder = find.byKey(
      const ValueKey<String>('origin-summary-brief'),
    );
    final brief = tester.widget<Text>(briefFinder.first);
    final displayedBrief = brief.textSpan!.toPlainText();
    expect(brief.maxLines, 2);
    expect(displayedBrief, contains('…'));
    expect(displayedBrief, startsWith('Two'));
    expect(displayedBrief, isNot(startsWith('…')));
    expect(displayedBrief, contains('rooftop'));
    expect(displayedBrief, endsWith('rooftop'));
    expect(_highlightedTextParts(brief), contains('rooftop'));
    expect(displayedBrief, isNot(contains('ro…')));

    final painter = TextPainter(
      text: TextSpan(style: brief.style, children: [brief.textSpan!]),
      maxLines: 2,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: tester.getSize(briefFinder.first).width);
    expect(painter.didExceedMaxLines, isFalse);
  });

  testWidgets('highlights every documented v2 search match field', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport();
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(_highlightedTextParts(tester.widget<Text>(find.text('#Origin 1'))), [
      'Origin',
    ]);
    expect(
      _highlightedTextParts(
        tester.widget<Text>(
          find.byKey(const ValueKey<String>('origin-summary-brief')).first,
        ),
      ),
      ['Origin', 'brief'],
    );
    expect(
      _highlightedTextParts(
        tester.widget<Text>(find.text('Character 1, Supporting 1')),
      ),
      ['Character', 'Supporting'],
    );

    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    expect(_highlightedTextParts(tester.widget<Text>(find.text('World 1'))), [
      'World',
    ]);

    await tester.tap(find.text('User'));
    await tester.pumpAndSettle();
    expect(_highlightedTextParts(tester.widget<Text>(find.text('User 1'))), [
      'User',
    ]);
  });

  testWidgets('highlights matched OID WID and UID text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport(includeIdMatches: true);
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'id-query');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(
      _highlightedTextParts(
        tester.widget<Text>(find.textContaining('OID: origin_1')),
      ),
      ['origin_1'],
    );

    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    expect(
      _highlightedTextParts(tester.widget<Text>(find.text('WID: world_1'))),
      ['world_1'],
    );

    await tester.tap(find.text('User'));
    await tester.pumpAndSettle();
    expect(
      _highlightedTextParts(tester.widget<Text>(find.text('UID: user_1'))),
      ['user_1'],
    );
  });

  testWidgets('highlights ID query when backend omits ID match ranges', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport();
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'origin_1');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(
      _highlightedTextParts(
        tester.widget<Text>(find.textContaining('OID: origin_1')),
      ),
      ['origin_1'],
    );

    await tester.enterText(find.byType(TextField), 'world_1');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();
    expect(
      _highlightedTextParts(tester.widget<Text>(find.text('WID: world_1'))),
      ['world_1'],
    );

    await tester.enterText(find.byType(TextField), 'USER_1');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.text('User'));
    await tester.pumpAndSettle();
    expect(
      _highlightedTextParts(tester.widget<Text>(find.text('UID: user_1'))),
      ['user_1'],
    );
  });

  testWidgets('shows the documented origin owner name in search results', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport();
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.textContaining('Originator: Deleted User'), findsOneWidget);
  });

  testWidgets('dismisses search focus when tapping result area', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport();
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isTrue);

    await tester.tapAt(const Offset(400, 1100));
    await tester.pump();

    expect(editable.widget.focusNode.hasFocus, isFalse);
  });

  testWidgets('uses the Worldo cover ratio and compact result spacing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1400);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport();
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final originTile = find
        .ancestor(
          of: find.text('#Origin 1'),
          matching: find.byType(GestureDetector),
        )
        .first;
    final originImage = tester.widget<GenesisListImage>(
      find.descendant(of: originTile, matching: find.byType(GenesisListImage)),
    );
    expect(
      (originImage.placeholder as ColoredBox).color,
      GenesisColors.darkFaintFill,
    );
    expect(originImage.width, 60);
    expect(originImage.height, 60 / genesisOriginCoverAspectRatio);

    final originSizedBoxes = tester
        .widgetList<SizedBox>(
          find.descendant(of: originTile, matching: find.byType(SizedBox)),
        )
        .toList();
    expect(
      originSizedBoxes.any((box) => box.width == 14),
      isTrue,
      reason: 'Worldo image-to-text gap should match the shared list layout.',
    );
    expect(
      originSizedBoxes.any((box) => box.height == 4),
      isTrue,
      reason: 'Every Worldo content-row gap should be 4px.',
    );
    expect(
      originSizedBoxes.any((box) => box.height == 5 || box.height == 8),
      isFalse,
      reason: 'Worldo should not retain the old 5px or 8px row gaps.',
    );
    final originSubtitle = tester.widget<Text>(
      find.descendant(
        of: originTile,
        matching: find.textContaining('OID: origin_1'),
      ),
    );
    expect(originSubtitle.style?.height, 1.2);
    expect(originSubtitle.style?.color, GenesisColors.darkTextTertiary);
    final originStatTexts = tester.widgetList<Text>(
      find.descendant(of: originTile, matching: find.text('1')),
    );
    expect(originStatTexts, isNotEmpty);
    expect(
      originStatTexts.every(
        (text) => text.style?.color == GenesisColors.darkTextSecondary,
      ),
      isTrue,
    );
    final originStatIcons = tester.widgetList<SvgPicture>(
      find.descendant(of: originTile, matching: find.byType(SvgPicture)),
    );
    expect(originStatIcons, isNotEmpty);
    expect(
      originStatIcons.every((icon) => icon.width == 12 && icon.height == 12),
      isTrue,
    );
    expect(
      originStatIcons.every(
        (icon) =>
            icon.colorFilter ==
            const ColorFilter.mode(
              GenesisColors.darkTextSecondary,
              BlendMode.srcIn,
            ),
      ),
      isTrue,
    );

    await tester.tap(find.text('World'));
    await tester.pumpAndSettle();

    final worldTile = find
        .ancestor(
          of: find.text('World 1'),
          matching: find.byType(GestureDetector),
        )
        .first;
    final worldImage = tester.widget<GenesisListImage>(
      find.descendant(of: worldTile, matching: find.byType(GenesisListImage)),
    );
    expect(
      (worldImage.placeholder as ColoredBox).color,
      GenesisColors.darkFaintFill,
    );
    expect(worldImage.width, 60);
    expect(worldImage.height, 90);
    final worldSizedBoxes = tester
        .widgetList<SizedBox>(
          find.descendant(of: worldTile, matching: find.byType(SizedBox)),
        )
        .toList();
    expect(
      worldSizedBoxes.any((box) => box.width == 14),
      isTrue,
      reason: 'World image-to-text gap should match My Worlds cards.',
    );
    expect(
      worldSizedBoxes.where((box) => box.height == 4),
      hasLength(3),
      reason: 'World result rows should use 4px vertical gaps.',
    );
    final worldMetadata = tester.widget<Text>(
      find.descendant(of: worldTile, matching: find.text('WID: world_1')),
    );
    expect(worldMetadata.style?.fontSize, 12);
    expect(worldMetadata.style?.height, 1.2);
    expect(worldMetadata.style?.color, GenesisColors.darkTextTertiary);
    final worldStats = tester.widget<Text>(
      find.descendant(
        of: worldTile,
        matching: find.text('Tick 11-2 · 21 Messages · 41 Players'),
      ),
    );
    expect(worldStats.style?.fontSize, 12);
    expect(worldStats.style?.height, 1.2);
    expect(worldStats.style?.color, GenesisColors.darkTextSecondary);

    await tester.tap(find.text('User'));
    await tester.pumpAndSettle();

    final userTile = find
        .ancestor(
          of: find.text('User 1'),
          matching: find.byType(GestureDetector),
        )
        .first;
    final userAvatar = tester.widget<GenesisAvatar>(
      find.descendant(of: userTile, matching: find.byType(GenesisAvatar)),
    );
    expect(userAvatar.size, 52);
    expect(userAvatar.borderRadius, GenesisAvatarRadii.user);

    final userAvatarRect = tester.getRect(
      find.descendant(of: userTile, matching: find.byType(GenesisAvatar)),
    );
    final userNameRect = tester.getRect(
      find.descendant(of: userTile, matching: find.text('User 1')),
    );
    expect(userNameRect.top, closeTo(userAvatarRect.top, 1));

    final userUid = tester.widget<Text>(
      find.descendant(of: userTile, matching: find.text('UID: user_1')),
    );
    expect(userUid.style?.color, GenesisColors.darkTextTertiary);

    final userSizedBoxes = tester
        .widgetList<SizedBox>(
          find.descendant(of: userTile, matching: find.byType(SizedBox)),
        )
        .toList();
    expect(userSizedBoxes.any((box) => box.width == 10), isTrue);
    expect(userSizedBoxes.any((box) => box.height == 7), isTrue);
  });

  testWidgets('uses the full screen DPR for every search result image', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1290, 4200);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport();
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final listImages = tester.widgetList<GenesisListImage>(
      find.byType(GenesisListImage),
    );
    expect(listImages, isNotEmpty);
    expect(listImages.every((image) => image.maxDevicePixelRatio == 3), isTrue);

    await tester.tap(find.text('User'));
    await tester.pumpAndSettle();
    final userAvatars = tester.widgetList<GenesisAvatar>(
      find.byType(GenesisAvatar),
    );
    expect(userAvatars, isNotEmpty);
    expect(
      userAvatars.every((avatar) => avatar.maxDevicePixelRatio == 3),
      isTrue,
    );
  });

  testWidgets('Worldo keeps matched character names whole within two lines', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(tester.view.reset);

    final transport = _SearchPageTransport(longOriginContent: true);
    await _pumpSearchPage(tester, transport);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final tile = find
        .ancestor(
          of: find.text('#Origin 1'),
          matching: find.byType(GestureDetector),
        )
        .first;
    final brief = tester.widget<Text>(
      find.byKey(const ValueKey<String>('origin-summary-brief')),
    );
    final characters = find.byKey(
      const ValueKey<String>('origin-summary-characters'),
    );
    final charactersText = tester.widget<Text>(
      find.descendant(
        of: characters,
        matching: find.text('Extra Character 12'),
      ),
    );
    final charactersValue = charactersText.textSpan!.toPlainText();

    expect(brief.maxLines, 2);
    expect(brief.textSpan?.toPlainText(), contains('…'));
    expect(brief.textSpan?.toPlainText(), contains('Latest Version visible'));
    expect(_highlightedTextParts(brief), contains('Latest Version visible'));
    expect(characters, findsOneWidget);
    expect(charactersText.maxLines, 2);
    expect(charactersValue, 'Extra Character 12');
    expect(
      _highlightedTextParts(charactersText),
      contains('Extra Character 12'),
    );
    expect(
      tester.getTopLeft(characters).dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey<String>('origin-summary-brief')),
            )
            .dy,
      ),
    );
    expect(find.textContaining('Latest Version:'), findsNothing);
    expect(tester.getSize(tile).height, greaterThan(90));
  });

  testWidgets('removes deleted world from search results after detail closes', (
    tester,
  ) async {
    final transport = _SearchPageTransport(singleWorldResult: true);
    await _pumpSearchPage(
      tester,
      transport,
      onGenerateRoute: (settings) {
        if (settings.name != RouteNames.world) return null;
        return MaterialPageRoute<WorldPageResult>(
          settings: settings,
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(const WorldPageResult.deleted(deletedWorldId: 'world_1')),
                child: const Text('Delete world'),
              ),
            ),
          ),
        );
      },
    );

    await tester.enterText(find.byType(TextField), 'w_abc123');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('World 1'), findsOneWidget);
    await tester.tap(find.text('World 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete world'));
    await tester.pumpAndSettle();

    expect(find.text('World 1'), findsNothing);
    expect(find.text('No results.'), findsOneWidget);
  });
}

Finder _searchTabCount(String tab, String count) {
  return find.descendant(
    of: find.byKey(ValueKey<String>('search-tab-count-$tab')),
    matching: find.text(count),
  );
}

Future<void> _pumpSearchPage(
  WidgetTester tester,
  _SearchPageTransport transport, {
  RouteFactory? onGenerateRoute,
}) async {
  await tester.pumpWidget(
    AppServicesScope(
      services: await _servicesWithTransport(transport),
      child: MaterialApp(
        home: const SearchPage(),
        onGenerateRoute: onGenerateRoute,
      ),
    ),
  );
  await tester.pump();
}

Future<AppServices> _servicesWithTransport(
  _SearchPageTransport transport,
) async {
  final base = ServiceRegistry.build(config: const AppConfig(useMock: true));
  final apiClient = ApiClient(
    baseUrl: 'http://localhost:8080/api/',
    defaultHeaders: const {
      'content-type': 'application/json',
      'accept': 'application/json',
    },
    transport: transport,
  );
  final healthClient = ApiClient(
    baseUrl: 'http://localhost:8080/',
    defaultHeaders: const {'accept': 'application/json'},
    transport: transport,
  );
  final sessionStore = MemoryUserSessionStore();
  await sessionStore.saveUid('u_test');
  await sessionStore.saveAuthToken('test-token');
  final api = GenesisApi(
    apiClient: apiClient,
    healthClient: healthClient,
    sessionStore: sessionStore,
  );
  return AppServices(
    config: base.config,
    platformConfig: base.platformConfig,
    deviceId: base.deviceId,
    sessionStore: sessionStore,
    identityAuth: base.identityAuth,
    backendAuth: base.backendAuth,
    api: api,
    chatroom: base.chatroom,
    chatroomMessages: MemoryChatroomMessageStorage(),
    directMessageConversations: DirectMessageConversationStore(
      api: api,
      sessionStore: sessionStore,
      storage: MemoryDirectMessageConversationStorage(),
    ),
    directMessageMessages: DirectMessageMessageStore(
      api: api,
      sessionStore: sessionStore,
      storage: MemoryDirectMessageMessageStorage(),
    ),
    appVersionCheck: base.appVersionCheck,
    externalUrlOpener: base.externalUrlOpener,
  );
}

class _SearchPageTransport implements HttpTransport {
  _SearchPageTransport({
    this.singleWorldResult = false,
    this.longOriginContent = false,
    this.originNameMatchOnly = false,
    this.trailingBriefMatch = false,
    this.includeTagMatches = false,
    this.includeIdMatches = false,
    this.paginated = false,
    this.sectionTotals = const <String, int>{},
    this.searchDelay = Duration.zero,
    this.loadMoreDelay = Duration.zero,
  });

  final bool singleWorldResult;
  final bool longOriginContent;
  final bool originNameMatchOnly;
  final bool trailingBriefMatch;
  final bool includeTagMatches;
  final bool includeIdMatches;
  final bool paginated;
  final Map<String, int> sectionTotals;
  final Duration searchDelay;
  final Duration loadMoreDelay;
  final List<TransportRequest> requests = <TransportRequest>[];

  List<TransportRequest> get searchRequests => requests
      .where((request) => request.uri.path.endsWith('/v2/search'))
      .toList(growable: false);

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    if (request.uri.path.endsWith('/v2/search')) {
      final pageNumber =
          int.tryParse(request.uri.queryParameters['pn'] ?? '') ?? 1;
      final delay = pageNumber > 1 ? loadMoreDelay : searchDelay;
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (singleWorldResult) {
        return _jsonResponse({
          'keyword': request.uri.queryParameters['keyword'] ?? '',
          'type': request.uri.queryParameters['type'] ?? '',
          'origins': _emptySection(),
          'worlds': {
            'list': [_item('world', 1)],
            'total': 1,
            'pn': 1,
            'rn': 20,
          },
          'users': _emptySection(),
        });
      }
      return _jsonResponse({
        'keyword': request.uri.queryParameters['keyword'] ?? '',
        'type': request.uri.queryParameters['type'] ?? '',
        'origins': _section(
          'origin',
          request.uri.queryParameters['type'],
          total: sectionTotals['origin'],
          longOriginContent: longOriginContent,
          originNameMatchOnly: originNameMatchOnly,
          trailingBriefMatch: trailingBriefMatch,
          includeTagMatches: includeTagMatches,
          includeIdMatches: includeIdMatches,
          paginated: paginated,
          pageNumber: pageNumber,
        ),
        'worlds': _section(
          'world',
          request.uri.queryParameters['type'],
          total: sectionTotals['world'],
          includeTagMatches: includeTagMatches,
          includeIdMatches: includeIdMatches,
          paginated: paginated,
          pageNumber: pageNumber,
        ),
        'users': _section(
          'user',
          request.uri.queryParameters['type'],
          total: sectionTotals['user'],
          includeIdMatches: includeIdMatches,
          paginated: paginated,
          pageNumber: pageNumber,
        ),
      });
    }
    return _jsonResponse(const <String, dynamic>{});
  }
}

Map<String, dynamic> _emptySection() {
  return const {'list': <Object?>[], 'total': 0, 'pn': 1, 'rn': 20};
}

Map<String, dynamic> _section(
  String type,
  String? requestedType, {
  int? total,
  bool longOriginContent = false,
  bool originNameMatchOnly = false,
  bool trailingBriefMatch = false,
  bool includeTagMatches = false,
  bool includeIdMatches = false,
  bool paginated = false,
  int pageNumber = 1,
}) {
  final resultTotal = total ?? (paginated ? 21 : 4);
  if (requestedType != null &&
      requestedType.isNotEmpty &&
      requestedType != type) {
    return {
      'list': const <Object?>[],
      'total': resultTotal,
      'pn': pageNumber,
      'rn': 20,
    };
  }
  final itemCount = paginated
      ? switch (pageNumber) {
          1 => 20,
          2 => 1,
          _ => 0,
        }
      : longOriginContent && type == 'origin'
      ? 1
      : 4;
  final firstItemIndex = paginated ? ((pageNumber - 1) * 20) + 1 : 1;
  return {
    'list': [
      for (var offset = 0; offset < itemCount; offset += 1)
        _item(
          type,
          firstItemIndex + offset,
          longOriginContent: longOriginContent,
          originNameMatchOnly: originNameMatchOnly,
          trailingBriefMatch: trailingBriefMatch,
          includeTagMatches: includeTagMatches,
          includeIdMatches: includeIdMatches,
        ),
    ],
    'total': total ?? (paginated ? 21 : itemCount),
    'pn': pageNumber,
    'rn': 20,
  };
}

const _longOriginBrief =
    'This is a deliberately long Worldo brief used to verify that the '
    'search result card measures its complete content, wraps onto '
    'additional lines, and still keeps Latest Version visible.';

const _trailingMatchBrief =
    'Two delinquents who bully you are kissing?! You saw the whole scene '
    'on the rooftop';

Map<String, dynamic> _item(
  String type,
  int index, {
  bool longOriginContent = false,
  bool originNameMatchOnly = false,
  bool trailingBriefMatch = false,
  bool includeTagMatches = false,
  bool includeIdMatches = false,
}) {
  return switch (type) {
    'origin' => {
      'origin_id': 'origin_$index',
      'origin_name': 'Origin $index',
      'origin_version': '$index',
      'brief': trailingBriefMatch
          ? _trailingMatchBrief
          : longOriginContent
          ? _longOriginBrief
          : 'Origin brief $index',
      'language': 'en',
      'owner': {
        'uid': 'owner_$index',
        'name': index == 1 ? 'Deleted User' : 'Owner $index',
        'avatar': '',
      },
      'latestVersion': {'versionNum': index},
      'cover': '',
      'tags': ['tag-$index'],
      'characters': [
        {'character_id': 'character_$index', 'name': 'Character $index'},
        {'character_id': 'supporting_$index', 'name': 'Supporting $index'},
        if (longOriginContent)
          for (
            var characterIndex = 3;
            characterIndex <= 12;
            characterIndex += 1
          )
            {
              'character_id': 'extra_${index}_$characterIndex',
              'name': 'Extra Character $characterIndex',
            },
      ],
      'stats': {
        'copy_cnt': index,
        'discuss_cnt': index + 10,
        'connect_cnt': index,
        'character_cnt': index,
        'location_cnt': index + 20,
        'max_tick_cnt': index + 30,
      },
      'matches': [
        if (includeIdMatches)
          {
            'field': 'origin_id',
            'highlight_ranges': [
              {'start': 0, 'length': 'origin_1'.length},
            ],
          },
        {
          'field': 'origin_name',
          'highlight_ranges': [
            {'start': 0, 'length': 6},
          ],
        },
        if (!originNameMatchOnly) ...[
          {
            'field': 'brief',
            'highlight_ranges': [
              if (trailingBriefMatch) ...[
                {
                  'start': _trailingMatchBrief.indexOf('rooftop'),
                  'length': 'rooftop'.length,
                },
              ] else ...[
                {'start': 0, 'length': 6},
                {'start': 7, 'length': 5},
              ],
              if (longOriginContent)
                {
                  'start': _longOriginBrief.indexOf('Latest Version visible'),
                  'length': 'Latest Version visible'.length,
                },
            ],
          },
          if (!longOriginContent)
            {
              'field': 'character_name',
              'character_id': 'character_$index',
              'highlight_ranges': [
                {'start': 0, 'length': 9},
              ],
            },
          if (!longOriginContent)
            {
              'field': 'character_name',
              'character_id': 'supporting_$index',
              'highlight_ranges': [
                {'start': 0, 'length': 10},
              ],
            },
          if (longOriginContent)
            {
              'field': 'character_name',
              'character_id': 'extra_${index}_12',
              'highlight_ranges': [
                {'start': 0, 'length': 'Extra Character 12'.length},
              ],
            },
        ],
        if (includeTagMatches)
          {
            'field': 'tag',
            'tag_index': 0,
            'highlight_ranges': [
              {'start': 0, 'length': 3},
            ],
          },
      ],
      'matches_truncated': false,
    },
    'world' => {
      'world_id': 'world_$index',
      'world_name': 'World $index',
      'origin_id': 'origin_$index',
      'language': 'en',
      'cover': '',
      'tags': ['world-tag-$index'],
      'owner': {'uid': 'owner_$index', 'name': 'Owner $index', 'avatar': ''},
      'stats': {
        'tick_cnt': index + 10,
        'sub_tick_no': index + 1,
        'connect_cnt': index + 20,
        'character_cnt': index + 30,
        'player_cnt': index + 40,
      },
      'created_at': 1777680000 + index,
      'matches': [
        if (includeIdMatches)
          {
            'field': 'world_id',
            'highlight_ranges': [
              {'start': 0, 'length': 'world_1'.length},
            ],
          },
        {
          'field': 'world_name',
          'highlight_ranges': [
            {'start': 0, 'length': 5},
          ],
        },
        if (includeTagMatches)
          {
            'field': 'tag',
            'tag_index': 0,
            'highlight_ranges': [
              {'start': 6, 'length': 3},
            ],
          },
      ],
    },
    _ => {
      'uid': 'user_$index',
      'name': 'User $index',
      'avatar': '',
      'matches': [
        if (includeIdMatches)
          {
            'field': 'uid',
            'highlight_ranges': [
              {'start': 0, 'length': 'user_1'.length},
            ],
          },
        {
          'field': 'user_name',
          'highlight_ranges': [
            {'start': 0, 'length': 4},
          ],
        },
      ],
    },
  };
}

List<String> _highlightedTextParts(Text text) {
  final result = <String>[];

  void collect(InlineSpan span) {
    if (span is! TextSpan) return;
    if (span.style?.color == GenesisColors.redSecondary && span.text != null) {
      expect(span.style?.backgroundColor, isNull);
      result.add(span.text!);
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      collect(child);
    }
  }

  final span = text.textSpan;
  if (span != null) collect(span);
  return result;
}

TransportResponse _jsonResponse(Map<String, dynamic> data) {
  return TransportResponse(
    statusCode: 200,
    headers: const {'content-type': 'application/json'},
    body: jsonEncode({'err_no': 0, 'err_msg': 'succ', 'data': data}),
  );
}

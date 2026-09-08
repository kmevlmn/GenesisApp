import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/pages/world/world_page_result.dart';
import 'package:genesis_flutter_android/routers/app_router.dart';

void main() {
  test('world route keeps its typed result', () {
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(
        name: RouteNames.world,
        arguments: <String, Object?>{'wid': 'w_test'},
      ),
    );

    expect(route, isA<MaterialPageRoute<WorldPageResult>>());
  });

  test('origin world route keeps its void material result', () {
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(
        name: RouteNames.originWorld,
        arguments: <String, Object?>{'oid': 'o_test'},
      ),
    );

    expect(route, isA<MaterialPageRoute<void>>());
  });

  test('debug Worldo sheet entry uses the local developer setting', () {
    expect(
      originWorldSheetShouldExpandOnEntry(
        globalConfigEnabled: true,
        debugSettingEnabled: false,
        isDebugBuild: true,
      ),
      isFalse,
    );
    expect(
      originWorldSheetShouldExpandOnEntry(
        globalConfigEnabled: false,
        debugSettingEnabled: true,
        isDebugBuild: true,
      ),
      isTrue,
    );
  });

  test('non-debug Worldo sheet entry keeps using global config', () {
    expect(
      originWorldSheetShouldExpandOnEntry(
        globalConfigEnabled: true,
        debugSettingEnabled: false,
        isDebugBuild: false,
      ),
      isTrue,
    );
    expect(
      originWorldSheetShouldExpandOnEntry(
        globalConfigEnabled: false,
        debugSettingEnabled: true,
        isDebugBuild: false,
      ),
      isFalse,
    );
  });

  testWidgets('page not found route shows text without retry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: RouteNames.pageNotFound,
        onGenerateRoute: AppRouter.onGenerateRoute,
        onGenerateInitialRoutes: (_) => [
          AppRouter.onGenerateRoute(
            const RouteSettings(name: RouteNames.pageNotFound),
          ),
        ],
      ),
    );

    expect(find.text('Page not found.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('page not found back button returns to previous page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed(RouteNames.pageNotFound),
              child: const Text('Open missing page'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open missing page'));
    await tester.pumpAndSettle();
    expect(find.text('Page not found.'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open missing page'), findsOneWidget);
  });

  testWidgets('page not found back button returns home without history', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: RouteNames.pageNotFound,
        onGenerateRoute: (settings) {
          if (settings.name == RouteNames.home) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('Home fallback')),
            );
          }
          return AppRouter.onGenerateRoute(settings);
        },
        onGenerateInitialRoutes: (_) => [
          AppRouter.onGenerateRoute(
            const RouteSettings(name: RouteNames.pageNotFound),
          ),
        ],
      ),
    );

    expect(find.text('Page not found.'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Page not found.'), findsNothing);
    expect(find.text('Home fallback'), findsOneWidget);
  });

  testWidgets('unknown route falls back to page not found', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/missing',
        onGenerateRoute: AppRouter.onGenerateRoute,
        onGenerateInitialRoutes: (_) => [
          AppRouter.onGenerateRoute(const RouteSettings(name: '/missing')),
        ],
      ),
    );

    expect(find.text('Page not found.'), findsOneWidget);
  });

  for (final name in [RouteNames.discuss, RouteNames.postDetail]) {
    testWidgets(
      '$name keeps outgoing Android transition dark under a light app theme',
      (tester) async {
        final route =
            AppRouter.onGenerateRoute(RouteSettings(name: name))
                as PageRoute<void>;
        final secondary = AnimationController(
          vsync: tester,
          duration: const Duration(seconds: 1),
        );
        addTearDown(secondary.dispose);
        secondary.forward();
        {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                platform: TargetPlatform.android,
                colorScheme: const ColorScheme.light(surface: Colors.white),
              ),
              home: Builder(
                builder: (context) {
                  const child = SizedBox.expand();
                  return route.delegatedTransition!(
                    context,
                    const AlwaysStoppedAnimation(1.0),
                    secondary,
                    false,
                    child,
                  )!;
                },
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is ColoredBox &&
                  widget.color == const Color(0xFF151517),
            ),
            findsOneWidget,
          );
        }
        secondary.stop();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('location chat route fades during iOS transitions', (
    WidgetTester tester,
  ) async {
    final route =
        AppRouter.onGenerateRoute(
              const RouteSettings(name: RouteNames.locationChat),
            )
            as PageRoute<dynamic>;

    expect(route.opaque, isFalse);
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) {
            return route.buildTransitions(
              context,
              const AlwaysStoppedAnimation<double>(0.5),
              const AlwaysStoppedAnimation<double>(0),
              const SizedBox.shrink(),
            );
          },
        ),
      ),
    );

    final fade = tester.widget<FadeTransition>(find.byType(FadeTransition));
    expect(fade.opacity.value, greaterThan(0));
    expect(fade.opacity.value, lessThan(1));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_dark_theme.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/components/common/list_loading_skeleton.dart';

void main() {
  testWidgets('dark world skeleton matches covers and stays static', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        scrollBehavior: GenesisScrollBehavior(),
        home: GenesisDarkTheme(
          child: Scaffold(
            body: GenesisListLoadingSkeleton.worldList(itemCount: 2),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final skeleton = find.byKey(
      const ValueKey<String>('genesis-world-list-skeleton'),
    );
    expect(
      tester.getSize(
        find
            .byKey(
              const ValueKey<String>('genesis-world-list-thumbnail-skeleton'),
            )
            .first,
      ),
      const Size(60, 90),
    );
    expect(
      find.descendant(of: skeleton, matching: find.byType(AnimatedBuilder)),
      findsNothing,
    );
    final bones = tester.widgetList<DecoratedBox>(
      find.descendant(of: skeleton, matching: find.byType(DecoratedBox)),
    );
    expect(bones, isNotEmpty);
    for (final bone in bones) {
      final decoration = bone.decoration as BoxDecoration;
      expect(decoration.color, GenesisColors.darkFaintFill);
      expect(decoration.gradient, isNull);
    }
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('renders list loading skeleton variants', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GenesisListLoadingSkeleton.worldList(itemCount: 2),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('genesis-world-list-skeleton')),
      findsOneWidget,
    );
    final worldThumbnail = find
        .byKey(const ValueKey<String>('genesis-world-list-thumbnail-skeleton'))
        .first;
    expect(tester.getSize(worldThumbnail), const Size(60, 60));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GenesisListLoadingSkeleton.originGrid(itemCount: 2),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('genesis-origin-grid-skeleton')),
      findsOneWidget,
    );
    final originGridPadding = tester.widget<SliverPadding>(
      find.byType(SliverPadding),
    );
    expect(originGridPadding.padding, const EdgeInsets.fromLTRB(2, 5, 2, 0));
    final firstItem = find
        .byKey(const ValueKey<String>('genesis-origin-grid-item-skeleton'))
        .first;
    final itemSize = tester.getSize(firstItem);
    expect(itemSize.width, greaterThan(100));
    expect(itemSize.height, closeTo(itemSize.width * 1.5 + 67, 0.01));
    expect(find.byType(GenesisOriginCardLoadingBone), findsNWidgets(2));
    final decoration =
        tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration
            as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, const [Color(0xFFE8EBF0), Color(0xFFF3F4F6)]);
    expect(
      find.descendant(of: firstItem, matching: find.byType(AnimatedBuilder)),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xFF111111),
      ),
      findsNothing,
    );
  });
}

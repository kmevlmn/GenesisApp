import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/common/genesis_action_box.dart';
import 'package:genesis_flutter_android/components/page_header.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';

void main() {
  testWidgets(
    'action box isolates dark styling and preserves action behavior',
    (tester) async {
      String? selected;
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: GenesisActionBox<String>(
              title: 'Join request',
              titleContent: const Text('Request details'),
              actions: const [
                GenesisActionBoxAction(label: 'Approve', value: 'approve'),
                GenesisActionBoxAction(label: 'Reject', value: 'reject'),
                GenesisActionBoxAction(
                  label: 'Unavailable',
                  value: 'disabled',
                  enabled: false,
                ),
              ],
              onActionSelected: (value) => selected = value,
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.light,
      );
      expect(
        Theme.of(tester.element(find.text('Join request'))).brightness,
        Brightness.dark,
      );
      expect(
        tester.widget<Text>(find.text('Join request')).style?.color,
        GenesisColors.darkTextPrimary,
      );
      expect(
        DefaultTextStyle.of(
          tester.element(find.text('Request details')),
        ).style.color,
        GenesisColors.darkTextSecondary,
      );
      expect(
        tester.widget<Text>(find.text('Approve')).style?.color,
        GenesisColors.redSecondary,
      );
      expect(
        tester.widget<Text>(find.text('Reject')).style?.color,
        GenesisColors.darkTextPrimary,
      );
      expect(
        tester.widget<Text>(find.text('Unavailable')).style?.color,
        GenesisColors.darkTextTertiary,
      );
      final panels = tester.widgetList<Material>(
        find.descendant(
          of: find.byType(GenesisActionBox<String>),
          matching: find.byType(Material),
        ),
      );
      expect(panels.any((panel) => panel.color == Colors.white), isFalse);
      expect(
        panels
            .where(
              (panel) => panel.color == GenesisColors.darkOverlayBackground,
            )
            .length,
        2,
      );
      await tester.tap(find.text('Unavailable'));
      expect(selected, isNull);
      await tester.tap(find.text('Approve'));
      expect(selected, 'approve');
      await tester.tap(find.text('Reject'));
      expect(selected, 'reject');
      await tester.tap(find.text('Cancel'));
      expect(cancelled, isTrue);
    },
  );

  testWidgets('standard header reserves trailing space without scaling title', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const title = 'A long standard page header title';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PageHeader(
            pageName: title,
            showSearchBar: false,
            trailing: SizedBox(width: 44, height: 44),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text(title));
    expect(tester.getTopLeft(find.text(title)).dx, 16);
    expect(text.style?.fontSize, 20);
    expect(text.style?.fontWeight, FontWeight.w600);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });
}

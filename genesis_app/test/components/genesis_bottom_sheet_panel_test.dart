import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/common/genesis_bottom_sheet_panel.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_radii.dart';
import 'package:genesis_flutter_android/ui/components/genesis_dark_close_button.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_dark_theme.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';

void main() {
  testWidgets(
    'dark panel close delegates taps and respects the disabled state',
    (tester) async {
      var closed = 0;
      for (final enabled in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: GenesisDarkTheme(
              child: Scaffold(
                body: GenesisBottomSheetPanel(
                  title: 'Dark sheet',
                  height: 300,
                  trailing: GenesisBottomSheetCloseButton(
                    onPressed: enabled ? () => closed++ : null,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
        expect(find.byType(GenesisDarkCloseButton), findsOneWidget);
        expect(
          tester.getSize(find.byType(GenesisDarkCloseButton)),
          const Size.square(28),
        );
        final close = tester.widget<IconButton>(find.byType(IconButton));
        expect(
          close.style!.foregroundColor!.resolve(
            enabled ? {} : {WidgetState.disabled},
          ),
          enabled
              ? GenesisColors.darkTextPrimary
              : GenesisColors.darkTextTertiary,
        );
        await tester.tap(find.byTooltip('Close'));
        await tester.pump();
        expect(closed, 1);
      }
    },
  );

  testWidgets('standard bottom sheet header uses shared spacing and type', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GenesisBottomSheetPanel(
            title: 'Sheet title',
            height: 300,
            trailing: GenesisBottomSheetCloseButton(
              buttonKey: ValueKey<String>('sheet-close'),
              onPressed: null,
            ),
            child: ColoredBox(
              key: ValueKey<String>('sheet-content'),
              color: Colors.white,
            ),
          ),
        ),
      ),
    );

    final panel = find.byType(GenesisBottomSheetPanel);
    final title = find.text('Sheet title');
    final content = find.byKey(const ValueKey<String>('sheet-content'));
    final titleWidget = tester.widget<Text>(title);
    final material = tester.widget<Material>(
      find.descendant(of: panel, matching: find.byType(Material)).first,
    );

    expect(material.borderRadius, GenesisBottomSheetPanel.borderRadius);
    expect(GenesisBottomSheetPanel.borderRadius, GenesisRadii.sheet);
    expect(GenesisRadii.sheetTopRadiusValue, 18);
    expect(titleWidget.style?.fontSize, 18);
    expect(titleWidget.style?.height, 24 / 18);
    expect(titleWidget.style?.fontWeight, FontWeight.w600);
    expect(titleWidget.style?.color, const Color(0xFF111111));
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('sheet-close'))),
      const Size.square(24),
    );
    expect(tester.getTopLeft(title).dx - tester.getTopLeft(panel).dx, 16);
    expect(tester.getTopLeft(title).dy - tester.getTopLeft(panel).dy, 20);
    expect(tester.getTopLeft(content).dy - tester.getBottomLeft(title).dy, 20);
  });
}

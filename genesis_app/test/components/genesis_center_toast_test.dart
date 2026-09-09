import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/common/genesis_center_toast.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_dark_theme.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_typography.dart';

void main() {
  testWidgets('shows centered translucent toast on light pages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => showGenesisToast(context, 'Network failed'),
              child: const Text('Show'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    final toastText = find.text('Network failed');
    expect(toastText, findsOneWidget);

    final text = tester.widget<Text>(toastText);
    expect(text.style?.inherit, isFalse);
    expect(text.style?.fontFamily, GenesisTypography.fontFamily);
    expect(
      text.style?.fontFamilyFallback,
      GenesisTypography.fontFamilyFallback,
    );
    expect(text.style?.fontSize, 14);
    expect(text.style?.fontWeight, FontWeight.w500);
    expect(text.style?.color, Colors.white);
    expect(text.style?.decoration, TextDecoration.none);

    final decoratedBox = tester.widget<DecoratedBox>(
      find.ancestor(of: toastText, matching: find.byType(DecoratedBox)).first,
    );
    final decoration = decoratedBox.decoration as BoxDecoration;
    expect(decoration.color, Colors.black.withValues(alpha: 0.72));
    expect(decoration.borderRadius, BorderRadius.circular(8));

    final screenCenter = tester.getCenter(find.byType(MaterialApp));
    final toastCenter = tester.getCenter(toastText);
    expect((toastCenter.dx - screenCenter.dx).abs(), lessThan(1));
    expect((toastCenter.dy - screenCenter.dy).abs(), lessThan(1));

    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump();

    expect(toastText, findsNothing);
  });

  testWidgets('dark page toast keeps its colors in the light root overlay', (
    tester,
  ) async {
    for (final explicitBrightness in [false, true]) {
      final trigger = Builder(
        builder: (context) => TextButton(
          onPressed: () => showGenesisToast(
            context,
            'Copied',
            brightness: explicitBrightness ? Brightness.dark : null,
          ),
          child: const Text('Show'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: explicitBrightness ? trigger : GenesisDarkTheme(child: trigger),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pump();

      final toast = find.text('Copied');
      expect(
        tester.widget<Text>(toast).style?.color,
        GenesisColors.darkTextPrimary,
      );
      final box = tester.widget<DecoratedBox>(
        find.ancestor(of: toast, matching: find.byType(DecoratedBox)).first,
      );
      expect(
        (box.decoration as BoxDecoration).color,
        GenesisColors.darkFaintSurface,
      );
      expect(
        (box.decoration as BoxDecoration).border,
        Border.all(color: GenesisColors.darkFaintFill),
      );
      final padding = tester.widget<Padding>(
        find.ancestor(of: toast, matching: find.byType(Padding)).first,
      );
      expect(
        padding.padding,
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(toast, findsNothing);
    }
  });
}

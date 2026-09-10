import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_dark_theme.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_ui_theme.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';

void main() {
  test(
    'dark defaults cover Material surfaces, inputs and disabled actions',
    () {
      final theme = GenesisTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.canvasColor, GenesisColors.darkBackground);
      expect(theme.scaffoldBackgroundColor, GenesisColors.darkBackground);
      expect(
        theme.dialogTheme.backgroundColor,
        GenesisColors.darkRaisedBackground,
      );
      expect(
        theme.bottomSheetTheme.modalBackgroundColor,
        GenesisColors.darkRaisedBackground,
      );
      expect(theme.textTheme.bodyMedium?.color, GenesisColors.darkTextPrimary);
      expect(theme.textTheme.bodySmall?.color, GenesisColors.darkTextTertiary);
      expect(
        theme.inputDecorationTheme.hintStyle?.color,
        GenesisColors.darkInputPlaceholder,
      );
      expect(
        theme.textSelectionTheme.cursorColor,
        GenesisColors.darkTextPrimary,
      );
      expect(
        theme.progressIndicatorTheme.color,
        GenesisColors.darkTextSecondary,
      );
      final button = theme.filledButtonTheme.style!;
      expect(
        button.backgroundColor!.resolve({WidgetState.disabled}),
        GenesisColors.darkButtonDisabledBackground,
      );
      expect(
        button.foregroundColor!.resolve({WidgetState.disabled}),
        GenesisColors.darkButtonDisabledForeground,
      );
      final ui = theme.extension<GenesisUiTheme>()!;
      expect(ui.tabUnselectedColor, GenesisColors.darkTextSecondary);
      expect(ui.searchBackgroundColor, GenesisColors.darkFaintFill);
    },
  );

  testWidgets('unconfigured page, field and dialog inherit dark defaults', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GenesisTheme.dark(),
        home: Scaffold(
          body: Column(
            children: [
              const TextField(decoration: InputDecoration(hintText: 'Hint')),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(title: Text('Dialog')),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final input = tester.widget<EditableText>(find.byType(EditableText));
    expect(input.cursorColor, GenesisColors.darkTextPrimary);
    expect(input.style.color, GenesisColors.darkTextPrimary);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final dialogMaterial = tester.widget<Material>(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );
    expect(dialogMaterial.color, GenesisColors.darkRaisedBackground);
  });

  testWidgets('light exclusions stay light and nested dark dialogs stay dark', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GenesisTheme.dark(),
        home: const GenesisLightTheme(
          child: Scaffold(
            body: Column(
              children: [
                Text('Developer'),
                GenesisDarkTheme(child: Text('Dark dialog')),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      Theme.of(tester.element(find.text('Developer'))).brightness,
      Brightness.light,
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('Developer'))).style.color,
      GenesisColors.textPrimary,
    );
    expect(
      Theme.of(tester.element(find.text('Dark dialog'))).brightness,
      Brightness.dark,
    );
    expect(
      Theme.of(tester.element(find.text('Dark dialog'))).colorScheme.surface,
      GenesisColors.darkBackground,
    );
  });

  test('local dark scopes retain typography and are idempotent', () {
    final base = GenesisTheme.light().copyWith(
      textTheme: GenesisTheme.light().textTheme.apply(fontFamily: 'CustomFont'),
    );
    final dark = GenesisTheme.asDark(base);
    expect(dark.textTheme.bodyMedium?.fontFamily, 'CustomFont');
    final nested = GenesisTheme.asDark(dark);
    expect(nested.textTheme, dark.textTheme);
    expect(nested.colorScheme, dark.colorScheme);
    expect(nested.scaffoldBackgroundColor, dark.scaffoldBackgroundColor);
    expect(nested.inputDecorationTheme, dark.inputDecorationTheme);
  });
}

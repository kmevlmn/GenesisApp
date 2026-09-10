import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/page_header.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';

void main() {
  for (final centered in [false, true]) {
    testWidgets('header defaults dark under light theme centered=$centered', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: GenesisBackAppBar(pageName: 'Title', centerTitle: centered),
          ),
        ),
      );
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.backgroundColor, GenesisColors.darkBackground);
      expect(bar.systemOverlayStyle, SystemUiOverlayStyle.light);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.arrow_back_ios_new)).color,
        GenesisColors.darkTextPrimary,
      );
      expect(
        tester.widget<Text>(find.text('Title')).style?.color,
        GenesisColors.darkTextPrimary,
      );
    });
  }
  testWidgets('header preserves explicit light overrides', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: GenesisBackAppBar(
            pageName: 'Title',
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            systemOverlayStyle: SystemUiOverlayStyle.dark,
          ),
        ),
      ),
    );
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
      Colors.white,
    );
    expect(tester.widget<Text>(find.text('Title')).style?.color, Colors.black);
  });
}

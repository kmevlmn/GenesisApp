import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/pages/common/page_not_found_page.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';

void main() {
  testWidgets(
    'not found uses dark header and light back arrow in a light host',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PageNotFoundPage()));
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        GenesisColors.darkBackground,
      );
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
        GenesisColors.darkBackground,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.arrow_back_ios_new)).color,
        GenesisColors.darkTextPrimary,
      );
    },
  );
}

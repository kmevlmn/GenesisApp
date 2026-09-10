import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/gems/profile_membership_card.dart';
import 'package:genesis_flutter_android/ui/components/genesis_primary_button.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_typography.dart';

void main() {
  testWidgets('membership and shared buttons inherit the active theme font', (
    tester,
  ) async {
    const themeFont = 'ThemeAuditFont';
    TextStyle? painterStyle;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: themeFont),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              painterStyle = GenesisTypography.resolve(
                context,
                const TextStyle(fontSize: 13),
              );
              return Column(
                children: [
                  const ProfileMembershipCard(),
                  GenesisPrimaryButton(label: 'Save', onPressed: () {}),
                ],
              );
            },
          ),
        ),
      ),
    );

    for (final label in [
      'Pro',
      'Subscribe',
      'Monthly Blue Gems included',
      'Save',
    ]) {
      final richText = tester.widget<RichText>(
        find.descendant(of: find.text(label), matching: find.byType(RichText)),
      );
      expect(richText.text.style?.fontFamily, themeFont, reason: label);
    }
    expect(painterStyle?.fontFamily, themeFont);
    expect(painterStyle?.fontSize, 13);
    expect(tester.takeException(), isNull);
  });
}

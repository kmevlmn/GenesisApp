import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_typography.dart';

/// Checks resolved spans, including inherited styles and rich-text children.
void expectInterText(WidgetTester tester, Finder scope) {
  final richTexts = find.descendant(
    of: scope,
    matching: find.byType(RichText),
    matchRoot: true,
  );
  expect(richTexts, findsWidgets);
  for (final text in tester.widgetList<RichText>(richTexts)) {
    _checkSpan(text.text, const TextStyle());
  }
}

void _checkSpan(InlineSpan span, TextStyle parent) {
  final style = parent.merge(span.style);
  if (span is! TextSpan) return;
  if (span.text?.isNotEmpty ?? false) {
    // Icon widgets also render spans; their glyph fonts must remain intact.
    if (!const {
      'MaterialIcons',
      'CupertinoIcons',
      'packages/cupertino_icons/CupertinoIcons',
      'MyFlutterApp',
    }.contains(style.fontFamily)) {
      expect(
        style.fontFamily,
        GenesisTypography.fontFamily,
        reason: 'Wrong font for ${span.text}',
      );
      expect(
        style.fontFamilyFallback,
        GenesisTypography.fontFamilyFallback,
        reason: 'Missing fallback for ${span.text}',
      );
    }
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    _checkSpan(child, style);
  }
}

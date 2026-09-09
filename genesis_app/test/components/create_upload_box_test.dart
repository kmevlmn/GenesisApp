import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/pages/create/create_form_widgets.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/ui/components/genesis_delete_button.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_typography.dart';

void main() {
  testWidgets('CreateUploadBox uses neutral border and red upload icon', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateUploadBox(
            controller: controller,
            label: 'UPLOAD',
            onChanged: () {},
          ),
        ),
      ),
    );

    final uploadIcon = tester.widget<Icon>(
      find.byIcon(Icons.add_photo_alternate_outlined),
    );
    expect(uploadIcon.color, GenesisColors.createAdd);

    final dashedPaint = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<CreateDashedRRectPainter>()
        .single;
    expect(dashedPaint.color, const Color(0xFFE1E1E6));
  });

  testWidgets(
    'CreateUploadBox shows preview after external controller update',
    (WidgetTester tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreateUploadBox(
              controller: controller,
              label: 'AVATAR\n(Optional)',
              onChanged: () {},
            ),
          ),
        ),
      );

      expect(find.text('AVATAR\n(Optional)'), findsOneWidget);

      controller.text = 'assets/images/default_list_image.png';
      await tester.pump();

      expect(find.text('AVATAR\n(Optional)'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      expect(find.byType(GenesisDeleteButton), findsOneWidget);

      controller.text = 'assets/images/default_list_image.png';
      await tester.pump();

      expect(find.text('AVATAR\n(Optional)'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      expect(find.byType(GenesisDeleteButton), findsOneWidget);

      controller.clear();
      await tester.pump();

      expect(find.text('AVATAR\n(Optional)'), findsOneWidget);
      expect(find.byType(GenesisDeleteButton), findsNothing);
    },
  );

  testWidgets('CreateUploadBox delete button clears avatar', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController(
      text: 'assets/images/default_list_image.png',
    );
    var changedCount = 0;
    Uint8List? previewBytes = Uint8List.fromList(<int>[1, 2, 3]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateUploadBox(
            controller: controller,
            label: 'AVATAR\n(Optional)',
            onPreviewBytesChanged: (bytes) => previewBytes = bytes,
            onChanged: () => changedCount += 1,
          ),
        ),
      ),
    );

    expect(find.text('AVATAR\n(Optional)'), findsNothing);
    expect(find.text('Remove'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    final removeButton = tester.widget<GenesisDeleteButton>(
      find.byType(GenesisDeleteButton),
    );
    expect(removeButton.enabled, isTrue);
    final uploadRect = tester.getRect(find.byType(CreateUploadBox));
    final deleteRect = tester.getRect(
      find.byKey(const ValueKey('create-upload-remove')),
    );
    expect(deleteRect.top, closeTo(uploadRect.top + 4, 0.01));
    expect(deleteRect.right, closeTo(uploadRect.right - 4, 0.01));

    await tester.tap(find.byKey(const ValueKey('create-upload-remove')));
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(previewBytes, isNull);
    expect(changedCount, 1);
    expect(find.byType(GenesisDeleteButton), findsNothing);
    expect(find.text('AVATAR\n(Optional)'), findsOneWidget);
  });

  testWidgets('CreateFormNote uses Inter markdown emphasis on iOS', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: const Scaffold(
          body: CreateFormNote(note: 'Use *gentle* emphasis', markdown: true),
        ),
      ),
    );

    final richText = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((text) => text.text.toPlainText().contains('gentle'));
    final style = _textFragmentStyle(richText.text, 'gentle');
    var hasWidgetSpan = false;
    richText.text.visitChildren((child) {
      hasWidgetSpan = hasWidgetSpan || child is WidgetSpan;
      return !hasWidgetSpan;
    });

    expect(style?.fontStyle, FontStyle.italic);
    expect(richText.text.style?.fontFamily, GenesisTypography.fontFamily);
    expect(hasWidgetSpan, isFalse);
  });

  testWidgets(
    'CreateTextFieldBlock uses Inter without rewriting decorative unicode',
    (WidgetTester tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      const raw = '☛ ˙۵ও⃢♥︎ ━  𝙏ᶦⁿᶦᵗᵃ 🍓|🎀〬𓈒ֹ⁠꙳';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreateTextFieldBlock(
              label: 'Name',
              controller: controller,
              hintText: 'Worldo Name',
              onChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), raw);
      await tester.pump();

      expect(controller.text, raw);
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.style?.fontFamily, GenesisTypography.fontFamily);
      expect(
        input.style?.fontFamilyFallback,
        GenesisTypography.fontFamilyFallback,
      );
      expect(
        input.decoration?.hintStyle?.fontFamilyFallback,
        GenesisTypography.fontFamilyFallback,
      );

      controller.text = raw;
      await tester.pump();

      expect(controller.text, raw);
    },
  );

  testWidgets('CreateTextFieldBlock cursor matches its input text', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateTextFieldBlock(
            label: 'Name',
            controller: controller,
            hintText: 'Worldo Name',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.cursorColor, input.style?.color);
    expect(input.cursorColor, createFormText);
  });

  testWidgets('CreateTextFieldBlock advances focus on done', (
    WidgetTester tester,
  ) async {
    final firstController = TextEditingController();
    final secondController = TextEditingController();
    final firstFocusNode = FocusNode();
    final secondFocusNode = FocusNode();
    addTearDown(firstController.dispose);
    addTearDown(secondController.dispose);
    addTearDown(firstFocusNode.dispose);
    addTearDown(secondFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CreateTextFieldBlock(
                label: 'First',
                controller: firstController,
                hintText: 'First',
                focusNode: firstFocusNode,
                nextFocusNode: secondFocusNode,
                onChanged: (_) {},
              ),
              CreateTextFieldBlock(
                label: 'Second',
                controller: secondController,
                hintText: 'Second',
                focusNode: secondFocusNode,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(TextField, 'First'));
    await tester.pump();
    expect(firstFocusNode.hasFocus, isTrue);

    final firstInput = tester.widget<TextField>(find.byType(TextField).first);
    expect(firstInput.textInputAction, TextInputAction.done);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(firstFocusNode.hasFocus, isFalse);
    expect(secondFocusNode.hasFocus, isTrue);
  });

  testWidgets('CreateTextFieldBlock uses newline action for multiline fields', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateTextFieldBlock(
            label: 'Brief',
            controller: controller,
            hintText: 'Brief',
            minLines: 4,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.textInputAction, TextInputAction.newline);
    expect(input.keyboardType, TextInputType.multiline);
    expect(input.onEditingComplete, isNull);

    await tester.enterText(find.byType(TextField), 'a\n\n\n\nb');
    await tester.pump();

    expect(controller.text, 'a\n\nb');

    controller.text = 'c\n\n\nd';
    await tester.pump();

    expect(controller.text, 'c\n\nd');
  });
}

TextStyle? _textFragmentStyle(InlineSpan span, String value) {
  TextStyle? style;
  span.visitChildren((child) {
    if (child is TextSpan && child.text == value) {
      style = child.style;
      return false;
    }
    return true;
  });
  return style;
}

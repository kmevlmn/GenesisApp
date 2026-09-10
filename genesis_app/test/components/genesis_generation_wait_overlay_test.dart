import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/pages/origin_editor/origin_generation_wait_content.dart';
import 'package:genesis_flutter_android/components/common/genesis_generation_wait_overlay.dart';

void main() {
  testWidgets(
    'creating and publishing share dark static content with preview',
    (tester) async {
      for (final publishing in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: OriginGenerationWaitOverlay(publishing: publishing),
          ),
        );
        final overlay = tester.widget<GenesisGenerationWaitOverlay>(
          find.byType(GenesisGenerationWaitOverlay),
        );
        expect(overlay.brightness, Brightness.dark);
        expect(
          overlay.title,
          publishing ? 'Publishing your Worldo' : 'Creating your Worldo',
        );
        expect(find.text(overlay.message), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        expect(find.byType(Scrollable), findsNothing);
        await tester.pump(const Duration(seconds: 3));
        expect(find.text(overlay.message), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets('generation wait overlay supports the world dark style', (
    WidgetTester tester,
  ) async {
    const title = 'Progressing the World';
    const message = 'Advancing the world timeline';

    await tester.pumpWidget(
      const MaterialApp(
        home: GenesisGenerationWaitOverlay(
          title: title,
          message: message,
          animateTitleDots: false,
          brightness: Brightness.dark,
        ),
      ),
    );

    final dialog = tester.widget<AlertDialog>(
      find.byKey(const ValueKey('world-tick1-wait-dialog')),
    );
    expect(dialog.backgroundColor, Colors.transparent);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .any((box) => box.color == GenesisColors.darkOverlayBackground),
      isTrue,
    );
    expect(dialog.surfaceTintColor, Colors.transparent);
    expect(
      tester.widget<Text>(find.text(title)).style?.color,
      const Color(0xF2FFFFFF),
    );
    expect(
      tester.widget<Text>(find.text(message)).style?.color,
      const Color(0xB8FFFFFF),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

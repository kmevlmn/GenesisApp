import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/bootstrap/app_services_scope.dart';
import 'package:genesis_flutter_android/app/bootstrap/service_registry.dart';
import 'package:genesis_flutter_android/app/config/app_config.dart';
import 'package:genesis_flutter_android/components/common/genesis_action_box.dart';
import 'package:genesis_flutter_android/components/common/genesis_report_actions.dart';

import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';

void main() {
  testWidgets('report button menu appears to the left with icon', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_testApp(const _ReportMenuHost()));

    await tester.tap(find.byKey(const ValueKey<String>('report-menu-button')));
    await tester.pump();

    expect(find.text('Report'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    final reportText = tester.widget<Text>(find.text('Report'));
    expect(reportText.style?.fontSize, 12);
    expect(reportText.style?.color, Colors.white);
    final reportIcon = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      reportIcon.colorFilter,
      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
    );
    final darkBody = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .any((box) {
          final decoration = box.decoration;
          return decoration is BoxDecoration &&
              decoration.color == const Color(0xFF666666);
        });
    expect(darkBody, isTrue);
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey<String>('report-menu-button')),
    );
    final menuRect = tester.getRect(find.text('Report'));
    expect(menuRect.right, lessThanOrEqualTo(buttonRect.left));
    expect(menuRect.center.dy, closeTo(buttonRect.center.dy, 1));
    expect(
      tester.getCenter(find.text('Block')).dy,
      greaterThan(tester.getCenter(find.text('Report')).dy),
    );
  });

  testWidgets('report button menu disappears when host page is removed', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(const _ReportMenuHost()));

    await tester.tap(find.byKey(const ValueKey<String>('report-menu-button')));
    await tester.pump();
    expect(find.text('Report'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('replace-page')));
    await tester.pumpAndSettle();

    expect(find.text('Report'), findsNothing);
  });

  testWidgets('opening another report menu replaces the current one', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(const _ReportMenuHost()));

    await tester.tap(find.byKey(const ValueKey<String>('report-menu-button')));
    await tester.pump();
    expect(find.text('Report'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('second-report-menu-button')),
    );
    await tester.pump();

    expect(find.text('Report'), findsOneWidget);
    final secondButtonRect = tester.getRect(
      find.byKey(const ValueKey<String>('second-report-menu-button')),
    );
    final menuRect = tester.getRect(find.text('Report'));
    expect(menuRect.right, lessThanOrEqualTo(secondButtonRect.left));
  });

  testWidgets('outside tap closes report menu and triggers the tapped action', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(const _ReportMenuHost()));

    await tester.tap(find.byKey(const ValueKey<String>('report-menu-button')));
    await tester.pump();
    expect(find.text('Report'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('outside-action')));
    await tester.pump();

    expect(find.text('Report'), findsNothing);
    expect(find.text('Outside taps: 1'), findsOneWidget);
  });

  testWidgets('dragging the page closes the report menu', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_testApp(const _ReportMenuHost()));

    await tester.tap(find.byKey(const ValueKey<String>('report-menu-button')));
    await tester.pump();
    expect(find.text('Report'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey<String>('report-menu-scroll-view')),
      const Offset(0, -80),
    );
    await tester.pump();

    expect(find.text('Report'), findsNothing);
  });

  testWidgets('message action menu uses horizontal dark icon layout', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(const _MessageActionMenuHost()));

    await tester.tap(find.byKey(const ValueKey<String>('open-message-menu')));
    await tester.pump();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Copy')).dy,
      tester.getTopLeft(find.text('Report')).dy,
    );
    final copyText = tester.widget<Text>(find.text('Copy'));
    final reportText = tester.widget<Text>(find.text('Report'));
    expect(copyText.style?.fontSize, 12);
    expect(reportText.style?.fontSize, 12);
    expect(copyText.style?.color, Colors.white);
    expect(reportText.style?.color, Colors.white);
    expect(copyText.overflow, isNull);
    expect(reportText.overflow, isNull);
    expect(tester.getSize(find.text('Copy')).width, greaterThan(20));
    expect(tester.getSize(find.text('Report')).width, greaterThan(34));
    final darkBody = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .any((box) {
          final decoration = box.decoration;
          return decoration is BoxDecoration &&
              decoration.color == const Color(0xFF666666);
        });
    expect(darkBody, isTrue);
  });

  testWidgets('message action menu keeps labels visible when text is scaled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const _MessageActionMenuHost(),
        textScaler: const TextScaler.linear(1.8),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('open-message-menu')));
    await tester.pump();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(tester.getSize(find.text('Copy')).width, greaterThan(35));
    expect(tester.getSize(find.text('Report')).width, greaterThan(60));
  });

  testWidgets('message action menu expands down only in the top 20 percent', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _testApp(
        const _PositionedMessageActionMenuHost(
          alignment: Alignment.topCenter,
          padding: EdgeInsets.only(top: 40),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('open-message-menu')));
    await tester.pump();

    final buttonRect = tester.getRect(
      find.byKey(const ValueKey<String>('open-message-menu')),
    );
    final menuRect = tester.getRect(find.text('Copy'));
    expect(menuRect.top, greaterThan(buttonRect.bottom));
  });

  testWidgets('message action menu expands up below the top 20 percent', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_testApp(const _PositionedMessageActionMenuHost()));

    await tester.tap(find.byKey(const ValueKey<String>('open-message-menu')));
    await tester.pump();

    final buttonRect = tester.getRect(
      find.byKey(const ValueKey<String>('open-message-menu')),
    );
    final menuRect = tester.getRect(find.text('Copy'));
    expect(menuRect.bottom, lessThan(buttonRect.top));
  });

  testWidgets('report submit surface uses action box with three-line input', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(const _ReportDialogHost()));

    await tester.tap(find.text('Open report'));
    await tester.pumpAndSettle();

    expect(find.byType(GenesisActionBox<bool>), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Submit'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Cancel'), findsOneWidget);

    final input = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('genesis-report-content-input')),
    );
    expect(input.style?.color, GenesisColors.darkTextPrimary);
    expect(input.cursorColor, GenesisColors.darkTextPrimary);
    expect(input.decoration?.filled, isTrue);
    expect(input.decoration?.fillColor, GenesisColors.darkFaintFill);
    expect(input.decoration?.focusedBorder?.borderSide, BorderSide.none);
    expect(
      input.decoration?.hintStyle?.color,
      GenesisColors.darkInputPlaceholder,
    );
    expect(input.minLines, 3);
    expect(input.maxLines, 3);
    expect(input.autofocus, isTrue);
    expect(input.focusNode?.hasFocus, isTrue);
    expect(input.decoration?.focusedBorder, input.decoration?.enabledBorder);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('genesis-action-box-title-row')),
        matching: find.byKey(
          const ValueKey<String>('genesis-report-content-input'),
        ),
      ),
      findsOneWidget,
    );
    final titleRect = tester.getRect(find.text('Report'));
    final titleRowRect = tester.getRect(
      find.byKey(const ValueKey('genesis-action-box-title-row')),
    );
    final inputRect = tester.getRect(
      find.byKey(const ValueKey<String>('genesis-report-content-input')),
    );
    // The fixed-height title row centers this group (14px in the existing
    // layout); its separate title-to-input spacing remains 16px.
    expect(titleRect.top - titleRowRect.top, closeTo(14, 1));
    expect(inputRect.top - titleRect.bottom, closeTo(16, 1));
  });
}

Widget _testApp(Widget home, {TextScaler textScaler = TextScaler.noScaling}) {
  return AppServicesScope(
    services: ServiceRegistry.build(config: const AppConfig(useMock: true)),
    child: MaterialApp(
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: home,
    ),
  );
}

class _ReportMenuHost extends StatefulWidget {
  const _ReportMenuHost();

  @override
  State<_ReportMenuHost> createState() => _ReportMenuHostState();
}

class _ReportMenuHostState extends State<_ReportMenuHost> {
  bool _replaced = false;
  int _outsideTaps = 0;

  @override
  Widget build(BuildContext context) {
    if (_replaced) {
      return const Scaffold(body: Center(child: Text('Replacement page')));
    }
    return Scaffold(
      appBar: AppBar(
        actions: [
          GenesisMoreActionMenuButton(
            key: const ValueKey<String>('report-menu-button'),
            items: [
              genesisReportMenuItem(
                context: context,
                targetType: 'origin',
                targetId: 'o_test',
              ),
              const GenesisActionMenuItem(label: 'Block', onSelected: _noop),
            ],
          ),
          GenesisMoreActionMenuButton(
            key: const ValueKey<String>('second-report-menu-button'),
            items: [
              genesisReportMenuItem(
                context: context,
                targetType: 'origin',
                targetId: 'o_second',
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey<String>('report-menu-scroll-view'),
        children: [
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              key: const ValueKey<String>('replace-page'),
              onPressed: () => setState(() => _replaced = true),
              child: const Text('Replace page'),
            ),
          ),
          Center(
            child: TextButton(
              key: const ValueKey<String>('outside-action'),
              onPressed: () => setState(() => _outsideTaps += 1),
              child: Text('Outside taps: $_outsideTaps'),
            ),
          ),
          const SizedBox(height: 900),
        ],
      ),
    );
  }
}

class _ReportDialogHost extends StatelessWidget {
  const _ReportDialogHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () {
            showGenesisReportDialog(
              context: context,
              targetType: 'origin',
              targetId: 'o_test',
            );
          },
          child: const Text('Open report'),
        ),
      ),
    );
  }
}

class _MessageActionMenuHost extends StatelessWidget {
  const _MessageActionMenuHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (buttonContext) {
            return TextButton(
              key: const ValueKey<String>('open-message-menu'),
              onPressed: () {
                final box = buttonContext.findRenderObject();
                if (box is! RenderBox) return;
                showGenesisActionMenuAt(
                  context: buttonContext,
                  globalPosition: box.localToGlobal(
                    Offset(box.size.width / 2, box.size.height / 2),
                  ),
                  appearance: GenesisActionMenuAppearance.message,
                  items: const [
                    GenesisActionMenuItem(
                      label: 'Copy',
                      iconData: Icons.copy_outlined,
                      onSelected: _noop,
                    ),
                    GenesisActionMenuItem(
                      label: 'Report',
                      iconAsset: genesisReportIconAsset,
                      onSelected: _noop,
                    ),
                  ],
                );
              },
              child: const Text('Open message menu'),
            );
          },
        ),
      ),
    );
  }
}

class _PositionedMessageActionMenuHost extends StatelessWidget {
  const _PositionedMessageActionMenuHost({
    this.alignment = Alignment.center,
    this.padding = EdgeInsets.zero,
  });

  final Alignment alignment;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Align(
        alignment: alignment,
        child: Padding(
          padding: padding,
          child: const _MessageActionMenuButton(),
        ),
      ),
    );
  }
}

class _MessageActionMenuButton extends StatelessWidget {
  const _MessageActionMenuButton();

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) {
        return TextButton(
          key: const ValueKey<String>('open-message-menu'),
          onPressed: () {
            final box = buttonContext.findRenderObject();
            if (box is! RenderBox) return;
            showGenesisActionMenuAt(
              context: buttonContext,
              globalPosition: box.localToGlobal(
                Offset(box.size.width / 2, box.size.height / 2),
              ),
              appearance: GenesisActionMenuAppearance.message,
              items: const [
                GenesisActionMenuItem(
                  label: 'Copy',
                  iconData: Icons.copy_outlined,
                  onSelected: _noop,
                ),
                GenesisActionMenuItem(
                  label: 'Report',
                  iconAsset: genesisReportIconAsset,
                  onSelected: _noop,
                ),
              ],
            );
          },
          child: const Text('Open message menu'),
        );
      },
    );
  }
}

void _noop() {}

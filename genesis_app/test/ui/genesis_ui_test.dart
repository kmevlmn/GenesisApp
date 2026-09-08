import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/common/genesis_action_box.dart';
import 'package:genesis_flutter_android/components/page_header.dart';
import 'package:genesis_flutter_android/components/search_bar.dart';
import 'package:genesis_flutter_android/icons/custom_icon_assets.dart';
import 'package:genesis_flutter_android/ui/components/genesis_unread_badge.dart';
import 'package:genesis_flutter_android/ui/genesis_ui.dart';

void main() {
  testWidgets('GenesisTheme provides shared app styles', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GenesisTheme.light(),
        home: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            return Text('body', style: theme.textTheme.bodyMedium);
          },
        ),
      ),
    );

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme?.scaffoldBackgroundColor, GenesisColors.surface);
    expect(
      materialApp.theme?.textTheme.bodyMedium?.fontSize,
      GenesisTypography.body.fontSize,
    );
    expect(
      materialApp.theme?.textTheme.bodyMedium?.fontFamilyFallback,
      GenesisTypography.fontFamilyFallback,
    );
    expect(
      materialApp.theme?.textTheme.bodyMedium?.fontFamily,
      GenesisTypography.fontFamily,
    );
  });

  test('GenesisTheme uses the default text color and red selection handle', () {
    final theme = GenesisTheme.light();
    final selectionTheme = theme.textSelectionTheme;
    expect(selectionTheme.cursorColor, GenesisColors.textPrimary);
    expect(selectionTheme.selectionHandleColor, GenesisColors.create);
    expect(theme.colorScheme.primary, GenesisColors.brand);
    expect(GenesisColors.brandBright, GenesisColors.brand);
  });

  test('GenesisTheme disables Material state effects', () {
    final theme = GenesisTheme.light();
    const pressed = <WidgetState>{WidgetState.pressed};
    expect(theme.splashFactory, NoSplash.splashFactory);
    expect(theme.splashColor, Colors.transparent);
    expect(theme.highlightColor, Colors.transparent);
    expect(theme.hoverColor, Colors.transparent);
    expect(theme.focusColor, Colors.transparent);
    for (final style in <ButtonStyle?>[
      theme.filledButtonTheme.style,
      theme.textButtonTheme.style,
      theme.outlinedButtonTheme.style,
      theme.elevatedButtonTheme.style,
      theme.iconButtonTheme.style,
    ]) {
      expect(style?.splashFactory, NoSplash.splashFactory);
      expect(style?.overlayColor?.resolve(pressed), Colors.transparent);
    }
    expect(
      theme.checkboxTheme.overlayColor?.resolve(pressed),
      Colors.transparent,
    );
    expect(theme.radioTheme.overlayColor?.resolve(pressed), Colors.transparent);
    expect(
      theme.switchTheme.overlayColor?.resolve(pressed),
      Colors.transparent,
    );
    expect(theme.floatingActionButtonTheme.splashColor, Colors.transparent);
    expect(theme.tabBarTheme.splashFactory, NoSplash.splashFactory);
    expect(
      theme.tabBarTheme.overlayColor?.resolve(pressed),
      Colors.transparent,
    );
  });

  test('GenesisTypography applies the Worldo Inter font stack', () {
    expect(GenesisTypography.fontFamily, 'Inter');
    expect(GenesisTypography.fontFamilyFallback, const <String>[
      'PingFang SC',
      'Noto Sans CJK SC',
      'Noto Sans SC',
    ]);
    for (final style in <TextStyle>[
      GenesisTypography.pageTitle,
      GenesisTypography.body,
      GenesisTypography.bodyStrong,
      GenesisTypography.supporting,
      GenesisTypography.tabLabel,
    ]) {
      expect(style.fontFamily, GenesisTypography.fontFamily);
      expect(style.fontFamilyFallback, GenesisTypography.fontFamilyFallback);
    }
  });

  testWidgets('GenesisTextFallback keeps explicit Text styles unchanged', (
    tester,
  ) async {
    const styledText = '☛ ˙۵ও⃢♥︎ ━  𝙏ᶦⁿᶦᵗᵃ 🍓|🎀〬𓈒ֹ⁠꙳';

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: GenesisTextFallback(
          child: Text(
            styledText,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(find.byType(RichText));
    expect(richText.text.style?.fontFamily, isNull);
    expect(richText.text.style?.fontFamilyFallback, isNull);
  });

  testWidgets('Genesis UI components read styles from GenesisUiTheme', (
    tester,
  ) async {
    const searchColor = Color(0xFF123456);
    const titleColor = Color(0xFF654321);
    final uiTheme = GenesisUiTheme.light().copyWith(
      searchBackgroundColor: searchColor,
      pageTitleStyle: GenesisTypography.pageTitle.copyWith(color: titleColor),
      bottomNavigationProminentColor: Colors.orange,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: GenesisTheme.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[uiTheme],
        ),
        home: Scaffold(
          body: const Column(
            children: [
              GenesisPageTitle(text: 'Styled title'),
              GenesisSearchField(hintText: 'Styled search'),
            ],
          ),
          bottomNavigationBar: GenesisBottomNavigation(
            currentIndex: 0,
            onTap: (_) {},
            items: const [
              GenesisBottomNavigationItem(
                label: 'Create',
                icon: Icons.add_circle_outline,
                prominent: true,
              ),
            ],
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Styled title'));
    expect(title.style?.color, titleColor);

    final searchContainer = tester.widget<Container>(
      find.descendant(
        of: find.byType(GenesisSearchField),
        matching: find.byType(Container),
      ),
    );
    final searchDecoration = searchContainer.decoration as BoxDecoration;
    expect(searchDecoration.color, searchColor);

    final icon = tester.widget<Icon>(find.byIcon(Icons.add_circle_outline));
    expect(icon.color, Colors.orange);
  });

  testWidgets('GenesisSearchField keeps placeholder on one line', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(width: 180, child: GenesisSearchField())),
      ),
    );

    final placeholder = tester.widget<Text>(
      find.text('Worldo, Character, Tags'),
    );
    expect(placeholder.maxLines, 1);
    expect(placeholder.overflow, TextOverflow.ellipsis);
    expect(placeholder.softWrap, isFalse);
  });

  testWidgets(
    'GenesisSearchField uses decorative unicode visual fallback input',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      const raw = '☛ ˙۵ও⃢♥︎ ━  𝙏ᶦⁿᶦᵗᵃ 🍓|🎀〬𓈒ֹ⁠꙳';
      const rendered = '☛ ˙۵▤▤▤♥︎ ━  𝙏ᶦⁿᶦᵗᵃ 🍓|🎀°ₒ✩';

      await tester.pumpWidget(
        MaterialApp(
          theme: GenesisTheme.light(),
          home: Scaffold(
            body: GenesisSearchField(
              controller: controller,
              hintText: 'Search',
              textStyle: const TextStyle(
                color: Color(0xFF123456),
                fontSize: 16,
              ),
              hintStyle: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), raw);
      await tester.pump();

      expect(controller.text, rendered);
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.cursorColor, input.style?.color);
      expect(input.cursorColor, const Color(0xFF123456));
      expect(input.style?.fontFamily, GenesisTypography.fontFamily);
      expect(
        input.style?.fontFamilyFallback,
        GenesisTypography.fontFamilyFallback,
      );
      expect(
        input.decoration?.hintStyle?.fontFamilyFallback,
        GenesisTypography.fontFamilyFallback,
      );
    },
  );

  testWidgets('GenesisPageHeader composes title and search field', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenesisPageHeader(
            title: 'Worldo',
            onSearchTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Worldo'), findsOneWidget);
    expect(find.text('Worldo, Character, Tags'), findsOneWidget);

    await tester.tap(find.text('Worldo, Character, Tags'));
    expect(tapped, isTrue);
  });

  testWidgets('SearchBarPlaceholder remains compatible with UI kit field', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SearchBarPlaceholder())),
    );

    expect(
      tester.widget<SearchBarPlaceholder>(find.byType(SearchBarPlaceholder)),
      isA<GenesisSearchField>(),
    );
    final icon = tester.widget<Icon>(find.byIcon(CupertinoIcons.search));
    expect(icon.size, 16);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.search), findsNothing);
    expect(find.text('Worldo, Character, Tags'), findsOneWidget);
  });

  testWidgets('search and clear icons use symmetric horizontal insets', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Worldo');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: SearchBarPlaceholder(
                controller: controller,
                onClear: controller.clear,
              ),
            ),
          ),
        ),
      ),
    );

    final fieldRect = tester.getRect(find.byType(SearchBarPlaceholder));
    final searchIconRect = tester.getRect(find.byIcon(CupertinoIcons.search));
    final clearIconRect = tester.getRect(find.byIcon(Icons.close));
    final searchInset = searchIconRect.left - fieldRect.left;
    final clearInset = fieldRect.right - clearIconRect.right;

    expect(clearInset, searchInset);
  });

  testWidgets('PageHeader reuses SearchBarPlaceholder', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PageHeader(pageName: 'Worldo')),
      ),
    );

    expect(find.text('Worldo'), findsOneWidget);
    expect(find.byType(SearchBarPlaceholder), findsOneWidget);
  });

  testWidgets('PageHeader includes the top system view padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.only(top: 24),
          ),
          child: Scaffold(
            body: Column(
              children: [PageHeader(pageName: 'Origin', showSearchBar: false)],
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(PageHeader)).height, 74);
    expect(tester.getTopLeft(find.text('Origin')).dy, greaterThanOrEqualTo(24));
  });

  testWidgets('GenesisPrimaryButton uses the shared filled-button surface', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: GenesisTheme.light(),
        home: Scaffold(
          body: GenesisPrimaryButton(
            label: 'Continue',
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Continue'));
    expect(tapped, isTrue);

    final theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme;
    expect(
      theme?.filledButtonTheme.style?.backgroundColor?.resolve(
        const <WidgetState>{},
      ),
      GenesisColors.brand,
    );
  });

  testWidgets('GenesisPrimaryButton owns default disabled styling', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GenesisPrimaryButton(label: 'Continue', onPressed: null),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(button.onPressed, isNull);
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{
        WidgetState.disabled,
      }),
      GenesisColors.brandSoft,
    );
    expect(
      button.style?.foregroundColor?.resolve(<WidgetState>{
        WidgetState.disabled,
      }),
      Colors.white,
    );
  });

  testWidgets('GenesisPrimaryButton reports taps while disabled', (
    tester,
  ) async {
    var disabledTapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenesisPrimaryButton(
            label: 'Continue',
            onPressed: null,
            onDisabledPressed: () => disabledTapCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Continue'));

    expect(disabledTapCount, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('GenesisActionBox attaches cancel for a single action', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () async {
                  result = await showGenesisActionBox<bool>(
                    context: context,
                    title: 'Log out of your account?',
                    actions: const [
                      GenesisActionBoxAction<bool>(
                        label: 'Log out',
                        value: true,
                      ),
                    ],
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('genesis-action-box-attached-cancel')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('genesis-action-box-attached-cancel')),
      ),
      const Size(700, 186),
    );
    expect(find.text('Log out of your account?'), findsOneWidget);
    final dialogRect = tester.getRect(
      find.byKey(const ValueKey('genesis-action-box-attached-cancel')),
    );
    final title = tester.widget<Text>(find.text('Log out of your account?'));
    final action = tester.widget<Text>(find.text('Log out'));
    final cancel = tester.widget<Text>(find.text('Cancel'));
    expect(
      (tester.getCenter(find.text('Log out of your account?')).dy -
              dialogRect.top) /
          dialogRect.height,
      closeTo(0.22, 0.02),
    );
    expect(
      (tester.getCenter(find.text('Log out')).dy - dialogRect.top) /
          dialogRect.height,
      closeTo(0.58, 0.02),
    );
    expect(
      (tester.getCenter(find.text('Cancel')).dy - dialogRect.top) /
          dialogRect.height,
      closeTo(0.86, 0.02),
    );
    expect(title.style?.fontSize, 15);
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(action.style?.fontSize, 15);
    expect(action.style?.fontWeight, FontWeight.w600);
    expect(action.style?.color, const Color(0xFFFF2442));
    expect(cancel.style?.fontSize, 15);
    expect(cancel.style?.fontWeight, FontWeight.w400);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('GenesisActionBox uses 70 percent width on compact screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () {
                  showGenesisActionBox<bool>(
                    context: context,
                    title: 'Log out of your account?',
                    actions: const [
                      GenesisActionBoxAction<bool>(
                        label: 'Log out',
                        value: true,
                      ),
                    ],
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('genesis-action-box-attached-cancel')),
          )
          .width,
      224,
    );
  });

  testWidgets('GenesisActionBox can grow a dynamic title row', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                showGenesisActionBox<bool>(
                  context: context,
                  title: '',
                  titleWidget: const Text(
                    'Delete world\nwith a long name\nacross several lines',
                    textAlign: TextAlign.center,
                  ),
                  titleHeight: null,
                  actions: const [
                    GenesisActionBoxAction<bool>(label: 'Delete', value: true),
                  ],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const ValueKey('genesis-action-box-title-row')))
          .height,
      greaterThan(GenesisActionBox.defaultTitleHeight),
    );
  });

  testWidgets('GenesisActionBox can render one action without cancel', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () async {
                  result = await showGenesisActionBox<bool>(
                    context: context,
                    title: 'Purchase successful!',
                    actions: const [
                      GenesisActionBoxAction<bool>(label: 'OK', value: true),
                    ],
                    showCancel: false,
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsNothing);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('genesis-action-box-attached-cancel')),
      ),
      const Size(700, 134),
    );

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('GenesisActionBox detaches cancel for multiple actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () async {
                  result = await showGenesisActionBox<String>(
                    context: context,
                    title: 'Save the draft before leaving?',
                    actions: const [
                      GenesisActionBoxAction<String>(
                        label: 'Save',
                        value: 'save',
                      ),
                      GenesisActionBoxAction<String>(
                        label: 'Discard',
                        value: 'discard',
                      ),
                    ],
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('genesis-action-box-detached-cancel')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('genesis-action-box-detached-cancel')),
          )
          .width,
      800,
    );
    expect(find.text('Save the draft before leaving?'), findsOneWidget);
    final firstAction = tester.widget<Text>(find.text('Save'));
    final secondAction = tester.widget<Text>(find.text('Discard'));
    expect(firstAction.style?.fontSize, 15);
    expect(firstAction.style?.fontWeight, FontWeight.w600);
    expect(secondAction.style?.fontSize, 15);
    expect(secondAction.style?.fontWeight, FontWeight.w600);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, 'save');
  });

  testWidgets('GenesisActionBox renders optional content below title', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () async {
                  result = await showGenesisActionBox<String>(
                    context: context,
                    title: 'Join request',
                    content: const Text(
                      'Requester U_001',
                      key: ValueKey('action-box-custom-content'),
                    ),
                    actions: const [
                      GenesisActionBoxAction<String>(
                        label: 'Approve',
                        value: 'approve',
                      ),
                      GenesisActionBoxAction<String>(
                        label: 'Reject',
                        value: 'reject',
                      ),
                    ],
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('action-box-custom-content')),
      findsOneWidget,
    );

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(result, 'approve');
  });

  testWidgets('GenesisActionBox lets fixed areas use custom heights', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () {
                  showGenesisActionBox<bool>(
                    context: context,
                    title: 'Compact title',
                    titleHeight: 48,
                    actionRowHeight: 44,
                    cancelRowHeight: 46,
                    actions: const [
                      GenesisActionBoxAction<bool>(
                        label: 'Confirm',
                        value: true,
                      ),
                    ],
                  );
                },
                child: const Text('Open custom action box'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open custom action box'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(
        find.byKey(const ValueKey('genesis-action-box-attached-cancel')),
      ),
      const Size(700, 140),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('genesis-action-box-title-row')),
      ),
      const Size(700, 48),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('genesis-action-box-action-row')),
      ),
      const Size(700, 44),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('genesis-action-box-cancel-row')),
      ),
      const Size(700, 46),
    );
    expect(tester.getSize(find.text('Compact title')).height, lessThan(48));
    expect(tester.widget<Text>(find.text('Compact title')).style?.height, 1.4);
    expect(tester.getSize(find.text('Confirm')).height, lessThan(44));
  });

  testWidgets('GenesisPrimaryButton supports action-specific styling', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GenesisPrimaryButton(
            label: 'Log out',
            onPressed: null,
            backgroundColor: Color(0xFFE1E1E3),
            foregroundColor: Colors.black,
            disabledBackgroundColor: Color(0xFFE3E3E3),
            disabledForegroundColor: Color(0xFF6F6F6F),
          ),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Log out'),
    );
    expect(button.onPressed, isNull);
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{
        WidgetState.disabled,
      }),
      const Color(0xFFE3E3E3),
    );
    expect(
      button.style?.foregroundColor?.resolve(<WidgetState>{
        WidgetState.disabled,
      }),
      const Color(0xFF6F6F6F),
    );
    final shape =
        button.style?.shape?.resolve(<WidgetState>{}) as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(8));
    final textStyle = button.style?.textStyle?.resolve(<WidgetState>{});
    expect(textStyle?.fontSize, 16);
    expect(textStyle?.fontWeight, FontWeight.w600);
  });

  testWidgets('GenesisBottomNavigation delegates selection to onTap', (
    tester,
  ) async {
    var selectedIndex = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GenesisBottomNavigation(
            currentIndex: 0,
            onTap: (index) => selectedIndex = index,
            items: const [
              GenesisBottomNavigationItem(
                label: 'Home',
                icon: Icons.home_outlined,
              ),
              GenesisBottomNavigationItem(
                label: 'Create',
                icon: Icons.add_circle_outline,
                prominent: true,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Create'));
    expect(selectedIndex, 1);
  });

  testWidgets('GenesisBottomNavigation switches asset icon by selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GenesisBottomNavigation(
            currentIndex: 1,
            onTap: (_) {},
            items: const [
              GenesisBottomNavigationItem(
                label: 'Home',
                iconAsset: bottomNavHomeIconAsset,
                selectedIconAsset: bottomNavHomePressIconAsset,
              ),
              GenesisBottomNavigationItem(
                label: 'Inbox',
                iconAsset: bottomNavInboxIconAsset,
                selectedIconAsset: bottomNavInboxPressIconAsset,
                badgeCount: 4,
              ),
              GenesisBottomNavigationItem(
                label: 'Create',
                iconAsset: bottomNavCreateIconAsset,
                prominent: true,
              ),
            ],
          ),
        ),
      ),
    );

    final icons = tester
        .widgetList<SvgPicture>(find.byType(SvgPicture))
        .toList();
    expect(icons, hasLength(3));
    expect(icons[0].width, 24);
    expect(icons[0].height, 24);
    expect(
      (icons[0].bytesLoader as SvgAssetLoader).assetName,
      bottomNavHomeIconAsset,
    );
    expect(
      (icons[1].bytesLoader as SvgAssetLoader).assetName,
      bottomNavInboxPressIconAsset,
    );
    expect(icons[2].width, 22);
    expect(icons[2].height, 22);
    expect(
      (icons[2].bytesLoader as SvgAssetLoader).assetName,
      bottomNavCreateIconAsset,
    );

    final spacingBoxes = tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byType(GenesisBottomNavigation),
            matching: find.byType(SizedBox),
          ),
        )
        .where((box) => box.width == null)
        .map((box) => box.height)
        .toList();
    expect(spacingBoxes.where((height) => height == 2), hasLength(2));
    expect(spacingBoxes.where((height) => height == 1), hasLength(1));

    final navSizedBoxes = tester.widgetList<SizedBox>(
      find.descendant(
        of: find.byType(GenesisBottomNavigation),
        matching: find.byType(SizedBox),
      ),
    );
    expect(navSizedBoxes.any((box) => box.height == 49), isTrue);

    final decoration = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(GenesisBottomNavigation),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .singleWhere((decoration) => decoration.boxShadow != null);
    expect(decoration.color, Colors.white);
    expect(decoration.boxShadow, isNotNull);
    expect(decoration.boxShadow!.single.offset.dy, lessThan(0));

    final badgePosition = tester.widget<Positioned>(
      find.ancestor(
        of: find.byKey(const ValueKey('bottom-nav-Inbox-unread-badge')),
        matching: find.byType(Positioned),
      ),
    );
    expect(badgePosition.top, -1);
    expect(badgePosition.left, 19);
  });

  testWidgets('GenesisUnreadBadge applies platform optical offsets', (
    tester,
  ) async {
    Future<double> textOffsetFor(TargetPlatform platform) async {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(platform),
          theme: GenesisTheme.light().copyWith(platform: platform),
          home: const Scaffold(body: GenesisUnreadBadge(count: 4)),
        ),
      );
      final transform = tester.widget<Transform>(
        find.descendant(
          of: find.byType(GenesisUnreadBadge),
          matching: find.byType(Transform),
        ),
      );
      return transform.transform.getTranslation().y;
    }

    expect(await textOffsetFor(TargetPlatform.iOS), -0.5);
    expect(await textOffsetFor(TargetPlatform.android), 0.5);
  });

  testWidgets('GenesisBottomNavigation can show an icon-only create action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GenesisTheme.light(),
        home: Scaffold(
          bottomNavigationBar: GenesisBottomNavigation(
            currentIndex: 0,
            onTap: (_) {},
            items: const [
              GenesisBottomNavigationItem(
                label: 'Create',
                icon: Icons.add_rounded,
                prominent: true,
                showLabel: false,
                iconSize: 26,
                iconShadows: [
                  Shadow(color: Colors.white, offset: Offset(0.5, 0)),
                  Shadow(color: Colors.white, offset: Offset(-0.5, 0)),
                  Shadow(color: Colors.white, offset: Offset(0, 0.5)),
                  Shadow(color: Colors.white, offset: Offset(0, -0.5)),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Create'), findsNothing);
    expect(find.byKey(const ValueKey('bottom-nav-Create')), findsOneWidget);

    final createIcon = tester.widget<Icon>(find.byIcon(Icons.add_rounded));
    expect(createIcon.size, 26);
    expect(createIcon.color, Colors.white);
    expect(createIcon.shadows, hasLength(4));

    final decoration = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byKey(const ValueKey('bottom-nav-Create')),
            matching: find.byType(Container),
          ),
        )
        .map((container) => container.decoration)
        .whereType<ShapeDecoration>()
        .singleWhere(
          (decoration) =>
              decoration.color == GenesisColors.create &&
              decoration.shape ==
                  const ContinuousRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
        );
    expect(decoration.color, GenesisColors.create);

    final createSurface = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const ValueKey('bottom-nav-Create')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints?.maxWidth == 42 &&
              widget.constraints?.maxHeight == 33,
        ),
      ),
    );
    expect(createSurface.constraints?.maxWidth, 42);
    expect(createSurface.constraints?.maxHeight, 33);
    expect(
      tester.getCenter(find.byWidget(createSurface)).dy,
      tester.getCenter(find.byKey(const ValueKey('bottom-nav-Create'))).dy,
    );
  });

  testWidgets('GenesisBottomNavigation keeps minimum bottom padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.zero),
          child: Scaffold(
            bottomNavigationBar: GenesisBottomNavigation(
              currentIndex: 0,
              onTap: (_) {},
              items: const [
                GenesisBottomNavigationItem(
                  label: 'Home',
                  icon: Icons.home_outlined,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(GenesisBottomNavigation),
        matching: find.byType(Padding),
      ),
    );
    expect(
      padding.padding,
      const EdgeInsets.only(bottom: GenesisBottomNavigation.minBottomPadding),
    );
  });

  testWidgets('GenesisBottomNavigation uses bottom system view padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.only(bottom: 30),
          ),
          child: Scaffold(
            bottomNavigationBar: GenesisBottomNavigation(
              currentIndex: 0,
              onTap: (_) {},
              items: const [
                GenesisBottomNavigationItem(
                  label: 'Home',
                  icon: Icons.home_outlined,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(GenesisBottomNavigation),
        matching: find.byType(Padding),
      ),
    );
    expect(padding.padding, const EdgeInsets.only(bottom: 30));
  });

  testWidgets('GenesisBottomSystemBarBoundary excludes three-button area', (
    tester,
  ) async {
    MediaQueryData? innerMediaQuery;
    const systemBarColor = Color(0xFFEDF3EF);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: systemBarColor),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(300, 600),
            padding: EdgeInsets.only(bottom: 48),
            viewPadding: EdgeInsets.only(bottom: 48),
            systemGestureInsets: EdgeInsets.only(bottom: 48),
          ),
          child: GenesisBottomSystemBarStyleScope(
            style: const GenesisBottomSystemBarStyle(color: systemBarColor),
            child: GenesisBottomSystemBarBoundary(
              child: Builder(
                builder: (context) {
                  innerMediaQuery = MediaQuery.of(context);
                  return const ColoredBox(
                    key: ValueKey('bounded-content'),
                    color: Colors.red,
                    child: SizedBox.expand(),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('bounded-content'))).height,
      552,
    );
    expect(innerMediaQuery?.padding.bottom, 0);
    expect(innerMediaQuery?.viewPadding.bottom, 0);
    expect(innerMediaQuery?.systemGestureInsets.bottom, 0);
    expect(
      find.byKey(
        const ValueKey<String>('genesis-bottom-system-bar-opaque-overlay'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .any((box) => box.color == systemBarColor),
      isTrue,
    );
  });

  testWidgets('GenesisBottomSystemBarBoundary detects Samsung gesture mode', (
    tester,
  ) async {
    MediaQueryData? innerMediaQuery;
    const systemBarColor = Color(0xFFEDF3EF);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(300, 600),
            padding: EdgeInsets.only(bottom: 15),
            viewPadding: EdgeInsets.only(bottom: 15),
            systemGestureInsets: EdgeInsets.fromLTRB(30, 39, 30, 32),
          ),
          child: GenesisBottomSystemBarStyleScope(
            style: const GenesisBottomSystemBarStyle(color: systemBarColor),
            child: GenesisBottomSystemBarBoundary(
              child: Builder(
                builder: (context) {
                  innerMediaQuery = MediaQuery.of(context);
                  return const ColoredBox(
                    key: ValueKey('gesture-content'),
                    color: Colors.red,
                    child: SizedBox.expand(),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('gesture-content'))).height,
      600,
    );
    expect(innerMediaQuery?.padding.bottom, 15);
    expect(innerMediaQuery?.viewPadding.bottom, 15);
    expect(innerMediaQuery?.systemGestureInsets.bottom, 32);
    expect(
      find.byKey(
        const ValueKey<String>('genesis-bottom-system-bar-opaque-overlay'),
      ),
      findsNothing,
    );
    expect(
      tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .any((box) => box.color == systemBarColor),
      isTrue,
    );
  });

  testWidgets(
    'GenesisBottomSystemBarBoundary defaults ambiguous values to gesture',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(300, 600),
              padding: EdgeInsets.only(bottom: 24),
              viewPadding: EdgeInsets.only(bottom: 24),
              systemGestureInsets: EdgeInsets.only(bottom: 24),
            ),
            child: GenesisBottomSystemBarBoundary(
              child: ColoredBox(
                key: ValueKey('ambiguous-content'),
                color: Colors.red,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const ValueKey('ambiguous-content'))).height,
        600,
      );
      expect(
        find.byKey(
          const ValueKey<String>('genesis-bottom-system-bar-opaque-overlay'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('GenesisTabBar renders labels inside a DefaultTabController', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Scaffold(body: GenesisTabBar(labels: ['Latest', 'Popular'])),
        ),
      ),
    );

    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Popular'), findsOneWidget);
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.unselectedLabelColor, const Color(0xFF666666));
  });

  testWidgets('SecendTabs supports an explicit controller', (tester) async {
    final controller = TabController(length: 2, vsync: tester);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SecendTabs(
                controller: controller,
                labels: const ['Worldo', 'World'],
              ),
              Expanded(
                child: TabBarView(
                  controller: controller,
                  children: const [Text('Worldo list'), Text('World list')],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Worldo'), findsOneWidget);
    expect(find.text('World'), findsOneWidget);
  });

  testWidgets('SecendTabs can center scrollable tabs as a group', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            body: SecendTabs(
              labels: ['My Worlds', 'Popular'],
              tabAlignment: TabAlignment.center,
            ),
          ),
        ),
      ),
    );

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.isScrollable, isTrue);
    expect(tabBar.tabAlignment, TabAlignment.center);
  });

  testWidgets('SecendTabs can remove vertical padding', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            body: Column(
              children: [
                SecendTabs(labels: ['Worldo', 'World'], verticalPadding: 0),
              ],
            ),
          ),
        ),
      ),
    );

    final element = tester.element(find.byType(SecendTabs));
    late Widget child;
    element.visitChildren((childElement) {
      child = childElement.widget;
    });

    final padding = child as Padding;
    expect(padding.padding, EdgeInsets.zero);
  });
}

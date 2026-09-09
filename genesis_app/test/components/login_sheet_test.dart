import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/config/app_flavor_config.dart';
import 'package:genesis_flutter_android/components/common/genesis_bottom_sheet_panel.dart';
import 'package:genesis_flutter_android/components/common/genesis_modal_routes.dart';
import 'package:genesis_flutter_android/components/login_sheet.dart';
import 'package:genesis_flutter_android/components/login_provider_button.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/ui/components/genesis_dark_close_button.dart';

void main() {
  testWidgets('provider buttons follow the current flavor capability', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginProviderButtons(loggingInProvider: null, onLogin: (_) {}),
        ),
      ),
    );

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(
      find.text('Continue with Apple'),
      AppFlavorConfig.currentSupportsAppleSignIn
          ? findsOneWidget
          : findsNothing,
    );
  });

  testWidgets('provider buttons can expose Google only', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginProviderButtons(
            loggingInProvider: null,
            onLogin: (_) {},
            showApple: false,
          ),
        ),
      ),
    );

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);
  });

  testWidgets('login sheet inherits the standard panel title style', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LoginSheet(onLogin: (_) async => false)),
      ),
    );

    final title = tester.widget<Text>(find.text('Sign up to continue'));
    expect(
      title.style,
      GenesisBottomSheetPanel.titleStyle.copyWith(
        color: GenesisColors.darkTextPrimary,
      ),
    );
    expect(find.byType(GenesisDarkCloseButton), findsOneWidget);
    final panel = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(GenesisBottomSheetPanel),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(panel.color, GenesisColors.darkRaisedBackground);
    final legal = tester.widget<Text>(
      find.descendant(
        of: find.byType(LoginLegalText),
        matching: find.byType(Text),
      ),
    );
    final links = (legal.textSpan! as TextSpan).children!
        .whereType<TextSpan>()
        .where((span) => span.recognizer != null);
    expect(links, hasLength(3));
    for (final link in links) {
      expect(link.style?.color, GenesisColors.darkTextSecondary);
      expect(link.style?.decoration, TextDecoration.none);
    }
  });

  testWidgets('login sheet centers the branded Gems signup promo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LoginSheet(onLogin: (_) async => false)),
      ),
    );

    final promoFinder = find.text('Sign up and get 250 Gems!');
    final promo = tester.widget<Text>(promoFinder);
    expect(promo.style?.fontSize, 14);
    expect(promo.style?.fontWeight, FontWeight.w600);
    expect(promo.style?.color, GenesisColors.redSecondary);
    expect(promo.textAlign, TextAlign.center);
    expect(
      tester.getCenter(promoFinder).dx,
      closeTo(tester.getCenter(find.byType(LoginSheet)).dx, 0.01),
    );
  });

  testWidgets('login sheet keeps the global transparent status bar style', (
    tester,
  ) async {
    final calls = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
            calls.add(Map<dynamic, dynamic>.from(call.arguments as Map));
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AnnotatedRegion<SystemUiOverlayStyle>(
          value: kGenesisDefaultSystemUiOverlayStyle,
          child: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () => showLoginSheet(
                    context: context,
                    onLogin: (_) async => false,
                  ),
                  child: const Text('Open login'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    calls.clear();

    await tester.tap(find.text('Open login'));
    await tester.pumpAndSettle();
    final openingStatusBarCalls = calls
        .where((call) => call['statusBarColor'] != null)
        .toList(growable: false);
    expect(
      openingStatusBarCalls.every(
        (call) => call['statusBarColor'] == Colors.transparent.toARGB32(),
      ),
      isTrue,
    );
    expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.idle();

    expect(
      calls.where(
        (call) =>
            call['statusBarColor'] != null &&
            call['statusBarColor'] != Colors.transparent.toARGB32(),
      ),
      isEmpty,
    );
    expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
  });
}

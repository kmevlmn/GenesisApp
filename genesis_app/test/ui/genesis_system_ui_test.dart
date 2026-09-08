import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/ui/system/genesis_system_ui.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

void main() {
  test('global light theme uses the transparent default system UI style', () {
    expect(
      GenesisTheme.light().appBarTheme.systemOverlayStyle,
      kGenesisDefaultSystemUiOverlayStyle,
    );
    expect(
      kGenesisDefaultSystemUiOverlayStyle.statusBarColor,
      Colors.transparent,
    );
    expect(
      kGenesisDefaultSystemUiOverlayStyle.statusBarIconBrightness,
      Brightness.dark,
    );
    expect(
      kGenesisDefaultSystemUiOverlayStyle.statusBarBrightness,
      Brightness.light,
    );
    expect(
      kGenesisDefaultSystemUiOverlayStyle.systemStatusBarContrastEnforced,
      isFalse,
    );
  });

  test('dark top surfaces keep the status bar transparent', () {
    expect(
      kGenesisLightStatusIconsSystemUiOverlayStyle.statusBarColor,
      Colors.transparent,
    );
    expect(
      kGenesisLightStatusIconsSystemUiOverlayStyle.statusBarIconBrightness,
      Brightness.light,
    );
    expect(
      kGenesisLightSystemUiOverlayStyle.statusBarColor,
      Colors.transparent,
    );
    expect(
      kGenesisLightSystemUiOverlayStyle.statusBarIconBrightness,
      Brightness.light,
    );
  });

  testWidgets(
    'startup enables edge-to-edge before applying the dark launch style',
    (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      await tester.pump();
      calls.clear();

      await GenesisSystemUi.initialize();
      await tester.pump();

      final modeCall = calls.firstWhere(
        (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
      );
      expect(modeCall.arguments, SystemUiMode.edgeToEdge.toString());
      final styleCall = calls.lastWhere(
        (call) => call.method == 'SystemChrome.setSystemUIOverlayStyle',
      );
      final style = styleCall.arguments as Map<dynamic, dynamic>;
      expect(style['statusBarColor'], Colors.transparent.toARGB32());
      expect(style['statusBarIconBrightness'], Brightness.light.toString());
      expect(style['systemStatusBarContrastEnforced'], isFalse);
    },
  );
}

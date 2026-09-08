import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genesis_flutter_android/pages/me/about_us_page.dart';
import 'package:genesis_flutter_android/platform/channels/genesis_method_channels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(GenesisMethodChannels.device, null);
  });

  testWidgets('shows app version name from app metadata', (tester) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(GenesisMethodChannels.device, (call) async {
          if (call.method == GenesisMethodChannels.getAppVersion) {
            return {
              'versionName': '0.1.0',
              'versionCode': 1,
              'packageName': 'com.worldo.ai',
            };
          }
          return null;
        });

    await tester.pumpWidget(const MaterialApp(home: AboutUsPage()));
    await tester.pumpAndSettle();

    expect(find.text('v0.1.0'), findsOneWidget);
    expect(find.text('v1.0.0'), findsNothing);
  });
}

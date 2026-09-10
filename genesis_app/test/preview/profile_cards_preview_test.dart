import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/gems/gem_wallet_store.dart';
import 'package:genesis_flutter_android/components/me/user_profile_library.dart';
import 'package:genesis_flutter_android/network/models/gem_wallet.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_dark_theme.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

/// Renders the Me header against design 9k / 9k2 so the two cards can be
/// eyeballed next to `design-0910/export/*.png`. Not an assertion test.
void main() {
  testWidgets('render profile membership and gems cards', (tester) async {
    tester.view.physicalSize = const Size(390, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      final inter = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            'C:/dev/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await icons.load();
      final custom = FontLoader('MyFlutterApp')
        ..addFont(rootBundle.load('assets/custom-icons/fonts/MyFlutterApp.ttf'));
      await custom.load();
    });

    Future<void> shoot(String name, GemWalletState wallet) async {
      final state = ValueNotifier<GemWalletState>(wallet);
      addTearDown(state.dispose);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: GenesisTheme.dark(),
            home: GenesisDarkTheme(
              child: Scaffold(
                backgroundColor: const Color(0xFF131215),
                body: UserProfileContent(
                  data: const UserProfileData(
                    avatarUrl: '',
                    displayName: 'Eve',
                    uid: 'u_A7BN1K',
                    followingCount: 1,
                    followerCount: 2,
                    origins: [],
                    worlds: [],
                  ),
                  gemWalletStateListenable: state,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // _FollowStats overflows at this width independently of these cards;
      // drain it so the capture still runs.
      while (tester.takeException() != null) {}
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('test/preview')..createSync(recursive: true);
        File('${dir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    await shoot(
      'profile_9k',
      const GemWalletState(ownerUid: 'u_A7BN1K', balanceCent: 307220),
    );
    await shoot(
      'profile_expired',
      GemWalletState(
        ownerUid: 'u_A7BN1K',
        balanceCent: 307220,
        membership: GemWalletMembership(
          status: 2,
          planCode: 'pro_monthly',
          expiresAt: DateTime.utc(2026, 8, 1),
          autoRenew: false,
          blueGemsCent: 0,
          hasOverlap: false,
        ),
      ),
    );
    await shoot(
      'profile_9k2',
      GemWalletState(
        ownerUid: 'u_A7BN1K',
        balanceCent: 307220,
        membership: GemWalletMembership(
          status: 1,
          planCode: 'pro_yearly',
          expiresAt: DateTime.utc(2027, 9, 7),
          autoRenew: false,
          blueGemsCent: 30000,
          hasOverlap: false,
        ),
      ),
    );
  });
}

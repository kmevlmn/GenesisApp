import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/gems/gem_wallet_store.dart';
import 'package:genesis_flutter_android/components/me/user_profile_library.dart';
import 'package:genesis_flutter_android/network/models/gem_wallet.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_dark_theme.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

/// Dumps every rendered Text on the Me page with its effective size, so the
/// two cards can be pitched against the page's real type scale.
void main() {
  testWidgets('inventory Me page type scale', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = ValueNotifier<GemWalletState>(
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
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: GenesisTheme.dark(),
        home: GenesisDarkTheme(
          child: Scaffold(
            body: UserProfileContent(
              data: UserProfileData(
                avatarUrl: '',
                displayName: 'Eve',
                uid: 'u_A7BN1K',
                followingCount: 1,
                followerCount: 2,
                origins: List.generate(
                  3,
                  (i) => UserProfileOriginItem(
                    originId: i,
                    oid: 'o_$i',
                    title: 'Old Money',
                    subtitle: 'OID: o_7F2KQ9',
                    imageUrl: '',
                    copyCount: 1200,
                    interactCount: 86000,
                    characterCount: 5,
                  ),
                ),
                worlds: const [],
              ),
              showCollectionCounts: true,
              tabLabelFontSize: 14,
              gemWalletStateListenable: state,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    final rows = <String>[];
    for (final element in find.byType(Text).evaluate()) {
      final widget = element.widget as Text;
      final inherited = DefaultTextStyle.of(element).style;
      final style = widget.style == null
          ? inherited
          : (widget.style!.inherit
                ? inherited.merge(widget.style)
                : widget.style!);
      final label = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      if (label.trim().isEmpty) continue;
      rows.add(
        '${(style.fontSize ?? 14).toStringAsFixed(1).padLeft(5)}  '
        'w${style.fontWeight?.value ?? 400}  '
        '${label.replaceAll('\n', ' ')}',
      );
    }
    rows.sort(
      (a, b) => double.parse(
        b.substring(0, 5).trim(),
      ).compareTo(double.parse(a.substring(0, 5).trim())),
    );
    File(
      'test/preview/me_type_inventory.txt',
    ).writeAsStringSync(rows.join('\n'));
  });
}

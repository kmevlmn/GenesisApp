import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/chat/shared/chat_ui.dart';
import 'package:genesis_flutter_android/pages/world/world_constants.dart';
import 'package:genesis_flutter_android/pages/world/world_header.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

void main() {
  testWidgets(
    'map arrow matches Location Chat across safe areas and platforms',
    (tester) async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        for (final top in [0.0, 24.0, 59.0]) {
          Future<void> pump(Widget body) => tester.pumpWidget(
            MaterialApp(
              theme: GenesisTheme.light().copyWith(platform: platform),
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(800, 600),
                  padding: EdgeInsets.only(top: top),
                  viewPadding: EdgeInsets.only(top: top),
                ),
                child: Scaffold(body: body),
              ),
            ),
          );
          await pump(
            Stack(
              children: [
                Positioned(
                  left: worldMapBackButtonLeft,
                  right: worldMapTopBarRightInset,
                  top: top + worldMapBackButtonTop,
                  child: WorldMapTopBar(
                    title: 'World name',
                    timeText: 'Tick 1 · 12:00',
                    maxIdentityWidth: 600,
                    onBackPressed: () {},
                  ),
                ),
              ],
            ),
          );
          final mapRect = tester.getRect(find.byIcon(Icons.arrow_back_ios_new));
          await pump(
            ChatHeader(
              title: 'Location',
              titleOverline: 'Parent location',
              alignContentLeft: true,
              subtitle: '',
              connected: true,
              connecting: false,
              onBack: () {},
              showSubtitle: false,
              showMoreButton: false,
              style: kLocationChatStyle,
            ),
          );
          final chatRect = tester.getRect(
            find.byIcon(Icons.arrow_back_ios_new),
          );
          expect(mapRect, chatRect, reason: '$platform, top=$top');
          final locationIcon = tester.getRect(
            find.byIcon(Icons.place_outlined),
          );
          expect(locationIcon.left - chatRect.right, 12);
          final nameLeft = tester.getTopLeft(find.text('Location')).dx;
          expect(nameLeft - locationIcon.right, 4);
          expect(tester.getTopLeft(find.text('Parent location')).dx, nameLeft);
        }
      }
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/login_provider_button.dart';
import 'package:genesis_flutter_android/components/me/signed_out_me_view.dart';
import 'package:genesis_flutter_android/components/me/user_profile_content.dart';
import 'package:genesis_flutter_android/components/page_header.dart';
import 'package:genesis_flutter_android/platform/auth/auth_session.dart';
import 'package:genesis_flutter_android/ui/genesis_ui.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_dark_theme.dart';

void main() {
  testWidgets(
    'login controls follow the local theme and preserve light defaults',
    (tester) async {
      for (final dark in [false, true]) {
        final page = Scaffold(
          body: SignedOutMeView(loggingInProvider: null, onLogin: (_) {}),
        );
        await tester.pumpWidget(
          MaterialApp(home: dark ? GenesisDarkTheme(child: page) : page),
        );
        final button = tester.widget<FilledButton>(
          find.byType(FilledButton).first,
        );
        expect(
          button.style!.backgroundColor!.resolve({}),
          dark ? GenesisColors.darkFaintFill : const Color(0xFFF0F0F0),
        );
        expect(
          button.style!.foregroundColor!.resolve({}),
          dark ? GenesisColors.darkTextPrimary : Colors.black,
        );
        final promo = tester.widget<Text>(
          find.byKey(const ValueKey('signed-out-gems-promo')),
        );
        expect(
          promo.style!.color,
          dark ? GenesisColors.redSecondary : GenesisColors.redPrimary,
        );
      }
      await tester.pumpWidget(
        const MaterialApp(
          home: GenesisDarkTheme(
            child: Scaffold(
              body: LoginProviderIcon(provider: IdentityProvider.apple),
            ),
          ),
        ),
      );
      expect(
        tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
        const ColorFilter.mode(GenesisColors.darkTextPrimary, BlendMode.srcIn),
      );
    },
  );

  testWidgets(
    'left app bar title leaves a 12 pixel gap and truncates long names',
    (tester) async {
      const name = 'A very long profile name that must remain on a single line';
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [320.0, 390.0]) {
        await tester.binding.setSurfaceSize(Size(width, 800));
        await tester.pumpWidget(
          MaterialApp(
            home: GenesisDarkTheme(
              child: Scaffold(
                appBar: GenesisBackAppBar(
                  pageName: name,
                  centerTitle: false,
                  titleSpacing: 12,
                  backgroundColor: GenesisColors.darkBackground,
                ),
              ),
            ),
          ),
        );
        expect(tester.getTopLeft(find.text(name)).dx, 49);
        final title = tester.widget<Text>(find.text(name));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text(name), matching: find.byType(RichText)),
        );
        expect(paragraph.text.style!.fontSize, 20);
        expect(paragraph.textScaler.scale(20), 20);
        final transform = paragraph.getTransformTo(null);
        expect(transform.entry(0, 0), 1);
        expect(transform.entry(1, 1), 1);
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
        expect(title.style!.color, GenesisColors.darkTextPrimary);
      }
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(appBar: GenesisBackAppBar(pageName: 'Default')),
        ),
      );
      expect(tester.widget<AppBar>(find.byType(AppBar)).centerTitle, isTrue);
    },
  );

  testWidgets('profile tabs stay dark after the header scrolls away', (
    tester,
  ) async {
    var collapsed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: GenesisDarkTheme(
          child: Scaffold(
            body: SizedBox(
              height: 360,
              child: UserProfileContent(
                data: UserProfileData(
                  avatarUrl: '',
                  displayName: 'Test User',
                  uid: 'u_test',
                  followingCount: 3,
                  followerCount: 7,
                  origins: List.generate(
                    12,
                    (i) => UserProfileOriginItem(
                      originId: i,
                      oid: 'o_$i',
                      title: 'Worldo $i',
                      subtitle: 'OID: o_$i',
                      imageUrl: '',
                      copyCount: 0,
                      interactCount: 0,
                      characterCount: 0,
                    ),
                  ),
                  worlds: const [],
                ),
                onCollapsedChanged: (value) => collapsed = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(collapsed, isTrue);
    final tab = tester.widget<TabBar>(find.byType(TabBar));
    expect(tab.labelColor, GenesisColors.darkTextPrimary);
    expect(tab.unselectedLabelColor, GenesisColors.darkTextSecondary);
    final surfaces = tester.widgetList<ColoredBox>(
      find.ancestor(of: find.byType(TabBar), matching: find.byType(ColoredBox)),
    );
    expect(
      surfaces.any((box) => box.color == GenesisColors.darkBackground),
      isTrue,
    );
    expect(surfaces.any((box) => box.color == Colors.white), isFalse);
    final cards = tester.widgetList<Material>(
      find.descendant(
        of: find.byType(GenesisProfileCollectionListItem),
        matching: find.byType(Material),
      ),
    );
    expect(cards.any((card) => card.color == Colors.white), isFalse);
    expect(tester.takeException(), isNull);
  });
}

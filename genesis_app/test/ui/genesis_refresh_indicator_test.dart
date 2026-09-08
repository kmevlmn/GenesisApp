import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/me/user_profile_content.dart';
import 'package:genesis_flutter_android/ui/genesis_ui.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_dark_theme.dart';

void main() {
  testWidgets('refresh uses local appearance and waits for the request', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final complete = Completer<void>();
      var calls = 0;
      final page = Scaffold(
        body: GenesisRefreshIndicator(
          onRefresh: () {
            calls++;
            return complete.future;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [SizedBox(height: 1000)],
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            scaffoldBackgroundColor: const Color(0xFFF8F8F8),
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
          ),
          home: dark ? GenesisDarkTheme(child: page) : page,
        ),
      );
      final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      expect(
        indicator.backgroundColor,
        dark ? GenesisColors.darkRaisedBackground : const Color(0xFFF8F8F8),
      );
      expect(indicator.color, dark ? GenesisColors.darkTextSecondary : null);
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      complete.complete();
      await tester.pumpAndSettle();
      expect(find.byType(RefreshProgressIndicator), findsNothing);
    }
  });

  testWidgets('explicit surface and foreground overrides are preserved', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GenesisDarkTheme(
          child: Scaffold(
            body: GenesisRefreshIndicator(
              color: Colors.blue,
              backgroundColor: GenesisColors.darkFaintSurface,
              onRefresh: () async {},
              child: ListView(),
            ),
          ),
        ),
      ),
    );
    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    expect(indicator.color, Colors.blue);
    expect(indicator.backgroundColor, GenesisColors.darkFaintSurface);
  });

  testWidgets('both profile tabs use the shared loading color during loading', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final page = Scaffold(
        body: UserProfileContent(
          data: const UserProfileData(
            avatarUrl: '',
            displayName: 'User',
            uid: 'u_test',
            followingCount: 0,
            followerCount: 0,
            isSelf: false,
            origins: [],
            worlds: [],
          ),
          originsLoading: true,
          worldsLoading: true,
          originTabLabel: 'Worldo',
          worldTabLabel: 'Playing',
          onRefresh: () async {},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: dark ? GenesisDarkTheme(child: page) : page),
      );
      await tester.pump();
      for (final tab in ['Worldo', 'Playing']) {
        await tester.tap(find.text(tab));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        final key = tab == 'Worldo'
            ? 'profile-origin-list-loading'
            : 'profile-world-list-loading';
        final spinner = tester.widget<CircularProgressIndicator>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(CircularProgressIndicator),
          ),
        );
        expect(spinner.color, dark ? GenesisColors.darkTextSecondary : null);
        expect(spinner.strokeWidth, 2.4);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

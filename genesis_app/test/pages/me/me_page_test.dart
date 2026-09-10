import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genesis_flutter_android/app/gems/gem_wallet_store.dart';
import 'package:genesis_flutter_android/components/gems/profile_membership_card.dart';
import 'package:genesis_flutter_android/network/models/gem_wallet.dart';
import 'package:genesis_flutter_android/components/me/user_profile_content.dart';
import 'package:genesis_flutter_android/pages/me/me_page.dart';
import 'package:genesis_flutter_android/routers/app_router.dart';
import 'package:genesis_flutter_android/ui/components/genesis_avatar.dart';
import 'package:genesis_flutter_android/ui/components/genesis_profile_collection_list_item.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/utils/entity_deleted.dart';

void main() {
  testWidgets(
    'Me shows one membership card and keeps wallet and membership balances independent',
    (tester) async {
      final state = ValueNotifier<GemWalletState>(
        const GemWalletState(ownerUid: 'user'),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserProfileContent(
              data: const UserProfileData(
                avatarUrl: '',
                displayName: 'User',
                uid: 'user',
                followingCount: 0,
                followerCount: 0,
                origins: [],
                worlds: [],
              ),
              gemWalletStateListenable: state,
            ),
          ),
        ),
      );
      expect(find.byType(ProfileMembershipCard), findsOneWidget);
      expect(find.text('Subscribe'), findsOneWidget);
      expect(find.text('Expired'), findsNothing);
      for (final status in [1, 2, 0, 1]) {
        state.value = GemWalletState(
          ownerUid: 'user',
          balanceCent: 548240,
          membership: GemWalletMembership(
            status: status,
            planCode: 'pro_yearly',
            expiresAt: DateTime(2027, 9, 8),
            autoRenew: false,
            blueGemsCent: status == 1 ? 30000 : 0,
            hasOverlap: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ProfileMembershipCard), findsOneWidget);
        expect(
          find.text('Subscribe'),
          status == 1 ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('Expired'),
          status == 2 ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Expires 2027-09-08'),
          status == 1 ? findsOneWidget : findsNothing,
        );
        expect(find.text(status == 1 ? '300.0' : '0.0'), findsOneWidget);
        expect(find.text('5,482.4'), findsOneWidget);
      }
      state.value = const GemWalletState(
        ownerUid: 'user',
        balanceCent: 518240,
        membership: GemWalletMembership(
          status: 1,
          planCode: 'pro_monthly',
          expiresAt: null,
          autoRenew: false,
          blueGemsCent: 0,
          hasOverlap: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Subscribe'), findsNothing);
      expect(find.text('Expires —'), findsOneWidget);
      expect(find.text('0.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('empty backend name and avatar render uid and default avatar', () {
    const current = UserProfileData(
      avatarUrl: 'https://cdn.example.com/old_avatar.webp',
      displayName: 'Cached User',
      uid: 'u_cached',
      followingCount: 7,
      followerCount: 11,
      origins: <UserProfileOriginItem>[],
      worlds: <UserProfileWorldItem>[],
    );

    final next = mergeRemoteUserInfoForRenderForTest(current, {
      'uid': 'u_backend',
      'name': '',
      'avatar': {'sm_url': '', 'xl_url': '', 'object_key': ''},
      'following_cnt': 7,
      'follower_cnt': 11,
    });

    expect(next.displayName, 'u_backend');
    expect(next.avatarUrl, '');
  });

  test('deleted backend user renders deleted for name and uid', () {
    const current = UserProfileData(
      avatarUrl: 'https://cdn.example.com/old_avatar.webp',
      displayName: 'Cached User',
      uid: 'u_cached',
      followingCount: 7,
      followerCount: 11,
      origins: <UserProfileOriginItem>[],
      worlds: <UserProfileWorldItem>[],
    );

    final next = mergeRemoteUserInfoForRenderForTest(current, {
      'uid': 'u_backend',
      'name': '',
      'avatar': {'sm_url': '', 'xl_url': '', 'object_key': ''},
      'deleted': true,
      'following_cnt': 7,
      'follower_cnt': 11,
    });

    expect(next.deleted, isTrue);
    expect(next.displayName, deletedEntityDisplayText);
    expect(next.uid, deletedEntityDisplayText);
  });

  testWidgets('profile collection tabs report selected tab index', (
    tester,
  ) async {
    final selectedIndexes = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserProfileContent(
            data: const UserProfileData(
              avatarUrl: '',
              displayName: 'User',
              uid: 'u_user',
              followingCount: 0,
              followerCount: 0,
              origins: <UserProfileOriginItem>[],
              worlds: <UserProfileWorldItem>[],
            ),
            onCollectionTabChanged: selectedIndexes.add,
            originTabLabel: 'Worldo',
            worldTabLabel: 'Playing',
            showCollectionCounts: true,
            tabLabelFontSize: 14,
          ),
        ),
      ),
    );

    expect(find.text('No Worldo you created yet.'), findsOneWidget);
    expect(find.text('No Worldos you created yet.'), findsNothing);
    final gemBalance = tester.widget<Text>(
      find.byKey(const ValueKey('user-profile-gems-balance')),
    );
    expect(gemBalance.textSpan?.toPlainText(), '0.0');
    expect(gemBalance.style?.fontWeight, FontWeight.w800);
    expect(find.text('--'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('user-profile-gem-icon'))),
      const Size(26, 26),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('user-profile-gems-entry')),
        matching: find.text('Red gems'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('user-profile-gems-entry')),
        matching: find.text('Pink gems'),
      ),
      findsOneWidget,
    );
    expect(find.text('Top up'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-profile-gems-pattern')),
      findsOneWidget,
    );
    final backgroundDecoration =
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('user-profile-gems-background')),
                )
                .decoration!
            as BoxDecoration;
    // 9k grounds the gems entry in flat ink rather than the old red sweep.
    expect(backgroundDecoration.color, const Color(0xFF232228));
    expect(backgroundDecoration.gradient, isNull);
    expect(backgroundDecoration.border, isNull);
    expect(
      backgroundDecoration.borderRadius,
      BorderRadius.circular(16),
    );
    final topUpDecoration =
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('user-profile-gems-top-up')),
                )
                .decoration!
            as BoxDecoration;
    expect(topUpDecoration.color, GenesisColors.brand);

    expect(find.text('Worldo'), findsOneWidget);
    expect(find.text('Playing'), findsOneWidget);
    expect(_profileTabCount('origin', '0'), findsOneWidget);
    expect(_profileTabCount('world', '0'), findsOneWidget);
    expect(find.text('#Worldo'), findsNothing);
    expect(find.text('World'), findsNothing);
    final originCount = tester.widget<Text>(_profileTabCount('origin', '0'));
    final originLabelStyle = DefaultTextStyle.of(
      tester.element(find.text('Worldo')),
    ).style;
    expect(originCount.style?.fontSize, originLabelStyle.fontSize);
    expect(originCount.style?.color, originLabelStyle.color);
    expect(originCount.style?.fontWeight, FontWeight.w400);
    final originLabelBox = tester.getRect(
      find.byKey(const ValueKey<String>('profile-tab-origin')),
    );
    final originLabelText = tester.getRect(find.text('Worldo'));
    expect(originLabelBox.width, closeTo(originLabelText.width, 0.1));
    expect(originLabelBox.center.dx, closeTo(originLabelText.center.dx, 0.1));
    expect(
      tester.getRect(_profileTabCount('origin', '0')).left,
      greaterThan(originLabelText.right),
    );
    expect(
      tester.getRect(find.text('Playing')).left -
          tester.getRect(_profileTabCount('origin', '0')).right,
      lessThanOrEqualTo(24),
    );
    expect(
      tester.widget<TabBar>(find.byType(TabBar)).indicatorSize,
      TabBarIndicatorSize.label,
    );

    await tester.tap(find.text('Playing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Worldo'));
    await tester.pumpAndSettle();

    expect(selectedIndexes, <int>[1, 0]);
  });

  testWidgets('profile collection tab counts follow current list state', (
    tester,
  ) async {
    final originsState =
        ValueNotifier<UserProfileCollectionState<UserProfileOriginItem>>(
          const UserProfileCollectionState<UserProfileOriginItem>(
            items: <UserProfileOriginItem>[],
            isLoading: false,
          ),
        );
    final worldsState =
        ValueNotifier<UserProfileCollectionState<UserProfileWorldItem>>(
          const UserProfileCollectionState<UserProfileWorldItem>(
            items: <UserProfileWorldItem>[],
            isLoading: false,
          ),
        );
    addTearDown(originsState.dispose);
    addTearDown(worldsState.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserProfileContent(
            data: const UserProfileData(
              avatarUrl: '',
              displayName: 'User',
              uid: 'u_user',
              followingCount: 0,
              followerCount: 0,
              origins: <UserProfileOriginItem>[],
              worlds: <UserProfileWorldItem>[],
            ),
            originsListenable: originsState,
            worldsListenable: worldsState,
            originTabLabel: 'Worldo',
            worldTabLabel: 'Playing',
            showCollectionCounts: true,
            tabLabelFontSize: 14,
          ),
        ),
      ),
    );

    expect(_profileTabCount('origin', '0'), findsOneWidget);
    expect(_profileTabCount('world', '0'), findsOneWidget);

    originsState.value =
        const UserProfileCollectionState<UserProfileOriginItem>(
          items: <UserProfileOriginItem>[
            UserProfileOriginItem(
              originId: 1,
              oid: 'oid_1',
              title: 'Worldo One',
              subtitle: '',
              imageUrl: '',
              copyCount: 0,
              interactCount: 0,
              characterCount: 0,
            ),
          ],
          isLoading: false,
        );
    worldsState.value = const UserProfileCollectionState<UserProfileWorldItem>(
      items: <UserProfileWorldItem>[
        UserProfileWorldItem(
          wid: 'wid_1',
          title: 'World One',
          subtitle: '',
          imageUrl: '',
          progressCount: 4,
          subTickNo: 2,
          interactCount: 1,
          characterCount: 0,
          playerCount: 1200,
          ownerName: 'User',
        ),
        UserProfileWorldItem(
          wid: 'wid_2',
          title: 'World Two',
          subtitle: '',
          imageUrl: '',
          progressCount: 0,
          interactCount: 0,
          characterCount: 0,
          playerCount: 0,
          ownerName: 'User',
        ),
      ],
      isLoading: false,
    );
    await tester.pump();

    expect(_profileTabCount('origin', '1'), findsOneWidget);
    expect(_profileTabCount('world', '2'), findsOneWidget);

    await tester.tap(find.text('Playing'));
    await tester.pumpAndSettle();

    expect(find.text('Tick 4-2 · 1 Message · 1.2K Players'), findsOneWidget);
    expect(find.text('Tick 0 · 0 Message'), findsOneWidget);
  });

  testWidgets('profile collection pages keep a 10px gap while swiping', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserProfileContent(
            data: UserProfileData(
              avatarUrl: '',
              displayName: 'User',
              uid: 'u_user',
              followingCount: 0,
              followerCount: 0,
              origins: <UserProfileOriginItem>[
                UserProfileOriginItem(
                  originId: 1,
                  oid: 'oid_1',
                  title: 'Editable Worldo',
                  subtitle: '',
                  imageUrl: '',
                  copyCount: 0,
                  interactCount: 0,
                  characterCount: 0,
                ),
              ],
              worlds: <UserProfileWorldItem>[
                UserProfileWorldItem(
                  wid: 'wid_1',
                  title: 'Playing World',
                  subtitle: '',
                  imageUrl: '',
                  progressCount: 0,
                  interactCount: 0,
                  characterCount: 0,
                  playerCount: 0,
                  ownerName: 'User',
                ),
              ],
            ),
            originTabLabel: 'Worldo',
            worldTabLabel: 'Playing',
          ),
        ),
      ),
    );

    final tabBarView = find.byType(TabBarView);
    expect(
      tester.widget<TabBarView>(tabBarView).physics,
      isA<ClampingScrollPhysics>(),
    );
    final worldoPage = find.byKey(
      const ValueKey<String>('profile-origin-collection-page'),
      skipOffstage: false,
    );
    expect(tester.getRect(worldoPage), tester.getRect(tabBarView));

    final gesture = await tester.startGesture(tester.getCenter(tabBarView));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-180, 0));
    await tester.pump();

    final playingPage = find.byKey(
      const ValueKey<String>('profile-world-collection-page'),
      skipOffstage: false,
    );
    expect(worldoPage, findsOneWidget);
    expect(playingPage, findsOneWidget);
    expect(
      tester.getRect(playingPage).left - tester.getRect(worldoPage).right,
      closeTo(10, 0.1),
    );

    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playing'));
    await tester.pumpAndSettle();
    expect(tester.getRect(playingPage), tester.getRect(tabBarView));
  });

  testWidgets('self profile keeps collection cards virtualized', (
    tester,
  ) async {
    final origins = List<UserProfileOriginItem>.generate(
      100,
      (index) => UserProfileOriginItem(
        originId: index,
        oid: 'oid_$index',
        title: 'Worldo $index',
        subtitle: 'Subtitle $index',
        imageUrl: '',
        copyCount: 0,
        interactCount: 0,
        characterCount: 0,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserProfileContent(
            data: UserProfileData(
              avatarUrl: '',
              displayName: 'User',
              uid: 'u_user',
              followingCount: 0,
              followerCount: 0,
              origins: origins,
              worlds: const <UserProfileWorldItem>[],
            ),
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('#Worldo 0'), findsOneWidget);
    expect(find.text('#Worldo 99'), findsNothing);
    expect(
      find.byType(GenesisProfileCollectionListItem).evaluate().length,
      lessThan(origins.length),
    );
  });

  testWidgets('whole-profile pull moves the header with the collection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserProfileContent(
            data: const UserProfileData(
              avatarUrl: '',
              displayName: 'User',
              uid: 'u_user',
              followingCount: 0,
              followerCount: 0,
              origins: <UserProfileOriginItem>[
                UserProfileOriginItem(
                  originId: 1,
                  oid: 'oid_1',
                  title: 'Worldo One',
                  subtitle: '',
                  imageUrl: '',
                  copyCount: 0,
                  interactCount: 0,
                  characterCount: 0,
                ),
              ],
              worlds: <UserProfileWorldItem>[],
            ),
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.pump();

    final page = find.byType(NestedScrollView);
    final header = find.byKey(
      const ValueKey<String>('user-profile-follow-stats'),
    );
    final headerTopBefore = tester.getTopLeft(header).dy;
    final gesture = await tester.startGesture(tester.getCenter(page));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    await tester.pump();

    final nestedState = tester.state<NestedScrollViewState>(page);
    expect(
      nestedState.innerController.positions.any(
        (position) => position.pixels < 0,
      ),
      isTrue,
    );
    expect(tester.getTopLeft(header).dy, greaterThan(headerTopBefore));

    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'switching from a pinned long collection resets a short collection to top',
    (tester) async {
      tester.view.physicalSize = const Size(480, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final origins = List<UserProfileOriginItem>.generate(
        12,
        (index) => UserProfileOriginItem(
          originId: index,
          oid: 'oid_$index',
          title: 'Worldo $index',
          subtitle: '',
          imageUrl: '',
          copyCount: 0,
          interactCount: 0,
          characterCount: 0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserProfileContent(
              data: UserProfileData(
                avatarUrl: '',
                displayName: 'User',
                uid: 'u_user',
                followingCount: 0,
                followerCount: 0,
                origins: origins,
                worlds: const <UserProfileWorldItem>[
                  UserProfileWorldItem(
                    wid: 'wid_short',
                    title: 'Short World',
                    subtitle: '',
                    imageUrl: '',
                    progressCount: 0,
                    interactCount: 0,
                    characterCount: 0,
                    playerCount: 0,
                    ownerName: 'User',
                  ),
                ],
              ),
              originTabLabel: 'Worldo',
              worldTabLabel: 'Playing',
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pump();

      final page = find.byType(NestedScrollView);
      await tester.drag(page, const Offset(0, -520));
      await tester.pumpAndSettle();

      final tabBar = find.byType(TabBar);
      expect(tester.getTopLeft(tabBar).dy, closeTo(5, 0.1));

      await tester.tap(find.text('Playing'));
      await tester.pumpAndSettle();

      final shortCard = find.ancestor(
        of: find.text('Short World'),
        matching: find.byType(GenesisProfileCollectionListItem),
      );
      expect(shortCard, findsOneWidget);
      expect(
        tester.getTopLeft(shortCard).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(tabBar).dy + 9.5),
      );
    },
  );

  testWidgets('self Worldo edit icon opens the edit page directly', (
    tester,
  ) async {
    RouteSettings? openedSettings;

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          openedSettings = settings;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const SizedBox.shrink(),
          );
        },
        home: const Scaffold(
          body: UserProfileContent(
            data: UserProfileData(
              avatarUrl: '',
              displayName: 'User',
              uid: 'u_user',
              followingCount: 0,
              followerCount: 0,
              origins: [
                UserProfileOriginItem(
                  originId: 7,
                  oid: 'oid_7',
                  title: 'My Worldo',
                  subtitle: 'World seed',
                  imageUrl: '',
                  copyCount: 0,
                  interactCount: 0,
                  characterCount: 0,
                ),
              ],
              worlds: <UserProfileWorldItem>[],
            ),
          ),
        ),
      ),
    );

    final editAction = find.byKey(
      const ValueKey<String>('profile-collection-item-edit-oid_7'),
    );
    expect(editAction, findsOneWidget);

    await tester.tap(editAction);
    await tester.pumpAndSettle();

    expect(openedSettings?.name, RouteNames.edit);
    expect(openedSettings?.arguments, {'origin_id': 'oid_7'});
  });

  testWidgets('self profile shows Gems balance entry and opens wallet', (
    tester,
  ) async {
    String? openedRoute;
    final walletState = ValueNotifier<GemWalletState>(
      const GemWalletState(ownerUid: 'u_user', balanceCent: 43000),
    );
    addTearDown(walletState.dispose);

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          openedRoute = settings.name;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const SizedBox.shrink(),
          );
        },
        home: Scaffold(
          body: UserProfileContent(
            data: const UserProfileData(
              avatarUrl: '',
              displayName: 'User',
              uid: 'u_user',
              followingCount: 12,
              followerCount: 34,
              origins: <UserProfileOriginItem>[],
              worlds: <UserProfileWorldItem>[],
            ),
            gemWalletStateListenable: walletState,
          ),
        ),
      ),
    );

    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Followers'), findsOneWidget);
    expect(tester.widget<Text>(find.text('User')).style?.fontSize, 20);
    expect(tester.widget<Text>(find.text('12')).style?.fontSize, 16);
    expect(tester.widget<Text>(find.text('Following')).style?.fontSize, 14);
    expect(tester.widget<Text>(find.text('34')).style?.fontSize, 16);
    expect(tester.widget<Text>(find.text('Followers')).style?.fontSize, 14);
    expect(
      tester.widget<Text>(find.text('12')).style?.color,
      const Color(0xFF111111),
    );
    expect(
      tester.widget<Text>(find.text('Following')).style?.color,
      const Color(0xFF666666),
    );
    expect(
      tester.getCenter(find.text('12')).dy,
      moreOrLessEquals(tester.getCenter(find.text('Following')).dy),
    );
    expect(
      tester.getCenter(find.text('34')).dy,
      moreOrLessEquals(tester.getCenter(find.text('Followers')).dy),
    );
    final uidText = find.text('UID: u_user');
    final followingCount = find.text('12');
    expect(uidText, findsOneWidget);
    expect(followingCount, findsOneWidget);
    expect(tester.widget<Text>(uidText).style?.color, const Color(0xFF666666));
    expect(
      tester.getTopLeft(followingCount).dx,
      moreOrLessEquals(tester.getTopLeft(uidText).dx),
    );
    expect(
      tester.getTopLeft(followingCount).dy,
      greaterThan(tester.getBottomLeft(uidText).dy),
    );
    expect(
      tester
          .getBottomLeft(
            find.byKey(const ValueKey<String>('user-profile-follow-stats')),
          )
          .dy,
      moreOrLessEquals(tester.getBottomLeft(find.byType(GenesisAvatar)).dy),
    );
    expect(
      find.byKey(const ValueKey('user-profile-gems-entry')),
      findsOneWidget,
    );
    expect(find.text('430.0'), findsOneWidget);
    expect(find.text('Red gems'), findsOneWidget);
    expect(find.text('Pink gems'), findsOneWidget);

    walletState.value = const GemWalletState(
      ownerUid: 'u_user',
      balanceCent: 52000,
    );
    await tester.pump();

    expect(find.text('520.0'), findsOneWidget);
    expect(find.text('430.0'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('user-profile-gems-entry')));
    await tester.pumpAndSettle();

    expect(openedRoute, '/gems');
  });
}

Finder _profileTabCount(String tab, String count) {
  return find.descendant(
    of: find.byKey(ValueKey<String>('profile-tab-count-$tab')),
    matching: find.text(count),
  );
}

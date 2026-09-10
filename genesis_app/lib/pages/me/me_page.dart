import '../../components/gems/pro_membership_badge.dart';
import '../../app/gems/gem_wallet_store.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/theme/genesis_dark_theme.dart';
import '../../ui/navigation/genesis_dark_page_route.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../app/bootstrap/app_services_scope.dart';
import '../../app/debug_page_tracker.dart';
import '../../components/common/genesis_action_box.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../components/common/genesis_modal_routes.dart';
import '../../components/common/local_image_crop_page.dart';
import '../../components/page_header.dart';
import '../../components/me/signed_out_me_view.dart';
import '../../components/me/user_profile_content.dart';
import '../../network/genesis_api.dart';
import '../../network/json_utils.dart';
import '../../network/models/origin.dart';
import '../../platform/auth/auth_cancelled_exception.dart';
import '../../platform/auth/auth_session.dart';
import '../../platform/session/user_session_store.dart';
import '../../platform/session/user_info_cache.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/entity_deleted.dart';
import '../../utils/image_format_guards.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../ui/components/genesis_refresh_indicator.dart';
import '../../ui/text/genesis_text_input_formatters.dart';
import 'settings_page.dart';

part 'me_page_data.dart';
part 'me_page_actions.dart';
part 'me_page_models.dart';
part 'me_page_nickname.dart';

@visibleForTesting
const Size meProfileAvatarUploadSize = Size.square(1080);

class MePage extends StatefulWidget {
  const MePage({
    super.key,
    this.onLoggedOut,
    this.onLogin,
    this.onLoginCompleted,
    this.activationListenable,
    this.reselectionListenable,
    this.isActiveListenable,
  });

  final VoidCallback? onLoggedOut;
  final Future<bool> Function(IdentityProvider provider)? onLogin;
  final Future<void> Function()? onLoginCompleted;
  final ValueListenable<int>? activationListenable;
  final ValueListenable<int>? reselectionListenable;
  final ValueListenable<bool>? isActiveListenable;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> with RouteAware {
  static final Uri _discordUri = Uri.parse('https://discord.gg/wuKHk7cyX7');

  late Future<_MePageContent> _future;
  final ValueNotifier<bool> _isUpdatingProfile = ValueNotifier<bool>(false);
  final ValueNotifier<String> _avatarUrl = ValueNotifier<String>('');
  final ValueNotifier<String> _displayName = ValueNotifier<String>('');
  IdentityProvider? _loggingInProvider;
  final ValueNotifier<UserProfileCollectionState<UserProfileOriginItem>>
  _originsState =
      ValueNotifier<UserProfileCollectionState<UserProfileOriginItem>>(
        const UserProfileCollectionState<UserProfileOriginItem>(
          items: <UserProfileOriginItem>[],
          isLoading: false,
        ),
      );
  final ValueNotifier<UserProfileCollectionState<UserProfileWorldItem>>
  _worldsState =
      ValueNotifier<UserProfileCollectionState<UserProfileWorldItem>>(
        const UserProfileCollectionState<UserProfileWorldItem>(
          items: <UserProfileWorldItem>[],
          isLoading: false,
        ),
      );
  int _loadGeneration = 0;
  bool _profileCollapsed = false;
  bool _isActivationRefreshing = false;
  bool _hasPendingActivationRefresh = false;
  int _selectedCollectionTabIndex = 0;
  ValueListenable<int>? _sessionRevisionListenable;
  PageRoute<dynamic>? _subscribedRoute;
  bool _initialWalletRefreshStarted = false;
  // Extension method tear-offs are not equal across reads, so listener
  // registration and removal must reuse these stable callback objects.
  late final VoidCallback _tabActivatedListener;
  late final VoidCallback _sessionChangedListener;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _tabActivatedListener = _handleTabActivated;
    _sessionChangedListener = _handleSessionChanged;
    _future = _loadData();
    widget.activationListenable?.addListener(_tabActivatedListener);
  }

  @override
  void didUpdateWidget(covariant MePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activationListenable != widget.activationListenable) {
      oldWidget.activationListenable?.removeListener(_tabActivatedListener);
      widget.activationListenable?.addListener(_tabActivatedListener);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && !identical(route, _subscribedRoute)) {
      genesisPageRouteObserver.unsubscribe(this);
      _subscribedRoute = route;
      genesisPageRouteObserver.subscribe(this, route);
    }
    final sessionRevision = AppServicesScope.of(context).sessionRevision;
    if (!identical(_sessionRevisionListenable, sessionRevision)) {
      _sessionRevisionListenable?.removeListener(_sessionChangedListener);
      _sessionRevisionListenable = sessionRevision;
      sessionRevision.addListener(_sessionChangedListener);
    }
    if (!_initialWalletRefreshStarted && _isTabActive) {
      _initialWalletRefreshStarted = true;
      _refreshGemWallet();
    }
  }

  @override
  void didPopNext() {
    _handleTabActivated();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _loadGeneration += 1;
    genesisPageRouteObserver.unsubscribe(this);
    _sessionRevisionListenable?.removeListener(_sessionChangedListener);
    widget.activationListenable?.removeListener(_tabActivatedListener);
    _isUpdatingProfile.dispose();
    _avatarUrl.dispose();
    _displayName.dispose();
    _originsState.dispose();
    _worldsState.dispose();
    super.dispose();
  }

  void _updateState(VoidCallback callback) => setState(callback);

  void _refreshGemWallet() {
    if (!mounted || !_isTabActive) return;
    unawaited(AppServicesScope.read(context).gemWallet.refresh());
  }

  @override
  Widget build(BuildContext context) {
    return GenesisDarkTheme(
      child: ColoredBox(
        color: GenesisColors.darkBackground,
        child: FutureBuilder<_MePageContent>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: GenesisLoadingIndicator(strokeWidth: 4),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Load failed',
                      style: TextStyle(color: GenesisColors.darkTextSecondary),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final content = snapshot.data;
            if (content == null) {
              return const SizedBox.shrink();
            }
            if (!content.isSignedIn) {
              return SignedOutMeView(
                loggingInProvider: _loggingInProvider,
                onLogin: _login,
                reselectionListenable: widget.reselectionListenable,
                isActiveListenable: widget.isActiveListenable,
              );
            }
            final data = content.data!;
            final gemWalletState = AppServicesScope.of(context).gemWallet.state;

            return GenesisTopSafeArea(
              backgroundColor: GenesisColors.darkBackground,
              child: Column(
                children: [
                  SizedBox(
                    height: 50,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedOpacity(
                          opacity: _profileCollapsed ? 1 : 0,
                          duration: const Duration(milliseconds: 120),
                          child: const Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(left: 16, right: 112),
                              child: PageTitleText(pageName: 'Me'),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            // 12px inside the 48px button + 4px = 16px.
                            padding: const EdgeInsets.only(right: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: _openDiscord,
                                  icon: SizedBox.square(
                                    dimension: 24,
                                    child: Center(
                                      // Clyde fills its viewBox; the settings glyph
                                      // has inset space inside its 24px icon box.
                                      child: SvgPicture.asset(
                                        'assets/custom-icons/svg/discord-clyde-white.svg',
                                        width: 22,
                                        height: 16.5,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _openSettings,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 48,
                                    height: 48,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  icon: const Icon(Icons.settings, size: 24),
                                  color: GenesisColors.darkTextPrimary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<GemWalletState>(
                      valueListenable: gemWalletState,
                      builder: (context, wallet, _) => UserProfileContent(
                        data: data,
                        originsListenable: _originsState,
                        worldsListenable: _worldsState,
                        avatarUrlListenable: _avatarUrl,
                        displayNameListenable: _displayName,
                        // The crown now sits bare beside the name, so the
                        // 50x20 plate box it used to need is gone.
                        displayNameTrailing: wallet.membership?.isActive == true
                            ? ProMembershipBadge.beside(
                                key: const ValueKey('me-profile-crown-icon'),
                                // The display name renders at 20.
                                fontSize: MediaQuery.textScalerOf(
                                  context,
                                ).scale(20),
                              )
                            : null,
                        isUpdatingProfileListenable: _isUpdatingProfile,
                        gemWalletStateListenable: gemWalletState,
                        reselectionListenable: widget.reselectionListenable,
                        isActiveListenable: widget.isActiveListenable,
                        onEditAvatar: _editAvatar,
                        onEditDisplayName: _editNickName,
                        onRefresh: _refreshCurrentCollection,
                        onRefreshOrigins: _refreshOrigins,
                        onRefreshWorlds: _refreshWorlds,
                        onWorldDeleted: _handleWorldDeleted,
                        onCollectionTabChanged: _handleCollectionTabChanged,
                        onCollapsedChanged: _handleProfileCollapsedChanged,
                        originTabLabel: 'Worldo',
                        worldTabLabel: 'Playing',
                        showCollectionCounts: true,
                        tabLabelFontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleWorldDeleted(UserProfileWorldItem item) {
    final worldId = item.wid.trim();
    if (worldId.isEmpty) return;
    final current = _worldsState.value;
    final nextItems = current.items
        .where((world) => world.wid.trim() != worldId)
        .toList(growable: false);
    _setWorldsState(nextItems, isLoading: current.isLoading);
  }

  Future<void> _refreshCurrentCollection() async {
    await Future.wait<void>([
      _selectedCollectionTabIndex == 0 ? _refreshOrigins() : _refreshWorlds(),
      AppServicesScope.read(context).gemWallet.refresh(),
    ]);
  }
}

part of 'user_profile_library.dart';

const double _profileCollectionPageGap = 10;

class UserProfileContent extends StatefulWidget {
  const UserProfileContent({
    super.key,
    required this.data,
    this.originsListenable,
    this.worldsListenable,
    this.originsLoading = false,
    this.worldsLoading = false,
    this.isUpdatingProfile = false,
    this.avatarUrlListenable,
    this.displayNameListenable,
    this.isUpdatingProfileListenable,
    this.gemWalletStateListenable,
    this.reselectionListenable,
    this.isActiveListenable,
    this.onEditAvatar,
    this.onEditDisplayName,
    this.onRefresh,
    this.onRefreshOrigins,
    this.onRefreshWorlds,
    this.onWorldDeleted,
    this.onCollectionTabChanged,
    this.onCollapsedChanged,
    this.nameUidGap = 4,
    this.tabLabelFontSize = 16,
    this.originTabLabel = '#Worldo',
    this.worldTabLabel = 'World',
    this.showCollectionCounts = false,
    this.isBlocking = false,
    this.isBlocked = false,
  });

  final UserProfileData data;
  final ValueListenable<UserProfileCollectionState<UserProfileOriginItem>>?
  originsListenable;
  final ValueListenable<UserProfileCollectionState<UserProfileWorldItem>>?
  worldsListenable;
  final bool originsLoading;
  final bool worldsLoading;
  final bool isUpdatingProfile;
  final ValueListenable<String>? avatarUrlListenable;
  final ValueListenable<String>? displayNameListenable;
  final ValueListenable<bool>? isUpdatingProfileListenable;
  final ValueListenable<GemWalletState>? gemWalletStateListenable;
  final ValueListenable<int>? reselectionListenable;
  final ValueListenable<bool>? isActiveListenable;
  final VoidCallback? onEditAvatar;
  final VoidCallback? onEditDisplayName;
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onRefreshOrigins;
  final Future<void> Function()? onRefreshWorlds;
  final ValueChanged<UserProfileWorldItem>? onWorldDeleted;
  final ValueChanged<int>? onCollectionTabChanged;
  final ValueChanged<bool>? onCollapsedChanged;
  final double nameUidGap;
  final double? tabLabelFontSize;
  final String originTabLabel;
  final String worldTabLabel;
  final bool showCollectionCounts;
  final bool isBlocking;
  final bool isBlocked;

  @override
  State<UserProfileContent> createState() => _UserProfileContentState();
}

class _UserProfileContentState extends State<UserProfileContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final ScrollController _scrollController;
  final ValueNotifier<double> _profilePullOffset = ValueNotifier<double>(0);
  final GlobalKey _profileHeaderKey = GlobalKey();
  bool? _isFollowedOverride;
  int? _followerCountOverride;
  bool _followLoading = false;
  bool _lastCollapsed = false;
  bool _refreshGestureStartedAtPageTop = false;
  int _lastReportedTabIndex = 0;
  double _profileHeaderHeight = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _lastReportedTabIndex = _tabController.index;
    _tabController.addListener(_handleTabControllerChanged);
    _scrollController = ScrollController();
    _scrollController.addListener(_updateCollapsedState);
    widget.reselectionListenable?.addListener(_handleMainNavReselected);
    widget.isActiveListenable?.addListener(_handleTabActivityChanged);
  }

  @override
  void didUpdateWidget(covariant UserProfileContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reselectionListenable != widget.reselectionListenable) {
      oldWidget.reselectionListenable?.removeListener(_handleMainNavReselected);
      widget.reselectionListenable?.addListener(_handleMainNavReselected);
    }
    if (oldWidget.data.uid != widget.data.uid) {
      _isFollowedOverride = null;
      _followerCountOverride = null;
      _followLoading = false;
    }
    if (oldWidget.isActiveListenable != widget.isActiveListenable) {
      oldWidget.isActiveListenable?.removeListener(_handleTabActivityChanged);
      widget.isActiveListenable?.addListener(_handleTabActivityChanged);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabControllerChanged);
    _scrollController.removeListener(_updateCollapsedState);
    widget.reselectionListenable?.removeListener(_handleMainNavReselected);
    widget.isActiveListenable?.removeListener(_handleTabActivityChanged);
    _profilePullOffset.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final isFollowed = _isFollowedOverride ?? data.isFollowed;
    final followerCount = _followerCountOverride ?? data.followerCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureProfileHeader();
      _updateCollapsedState();
    });

    final refresh = widget.onRefresh;
    final scrollView = NestedScrollView(
      controller: _scrollController,
      physics: refresh == null
          ? null
          : const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverToBoxAdapter(
            child: _ProfilePullOffsetTransition(
              offsetListenable: _profilePullOffset,
              child: _buildProfileHeader(data, isFollowed, followerCount),
            ),
          ),
          if (!widget.isBlocking && !widget.isBlocked)
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverPersistentHeader(
                pinned: true,
                delegate: _ProfileTabsHeaderDelegate(
                  pullOffsetListenable: _profilePullOffset,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildCollectionTabs(data),
                  ),
                ),
              ),
            ),
        ];
      },
      body: _buildCollectionBody(data),
    );
    if (refresh == null) return scrollView;

    return NotificationListener<ScrollNotification>(
      onNotification: _handleProfilePullNotification,
      child: KeyedSubtree(
        key: const ValueKey<String>('profile-page-refresh'),
        child: GenesisRefreshIndicator(
          notificationPredicate: _pageRefreshNotificationPredicate,
          onRefresh: refresh,
          child: scrollView,
        ),
      ),
    );
  }

  Widget _buildCollectionTabs(UserProfileData data) {
    Widget buildTabs(int originCount, int worldCount) {
      final labels = [widget.originTabLabel, widget.worldTabLabel];
      return GenesisTabBar(
        controller: _tabController,
        labelColor: Theme.of(context).brightness == Brightness.dark
            ? GenesisColors.darkTextPrimary
            : null,
        unselectedLabelColor: Theme.of(context).brightness == Brightness.dark
            ? GenesisColors.darkTextSecondary
            : null,
        indicatorColor: Theme.of(context).brightness == Brightness.dark
            ? GenesisColors.redPrimary
            : null,
        labels: labels,
        labelWidgets: widget.showCollectionCounts
            ? [
                _ProfileCollectionTabLabel(
                  key: const ValueKey<String>('profile-tab-origin'),
                  label: widget.originTabLabel,
                  count: originCount,
                  countKey: const ValueKey<String>('profile-tab-count-origin'),
                ),
                _ProfileCollectionTabLabel(
                  key: const ValueKey<String>('profile-tab-world'),
                  label: widget.worldTabLabel,
                  count: worldCount,
                  countKey: const ValueKey<String>('profile-tab-count-world'),
                ),
              ]
            : null,
        horizontalPadding: 8,
        labelPadding: widget.showCollectionCounts
            ? const EdgeInsets.only(left: 8, right: 24)
            : const EdgeInsets.symmetric(horizontal: 8),
        labelFontSize: widget.tabLabelFontSize,
        onTap: _reportCollectionTab,
      );
    }

    if (!widget.showCollectionCounts) {
      return buildTabs(data.origins.length, data.worlds.length);
    }

    Widget buildWithWorldCount(int originCount) {
      final worldsListenable = widget.worldsListenable;
      if (worldsListenable == null) {
        return buildTabs(originCount, data.worlds.length);
      }
      return ValueListenableBuilder<
        UserProfileCollectionState<UserProfileWorldItem>
      >(
        valueListenable: worldsListenable,
        builder: (context, state, _) {
          return buildTabs(originCount, state.items.length);
        },
      );
    }

    final originsListenable = widget.originsListenable;
    if (originsListenable == null) {
      return buildWithWorldCount(data.origins.length);
    }
    return ValueListenableBuilder<
      UserProfileCollectionState<UserProfileOriginItem>
    >(
      valueListenable: originsListenable,
      builder: (context, state, _) {
        return buildWithWorldCount(state.items.length);
      },
    );
  }

  Widget _buildCollectionBody(UserProfileData data) {
    if (widget.isBlocking) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: GenesisLoadingIndicator(),
        ),
      );
    }
    if (widget.isBlocked) {
      return Center(
        child: Text(
          'User blocked',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? GenesisColors.darkTextSecondary
                : const Color(0xFF888888),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: TabBarView(
          controller: _tabController,
          physics: const ClampingScrollPhysics(),
          children: [
            _buildCollectionPage(
              index: 0,
              pageKey: const ValueKey<String>('profile-origin-collection-page'),
              child: _OriginProfileCollectionList(
                items: data.origins,
                emptyText: data.isSelf
                    ? 'No Worldo you created yet.'
                    : 'No Worldo yet.',
                isLoading: widget.originsLoading,
                listenable: widget.originsListenable,
                onRefresh: widget.onRefresh == null
                    ? widget.onRefreshOrigins
                    : null,
                sliverMode: false,
                injectNestedOverlap: true,
                alwaysScrollable: widget.onRefresh != null,
                canEditOrigins: data.isSelf,
              ),
            ),
            _buildCollectionPage(
              index: 1,
              pageKey: const ValueKey<String>('profile-world-collection-page'),
              child: _WorldProfileCollectionList(
                items: data.worlds,
                emptyText: data.isSelf
                    ? 'No Worlds you created yet.'
                    : 'No Worlds yet.',
                isLoading: widget.worldsLoading,
                listenable: widget.worldsListenable,
                onRefresh: widget.onRefresh == null
                    ? widget.onRefreshWorlds
                    : null,
                sliverMode: false,
                injectNestedOverlap: true,
                alwaysScrollable: widget.onRefresh != null,
                canDeleteWorlds: data.isSelf,
                onWorldDeleted: widget.onWorldDeleted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionPage({
    required int index,
    required Key pageKey,
    required Widget child,
  }) {
    final animation = _tabController.animation;
    final page = SizedBox.expand(key: pageKey, child: child);
    if (animation == null) return page;

    return AnimatedBuilder(
      animation: animation,
      child: page,
      builder: (context, child) {
        final distanceFromRest = animation.value - index;
        return Transform.translate(
          offset: Offset(-_profileCollectionPageGap * distanceFromRest, 0),
          child: child,
        );
      },
    );
  }

  Widget _buildProfileHeader(
    UserProfileData data,
    bool isFollowed,
    int followerCount,
  ) {
    return KeyedSubtree(
      key: _profileHeaderKey,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(
                  url: data.avatarUrl,
                  name: data.displayName,
                  urlListenable: widget.avatarUrlListenable,
                  nameListenable: widget.displayNameListenable,
                  isUpdating: widget.isUpdatingProfile,
                  updatingListenable: widget.isUpdatingProfileListenable,
                  onEdit: widget.onEditAvatar,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            fit: FlexFit.loose,
                            child: _DisplayNameText(
                              displayName: data.displayName,
                              displayNameListenable:
                                  widget.displayNameListenable,
                            ),
                          ),
                          if (widget.onEditDisplayName != null) ...[
                            const SizedBox(width: 4),
                            _ProfileEditButton(
                              isUpdating: widget.isUpdatingProfile,
                              updatingListenable:
                                  widget.isUpdatingProfileListenable,
                              onTap: widget.onEditDisplayName!,
                            ),
                          ],
                        ],
                      ),
                      if (widget.nameUidGap > 0)
                        SizedBox(height: widget.nameUidGap),
                      CopyableIdLabel(
                        label: 'UID',
                        customTextStyle:
                            Theme.of(context).brightness == Brightness.dark
                            ? CopyableIdLabel.textStyle.copyWith(
                                color: GenesisColors.darkTextTertiary,
                              )
                            : null,
                        customIconColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? GenesisColors.darkTextTertiary
                            : null,
                        value: data.uid,
                        displayValue: data.deleted
                            ? deletedEntityDisplayText
                            : formatUidForDisplay(data.uid),
                        enabled: !data.deleted,
                      ),
                      const SizedBox(height: 12),
                      _buildFollowStats(data, followerCount),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (data.isSelf) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _GemsBalanceEntry(
                stateListenable: widget.gemWalletStateListenable,
              ),
            ),
          ],
          if (!data.isSelf) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ProfileActionButtons(
                isFollowed: isFollowed,
                followLoading: _followLoading,
                onFollowToggle: () => _toggleFollow(isFollowed),
                onMessage: () => unawaited(_openMessages()),
              ),
            ),
          ],
          const SizedBox(height: 5),
        ],
      ),
    );
  }

  Widget _buildFollowStats(UserProfileData data, int followerCount) {
    return KeyedSubtree(
      key: const ValueKey<String>('user-profile-follow-stats'),
      child: _FollowStats(
        followingCount: data.followingCount,
        followerCount: followerCount,
        onFollowingTap: () => _openFollows(0),
        onFollowersTap: () => _openFollows(1),
      ),
    );
  }

  void _measureProfileHeader() {
    final context = _profileHeaderKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    _profileHeaderHeight = renderObject.size.height;
  }

  void _updateCollapsedState() {
    if (!_scrollController.hasClients) return;
    final threshold = _profileHeaderHeight > 0 ? _profileHeaderHeight - 1 : 120;
    final collapsed = _scrollController.offset >= threshold;
    if (collapsed == _lastCollapsed) return;
    _lastCollapsed = collapsed;
    widget.onCollapsedChanged?.call(collapsed);
  }

  bool _pageRefreshNotificationPredicate(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollStartNotification) {
      _refreshGestureStartedAtPageTop =
          (!_scrollController.hasClients || _scrollController.offset <= 0.5) &&
          notification.metrics.extentBefore <= 0.5;
    }
    final shouldHandle = _refreshGestureStartedAtPageTop;
    if (notification is ScrollEndNotification) {
      _refreshGestureStartedAtPageTop = false;
    }
    return shouldHandle;
  }

  bool _handleProfilePullNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final offset =
        (notification.metrics.minScrollExtent - notification.metrics.pixels)
            .clamp(0.0, double.infinity)
            .toDouble();
    if ((_profilePullOffset.value - offset).abs() > 0.1) {
      _profilePullOffset.value = offset;
    }
    return false;
  }

  void _handleTabActivityChanged() {
    if (widget.isActiveListenable?.value != false ||
        !_scrollController.hasClients) {
      return;
    }
    // Bottom-tab departure resets both nested scroll regions synchronously.
    // Detail routes do not change tab activity, so their return keeps position.
    _scrollController.jumpTo(_scrollController.position.minScrollExtent);
  }

  void _handleMainNavReselected() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels <= position.minScrollExtent) return;
    unawaited(
      position.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _handleTabControllerChanged() {
    if (_tabController.indexIsChanging) return;
    _reportCollectionTab(_tabController.index);
  }

  void _reportCollectionTab(int index) {
    if (_lastReportedTabIndex == index) return;
    _lastReportedTabIndex = index;
    widget.onCollectionTabChanged?.call(index);
  }

  Future<void> _toggleFollow(bool isFollowed) async {
    if (_followLoading) return;
    final uid = widget.data.uid.trim();
    if (uid.isEmpty) return;
    if (!await ensureGenesisLogin(context)) return;
    if (!mounted) return;

    setState(() => _followLoading = true);
    try {
      if (isFollowed) {
        await AppServicesScope.read(context).api.v1.follow.unfollow(uid: uid);
      } else {
        await AppServicesScope.read(context).api.v1.follow.follow(uid: uid);
      }
      if (!mounted) return;
      final nextFollowed = !isFollowed;
      final currentFollowerCount =
          _followerCountOverride ?? widget.data.followerCount;
      setState(() {
        _isFollowedOverride = nextFollowed;
        _followerCountOverride = nextFollowed
            ? currentFollowerCount + 1
            : _decrementCount(currentFollowerCount);
        _followLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _followLoading = false);
      showGenesisToast(context, apiErrorMessage(error));
    }
  }

  Future<void> _openMessages() async {
    if (!await ensureGenesisLogin(context)) return;
    if (!mounted) return;
    Navigator.of(context).pushNamed(
      RouteNames.chat,
      arguments: {
        'peer_uid': widget.data.uid,
        'peer_name': _currentDisplayName,
        'peer_avatar': widget.data.avatarUrl,
      },
    );
  }

  void _openFollows(int initialIndex) {
    Navigator.of(context).pushNamed(
      RouteNames.follows,
      arguments: {
        'uid': widget.data.uid,
        'title': _currentDisplayName,
        'initialIndex': initialIndex,
      },
    );
  }

  String get _currentDisplayName {
    final listenableName = widget.displayNameListenable?.value.trim() ?? '';
    if (listenableName.isNotEmpty) return listenableName;
    return widget.data.displayName;
  }

  int _decrementCount(int value) {
    return value > 0 ? value - 1 : 0;
  }
}

class _GemsBalanceEntry extends StatelessWidget {
  const _GemsBalanceEntry({this.stateListenable});

  final ValueListenable<GemWalletState>? stateListenable;

  @override
  Widget build(BuildContext context) {
    final listenable = stateListenable;
    if (listenable == null) return _buildEntry(context, null);
    return ValueListenableBuilder<GemWalletState>(
      valueListenable: listenable,
      builder: (context, state, _) => _buildEntry(context, state.balanceCent),
    );
  }

  Widget _buildEntry(BuildContext context, int? balanceCent) {
    return GestureDetector(
      key: const ValueKey('user-profile-gems-entry'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pushNamed(RouteNames.gemWallet),
      child: Container(
        key: const ValueKey('user-profile-gems-background'),
        height: 64,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF7F1021), Color(0xFFB8172E)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -16,
              right: 54,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.18,
                  child: SvgPicture.asset(
                    gemStackIconAsset,
                    key: const ValueKey('user-profile-gems-pattern'),
                    width: 112,
                    height: 92,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Balance',
                          style: TextStyle(
                            fontSize: 12,
                            height: 14 / 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFFD4DA),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            SizedBox(
                              key: const ValueKey('user-profile-gem-icon'),
                              width: 16,
                              height: 24,
                              child: SvgPicture.asset(
                                gemIconAsset,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Flexible(
                                    child: Text(
                                      formatGemCent(balanceCent ?? 0),
                                      key: const ValueKey(
                                        'user-profile-gems-balance',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        height: 22 / 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Gems',
                                    key: ValueKey('user-profile-gems-unit'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 14 / 11,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFFFFD4DA),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    key: const ValueKey('user-profile-gems-top-up'),
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: GenesisColors.brand,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Top Up',
                      style: TextStyle(
                        fontSize: 13,
                        height: 16 / 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCollectionTabLabel extends StatelessWidget {
  const _ProfileCollectionTabLabel({
    super.key,
    required this.label,
    required this.count,
    required this.countKey,
  });

  final String label;
  final int count;
  final Key countKey;

  @override
  Widget build(BuildContext context) {
    final labelStyle = DefaultTextStyle.of(context).style;
    final countStyle = labelStyle.copyWith(fontWeight: FontWeight.w400);
    final labelMetrics = _measure(context, label, labelStyle);
    final countText = '$count';
    final countMetrics = _measure(context, countText, countStyle);
    return SizedBox(
      width: labelMetrics.size.width,
      height: labelMetrics.size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: Text(label, maxLines: 1)),
          Positioned(
            left: labelMetrics.size.width + 4,
            top: labelMetrics.baseline - countMetrics.baseline,
            child: KeyedSubtree(
              key: countKey,
              child: Text(countText, maxLines: 1, style: countStyle),
            ),
          ),
        ],
      ),
    );
  }

  _ProfileTabTextMetrics _measure(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return _ProfileTabTextMetrics(
      size: painter.size,
      baseline: painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      ),
    );
  }
}

class _ProfileTabTextMetrics {
  const _ProfileTabTextMetrics({required this.size, required this.baseline});

  final Size size;
  final double baseline;
}

class _ProfilePullOffsetTransition extends StatelessWidget {
  const _ProfilePullOffsetTransition({
    required this.offsetListenable,
    required this.child,
  });

  final ValueListenable<double> offsetListenable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: offsetListenable,
      child: child,
      builder: (context, offset, child) {
        return Transform.translate(offset: Offset(0, offset), child: child);
      },
    );
  }
}

class _ProfileTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ProfileTabsHeaderDelegate({
    required this.pullOffsetListenable,
    required this.child,
  });

  static const double _height = 5 + genesisTabHeight;

  final ValueListenable<double> pullOffsetListenable;
  final Widget child;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _ProfilePullOffsetTransition(
      offsetListenable: pullOffsetListenable,
      child: ColoredBox(
        color: Theme.of(context).brightness == Brightness.dark
            ? GenesisColors.darkBackground
            : Colors.white,
        child: Column(
          children: [
            const SizedBox(height: 5),
            SizedBox(height: genesisTabHeight, child: child),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ProfileTabsHeaderDelegate oldDelegate) {
    return child != oldDelegate.child ||
        pullOffsetListenable != oldDelegate.pullOffsetListenable;
  }
}

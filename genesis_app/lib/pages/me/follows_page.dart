import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/components/genesis_refresh_indicator.dart';
import '../../app/bootstrap/app_services_scope.dart';
import '../../components/auth/login_guard.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../components/me/genesis_follow_user_list_tile.dart';
import '../../components/page_header.dart';
import '../../network/api_exception.dart';
import '../../network/genesis_api.dart';
import '../../network/json_utils.dart';
import '../../platform/session/session_revision_subscription.dart';
import '../../ui/components/secend_tabs.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/system/genesis_system_ui.dart';
import '../../utils/api_error_message.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/entity_deleted.dart';
import '../../utils/stat_count_formatter.dart';

class FollowsPage extends StatefulWidget {
  const FollowsPage({
    super.key,
    required this.uid,
    this.initialIndex = 0,
    this.initialTitle,
  });

  final String uid;
  final int initialIndex;
  final String? initialTitle;

  @override
  State<FollowsPage> createState() => _FollowsPageState();
}

class _FollowsPageState extends State<FollowsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final SessionRevisionSubscription _sessionRevision;
  Future<List<_FollowUserItem>>? _followingFuture;
  Future<List<_FollowUserItem>>? _followersFuture;
  final Set<String> _loadingUids = <String>{};
  final Map<String, bool> _followStateOverrides = <String, bool>{};
  String _title = 'Follows';
  bool _canToggleFollow = false;
  bool _didLoad = false;
  int? _followingTotal;
  int? _followersTotal;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _title = _cleanTitle(widget.initialTitle) ?? _title;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 1),
    );
    _sessionRevision = SessionRevisionSubscription(_handleSessionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sessionRevision.bind(AppServicesScope.of(context).sessionRevision);
    if (_didLoad) return;
    _didLoad = true;
    _reloadForSession();
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    _reloadForSession();
  }

  void _reloadForSession() {
    final generation = ++_loadGeneration;
    final following = _startUsersLoad(_FollowListType.following, generation);
    final followers = _startUsersLoad(_FollowListType.followers, generation);
    setState(() {
      _loadingUids.clear();
      _followStateOverrides.clear();
      _followingTotal = null;
      _followersTotal = null;
      _canToggleFollow = false;
      _title = _cleanTitle(widget.initialTitle) ?? 'Follows';
      _followingFuture = following;
      _followersFuture = followers;
    });
    unawaited(_loadCachedTotals(generation));
    unawaited(_loadCanToggleFollow(generation));
    if (_cleanTitle(widget.initialTitle) == null) {
      unawaited(_loadTitle(generation));
    }
  }

  Future<void> _loadCanToggleFollow(int generation) async {
    final uid = widget.uid.trim();
    if (uid.isEmpty) return;
    final localUid =
        (await AppServicesScope.read(context).sessionStore.readUid())?.trim() ??
        '';
    if (!mounted || generation != _loadGeneration) return;
    setState(() => _canToggleFollow = localUid.isNotEmpty && localUid == uid);
  }

  @override
  void dispose() {
    _sessionRevision.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedTotals(int generation) async {
    final uid = widget.uid.trim();
    if (uid.isEmpty) return;
    final sessionStore = AppServicesScope.read(context).sessionStore;
    final cachedUser = await sessionStore.readUserInfo();
    if (cachedUser == null || cachedUser.isEmpty) return;

    final localUid = (await sessionStore.readUid())?.trim() ?? '';
    final cachedUid = _mapString(cachedUser, 'uid') ?? '';
    final matchesCurrentUser =
        (localUid.isNotEmpty && localUid == uid) ||
        (cachedUid.isNotEmpty && cachedUid == uid);
    if (!matchesCurrentUser || !mounted || generation != _loadGeneration) {
      return;
    }

    setState(() {
      _followingTotal =
          _mapIntOrNull(cachedUser, 'following_cnt') ?? _followingTotal;
      _followersTotal =
          _mapIntOrNull(cachedUser, 'follower_cnt') ?? _followersTotal;
    });
  }

  Future<void> _loadTitle(int generation) async {
    final uid = widget.uid.trim();
    if (uid.isEmpty) return;
    try {
      final info = await AppServicesScope.read(
        context,
      ).api.v1.user.info(uid: uid);
      final user = _asMap(info['user']);
      final title =
          _mapString(user, 'name') ??
          _mapString(user, 'display_name') ??
          _mapString(user, 'nickname');
      if (!mounted || generation != _loadGeneration || title == null) return;
      setState(() => _title = title);
    } catch (_) {}
  }

  Future<List<_FollowUserItem>> _loadUsers(
    _FollowListType type,
    int generation,
  ) async {
    final uid = widget.uid.trim();
    if (uid.isEmpty) return const <_FollowUserItem>[];

    final followApi = AppServicesScope.read(context).api.v1.follow;
    final response = type == _FollowListType.following
        ? await followApi.following(uid: uid, pn: 1, rn: 50)
        : await followApi.followers(uid: uid, pn: 1, rn: 50);
    final rawList = _asList(response['list']);
    final items = rawList
        .map((entry) => _FollowUserItem.fromJson(entry, type: type))
        .where((item) => item.uid.trim().isNotEmpty)
        .toList(growable: false);
    final total = _mapInt(response, 'total', fallback: items.length);
    if (mounted && generation == _loadGeneration) {
      setState(() {
        if (type == _FollowListType.following) {
          _followingTotal = total;
        } else {
          _followersTotal = total;
        }
      });
    }
    return items;
  }

  Future<List<_FollowUserItem>> _startUsersLoad(
    _FollowListType type,
    int generation,
  ) {
    final load = _loadUsers(type, generation);
    // Both tab requests start before TabBarView necessarily mounts each
    // FutureBuilder. Attach an error handler immediately; the original future
    // still retains its error for the owning FutureBuilder to render.
    load.ignore();
    return load;
  }

  Future<void> _toggleFollow(_FollowUserItem item, bool isFollowed) async {
    final uid = item.uid.trim();
    if (uid.isEmpty || _loadingUids.contains(uid)) return;
    if (!await ensureGenesisLogin(context)) return;
    if (!mounted) return;
    final generation = _loadGeneration;

    setState(() => _loadingUids.add(uid));
    try {
      final api = AppServicesScope.read(context).api.v1.follow;
      if (isFollowed) {
        await api.unfollow(uid: uid);
      } else {
        await api.follow(uid: uid);
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        final nextFollowed = !isFollowed;
        _followStateOverrides[uid] = nextFollowed;
        _loadingUids.remove(uid);
        final followingTotal = _followingTotal;
        if (followingTotal != null) {
          _followingTotal = nextFollowed
              ? followingTotal + 1
              : _decrementCount(followingTotal);
        }
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadingUids.remove(uid));
      showGenesisToast(
        context,
        apiErrorMessage(error),
        brightness: Brightness.dark,
      );
    }
  }

  Future<void> _refresh(_FollowListType type) async {
    late final Future<List<_FollowUserItem>> refresh;
    setState(() {
      if (type == _FollowListType.following) {
        refresh = _followingFuture = _startUsersLoad(type, _loadGeneration);
      } else {
        refresh = _followersFuture = _startUsersLoad(type, _loadGeneration);
      }
    });
    try {
      await refresh;
    } on ApiException {
      // FutureBuilder renders the failure. Keep Retry/RefreshIndicator from
      // forwarding an expected request error to PlatformDispatcher.
    }
  }

  @override
  Widget build(BuildContext context) {
    final followingCount = formatStatCount(_followingTotal ?? 0);
    final followersCount = formatStatCount(_followersTotal ?? 0);
    return GenesisDarkTheme(
      child: Scaffold(
        backgroundColor: GenesisColors.darkBackground,
        appBar: GenesisBackAppBar(
          pageName: _title,
          backgroundColor: GenesisColors.darkBackground,
          foregroundColor: GenesisColors.darkTextPrimary,
          systemOverlayStyle: kGenesisLightSystemUiOverlayStyle,
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // const SizedBox(height: 12),
              SecendTabs(
                controller: _tabController,
                labelColor: GenesisColors.darkTextPrimary,
                unselectedLabelColor: GenesisColors.darkTextSecondary,
                indicatorColor: GenesisColors.redPrimary,
                labels: [
                  '$followingCount Following',
                  '$followersCount Followers',
                ],
                // horizontalPadding: 28,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              Expanded(
                child: TabBarView(
                  key: ValueKey<String>('follows-session-$_loadGeneration'),
                  controller: _tabController,
                  children: [
                    _FollowUsersPane(
                      future:
                          _followingFuture ??
                          Future.value(const <_FollowUserItem>[]),
                      emptyText: 'No following yet.',
                      defaultFollowed: true,
                      loadingUids: _loadingUids,
                      followStateOverrides: _followStateOverrides,
                      canToggleFollow: _canToggleFollow,
                      onRefresh: () => _refresh(_FollowListType.following),
                      onToggleFollow: _toggleFollow,
                    ),
                    _FollowUsersPane(
                      future:
                          _followersFuture ??
                          Future.value(const <_FollowUserItem>[]),
                      emptyText: 'No followers yet.',
                      defaultFollowed: false,
                      loadingUids: _loadingUids,
                      followStateOverrides: _followStateOverrides,
                      canToggleFollow: _canToggleFollow,
                      onRefresh: () => _refresh(_FollowListType.followers),
                      onToggleFollow: _toggleFollow,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowUsersPane extends StatelessWidget {
  const _FollowUsersPane({
    required this.future,
    required this.emptyText,
    required this.defaultFollowed,
    required this.loadingUids,
    required this.followStateOverrides,
    required this.canToggleFollow,
    required this.onRefresh,
    required this.onToggleFollow,
  });

  final Future<List<_FollowUserItem>> future;
  final String emptyText;
  final bool defaultFollowed;
  final Set<String> loadingUids;
  final Map<String, bool> followStateOverrides;
  final bool canToggleFollow;
  final Future<void> Function() onRefresh;
  final Future<void> Function(_FollowUserItem item, bool isFollowed)
  onToggleFollow;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_FollowUserItem>>(
      future: future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <_FollowUserItem>[];
        if (snapshot.connectionState == ConnectionState.waiting &&
            items.isEmpty) {
          return const Center(child: GenesisLoadingIndicator());
        }
        if (snapshot.hasError && items.isEmpty) {
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
                  onPressed: onRefresh,
                  style: FilledButton.styleFrom(
                    backgroundColor: GenesisColors.darkFaintFill,
                    foregroundColor: GenesisColors.darkTextPrimary,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (items.isEmpty) {
          return GenesisRefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.45,
                  child: Center(
                    child: Text(
                      emptyText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: GenesisColors.darkTextSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return GenesisRefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            // ignore: deprecated_member_use
            cacheExtent: 0,
            itemExtent: GenesisFollowUserListTile.itemExtent,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final isFollowed =
                  followStateOverrides[item.uid] ??
                  (defaultFollowed || item.isFollowed);
              return GenesisFollowUserListTile(
                uid: item.uid,
                displayName: item.displayName,
                avatarUrl: item.avatarUrl,
                deleted: item.deleted,
                isFollowed: isFollowed,
                isLoading: loadingUids.contains(item.uid),
                onToggleFollow: canToggleFollow
                    ? () => onToggleFollow(item, isFollowed)
                    : null,
              );
            },
          ),
        );
      },
    );
  }
}

enum _FollowListType { following, followers }

class _FollowUserItem {
  const _FollowUserItem({
    required this.uid,
    required this.displayName,
    required this.avatarUrl,
    this.deleted = false,
    required this.isFollowed,
  });

  final String uid;
  final String displayName;
  final String avatarUrl;
  final bool deleted;
  final bool isFollowed;

  factory _FollowUserItem.fromJson(
    Map<String, dynamic> json, {
    required _FollowListType type,
  }) {
    final user = _asMap(json['user']).isEmpty ? json : _asMap(json['user']);
    final relation = _asMap(json['relation']);
    final uid =
        _mapString(user, 'uid') ??
        _mapString(user, 'target_user_id') ??
        _mapString(relation, 'target_user_id') ??
        '';
    final displayName =
        _mapString(user, 'name') ??
        _mapString(user, 'display_name') ??
        _mapString(user, 'nickname') ??
        formatUidForDisplay(uid);
    final avatar = asResolvedImageUrl(
      user['avatar'],
      resolveAssetUrl,
      fallback: user['avatar_url'],
    );
    final isFollowed =
        type == _FollowListType.following ||
        _mapBool(relation, 'i_followed') ||
        _mapBool(relation, 'is_followed') ||
        _mapBool(user, 'i_followed') ||
        _mapBool(user, 'is_followed');
    return _FollowUserItem(
      uid: uid,
      displayName: formatUidForDisplay(displayName, fallback: 'User'),
      avatarUrl: avatar,
      deleted: entityDeleted(user['deleted']),
      isFollowed: isFollowed,
    );
  }
}

String? _cleanTitle(String? title) {
  final value = title?.trim() ?? '';
  return value.isEmpty ? null : value;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry('$key', value));
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _asList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value.map(_asMap).toList(growable: false);
}

String? _mapString(Map<dynamic, dynamic> map, String key) {
  final value = map[key]?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

int _mapInt(Map<dynamic, dynamic> map, String key, {required int fallback}) {
  return _mapIntOrNull(map, key) ?? fallback;
}

int? _mapIntOrNull(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

bool _mapBool(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

int _decrementCount(int value) {
  return value > 0 ? value - 1 : 0;
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/theme/genesis_dark_theme.dart';
import '../../ui/system/genesis_system_ui.dart';
import '../../ui/components/genesis_refresh_indicator.dart';
import '../../app/bootstrap/app_services_scope.dart';
import '../../components/auth/login_guard.dart';
import '../../components/common/genesis_action_box.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../components/discuss/origin_discuss_list.dart';
import '../../components/me/genesis_follow_user_list_tile.dart';
import '../../components/page_header.dart';
import '../../network/json_utils.dart';
import '../../platform/session/session_revision_subscription.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../utils/api_error_message.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/entity_deleted.dart';
import '../../utils/genesis_timestamp_formatter.dart';
import '../world/world_page_result.dart';

part 'message_notification_rows.dart';
part 'message_notification_model.dart';
part 'message_join_request_dialog.dart';

class MessageCategoryListPage extends StatefulWidget {
  const MessageCategoryListPage({
    super.key,
    required this.title,
    required this.block,
    required this.emptyText,
    this.onNotificationsRead,
  });

  final String title;
  final String block;
  final String emptyText;
  final Future<void> Function()? onNotificationsRead;

  @override
  State<MessageCategoryListPage> createState() =>
      _MessageCategoryListPageState();
}

class _MessageCategoryListPageState extends State<MessageCategoryListPage> {
  static const _pageSize = 20;

  final _scrollController = ScrollController();
  late final SessionRevisionSubscription _sessionRevision;
  final _items = <_NotificationItem>[];
  final _initialUnreadIds = <String>{};
  final _loadingFollowUids = <String>{};
  final _followStateOverrides = <String, bool>{};
  var _page = 1;
  var _total = 0;
  var _loading = true;
  var _loadingMore = false;
  var _refreshing = false;
  Object? _error;
  var _loadGeneration = 0;

  bool get _hasMore => _items.length < _total;
  bool get _isCommentsBlock => widget.block == 'interaction';

  @override
  void initState() {
    super.initState();
    _sessionRevision = SessionRevisionSubscription(_handleSessionChanged);
    _scrollController.addListener(_onScroll);
    unawaited(_loadFirstPage());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sessionRevision.bind(AppServicesScope.of(context).sessionRevision);
  }

  @override
  void dispose() {
    _sessionRevision.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore) return;
    if (!_hasMore) return;
    if (_scrollController.position.extentAfter < 600) {
      unawaited(_loadNextPage());
    }
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    _loadGeneration += 1;
    setState(() {
      _items.clear();
      _initialUnreadIds.clear();
      _loadingFollowUids.clear();
      _followStateOverrides.clear();
      _page = 1;
      _total = 0;
      _loading = true;
      _loadingMore = false;
      _refreshing = false;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
    unawaited(_loadFirstPage());
  }

  Future<void> _markCategoryRead(int generation) async {
    try {
      await AppServicesScope.read(
        context,
      ).api.v1.messages.markNotificationsRead(block: widget.block);
      if (!mounted || generation != _loadGeneration) return;
      if (_items.any((item) => !item.isRead)) {
        setState(() {
          for (var index = 0; index < _items.length; index += 1) {
            _items[index] = _items[index].copyWith(isRead: true);
          }
        });
      }
      await widget.onNotificationsRead?.call();
    } catch (error, stackTrace) {
      debugPrint(
        '[Messages] markNotificationsRead failed block=${widget.block}: $error',
      );
      debugPrint('[Messages] markNotificationsRead stacktrace:\n$stackTrace');
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = _items.isEmpty;
      _refreshing = true;
      _loadingMore = false;
      _error = null;
    });
    await _loadPage(1, replace: true);
  }

  Future<void> _loadNextPage() async {
    if (!_hasMore || _refreshing) return;
    setState(() => _loadingMore = true);
    await _loadPage(_page + 1, replace: false);
  }

  Future<void> _loadPage(int page, {required bool replace}) async {
    final generation = _loadGeneration;
    try {
      final data = await AppServicesScope.read(context).api.v1.messages
          .notifications(block: widget.block, pn: page, rn: _pageSize);
      final rawItems = asJsonList(data['list']);
      final items = rawItems
          .map((item) => _NotificationItem.fromJson(asJsonMap(item)))
          .toList(growable: false);
      if (!mounted || generation != _loadGeneration) return;
      if (replace) {
        _initialUnreadIds
          ..clear()
          ..addAll(items.where((item) => !item.isRead).map((item) => item.id));
      }
      setState(() {
        if (replace) {
          _items
            ..clear()
            ..addAll(items);
        } else {
          _items.addAll(items);
        }
        _page = page;
        _total = asInt(data['total'], fallback: _items.length);
        _loading = false;
        _loadingMore = false;
        _refreshing = false;
        _error = null;
      });
      if (replace) unawaited(_markCategoryRead(generation));
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _refreshing = false;
        _error = error;
      });
    }
  }

  Future<void> _openJoinRequestActions(_NotificationItem item) async {
    if (item.joinRequestApprovalStatus != _JoinRequestApprovalStatus.pending) {
      await _openJoinRequestView(item);
      return;
    }

    final action = await showGenesisActionBox<_JoinRequestAction>(
      context: context,
      title: 'Join request',
      content: _JoinRequestDialogContent(
        item: item,
        statusOnly: false,
        onOpenUser: item.senderDeleted
            ? null
            : () => _openUserFromDialog(item.senderUid),
        onOpenWorld: item.worldDeleted
            ? null
            : () => unawaited(_openWorldFromDialog(item.bizId)),
      ),
      actions: const [
        GenesisActionBoxAction<_JoinRequestAction>(
          label: 'Approve',
          value: _JoinRequestAction.approve,
        ),
        GenesisActionBoxAction<_JoinRequestAction>(
          label: 'Reject',
          value: _JoinRequestAction.reject,
          color: GenesisColors.darkTextPrimary,
        ),
      ],
    );
    if (action == null || !mounted) return;
    await _reviewJoinRequest(item, action);
  }

  Future<void> _openJoinRequestView(_NotificationItem item) {
    return showGenesisActionBox<void>(
      context: context,
      title: 'Join request',
      content: _JoinRequestDialogContent(
        item: item,
        statusOnly: true,
        onOpenUser: item.senderDeleted
            ? null
            : () => _openUserFromDialog(item.senderUid),
        onOpenWorld: item.worldDeleted
            ? null
            : () => _openWorldFromDialog(item.bizId),
      ),
      actions: const <GenesisActionBoxAction<void>>[],
      cancelLabel: 'OK',
      detachCancel: true,
    );
  }

  void _openUserFromDialog(String uid) {
    final cleanUid = uid.trim();
    Navigator.of(context, rootNavigator: true).pop();
    if (cleanUid.isEmpty || !mounted) return;
    unawaited(
      Navigator.of(
        context,
      ).pushNamed(RouteNames.userInfo, arguments: {'uid': cleanUid}),
    );
  }

  Future<void> _openWorldFromDialog(String wid) async {
    final cleanWid = wid.trim();
    Navigator.of(context, rootNavigator: true).pop();
    if (cleanWid.isEmpty || !mounted) return;
    final result = await Navigator.of(context).pushNamed<WorldPageResult>(
      RouteNames.world,
      arguments: {'wid': cleanWid},
    );
    if (!mounted || result == null) return;
    _markWorldDeleted(result.deletedWorldId);
  }

  Future<void> _reviewJoinRequest(
    _NotificationItem item,
    _JoinRequestAction action,
  ) async {
    if (!await ensureGenesisLogin(context)) return;
    if (!mounted) return;
    final applyId = item.applyId.trim();
    if (applyId.isEmpty) {
      showGenesisToast(context, 'Review failed', brightness: Brightness.dark);
      return;
    }

    try {
      await AppServicesScope.read(
        context,
      ).api.v1.world.reviewApply(applyId: applyId, action: action.apiValue);
      if (!mounted) return;
      setState(() {
        final index = _items.indexWhere((candidate) => candidate.id == item.id);
        if (index == -1) return;
        _items[index] = _items[index].copyWith(
          isRead: true,
          approvalStatus: action.approvalStatus,
        );
      });
      showGenesisToast(
        context,
        action.successText,
        brightness: Brightness.dark,
      );
    } catch (_) {
      if (!mounted) return;
      showGenesisToast(context, 'Review failed', brightness: Brightness.dark);
    }
  }

  Future<void> _toggleFollow(_NotificationItem item, bool isFollowed) async {
    final uid = item.followUserUid.trim();
    if (item.senderDeleted || uid.isEmpty || _loadingFollowUids.contains(uid)) {
      return;
    }
    if (!await ensureGenesisLogin(context)) return;
    if (!mounted) return;
    setState(() => _loadingFollowUids.add(uid));
    try {
      final api = AppServicesScope.read(context).api.v1.follow;
      if (isFollowed) {
        await api.unfollow(uid: uid);
      } else {
        await api.follow(uid: uid);
      }
      if (!mounted) return;
      setState(() {
        _followStateOverrides[uid] = !isFollowed;
        _loadingFollowUids.remove(uid);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingFollowUids.remove(uid));
      showGenesisToast(
        context,
        apiErrorMessage(error),
        brightness: Brightness.dark,
      );
    }
  }

  void _openNotification(_NotificationItem item) {
    if (item.isJoinRequest) {
      unawaited(_openJoinRequestActions(item));
      return;
    }
    if (item.isJoinRequestReview) {
      if (!item.worldDeleted) unawaited(_openWorld(item.bizId));
      return;
    }
    if (item.isDiscussNotification) {
      if (item.discussSourceDeleted) return;
      Navigator.of(context).pushNamed(
        RouteNames.postDetail,
        arguments: {'item': item.toDiscussListItem()},
      );
    }
  }

  Future<void> _openWorld(String wid) async {
    final cleanWid = wid.trim();
    if (cleanWid.isEmpty) return;
    final result = await Navigator.of(context).pushNamed<WorldPageResult>(
      RouteNames.world,
      arguments: {'wid': cleanWid},
    );
    if (!mounted || result == null) return;
    _markWorldDeleted(result.deletedWorldId);
  }

  void _markWorldDeleted(String rawWorldId) {
    final worldId = rawWorldId.trim();
    if (!mounted || worldId.isEmpty) return;
    setState(() {
      for (var index = 0; index < _items.length; index += 1) {
        final item = _items[index];
        if (item.bizId.trim() != worldId || item.worldDeleted) continue;
        _items[index] = item.copyWith(worldDeleted: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GenesisDarkTheme(
      child: Scaffold(
        backgroundColor: GenesisColors.darkBackground,
        appBar: GenesisBackAppBar(
          pageName: widget.title,
          backgroundColor: GenesisColors.darkBackground,
          foregroundColor: GenesisColors.darkTextPrimary,
          systemOverlayStyle: kGenesisLightSystemUiOverlayStyle,
        ),
        body: GenesisRefreshIndicator(
          onRefresh: _loadFirstPage,
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: GenesisLoadingIndicator(strokeWidth: 4));
    }

    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.3),
          const Center(
            child: Text(
              'Failed to load messages.',
              style: TextStyle(
                color: GenesisColors.darkTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.3),
          Center(
            child: Text(
              widget.emptyText,
              style: const TextStyle(
                color: GenesisColors.darkTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: 18 + GenesisSafeAreaInsets.bottom(context),
      ),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, index) {
        if (index < _items.length && _items[index].isFollowNotification) {
          return const SizedBox.shrink();
        }
        return const SizedBox(height: 24);
      },
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: GenesisLoadingIndicator(strokeWidth: 4)),
          );
        }
        final item = _items[index];
        final showUnreadDot = _initialUnreadIds.contains(item.id);
        if (_isCommentsBlock) {
          return _CommentNotificationRow(
            key: ValueKey(item.id),
            item: item,
            showUnreadDot: showUnreadDot,
            onTap: () => _openNotification(item),
          );
        }
        return _NotificationListItem(
          key: ValueKey(item.id),
          item: item,
          showUnreadDot: showUnreadDot,
          followIsLoading: _loadingFollowUids.contains(item.followUserUid),
          followStateOverride: _followStateOverrides[item.followUserUid],
          onTap: () => _openNotification(item),
          onToggleFollow: (isFollowed) => _toggleFollow(item, isFollowed),
        );
      },
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ui/theme/genesis_dark_theme.dart';
import '../../ui/components/genesis_refresh_indicator.dart';
import '../../app/bootstrap/app_services_scope.dart';
import '../../app/bootstrap/polling_scheduler.dart';
import '../../components/common/genesis_timestamp_text.dart';
import '../../components/page_header.dart';
import '../../network/api_client.dart';
import '../../network/direct_message_conversation_store.dart';
import '../../network/models/unread_summary.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_avatar.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../ui/components/genesis_unread_badge.dart';
import '../../ui/tokens/genesis_avatar_radii.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/genesis_image_resource.dart';
import 'message_category_list_page.dart';

@visibleForTesting
String resolvePrivateChatAvatarUrl({
  required String avatarUrl,
  required double devicePixelRatio,
  double logicalSize = 48,
}) {
  final source = avatarUrl.trim();
  if (source.isEmpty) return '';
  final resized = resizeGenesisImageUrl(
    source,
    logicalWidth: logicalSize,
    devicePixelRatio: devicePixelRatio,
  );
  return resized.isEmpty ? source : resized;
}

class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
    this.unreadSummary = UnreadSummary.zero,
    this.onMessagesDataRefresh,
    this.isActiveListenable,
    this.reselectionListenable,
    this.nowProvider,
  });

  final UnreadSummary unreadSummary;
  final Future<void> Function()? onMessagesDataRefresh;
  final ValueListenable<bool>? isActiveListenable;
  final ValueListenable<int>? reselectionListenable;
  @visibleForTesting
  final DateTime Function()? nowProvider;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _scrollController = ScrollController();
  GenesisPollingScheduler? _conversationPoller;
  Timer? _timeRefreshTimer;
  late final DirectMessageConversationStore _conversationStore;
  late DateTime _timeLabelNow;
  bool _loadedLocalConversations = false;
  bool _syncingConversations = false;

  @override
  void initState() {
    super.initState();
    _conversationStore = AppServicesScope.read(
      context,
    ).directMessageConversations;
    _timeLabelNow = _now();
    widget.isActiveListenable?.addListener(_handleActiveChanged);
    widget.reselectionListenable?.addListener(_handleMainNavReselected);
    _timeRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _refreshTimeLabels();
    });
    unawaited(_bootstrapConversations());
    if (widget.onMessagesDataRefresh == null) {
      _conversationPoller = GenesisPollingScheduler(
        interval: const Duration(seconds: 30),
        onTick: () =>
            _syncConversations(tracePolicy: ApiRequestTracePolicy.excluded),
      )..start(immediately: false);
    }
  }

  @override
  void didUpdateWidget(covariant MessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActiveListenable != widget.isActiveListenable) {
      oldWidget.isActiveListenable?.removeListener(_handleActiveChanged);
      widget.isActiveListenable?.addListener(_handleActiveChanged);
      if (_isActive) _refreshTimeLabels();
    }
    if (oldWidget.reselectionListenable != widget.reselectionListenable) {
      oldWidget.reselectionListenable?.removeListener(_handleMainNavReselected);
      widget.reselectionListenable?.addListener(_handleMainNavReselected);
    }
  }

  @override
  void dispose() {
    widget.isActiveListenable?.removeListener(_handleActiveChanged);
    widget.reselectionListenable?.removeListener(_handleMainNavReselected);
    _conversationPoller?.stop();
    _timeRefreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isActive => widget.isActiveListenable?.value ?? true;

  void _handleActiveChanged() {
    if (_isActive) _refreshTimeLabels();
  }

  void _handleMainNavReselected() {
    if (!_isActive || !_scrollController.hasClients) return;
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

  void _refreshTimeLabels() {
    if (!mounted || !_isActive) return;
    setState(() => _timeLabelNow = _now());
  }

  DateTime _now() => widget.nowProvider?.call() ?? DateTime.now();

  Future<void> _bootstrapConversations() async {
    try {
      await _conversationStore.loadFromDb();
      if (!mounted) return;
      setState(() => _loadedLocalConversations = true);
      if (widget.onMessagesDataRefresh == null) {
        await _syncConversations();
      }
    } catch (error, stackTrace) {
      debugPrint('[Messages][DM] bootstrap failed: $error');
      debugPrint('[Messages][DM] stacktrace:\n$stackTrace');
      if (!mounted) return;
      setState(() => _loadedLocalConversations = true);
    }
  }

  Future<void> _syncConversations({
    ApiRequestTracePolicy tracePolicy = ApiRequestTracePolicy.standard,
  }) async {
    if (_syncingConversations) return;
    setState(() => _syncingConversations = true);
    try {
      await _conversationStore.syncConversations(tracePolicy: tracePolicy);
    } catch (error, stackTrace) {
      debugPrint('[Messages][DM] sync failed: $error');
      debugPrint('[Messages][DM] stacktrace:\n$stackTrace');
    } finally {
      if (mounted) {
        setState(() => _syncingConversations = false);
      }
    }
  }

  Future<void> _refreshMessagesData() {
    final refresh = widget.onMessagesDataRefresh;
    if (refresh != null) return refresh();
    return _syncConversations();
  }

  Future<void> _openConversation(DirectMessageConversationRecord item) async {
    final peerUid = item.peerUid.trim();
    if (peerUid.isEmpty) {
      debugPrint(
        '[Messages][DM] conversation ${item.conversationId} has no peer uid',
      );
      return;
    }
    if (!mounted) return;
    final peerAvatar = selectGenesisImageUrl(
      item.avatarUrl,
      logicalWidth: _ConversationTile._avatarSize,
      logicalHeight: _ConversationTile._avatarSize,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    await Navigator.of(context).pushNamed(
      RouteNames.chat,
      arguments: {
        'peer_uid': peerUid,
        'peer_name': item.peerName,
        'peer_avatar': peerAvatar,
        'conv_id': item.conversationId,
      },
    );
    if (!mounted) return;
    unawaited(_refreshMessagesData());
  }

  @override
  Widget build(BuildContext context) {
    final unreadSummary = widget.unreadSummary;
    return GenesisDarkTheme(
      child: Scaffold(
        backgroundColor: GenesisColors.darkBackground,
        body: Column(
          children: [
            const PageHeader(pageName: 'Inbox', showSearchBar: false),
            Expanded(
              child: ValueListenableBuilder<List<String>>(
                valueListenable: _conversationStore.orderedConversationIds,
                builder: (context, conversationIds, _) {
                  return GenesisRefreshIndicator(
                    onRefresh: _refreshMessagesData,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      slivers: [
                        const SliverToBoxAdapter(child: SizedBox(height: 10)),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _MessageMenuButton(
                                    label: 'Notifications',
                                    routeName: RouteNames.notifications,
                                    block: 'world_apply',
                                    emptyText: 'No notifications yet.',
                                    unreadCount: unreadSummary.systemUnread,
                                    onMessagesDataRefresh:
                                        widget.onMessagesDataRefresh,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _MessageMenuButton(
                                    label: 'Followers',
                                    routeName: RouteNames.newFollowers,
                                    block: 'follow',
                                    emptyText: 'No new followers yet.',
                                    unreadCount: unreadSummary.followerUnread,
                                    onMessagesDataRefresh:
                                        widget.onMessagesDataRefresh,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _MessageMenuButton(
                                    label: 'Comments',
                                    routeName: RouteNames.comments,
                                    block: 'interaction',
                                    emptyText: 'No comments yet.',
                                    unreadCount: unreadSummary.commentUnread,
                                    onMessagesDataRefresh:
                                        widget.onMessagesDataRefresh,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Private Chats',
                              style: TextStyle(
                                color: GenesisColors.darkTextSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 8)),
                        if (!_loadedLocalConversations)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: GenesisLoadingIndicator(strokeWidth: 4),
                            ),
                          )
                        else if (conversationIds.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              key: ValueKey('direct-messages-empty-state'),
                              child: Text(
                                'Chat with your friends on Worldo.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: GenesisColors.darkTextSecondary,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              18 + GenesisSafeAreaInsets.bottom(context),
                            ),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final conversationId = conversationIds[index];
                                final listenable = _conversationStore
                                    .rowListenable(conversationId);
                                if (listenable == null) {
                                  return const SizedBox.shrink();
                                }
                                return ValueListenableBuilder<
                                  DirectMessageConversationRecord
                                >(
                                  key: ValueKey(conversationId),
                                  valueListenable: listenable,
                                  builder: (context, item, _) =>
                                      _ConversationTile(
                                        item: item,
                                        onTap: _openConversation,
                                        displayTime: item.lastMessageAtTime,
                                        displayTimeFallback: item.lastMessageAt,
                                        displayTimeNow: _timeLabelNow,
                                      ),
                                );
                              }, childCount: conversationIds.length),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageMenuButton extends StatelessWidget {
  const _MessageMenuButton({
    required this.label,
    required this.routeName,
    required this.block,
    required this.emptyText,
    required this.unreadCount,
    required this.onMessagesDataRefresh,
  });

  final String label;
  final String routeName;
  final String block;
  final String emptyText;
  final int unreadCount;
  final Future<void> Function()? onMessagesDataRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey<String>('message-menu-$routeName'),
      color: GenesisColors.darkFaintFill,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: routeName),
            builder: (_) => MessageCategoryListPage(
              title: label,
              block: block,
              emptyText: emptyText,
              onNotificationsRead: onMessagesDataRefresh,
            ),
          ),
        ),
        child: SizedBox(
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: GenesisColors.darkTextPrimary,
                  ),
                ),
              ),
              Positioned(
                top: -5,
                right: -5,
                child: GenesisUnreadBadge(
                  key: ValueKey('message-menu-$routeName-unread-badge'),
                  count: unreadCount,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.item,
    required this.onTap,
    required this.displayTime,
    required this.displayTimeFallback,
    required this.displayTimeNow,
  });

  static const double _avatarSize = 48;
  static const double _avatarBorderRadius = GenesisAvatarRadii.user;

  final DirectMessageConversationRecord item;
  final Future<void> Function(DirectMessageConversationRecord item) onTap;
  final DateTime? displayTime;
  final String displayTimeFallback;
  final DateTime? displayTimeNow;

  @override
  Widget build(BuildContext context) {
    final displayPeerName = formatUidForDisplay(
      item.peerName,
      fallback: 'Unknown user',
    );
    return Material(
      color: GenesisColors.darkBackground,
      child: InkWell(
        onTap: () => unawaited(onTap(item)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(
                avatarUrl: item.avatarUrl,
                title: displayPeerName,
                size: _avatarSize,
                borderRadius: _avatarBorderRadius,
                avatarKey: ValueKey('dm-avatar-${item.conversationId}'),
                unreadCount: item.unreadCount,
                unreadBadgeKey: ValueKey(
                  'dm-avatar-${item.conversationId}-unread-badge',
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayPeerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: GenesisColors.darkTextPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 112),
                          child: GenesisTimestampText(
                            timestamp: displayTime,
                            fallback: displayTimeFallback,
                            now: displayTimeNow,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 11,
                              color: GenesisColors.darkTextTertiary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 60),
                      child: Text(
                        item.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: GenesisColors.darkTextSecondary,
                        ),
                      ),
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

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.avatarUrl,
    required this.title,
    required this.size,
    required this.borderRadius,
    required this.avatarKey,
    required this.unreadCount,
    required this.unreadBadgeKey,
  });

  final String avatarUrl;
  final String title;
  final double size;
  final double borderRadius;
  final Key avatarKey;
  final int unreadCount;
  final Key unreadBadgeKey;

  @override
  Widget build(BuildContext context) {
    final resolvedAvatarUrl = resolvePrivateChatAvatarUrl(
      avatarUrl: avatarUrl,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      logicalSize: size,
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GenesisAvatar(
            key: avatarKey,
            url: resolvedAvatarUrl,
            name: title,
            size: size,
            borderRadius: borderRadius,
            showFallbackWhileLoading: false,
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Transform.translate(
              offset: const Offset(4, -4),
              child: GenesisUnreadBadge(
                key: unreadBadgeKey,
                count: unreadCount,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

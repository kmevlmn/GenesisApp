import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/bootstrap/app_services_scope.dart';
import 'discuss_dark_style.dart';
import '../../network/json_utils.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_avatar.dart';
import '../../ui/tokens/genesis_avatar_radii.dart';
import '../../utils/display_name_formatter.dart';
import '../auth/login_guard.dart';
import '../common/genesis_center_toast.dart';
import '../common/genesis_report_actions.dart';
import '../common/genesis_timestamp_text.dart';
import 'origin_discuss_list.dart';

class DiscussPageCommentList extends StatelessWidget {
  const DiscussPageCommentList({
    super.key,
    required this.controller,
    this.onItemReplyTap,
    this.onReplyTap,
    this.onViewAllRepliesTap,
  });

  final OriginDiscussListController controller;
  final OriginDiscussItemTap? onItemReplyTap;
  final OriginDiscussReplyTap? onReplyTap;
  final OriginDiscussItemTap? onViewAllRepliesTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final comments = controller.items;
        if (controller.isInitialLoading && comments.isEmpty) {
          return const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        if (controller.error != null && comments.isEmpty) {
          return TextButton(
            onPressed: controller.retryInitial,
            child: const Text('Retry'),
          );
        }
        if (comments.isEmpty) return const SizedBox.shrink();

        return Column(
          children: [
            for (final entry in comments.indexed) ...[
              DiscussPagePostRow(
                controller: controller,
                item: entry.$2,
                onItemReplyTap: onItemReplyTap,
                onReplyTap: onReplyTap,
                onViewAllRepliesTap: onViewAllRepliesTap,
              ),
              if (entry.$1 != comments.length - 1) const SizedBox(height: 28),
            ],
          ],
        );
      },
    );
  }
}

class DiscussPagePostRow extends StatefulWidget {
  const DiscussPagePostRow({
    super.key,
    required this.controller,
    required this.item,
    this.showReplyPreview = true,
    this.onItemReplyTap,
    this.onReplyTap,
    this.onViewAllRepliesTap,
  });

  final OriginDiscussListController controller;
  final OriginDiscussListItem item;
  final bool showReplyPreview;
  final OriginDiscussItemTap? onItemReplyTap;
  final OriginDiscussReplyTap? onReplyTap;
  final OriginDiscussItemTap? onViewAllRepliesTap;

  @override
  State<DiscussPagePostRow> createState() => _DiscussPagePostRowState();
}

class _DiscussPagePostRowState extends State<DiscussPagePostRow> {
  static const double _avatarSize = 40;
  static const double _avatarTextGap = 14;
  static const double _metaBodyGap = 6;
  static const double _progressPrefetchExtent = 600;

  ScrollPosition? _scrollPosition;
  bool _viewportCheckScheduled = false;
  bool _progressRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachScrollPosition();
      _scheduleViewportCheck();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachScrollPosition();
    _scheduleViewportCheck();
  }

  @override
  void didUpdateWidget(covariant DiscussPagePostRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.discussId != widget.item.discussId ||
        oldWidget.item.authorUid != widget.item.authorUid ||
        oldWidget.item.bizId != widget.item.bizId) {
      _progressRequested = false;
    }
    _attachScrollPosition();
    _scheduleViewportCheck();
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_handleScroll);
    super.dispose();
  }

  void _attachScrollPosition() {
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _scrollPosition)) return;
    _scrollPosition?.removeListener(_handleScroll);
    _scrollPosition = position;
    _scrollPosition?.addListener(_handleScroll);
  }

  void _handleScroll() {
    _scheduleViewportCheck();
  }

  void _scheduleViewportCheck() {
    if (_progressRequested || _viewportCheckScheduled) return;
    _viewportCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewportCheckScheduled = false;
      _maybeLoadProgress();
    });
  }

  void _maybeLoadProgress() {
    if (_progressRequested) return;
    if (!_isInOrNearViewport()) return;
    if (!widget.controller.hasProgressTarget(widget.item)) return;
    _progressRequested = true;
    final api = AppServicesScope.read(context).api.v1.world;
    unawaited(
      widget.controller.loadProgressForItem(
        item: widget.item,
        loader: ({required uid, required originId}) {
          return api.originProgress(uid: uid, originId: originId);
        },
      ),
    );
  }

  bool _isInOrNearViewport() {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return true;

    final rowRenderObject = context.findRenderObject();
    final viewportRenderObject = scrollable.context.findRenderObject();
    if (rowRenderObject is! RenderBox ||
        viewportRenderObject is! RenderBox ||
        !rowRenderObject.hasSize ||
        !viewportRenderObject.hasSize) {
      return false;
    }

    final rowTop = rowRenderObject
        .localToGlobal(Offset.zero, ancestor: viewportRenderObject)
        .dy;
    final rowBottom = rowTop + rowRenderObject.size.height;
    return rowBottom >= -_progressPrefetchExtent &&
        rowTop <= viewportRenderObject.size.height + _progressPrefetchExtent;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileAvatarLink(item: widget.item),
        const SizedBox(width: _avatarTextGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DiscussPageMeta(item: widget.item),
              const SizedBox(height: _metaBodyGap),
              Text(
                widget.item.content,
                style: const TextStyle(
                  color: DiscussDarkColors.primary,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 8),
              _DiscussPageActions(
                controller: widget.controller,
                item: widget.item,
                onReplyTap: widget.onItemReplyTap,
              ),
              if (widget.showReplyPreview &&
                  (widget.item.latestReplies.isNotEmpty ||
                      widget.controller.hasMoreReplies(widget.item))) ...[
                const SizedBox(height: 8),
                _DiscussPageReplyPreview(
                  controller: widget.controller,
                  item: widget.item,
                  onViewAllTap: widget.onViewAllRepliesTap,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DiscussPageMeta extends StatelessWidget {
  const _DiscussPageMeta({required this.item});

  final OriginDiscussListItem item;

  @override
  Widget build(BuildContext context) {
    final tappableMeta = Text(
      item.authorName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: DiscussDarkColors.secondary,
        fontSize: 14,
        height: 1.18,
        fontWeight: FontWeight.w600,
      ),
    );
    final canOpenProfile =
        item.authorUid.trim().isNotEmpty && !item.authorDeleted;

    return SizedBox(
      key: ValueKey('discuss-page-meta-${item.discussId}'),
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: canOpenProfile
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openProfile(context, item),
                      child: tappableMeta,
                    )
                  : tappableMeta,
            ),
          ),
          if (item.createdAt != null) ...[
            const SizedBox(width: 8),
            GenesisTimestampText(timestamp: item.createdAt, style: _timeStyle),
          ],
        ],
      ),
    );
  }
}

class _ProfileAvatarLink extends StatelessWidget {
  const _ProfileAvatarLink({required this.item});

  final OriginDiscussListItem item;

  @override
  Widget build(BuildContext context) {
    final avatar = GenesisAvatar(
      url: item.avatar.trim(),
      name: item.authorName,
      size: _DiscussPagePostRowState._avatarSize,
      borderRadius: GenesisAvatarRadii.user,
    );
    if (item.authorUid.trim().isEmpty || item.authorDeleted) return avatar;
    return GestureDetector(
      key: ValueKey('discuss-page-avatar-${item.authorUid}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _openProfile(context, item),
      child: avatar,
    );
  }
}

class _DiscussPageActions extends StatelessWidget {
  const _DiscussPageActions({
    required this.controller,
    required this.item,
    this.onReplyTap,
  });

  final OriginDiscussListController controller;
  final OriginDiscussListItem item;
  final OriginDiscussItemTap? onReplyTap;

  @override
  Widget build(BuildContext context) {
    final likePending = controller.isLikePending(item.discussId);
    final activeColor = item.isLiked
        ? DiscussDarkColors.accent
        : DiscussDarkColors.muted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          key: ValueKey('discuss-page-like-${item.discussId}'),
          behavior: HitTestBehavior.opaque,
          onTap: likePending ? null : () => _toggleLike(context),
          child: _DiscussActionCluster(
            iconAsset: _discussLikeFilledOrOutline(item.isLiked),
            count: item.likeCount,
            color: activeColor,
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          key: ValueKey('discuss-page-reply-${item.discussId}'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final handler = onReplyTap;
            if (handler != null) {
              handler(item);
              return;
            }
            unawaited(
              showOriginDiscussReplyComposer(
                context: context,
                controller: controller,
                item: item,
              ),
            );
          },
          child: _DiscussActionCluster(
            iconAsset: _discussReplyAsset,
            count: item.replyCount,
            color: _timeStyle.color ?? DiscussDarkColors.muted,
          ),
        ),
        const Spacer(),
        GenesisMoreActionMenuButton(
          key: ValueKey('discuss-page-report-${item.discussId}'),
          iconColor: DiscussDarkColors.secondary,
          buttonSize: 28,
          iconSize: 18,
          items: [
            genesisReportMenuItem(
              context: context,
              targetType: 'discuss',
              targetId: item.discussId,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _toggleLike(BuildContext context) async {
    final discussId = item.discussId.trim();
    if (discussId.isEmpty || controller.isLikePending(discussId)) return;
    if (!await ensureGenesisLogin(context)) return;
    if (!context.mounted) return;

    final previousLiked = item.isLiked;
    final previousCount = item.likeCount;
    final nextLiked = !previousLiked;
    final nextCount = previousLiked ? previousCount - 1 : previousCount + 1;

    controller.applyLikeState(
      discussId: discussId,
      isLiked: nextLiked,
      likeCount: nextCount,
    );
    controller.setLikePending(discussId, true);
    try {
      final api = AppServicesScope.read(context).api.v1.discuss;
      if (nextLiked) {
        await api.like(discussId: discussId);
      } else {
        await api.unlike(discussId: discussId);
      }
    } catch (_) {
      controller.applyLikeState(
        discussId: discussId,
        isLiked: previousLiked,
        likeCount: previousCount,
      );
      if (context.mounted) showGenesisToast(context, 'Like failed');
    } finally {
      controller.setLikePending(discussId, false);
    }
  }
}

class _DiscussActionCluster extends StatelessWidget {
  const _DiscussActionCluster({
    required this.iconAsset,
    required this.count,
    required this.color,
  });

  static const double _iconSize = 15;

  final String iconAsset;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 10, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            iconAsset,
            color: color == DiscussDarkColors.accent
                ? DiscussDarkColors.accent
                : DiscussDarkColors.secondary,
            width: _iconSize,
            height: _iconSize,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscussPageReplyPreview extends StatelessWidget {
  const _DiscussPageReplyPreview({
    required this.controller,
    required this.item,
    this.onViewAllTap,
  });

  final OriginDiscussListController controller;
  final OriginDiscussListItem item;
  final OriginDiscussItemTap? onViewAllTap;

  @override
  Widget build(BuildContext context) {
    final hasLoadedReplies = controller.hasLoadedReplies(item.discussId);
    final replies = hasLoadedReplies
        ? item.latestReplies
        : item.latestReplies.take(2).toList(growable: false);
    final visibleReplies = replies.take(2).toList(growable: false);
    final showViewAll = item.replyCount >= 3;

    return GestureDetector(
      key: ValueKey('discuss-page-reply-preview-${item.discussId}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final viewAllHandler = onViewAllTap;
        if (viewAllHandler != null) {
          viewAllHandler(item);
          return;
        }
        unawaited(_loadMoreReplies(context));
      },
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: DiscussDarkColors.border),
            Expanded(
              child: Container(
                width: double.infinity,
                color: DiscussDarkColors.inputFill,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final reply in visibleReplies) ...[
                      _DiscussPageReplyPreviewLine(reply: reply),
                      if (reply != visibleReplies.last)
                        const SizedBox(height: 6),
                    ],
                    if (showViewAll) ...[
                      if (visibleReplies.isNotEmpty) const SizedBox(height: 6),
                      Text(
                        'View all ${item.replyCount} replies',
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: DiscussDarkColors.secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadMoreReplies(BuildContext context) async {
    try {
      await controller.loadMoreReplies(
        rootDiscussId: item.replyRootDiscussId,
        loader: ({required rootDiscussId, required pn, required rn}) async {
          final data = await AppServicesScope.read(context).api.v1.discuss
              .replies(rootDiscussId: rootDiscussId, pn: pn, rn: rn);
          return OriginDiscussRepliesPage.fromJson(data);
        },
      );
    } catch (_) {
      if (context.mounted) showGenesisToast(context, 'Load replies failed');
    }
  }
}

class _DiscussPageReplyPreviewLine extends StatelessWidget {
  const _DiscussPageReplyPreviewLine({required this.reply});

  final Map<String, dynamic> reply;

  @override
  Widget build(BuildContext context) {
    final author = reply['author'] is Map ? asJsonMap(reply['author']) : null;
    final uid = asString(author?['uid'], fallback: asString(reply['uid']));
    final name = asString(
      author?['name'] ??
          author?['user_name'] ??
          author?['nickname'] ??
          author?['display_name'] ??
          reply['author_name'] ??
          reply['user_name'],
      fallback: formatUidForDisplay(uid, fallback: 'User'),
    );
    final authorName = formatUidForDisplay(name, fallback: 'User');
    final content = asString(reply['content']);
    final parentDiscussId = asString(reply['parent_discuss_id']).trim();
    final rootDiscussId = asString(reply['root_discuss_id']).trim();
    final replyToUid = asString(reply['reply_to_uid']).trim();
    final replyToUsername = asString(reply['reply_to_username']).trim();
    final replyToName = replyToUsername.isNotEmpty
        ? replyToUsername
        : replyToUid;
    final showReplyTo =
        parentDiscussId.isNotEmpty &&
        rootDiscussId.isNotEmpty &&
        parentDiscussId != rootDiscussId &&
        replyToName.isNotEmpty;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$authorName: ',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: DiscussDarkColors.secondary,
            ),
          ),
          if (showReplyTo)
            TextSpan(
              text: '@$replyToName ',
              style: const TextStyle(
                fontWeight: FontWeight.w400,
                color: DiscussDarkColors.secondary,
              ),
            ),
          TextSpan(text: content),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w400,
        color: DiscussDarkColors.primary,
      ),
    );
  }
}

void _openProfile(BuildContext context, OriginDiscussListItem item) {
  Navigator.of(
    context,
  ).pushNamed(RouteNames.userInfo, arguments: {'uid': item.authorUid});
}

String _discussLikeFilledOrOutline(bool isLiked) {
  return isLiked
      ? 'assets/custom-icons/png/discuss_like_filled.png'
      : 'assets/custom-icons/png/discuss_like_outline.png';
}

const String _discussReplyAsset = 'assets/custom-icons/png/discuss_reply.png';

const _timeStyle = TextStyle(
  color: DiscussDarkColors.muted,
  fontSize: 12,
  height: 1.2,
  fontWeight: FontWeight.w400,
);

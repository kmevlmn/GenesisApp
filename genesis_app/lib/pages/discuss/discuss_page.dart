import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/components/genesis_refresh_indicator.dart';
import '../../app/bootstrap/app_services_scope.dart';
import '../../components/discuss/discuss_dark_style.dart';
import '../../components/discuss/discuss_page_comment_list.dart';
import '../../components/discuss/discuss_post_input.dart';
import '../../components/discuss/origin_discuss_list.dart';
import '../../components/page_header.dart';
import '../../network/genesis_api.dart';
import '../../network/json_utils.dart';
import '../../network/models/origin.dart';
import '../../platform/session/session_revision_subscription.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_list_image.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../ui/tokens/genesis_avatar_radii.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/tokens/genesis_image_radii.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/entity_deleted.dart';

class DiscussPage extends StatefulWidget {
  const DiscussPage({super.key, required this.oid, this.originId = 0});

  final String oid;
  final int originId;

  @override
  State<DiscussPage> createState() => _DiscussPageState();
}

class _DiscussPageState extends State<DiscussPage> {
  static const double _loadMoreThreshold = 600;
  static const double _loadMoreDragDistance = 48;
  static const double _postInputReservedHeight = 96;

  late final OriginDiscussListController _discussController;
  late final SessionRevisionSubscription _sessionRevision;
  final ScrollController _scrollController = ScrollController();
  Future<OriginDetail>? _future;
  OriginDetail? _origin;
  double _downwardDragDistance = 0;
  var _loadGeneration = 0;
  var _sessionListGeneration = 0;

  @override
  void initState() {
    super.initState();
    _discussController = OriginDiscussListController();
    _sessionRevision = SessionRevisionSubscription(_handleSessionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sessionRevision.bind(AppServicesScope.of(context).sessionRevision);
    _future ??= _loadOriginDetail();
  }

  @override
  void didUpdateWidget(covariant DiscussPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.oid != widget.oid) {
      _origin = null;
      _future = _loadOriginDetail();
    }
  }

  @override
  void dispose() {
    _sessionRevision.dispose();
    _scrollController.dispose();
    _discussController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollStartNotification) {
      _downwardDragDistance = 0;
      return false;
    }
    if (notification is! ScrollUpdateNotification) return false;
    if (notification.dragDetails == null) return false;
    final delta = notification.scrollDelta;
    if (delta == null || delta <= 0) return false;
    _downwardDragDistance += delta;
    if (_downwardDragDistance < _loadMoreDragDistance) return false;
    if (notification.metrics.extentAfter > _loadMoreThreshold) return false;
    _downwardDragDistance = 0;
    unawaited(_discussController.loadNextPage());
    return false;
  }

  Future<OriginDetail> _loadOriginDetail({
    bool forceDiscussRefresh = false,
  }) async {
    final generation = ++_loadGeneration;
    final api = AppServicesScope.read(context).api;
    final origin = await api.getOrigin(widget.oid);
    if (!mounted || generation != _loadGeneration) return origin;
    _origin = origin;
    _discussController.configure(
      oid: origin.oid,
      loader: ({required String oid, required int pn, required int rn}) async {
        return loadOriginDiscussPage(context, oid, pn: pn, rn: rn);
      },
    );
    if (forceDiscussRefresh) {
      await _discussController.refreshFirstPage();
    } else {
      await _discussController.loadInitialIfNeeded();
    }
    return origin;
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    _loadGeneration += 1;
    _sessionListGeneration += 1;
    final future = _loadOriginDetail(forceDiscussRefresh: true);
    setState(() {
      _origin = null;
      _future = future;
      _downwardDragDistance = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  Future<void> _refresh() async {
    final future = _loadOriginDetail(forceDiscussRefresh: true);
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final origin = _origin;
    return DiscussDarkTheme(
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: DiscussDarkColors.background,
        appBar: const GenesisBackAppBar(
          pageName: 'Discuss',
          backgroundColor: DiscussDarkColors.background,
          foregroundColor: DiscussDarkColors.primary,
          titleStyle: TextStyle(color: DiscussDarkColors.primary),
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: FutureBuilder<OriginDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                origin == null) {
              return const _DiscussPageLoadingSkeleton();
            }

            if (snapshot.hasError && origin == null) {
              return Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _future = _loadOriginDetail();
                  }),
                  child: const Text('Retry'),
                ),
              );
            }

            final data = snapshot.data ?? origin;
            if (data == null) return const SizedBox.shrink();

            final bottomPadding =
                _postInputReservedHeight +
                GenesisSafeAreaInsets.bottom(context);
            return Stack(
              children: [
                Positioned.fill(
                  child: GenesisRefreshIndicator(
                    backgroundColor: DiscussDarkColors.surface,
                    onRefresh: _refresh,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _handleScrollNotification,
                      child: ListView(
                        key: ValueKey<String>(
                          'discuss-session-$_sessionListGeneration',
                        ),
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(20, 10, 20, bottomPadding),
                        children: [
                          _DiscussOriginSummary(origin: data),
                          const Padding(
                            padding: EdgeInsets.only(top: 10, bottom: 16),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: DiscussDarkColors.border,
                            ),
                          ),
                          DiscussPageCommentList(
                            controller: _discussController,
                            onItemReplyTap: _openReplyComposer,
                            onReplyTap: _handleReplyListItemTap,
                            onViewAllRepliesTap: _openPostDetail,
                          ),
                          AnimatedBuilder(
                            animation: _discussController,
                            builder: (context, _) {
                              if (!_discussController.isLoadingMore) {
                                return const SizedBox.shrink();
                              }
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox.square(
                                    dimension: 18,
                                    child: GenesisLoadingIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: DiscussDarkColors.background,
                    child: KeyedSubtree(
                      key: const ValueKey<String>(
                        'discuss-page-post-input-bar',
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                          child: DiscussPostInput(
                            bizId: data.oid,
                            backgroundColor: DiscussDarkColors.inputFill,
                            placeholderColor:
                                GenesisColors.darkInputPlaceholder,
                            onSubmitted: () => unawaited(
                              _discussController.refreshFirstPage(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _handleReplyListItemTap(
    OriginDiscussListItem item,
    Map<String, dynamic> reply,
  ) => _openReplyComposerForReply(item, reply);

  void _openReplyComposer(OriginDiscussListItem item) {
    unawaited(
      showOriginDiscussReplyComposer(
        context: context,
        controller: _discussController,
        item: item,
      ),
    );
  }

  void _openReplyComposerForReply(
    OriginDiscussListItem item,
    Map<String, dynamic> reply,
  ) {
    unawaited(
      showOriginDiscussReplyComposer(
        context: context,
        controller: _discussController,
        item: item,
        parentDiscussId: asString(reply['discuss_id']),
        replyToUid: _replyAuthorUid(reply),
        replyToUsername: _replyAuthorName(reply),
      ),
    );
  }

  void _openPostDetail(OriginDiscussListItem item) {
    unawaited(
      Navigator.of(context)
          .pushNamed(
            RouteNames.postDetail,
            arguments: {'item': item, 'oid': item.bizId},
          )
          .then((_) {
            if (!mounted) return;
            unawaited(_discussController.refreshFirstPage());
          }),
    );
  }

  String _replyAuthorUid(Map<String, dynamic> reply) {
    final author = reply['author'] is Map ? asJsonMap(reply['author']) : null;
    return asString(author?['uid'], fallback: asString(reply['uid']));
  }

  String _replyAuthorName(Map<String, dynamic> reply) {
    final author = reply['author'] is Map ? asJsonMap(reply['author']) : null;
    final uid = _replyAuthorUid(reply);
    return asString(
      author?['name'] ??
          author?['user_name'] ??
          author?['nickname'] ??
          author?['display_name'] ??
          reply['author_name'] ??
          reply['user_name'],
      fallback: formatUidForDisplay(uid, fallback: 'User'),
    );
  }
}

class _DiscussPageLoadingSkeleton extends StatelessWidget {
  const _DiscussPageLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey<String>('discuss-page-loading-skeleton'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: const [
        _DiscussOriginSummarySkeleton(),
        Padding(
          padding: EdgeInsets.only(top: 10, bottom: 16),
          child: Divider(
            height: 1,
            thickness: 1,
            color: DiscussDarkColors.border,
          ),
        ),
        _DiscussCommentSkeleton(),
        SizedBox(height: 22),
        _DiscussCommentSkeleton(),
        SizedBox(height: 22),
        _DiscussCommentSkeleton(compact: true),
      ],
    );
  }
}

class _DiscussOriginSummarySkeleton extends StatelessWidget {
  const _DiscussOriginSummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _DiscussSkeletonBone(
          width: 48,
          height: 48,
          borderRadius: GenesisImageRadii.contentValue,
        ),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DiscussSkeletonBone(widthFactor: 0.48, height: 14),
              SizedBox(height: 8),
              _DiscussSkeletonBone(widthFactor: 0.86, height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiscussCommentSkeleton extends StatelessWidget {
  const _DiscussCommentSkeleton({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DiscussSkeletonBone(
          width: 30,
          height: 30,
          borderRadius: GenesisAvatarRadii.user,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _DiscussSkeletonBone(widthFactor: 0.34, height: 12),
              const SizedBox(height: 10),
              const _DiscussSkeletonBone(widthFactor: 0.96, height: 10),
              const SizedBox(height: 7),
              _DiscussSkeletonBone(
                widthFactor: compact ? 0.58 : 0.82,
                height: 10,
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  _DiscussSkeletonBone(width: 42, height: 12),
                  SizedBox(width: 16),
                  _DiscussSkeletonBone(width: 46, height: 12),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiscussSkeletonBone extends StatelessWidget {
  const _DiscussSkeletonBone({
    this.width,
    this.widthFactor,
    required this.height,
    this.borderRadius = 4,
  }) : assert(width == null || widthFactor == null);

  final double? width;
  final double? widthFactor;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    Widget child = DecoratedBox(
      decoration: BoxDecoration(
        // Match the static loading bones in Worldo Sheet.
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: SizedBox(width: width, height: height),
    );

    if (widthFactor case final factor?) {
      child = FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: factor,
        child: child,
      );
    }
    return child;
  }
}

class _DiscussOriginSummary extends StatelessWidget {
  const _DiscussOriginSummary({required this.origin});

  final OriginDetail origin;

  @override
  Widget build(BuildContext context) {
    final originator = formatUidForDisplay(origin.originator);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _OriginCover(url: origin.mapImage),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                originDisplayName(origin.name, fallback: origin.oid),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: DiscussDarkColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'OID: ${deletedAwareIdLabel(origin.oid, deleted: origin.deleted)}${originator.isEmpty ? '' : ' · Originator: ${origin.ownerDeleted ? deletedEntityDisplayText : originator}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w400,
                  color: DiscussDarkColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OriginCover extends StatelessWidget {
  const _OriginCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final imageUrl = resolveAssetUrl(url);
    return GenesisListImage(
      imageUrl: imageUrl,
      width: 48,
      height: 48,
      borderRadius: GenesisImageRadii.content,
    );
  }
}

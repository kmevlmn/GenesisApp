part of 'origin_world_page.dart';

class _WorldViewSection extends StatelessWidget {
  const _WorldViewSection({required this.origin});

  final OriginDetail origin;

  @override
  Widget build(BuildContext context) {
    final body = _originWorldoBrief(origin);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Worldo Brief'),
        const SizedBox(height: 8),
        Text(body, style: _bodyTextStyle),
      ],
    );
  }
}

String _originWorldoBrief(OriginDetail origin) {
  final worldView = origin.worldView.trim();
  return worldView.isEmpty ? origin.description.trim() : worldView;
}

class _OriginPreviewImage extends StatelessWidget {
  const _OriginPreviewImage({
    required this.url,
    required this.width,
    required this.height,
  });
  static const double _maxDevicePixelRatio = 2;

  final String url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final viewerUrl = url.trim();
    final imageUrl = selectGenesisImageUrl(
      viewerUrl,
      logicalWidth: width,
      logicalHeight: height,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      maxDevicePixelRatio: _maxDevicePixelRatio,
    ).trim();
    final fallback = Container(
      color: originWorldDetailSheetSubtleSurfaceColor,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        color: originWorldDetailSheetTertiaryTextColor,
      ),
    );
    final preview = Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        key: const ValueKey<String>('origin-info-cover'),
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: imageUrl.isEmpty
              ? fallback
              : imageUrl.startsWith('assets/')
              ? Image.asset(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => fallback,
                )
              : GenesisStaticNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  maxDevicePixelRatio: _maxDevicePixelRatio,
                  placeholder: (_) => fallback,
                  errorWidget: (_, _) => fallback,
                ),
        ),
      ),
    );
    if (viewerUrl.isEmpty) return preview;
    return GestureDetector(
      key: const ValueKey<String>('origin-info-cover-viewer'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showGenesisImageViewer(
        context,
        imageUrls: [viewerUrl],
        maxDevicePixelRatio: _maxDevicePixelRatio,
        previewImageProviders: [
          genesisImageViewerPreviewProvider(
            context,
            imageUrl: imageUrl,
            logicalWidth: width,
            logicalHeight: height,
            fit: BoxFit.cover,
            maxDevicePixelRatio: _maxDevicePixelRatio,
          ),
        ],
      ),
      child: preview,
    );
  }
}

class _DiscussSection extends StatelessWidget {
  const _DiscussSection({required this.origin, required this.controller});

  final OriginDetail origin;
  final OriginDiscussListController controller;

  bool get _hasDiscussContent =>
      origin.discussCount > 0 ||
      controller.totalAll > 0 ||
      controller.items.isNotEmpty;

  Future<void> _handleDiscussAreaTap(BuildContext context) {
    if (_hasDiscussContent) return _openDiscussPage(context);
    return _openPostComposer(context);
  }

  Future<void> _openDiscussPage(BuildContext context) {
    return Navigator.of(context).pushNamed(
      RouteNames.discuss,
      arguments: {'oid': origin.oid, 'originId': origin.id},
    );
  }

  Future<void> _openPostComposer(BuildContext context) async {
    final submitted = await showDiscussPostComposer(
      context: context,
      title: 'New post',
      placeholder: 'Write a post',
      submitter: (content, images) async {
        await AppServicesScope.read(context).api.v1.discuss.post(
          bizId: origin.oid.trim(),
          bizType: 1,
          content: content,
          images: images,
        );
      },
    );
    if (!context.mounted || !submitted) return;
    unawaited(controller.refreshFirstPage());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final hasDiscussContent = _hasDiscussContent;
        final showDiscussList =
            hasDiscussContent ||
            controller.isInitialLoading ||
            controller.error != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              key: const ValueKey('origin-discuss-summary-area'),
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_handleDiscussAreaTap(context)),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SectionTitle(
                            title: 'Discuss (${origin.discussCount})',
                          ),
                        ),
                        if (hasDiscussContent)
                          GestureDetector(
                            key: const ValueKey('origin-discuss-view-all'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => unawaited(_openDiscussPage(context)),
                            child: const Text(
                              'View all >',
                              style: TextStyle(
                                fontSize: 10,
                                height: 1.2,
                                fontWeight: FontWeight.w400,
                                color: originWorldDetailSheetTertiaryTextColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (showDiscussList) ...[
                      const SizedBox(height: 8),
                      OriginDiscussList(
                        controller: controller,
                        count: origin.discussCount,
                        contentLineHeight: 1.4,
                        authorColor: originWorldDetailSheetSecondaryTextColor,
                        contentColor: originWorldDetailSheetSecondaryTextColor,
                        metadataColor: originWorldDetailSheetTertiaryTextColor,
                        showHeader: false,
                        enableViewMore: false,
                        showActions: false,
                        showReplies: false,
                        disableAvatarProfileTap: true,
                        listenToController: false,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!hasDiscussContent) ...[
              const SizedBox(height: 8),
              DiscussPostInput(
                bizId: origin.oid,
                backgroundColor: originWorldDetailSheetFaintSurfaceColor,
                placeholderColor: originWorldDetailSheetFaintPlaceholderColor,
                onSubmitted: () => unawaited(controller.refreshFirstPage()),
              ),
            ],
          ],
        );
      },
    );
  }
}

List<Widget> _originInitialDialogueSlivers(
  BuildContext context,
  OriginDetail origin,
  _OriginInitialDialoguePreview preview, {
  Key? contentStartKey,
  Key? messageEndKey,
  bool cacheAllMessages = false,
}) {
  final style = kLocationChatStyle.copyWith(bubbleBackdropBlurSigma: 0);
  final padding = style.messageListPadding;
  final bubbleWidthCaps =
      locationChatOrdinaryMessageBubbleMaxWidthCapsForMetrics(
        logicalWidth: MediaQuery.sizeOf(context).width,
        textScaler: MediaQuery.textScalerOf(context),
        bubbleFontSize: style.bubbleTextStyle.fontSize ?? 14,
        crowdedEffectiveWidthThreshold: locationChatBubbleLayoutSettings
            .value
            .crowdedEffectiveWidthThreshold,
        avatarSize: style.avatarSize,
        avatarBubbleGap: style.avatarBubbleGap,
        avatarSideSpacerWidth: style.avatarSideSpacerWidth,
        messageListHorizontalPadding: style.messageListPadding.horizontal,
      );
  final brief = _originWorldoBrief(origin);
  final locationTopPadding = brief.isEmpty ? 6.0 : 0.0;
  Widget buildMessage(BuildContext context, int index) {
    final message = preview.messages[index];
    final isLast = index == preview.messages.length - 1;
    final messageStyle = isLast
        ? style.copyWith(
            rowBottomPadding: 0,
            systemMessageMargin: style.systemMessageMargin.copyWith(bottom: 0),
          )
        : style;
    final row = ChatMessageRow(
      key: ValueKey<String>(message.localId),
      message: message,
      showDateDivider: false,
      style: messageStyle,
      selfMessageBubbleMaxWidthCap: bubbleWidthCaps.selfMessage,
      otherMessageBubbleMaxWidthCap: bubbleWidthCaps.otherMessage,
    );
    if (!isLast || messageEndKey == null) return row;
    return KeyedSubtree(key: messageEndKey, child: row);
  }

  return <Widget>[
    SliverToBoxAdapter(
      child: RepaintBoundary(
        child: _OriginOpeningLocationHeader(
          locationName: preview.locationName,
          contentStartKey: contentStartKey,
          horizontalPadding: padding,
          topPadding: locationTopPadding,
          iconColor: originWorldDetailSheetPrimaryTextColor,
          iconGap: style.headerTitleIconGap,
          textStyle: style.headerTitleTextStyle.copyWith(
            color: originWorldDetailSheetPrimaryTextColor,
            fontSize: 14,
          ),
        ),
      ),
    ),
    SliverPadding(
      key: const ValueKey<String>('origin-opening-dialogue'),
      padding: EdgeInsets.fromLTRB(
        padding.left,
        0,
        padding.right,
        originOpeningDialogueRoleGapForTesting,
      ),
      sliver: cacheAllMessages
          ? SliverToBoxAdapter(
              child: RepaintBoundary(
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < preview.messages.length;
                      index += 1
                    )
                      buildMessage(context, index),
                  ],
                ),
              ),
            )
          : SliverList(
              delegate: SliverChildBuilderDelegate(
                buildMessage,
                childCount: preview.messages.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
              ),
            ),
    ),
  ];
}

class _OriginOpeningLocationHeader extends StatelessWidget {
  const _OriginOpeningLocationHeader({
    required this.locationName,
    this.contentStartKey,
    required this.horizontalPadding,
    required this.topPadding,
    required this.iconColor,
    required this.iconGap,
    required this.textStyle,
  });

  static const double _contentHeight = 25;

  final String locationName;
  final Key? contentStartKey;
  final EdgeInsets horizontalPadding;
  final double topPadding;
  final Color iconColor;
  final double iconGap;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: topPadding + _contentHeight,
      child: ColoredBox(
        color: originWorldDetailSheetBackgroundColor,
        child: Padding(
          key: const ValueKey<String>('origin-opening-location'),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding.left,
            topPadding,
            horizontalPadding.right,
            8,
          ),
          child: Row(
            key: contentStartKey,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(Icons.place_outlined, size: 14, color: iconColor),
              SizedBox(width: iconGap),
              Expanded(
                child: Text(
                  locationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: textStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<Widget> _originWorldoBriefSlivers(
  OriginDetail origin, {
  Key? contentStartKey,
}) {
  final brief = _originWorldoBrief(origin);
  if (brief.isEmpty) return const <Widget>[];
  final padding = kLocationChatStyle.messageListPadding;
  return <Widget>[
    SliverToBoxAdapter(
      child: RepaintBoundary(
        child: Padding(
          key: const ValueKey<String>('origin-opening-worldo-brief'),
          padding: EdgeInsets.fromLTRB(
            padding.left,
            6,
            padding.right,
            originDetailSectionGapForTesting,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Worldo Brief',
                key: contentStartKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: originWorldDetailSheetPrimaryTextColor,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                brief,
                key: const ValueKey<String>('origin-opening-worldo-brief-body'),
                style: _bodyTextStyle.copyWith(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    ),
  ];
}

String _originRoleCardAvatarUrl(BuildContext context, String sourceUrl) {
  return selectGenesisImageUrl(
    sourceUrl,
    logicalWidth: _OriginSetupRoleSection._cardWidth,
    logicalHeight: _OriginSetupRoleSection._cardWidth,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    maxDevicePixelRatio: originWorldOpeningRoleAvatarMaxDevicePixelRatio,
  ).trim();
}

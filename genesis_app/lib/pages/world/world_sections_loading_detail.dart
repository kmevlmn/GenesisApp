// ignore_for_file: use_key_in_widget_constructors

part of 'world_sections_library.dart';

class WorldDetailsLoadingContent extends StatelessWidget {
  const WorldDetailsLoadingContent({
    this.infoHeaderHeight = worldInfoHeaderHeight,
    this.useCompactAction = false,
  });

  final double infoHeaderHeight;
  final bool useCompactAction;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        const SliverToBoxAdapter(
          child: SizedBox(height: worldStatsTopSpacerHeight),
        ),
        SliverToBoxAdapter(
          child: WorldInfoHeaderLoadingSkeleton(
            height: infoHeaderHeight,
            useCompactAction: useCompactAction,
          ),
        ),
      ],
    );
  }
}

class WorldInfoHeaderLoadingSkeleton extends StatelessWidget {
  const WorldInfoHeaderLoadingSkeleton({
    this.height = worldInfoHeaderHeight,
    this.useCompactAction = false,
  });

  final double height;
  final bool useCompactAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey<String>('world-panel-info-row'),
      height: height,
      child: Align(
        alignment: Alignment.center,
        child: SizedBox(
          height: worldCharacterAvatarLogicalSize,
          child: Row(
            children: [
              const Expanded(
                child: Row(
                  children: [
                    WorldLoadingBone(
                      width: worldCharacterAvatarLogicalSize,
                      height: worldCharacterAvatarLogicalSize,
                      radius: 12,
                    ),
                    SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WorldLoadingBone(width: 74, height: 13),
                        SizedBox(height: 2),
                        WorldLoadingBone(width: 58, height: 12),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              WorldLoadingBone(
                key: const ValueKey<String>('world-loading-action'),
                width: useCompactAction ? 92 : 140,
                height: useCompactAction ? 34 : worldInfoHeaderContentHeight,
                radius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorldEventLoadingSkeleton extends StatelessWidget {
  const WorldEventLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorldLoadingBone(width: 96, height: 14),
        SizedBox(height: 14),
        WorldLoadingBone(widthFactor: 0.92, height: 12),
        SizedBox(height: 8),
        WorldLoadingBone(widthFactor: 0.78, height: 12),
        SizedBox(height: 8),
        WorldLoadingBone(widthFactor: 0.86, height: 12),
        SizedBox(height: 18),
        WorldLoadingBone(widthFactor: 0.48, height: 12),
        SizedBox(height: 14),
        WorldLoadingBone(widthFactor: 0.96, height: 92, radius: 6),
      ],
    );
  }
}

class WorldLoadingBone extends StatelessWidget {
  const WorldLoadingBone({
    super.key,
    this.width,
    this.widthFactor,
    required this.height,
    this.radius = 4,
  });

  final double? width;
  final double? widthFactor;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final child = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE9EDF2),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox(width: width, height: height),
    );
    final widthFactor = this.widthFactor;
    if (widthFactor == null) return child;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

class WorldDetailSection extends StatelessWidget {
  const WorldDetailSection({
    required this.world,
    required this.currentUid,
    this.newUserJoinNotice,
    this.onDeleteWorld,
    this.showCharacters = true,
  });

  final WorldDetail world;
  final String currentUid;
  final WorldNewUserJoinNotice? newUserJoinNotice;
  final Future<void> Function(BuildContext context, WorldDetail world)?
  onDeleteWorld;
  final bool showCharacters;

  @override
  Widget build(BuildContext context) {
    final title = world.name.trim().isEmpty ? world.worldId : world.name.trim();
    final owner = worldOwnerDisplayName(world);
    final ownerUid = world.ownerUid.trim();
    final version = world.origin.versionNum <= 0 ? 1 : world.origin.versionNum;
    final sourceWorldoOid = world.origin.oid.trim();
    final sourceWorldoRouteId = sourceWorldoOid.isNotEmpty
        ? sourceWorldoOid
        : world.originId > 0
        ? '${world.originId}'
        : '';
    final sourceOid = sourceWorldoOid.isEmpty
        ? '${world.originId}'
        : sourceWorldoOid;
    final canOpenSourceWorldo = sourceWorldoRouteId.isNotEmpty;
    final brief = world.brief.trim().isEmpty ? '-' : world.brief.trim();
    final cover = worldResolveAssetUrl(world.cover).trim();
    final canDeleteWorld = worldCanDeleteLaunchedOnlyBySelf(world, currentUid);
    final metaStyle = CopyableIdLabel.textStyle.copyWith(height: 1.2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          key: const ValueKey<String>('world-detail-basic-info'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WorldDetailCoverImage(url: cover),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          key: const ValueKey<String>('world-detail-name'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4B6192),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      GenesisMoreActionMenuButton(
                        buttonSize: 18 * 1.25,
                        items: [
                          genesisReportMenuItem(
                            context: context,
                            targetType: 'world',
                            targetId: world.worldId,
                          ),
                          GenesisActionMenuItem(
                            label: 'Delete',
                            iconAsset: genesisDeleteIconAsset,
                            textStyle: TextStyle(
                              fontSize: 12,
                              height: 1.2,
                              fontWeight: FontWeight.w400,
                              color: canDeleteWorld
                                  ? Colors.white
                                  : GenesisColors.darkTextTertiary,
                            ),
                            onSelected: () {
                              if (!canDeleteWorld) {
                                showGenesisToast(
                                  context,
                                  'Only worlds launched by you alone can be deleted.',
                                  duration: const Duration(seconds: 3),
                                );
                                return;
                              }
                              unawaited(onDeleteWorld?.call(context, world));
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  CopyableIdLabel(
                    label: 'WID',
                    value: world.worldId,
                    displayValue: world.deleted
                        ? deletedEntityDisplayText
                        : null,
                    enabled: !world.deleted,
                    customTextStyle: metaStyle,
                    customIconColor: worldHeaderMetaColor,
                  ),
                  GenesisInlineMetaLabel(
                    text: 'Owner: $owner',
                    onTap: ownerUid.isEmpty || world.ownerDeleted
                        ? null
                        : () => Navigator.of(context).pushNamed(
                            RouteNames.userInfo,
                            arguments: {'uid': ownerUid},
                          ),
                    style: metaStyle,
                    trailingIcon: ownerUid.isEmpty || world.ownerDeleted
                        ? null
                        : Icons.chevron_right,
                    trailingIconColor: worldHeaderMetaColor,
                    trailingIconSize: genesisCopyableIdIconSize,
                    trailingGap: 4,
                  ),
                  GenesisInlineMetaLabel(
                    text: 'Source Worldo: $sourceOid · V$version',
                    onTap: !canOpenSourceWorldo
                        ? null
                        : () => Navigator.of(context).pushNamed(
                            RouteNames.originWorld,
                            arguments: {
                              'oid': sourceWorldoRouteId,
                              'originId': world.originId,
                              'initialName': world.origin.name,
                            },
                          ),
                    style: metaStyle,
                    trailingIcon: canOpenSourceWorldo
                        ? Icons.chevron_right
                        : null,
                    trailingIconColor: worldHeaderMetaColor,
                    trailingIconSize: genesisCopyableIdIconSize,
                    trailingGap: 4,
                  ),
                  const SizedBox(height: 10),
                  GenesisPrimaryButton(
                    key: const ValueKey<String>('world-detail-invite-button'),
                    label: 'Invite',
                    onPressed: () => _copyInviteText(context, worldName: title),
                    height: 34,
                    width: 92,
                    backgroundColor: const Color(0xFFFF2442),
                    disabledBackgroundColor: const Color(
                      0xFFFF2442,
                    ).withValues(alpha: 0.62),
                    foregroundColor: Colors.white,
                    fontSize: 14,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  if (newUserJoinNotice != null) ...[
                    const SizedBox(height: 8),
                    _WorldNewUserJoinNoticeSwitcher(notice: newUserJoinNotice!),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const WorldDetailSectionTitle(title: 'World Brief'),
        const SizedBox(height: 8),
        Text(brief, style: worldDetailBodyTextStyle),
        const SizedBox(height: 24),
        const WorldDetailSectionTitle(title: 'Cast'),
        const SizedBox(height: 8),
        if (showCharacters)
          WorldCharactersSection(world: world, currentUid: currentUid),
      ],
    );
  }

  Future<void> _copyInviteText(
    BuildContext context, {
    required String worldName,
  }) async {
    await Clipboard.setData(
      ClipboardData(
        text: worldInviteShareTextForTesting(
          worldName: worldName,
          wid: world.worldId,
        ),
      ),
    );
    if (!context.mounted) return;
    showGenesisToast(context, 'Link copied. Share it with your friends.');
  }
}

class WorldDetailSectionListView extends StatelessWidget {
  const WorldDetailSectionListView({
    required this.storageKey,
    required this.world,
    required this.currentUid,
    this.controller,
    this.newUserJoinNotice,
    this.onDeleteWorld,
  });

  final String storageKey;
  final WorldDetail world;
  final String currentUid;
  final ScrollController? controller;
  final WorldNewUserJoinNotice? newUserJoinNotice;
  final Future<void> Function(BuildContext context, WorldDetail world)?
  onDeleteWorld;

  @override
  Widget build(BuildContext context) {
    final sortedCharacters = worldSortedCharacters(
      world.characters,
      currentUid,
    );
    final hasCharacterRole = sortedCharacters.any(worldIsCharacterRole);
    final itemCount = 1 + math.max(sortedCharacters.length, 1).toInt();
    return WorldSectionListView.builder(
      storageKey: storageKey,
      controller: controller,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: 5),
            child: WorldDetailSection(
              world: world,
              currentUid: currentUid,
              newUserJoinNotice: newUserJoinNotice,
              onDeleteWorld: onDeleteWorld,
              showCharacters: false,
            ),
          );
        }
        if (sortedCharacters.isEmpty) {
          return const WorldEmptySection(text: 'No characters yet.');
        }
        final characterIndex = index - 1;
        final character = sortedCharacters[characterIndex];
        return Padding(
          padding: EdgeInsets.only(
            top: characterIndex == 0 ? (hasCharacterRole ? 5 : 0) : 22,
          ),
          child: WorldCharacterRow(
            character: character,
            currentUid: currentUid,
            subtitle: worldCharacterDescriptionText(character),
            subtitleColor: const Color(0xFF666666),
            showCharacterDetails: true,
          ),
        );
      },
    );
  }
}

String worldInviteShareTextForTesting({
  required String worldName,
  required String wid,
}) {
  final resolvedWid = wid.trim();
  final resolvedWorldName = worldName.trim().isEmpty
      ? resolvedWid
      : worldName.trim();
  return 'Join my world "$resolvedWorldName" on Worldo!\n'
      '$resolvedWid\n'
      'Search this WID on Worldo to find and join.\n'
      'https://worldo.ai/download';
}

class _WorldNewUserJoinNoticeSwitcher extends StatelessWidget {
  const _WorldNewUserJoinNoticeSwitcher({required this.notice});

  final WorldNewUserJoinNotice notice;

  @override
  Widget build(BuildContext context) {
    final currentKey = ValueKey<String>(_noticeAnimationKey(notice));
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final isIncoming = child.key == currentKey;
          final offset = isIncoming
              ? Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(animation)
              : Tween<Offset>(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(animation);
          return SlideTransition(position: offset, child: child);
        },
        child: _WorldNewUserJoinNoticeText(key: currentKey, notice: notice),
      ),
    );
  }

  String _noticeAnimationKey(WorldNewUserJoinNotice notice) {
    return [
      notice.characterId,
      notice.playerUid,
      notice.playerUsername,
      notice.characterName,
      notice.ts?.millisecondsSinceEpoch ?? 0,
    ].join('|');
  }
}

class _WorldNewUserJoinNoticeText extends StatelessWidget {
  const _WorldNewUserJoinNoticeText({super.key, required this.notice});

  final WorldNewUserJoinNotice notice;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      color: Color(0xFF666666),
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w400,
    );
    const emphasisStyle = TextStyle(
      color: Color(0xFF111111),
      fontWeight: FontWeight.w600,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: constraints.maxWidth,
              child: RichText(
                maxLines: 2,
                overflow: TextOverflow.clip,
                text: TextSpan(
                  style: baseStyle,
                  children: [
                    TextSpan(
                      text: notice.displayPlayerUsername,
                      style: emphasisStyle,
                    ),
                    const TextSpan(text: ' playing as '),
                    TextSpan(
                      text: notice.displayCharacterName,
                      style: emphasisStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class WorldDetailSectionTitle extends StatelessWidget {
  const WorldDetailSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: Color(0xFF111111),
      ),
    );
  }
}

class WorldDetailCoverImage extends StatelessWidget {
  const WorldDetailCoverImage({required this.url});

  static const double width = 120;
  static const double height = 180;

  final String url;

  @override
  Widget build(BuildContext context) {
    final viewerUrl = url.trim();
    final fallback = Container(
      color: const Color(0xFFEFF1F4),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: Color(0xFF9A9A9A)),
    );

    final imageUrl = selectGenesisImageUrl(
      url,
      logicalWidth: width,
      logicalHeight: height,
      devicePixelRatio: MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1,
    );
    final preview = Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        key: const ValueKey<String>('world-detail-cover'),
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: GenesisImageRadii.content,
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
                  placeholder: (_) => fallback,
                  errorWidget: (_, _) => fallback,
                ),
        ),
      ),
    );
    if (viewerUrl.isEmpty) return preview;
    return GestureDetector(
      key: const ValueKey<String>('world-detail-cover-viewer'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showGenesisImageViewer(
        context,
        imageUrls: [viewerUrl],
        previewImageProviders: [
          genesisImageViewerPreviewProvider(
            context,
            imageUrl: imageUrl,
            logicalWidth: width,
            logicalHeight: height,
            fit: BoxFit.cover,
          ),
        ],
      ),
      child: preview,
    );
  }
}

class WorldSectionListView extends StatelessWidget {
  const WorldSectionListView({
    required this.storageKey,
    required this.child,
    this.controller,
  }) : itemCount = null,
       itemBuilder = null;

  const WorldSectionListView.builder({
    required this.storageKey,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
  }) : child = null;

  final String storageKey;
  final ScrollController? controller;
  final Widget? child;
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;

  @override
  Widget build(BuildContext context) {
    final itemBuilder = this.itemBuilder;
    if (itemBuilder != null) {
      return ListView.builder(
        key: PageStorageKey<String>(storageKey),
        controller: controller,
        primary: false,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          12,
          worldSheetVisibleContentTopGap,
          12,
          32,
        ),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    }
    return ListView(
      key: PageStorageKey<String>(storageKey),
      controller: controller,
      primary: false,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        12,
        worldSheetVisibleContentTopGap,
        12,
        32,
      ),
      children: [child!],
    );
  }
}

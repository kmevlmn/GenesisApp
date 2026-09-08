part of 'origin_world_page.dart';

class _OriginCharactersSection extends StatelessWidget {
  const _OriginCharactersSection({required this.characters});

  final List<OriginCharacter> characters;

  @override
  Widget build(BuildContext context) {
    final sortedCharacters = originCharactersRecommendedFirst(characters);
    final characterAvatarUrls = characters
        .map((character) => _resolveAssetUrl(character.avatar).trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    final imageIndexByUrl = <String, int>{};
    for (final entry in characterAvatarUrls.indexed) {
      imageIndexByUrl.putIfAbsent(entry.$2, () => entry.$1);
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _SectionTitle(title: 'Characters (${characters.length})'),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        if (characters.isEmpty)
          const SliverToBoxAdapter(
            child: Text('No characters', style: _mutedBodyTextStyle),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final character = sortedCharacters[index];
              final avatarUrl = _resolveAssetUrl(character.avatar).trim();
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == sortedCharacters.length - 1 ? 0 : 20,
                ),
                child: _OriginCharacterRow(
                  character: character,
                  imageUrls: characterAvatarUrls,
                  initialImageIndex: imageIndexByUrl[avatarUrl] ?? 0,
                ),
              );
            }, childCount: sortedCharacters.length),
          ),
      ],
    );
  }
}

class _OriginCharacterRow extends StatelessWidget {
  const _OriginCharacterRow({
    required this.character,
    required this.imageUrls,
    required this.initialImageIndex,
  });

  final OriginCharacter character;
  final List<String> imageUrls;
  final int initialImageIndex;

  @override
  Widget build(BuildContext context) {
    final identity = _splitTags(character.tags).join(' · ');
    final tagline = character.tagline.trim();
    final goal = character.goal.trim();
    final avatarUrl = _resolveAssetUrl(character.avatar);

    return Row(
      key: ValueKey<String>(
        'origin-character-row-${_characterStableId(character)}',
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OriginCharacterPortrait(
          characterId: _characterStableId(character),
          url: avatarUrl,
          name: character.name,
          imageUrls: imageUrls,
          initialImageIndex: initialImageIndex,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                character.name,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: originWorldDetailSheetPrimaryTextColor,
                  decoration: TextDecoration.none,
                ),
              ),
              if (identity.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(identity, style: _bodyTextStyle),
              ],
              if (tagline.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  tagline,
                  style: _bodyTextStyle.copyWith(
                    color: GenesisColors.redSecondary,
                  ),
                ),
              ],
              if (goal.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text('Goal: $goal', style: _characterBodyTextStyle),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OriginCharacterPortrait extends StatelessWidget {
  const _OriginCharacterPortrait({
    required this.characterId,
    required this.url,
    required this.name,
    required this.imageUrls,
    required this.initialImageIndex,
  });

  static const double _width = 86;
  static const double _borderRadius = GenesisAvatarRadii.character;

  final String characterId;
  final String url;
  final String name;
  final List<String> imageUrls;
  final int initialImageIndex;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final resolvedUrl = selectGenesisImageUrl(
      url,
      logicalWidth: _width,
      logicalHeight: _width,
      devicePixelRatio: devicePixelRatio,
      maxDevicePixelRatio: devicePixelRatio,
    ).trim();
    final fallback = GenesisAvatarFallback(
      name: name,
      width: _width,
      height: _width,
      borderRadius: _borderRadius,
    );
    final image = resolvedUrl.isEmpty
        ? fallback
        : resolvedUrl.startsWith('assets/')
        ? Image.asset(
            resolvedUrl,
            width: _width,
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
            errorBuilder: (context, error, stackTrace) => fallback,
          )
        : GenesisStaticNetworkImage(
            imageUrl: resolvedUrl,
            width: _width,
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
            maxDevicePixelRatio: devicePixelRatio,
            placeholder: (_) => const SizedBox(width: _width, height: _width),
            errorWidget: (_, _) => fallback,
          );
    final portrait = SizedBox(
      width: _width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_borderRadius),
        child: image,
      ),
    );
    if (resolvedUrl.isEmpty) return portrait;
    return GestureDetector(
      key: ValueKey('origin-character-portrait-$characterId'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showGenesisImageViewer(
        context,
        imageUrls: imageUrls,
        maxDevicePixelRatio: devicePixelRatio,
        previewImageProviders: [
          for (final imageUrl in imageUrls)
            genesisImageViewerPreviewProvider(
              context,
              imageUrl: selectGenesisImageUrl(
                imageUrl,
                logicalWidth: _width,
                logicalHeight: _width,
                devicePixelRatio: devicePixelRatio,
                maxDevicePixelRatio: devicePixelRatio,
              ).trim(),
              logicalWidth: _width,
              fit: BoxFit.fitWidth,
              maxDevicePixelRatio: devicePixelRatio,
            ),
        ],
        initialIndex: initialImageIndex,
      ),
      child: portrait,
    );
  }
}

const _bodyTextStyle = TextStyle(
  fontSize: 13,
  height: 1.4,
  fontWeight: FontWeight.w400,
  color: originWorldDetailSheetSecondaryTextColor,
  decoration: TextDecoration.none,
);

const _characterBodyTextStyle = TextStyle(
  fontSize: 13,
  height: 1.4,
  fontWeight: FontWeight.w400,
  color: originWorldDetailSheetSecondaryTextColor,
  decoration: TextDecoration.none,
);

const _mutedBodyTextStyle = TextStyle(
  fontSize: 13,
  height: 1.3,
  fontWeight: FontWeight.w400,
  color: originWorldDetailSheetTertiaryTextColor,
  decoration: TextDecoration.none,
);

const _originTickContentLabelStyle = TextStyle(
  fontSize: 13,
  height: 1.4,
  fontWeight: FontWeight.w600,
  color: originWorldDetailSheetPrimaryTextColor,
  decoration: TextDecoration.none,
);

const _originTickContentTextStyle = TextStyle(
  fontSize: 13,
  height: 1.4,
  fontWeight: FontWeight.w400,
  color: originWorldDetailSheetSecondaryTextColor,
  decoration: TextDecoration.none,
);

const _originTickContentTimestampStyle = TextStyle(
  fontSize: 13,
  height: 1.4,
  fontWeight: FontWeight.w400,
  color: originWorldDetailSheetTertiaryTextColor,
  decoration: TextDecoration.none,
);

String _characterStableId(OriginCharacter character) {
  final explicitId = character.characterId.trim();
  if (explicitId.isNotEmpty) return explicitId;
  if (character.id > 0) return '${character.id}';
  return character.name.trim();
}

List<String> _splitTags(String tags) {
  if (tags.trim().isEmpty) return const [];
  return tags
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

Map<String, dynamic>? _originPreviewTick(OriginDetail origin) {
  final tick = _originTick1(origin);
  if (tick == null) return null;
  final result = tick['tick_result'] is Map
      ? (tick['tick_result'] as Map).cast<String, dynamic>()
      : const <String, dynamic>{};
  final narrator = _mapString(result, const ['narrator']);
  final paragraphsRaw = result['paragraphs'];
  final paragraphs = paragraphsRaw is List
      ? paragraphsRaw
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .where(_originPreviewParagraphHasText)
            .toList(growable: false)
      : const <Map<String, dynamic>>[];

  return <String, dynamic>{
    'created_at': tick['created_at'] ?? origin.updatedAt,
    'tick_result': <String, dynamic>{
      'current_time': _mapString(result, const ['current_time']),
      'narrator': narrator,
      'paragraphs': paragraphs,
    },
  };
}

Map<String, dynamic>? _originTick1(OriginDetail origin) {
  for (final tick in origin.ticks) {
    if (_mapInt(tick, const ['tick_no']) == 1) return tick;
  }
  return origin.ticks.isEmpty ? null : origin.ticks.first;
}

bool _originPreviewParagraphHasText(Map<String, dynamic> paragraph) {
  return _mapString(paragraph, const [
    'content',
    'text',
    'summary',
    'narrator',
  ]).isNotEmpty;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

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
        color: originWorldDetailSheetPrimaryTextColor,
      ),
    );
  }
}

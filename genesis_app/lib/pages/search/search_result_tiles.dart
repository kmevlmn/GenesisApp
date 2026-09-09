part of 'search_page.dart';

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.item, required this.onTap});

  final _SearchResultItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isUser = item.tab == _SearchTab.user;
    const titleStyle = TextStyle(
      color: GenesisColors.darkTextPrimary,
      fontSize: 14,
      height: 1.1,
      fontWeight: FontWeight.w600,
    );
    final content = Padding(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            _searchResultTitleSpan(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
          SizedBox(height: isUser ? 7 : 4),
          if (item.tab == _SearchTab.origin)
            _OriginSearchMetadata(item: item)
          else if (isUser)
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'UID: '),
                  _highlightedSearchSpan(
                    formatCopyableIdValue(item.displaySubtitle),
                    _userIdRanges(item.userV2!, item.searchQuery),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CopyableIdLabel.textStyle.copyWith(
                color: GenesisColors.darkTextTertiary,
              ),
            )
          else
            _WorldSearchMetadata(item: item),
          if (!isUser) ...[const SizedBox(height: 4), _ResultStats(item: item)],
        ],
      ),
    );
    final tile = item.tab == _SearchTab.world
        ? GenesisWorldListCardLayout(
            imageUrl: item.coverImage,
            placeholder: const ColoredBox(color: GenesisColors.darkFaintFill),
            content: content,
          )
        : item.tab == _SearchTab.origin
        ? GenesisOriginListCardLayout(
            imageUrl: item.coverImage,
            placeholder: const ColoredBox(color: GenesisColors.darkFaintFill),
            content: content,
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResultThumb(item: item),
              const SizedBox(width: 10),
              Expanded(child: content),
            ],
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: tile,
    );
  }
}

const _searchMetadataStyle = TextStyle(
  color: GenesisColors.darkTextTertiary,
  fontSize: 12,
  fontWeight: FontWeight.w400,
  height: 1.2,
);

const _searchSummaryStyle = TextStyle(
  color: GenesisColors.darkTextSecondary,
  fontSize: 12,
  fontWeight: FontWeight.w400,
  height: 1.2,
);

const _worldSearchMetadataStyle = TextStyle(
  color: GenesisColors.darkTextTertiary,
  fontSize: 12,
  fontWeight: FontWeight.w400,
  height: 1.2,
);

const _searchMatchStyle = TextStyle(
  color: GenesisColors.redSecondary,
  fontWeight: FontWeight.w600,
);

class _OriginSearchMetadata extends StatelessWidget {
  const _OriginSearchMetadata({required this.item});

  final _SearchResultItem item;

  @override
  Widget build(BuildContext context) {
    final origin = item.originV2!;
    final brief = origin.brief.isEmpty ? '-' : origin.brief;
    final briefRanges = origin.brief.isEmpty
        ? const <SearchV2HighlightRange>[]
        : _originRanges(origin, 'brief');
    final showBrief = origin.matches.whereType<SearchV2TextMatch>().any(
      (match) => match.field == 'brief',
    );
    final showCharacters = origin.matches
        .whereType<SearchV2CharacterMatch>()
        .any((match) => match.field == 'character_name');
    final tagMatches = origin.matches.whereType<SearchV2TagMatch>();
    final showTags = _matchedTagEntries(origin.tags, tagMatches).isNotEmpty;
    final summaries = <Widget>[
      if (showCharacters) _OriginCharactersSummary(origin: origin),
      if (showBrief)
        _SearchBriefExcerpt(text: brief, highlightRanges: briefRanges),
      if (showTags) _MatchedTagsSummary(tags: origin.tags, matches: tagMatches),
    ];
    if (summaries.isEmpty) {
      summaries.add(
        _SearchBriefExcerpt(
          text: brief,
          highlightRanges: const <SearchV2HighlightRange>[],
        ),
      );
    }
    final rows = <Widget>[
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'OID: '),
            _highlightedSearchSpan(
              _dashOrValue(origin.originId),
              _originIdRanges(origin, item.searchQuery),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _searchMetadataStyle,
      ),
      Text(
        'Originator: ${formatUidForDisplay(origin.owner.name, fallback: '-')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _searchMetadataStyle.copyWith(
          color: GenesisColors.darkTextSecondary,
        ),
      ),
      ...summaries.take(2),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < rows.length; index += 1) ...[
          if (index > 0) const SizedBox(height: 4),
          rows[index],
        ],
      ],
    );
  }
}

class _WorldSearchMetadata extends StatelessWidget {
  const _WorldSearchMetadata({required this.item});

  final _SearchResultItem item;

  @override
  Widget build(BuildContext context) {
    final world = item.worldV2!;
    final owner = formatUidForDisplay(world.owner.name, fallback: '-');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'WID: '),
              _highlightedSearchSpan(
                _dashOrValue(world.worldId),
                _worldIdRanges(world, item.searchQuery),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _worldSearchMetadataStyle,
        ),
        const SizedBox(height: 4),
        Text(
          'Owner: $owner',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _worldSearchMetadataStyle.copyWith(
            color: GenesisColors.darkTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _MatchedTagsSummary extends StatelessWidget {
  const _MatchedTagsSummary({required this.tags, required this.matches});

  final List<String> tags;
  final Iterable<SearchV2TagMatch> matches;

  @override
  Widget build(BuildContext context) {
    final entries = _matchedTagEntries(tags, matches);
    if (entries.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      key: const ValueKey<String>('origin-summary-tags'),
      decoration: BoxDecoration(
        color: GenesisColors.darkFaintFill,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 20,
          child: Center(
            widthFactor: 1,
            child: Text.rich(
              TextSpan(
                children: [
                  for (var index = 0; index < entries.length; index += 1) ...[
                    if (index > 0) const TextSpan(text: ', '),
                    _highlightedSearchSpan(
                      entries[index].tag,
                      entries[index].highlightRanges,
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _searchSummaryStyle,
            ),
          ),
        ),
      ),
    );
  }
}

List<_MatchedTagEntry> _matchedTagEntries(
  List<String> tags,
  Iterable<SearchV2TagMatch> matches,
) {
  final rangesByIndex = <int, List<SearchV2HighlightRange>>{};
  for (final match in matches) {
    final tagIndex = match.tagIndex;
    if (match.field != 'tag' || tagIndex < 0 || tagIndex >= tags.length) {
      continue;
    }
    (rangesByIndex[tagIndex] ??= <SearchV2HighlightRange>[]).addAll(
      match.highlightRanges,
    );
  }
  final indexes = rangesByIndex.keys.toList(growable: false)..sort();
  return [
    for (final index in indexes)
      _MatchedTagEntry(
        tag: tags[index],
        highlightRanges: rangesByIndex[index]!,
      ),
  ];
}

class _MatchedTagEntry {
  const _MatchedTagEntry({required this.tag, required this.highlightRanges});

  final String tag;
  final List<SearchV2HighlightRange> highlightRanges;
}

class _OriginCharactersSummary extends StatelessWidget {
  const _OriginCharactersSummary({required this.origin});

  final SearchV2OriginItem origin;

  @override
  Widget build(BuildContext context) {
    final matchesByCharacterId = <String, List<SearchV2HighlightRange>>{};
    for (final match in origin.matches.whereType<SearchV2CharacterMatch>()) {
      if (match.field != 'character_name') continue;
      (matchesByCharacterId[match.characterId] ??= <SearchV2HighlightRange>[])
          .addAll(match.highlightRanges);
    }
    final matchedCharacters = origin.characters
        .where(
          (character) =>
              matchesByCharacterId.containsKey(character.characterId),
        )
        .toList(growable: false);
    if (matchedCharacters.isEmpty) return const SizedBox.shrink();
    return Row(
      key: const ValueKey<String>('origin-summary-characters'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: SvgPicture.asset(
            characterStatIconAsset,
            width: 12,
            height: 12,
            colorFilter: const ColorFilter.mode(
              GenesisColors.darkTextSecondary,
              BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                for (
                  var index = 0;
                  index < matchedCharacters.length;
                  index += 1
                ) ...[
                  if (index > 0) const TextSpan(text: ', '),
                  _highlightedSearchSpan(
                    _dashOrValue(matchedCharacters[index].name),
                    matchesByCharacterId[matchedCharacters[index].characterId]!,
                  ),
                ],
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: _searchSummaryStyle,
          ),
        ),
      ],
    );
  }
}

class _SearchBriefExcerpt extends StatelessWidget {
  const _SearchBriefExcerpt({
    required this.text,
    required this.highlightRanges,
  });

  final String text;
  final Iterable<SearchV2HighlightRange> highlightRanges;

  @override
  Widget build(BuildContext context) {
    final ranges = _mergedSearchHighlightRanges(text, highlightRanges);
    return LayoutBuilder(
      builder: (context, constraints) {
        final excerpt = _searchBriefExcerptForWidth(
          context,
          text: text,
          ranges: ranges,
          maxWidth: constraints.maxWidth,
        );
        return Text.rich(
          TextSpan(
            children: [
              _highlightedSearchSpan(excerpt.text, excerpt.highlightRanges),
            ],
          ),
          key: const ValueKey<String>('origin-summary-brief'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: _searchSummaryStyle,
        );
      },
    );
  }
}

_SearchBriefExcerptData _searchBriefExcerptForWidth(
  BuildContext context, {
  required String text,
  required List<_SearchHighlightRange> ranges,
  required double maxWidth,
}) {
  final full = _SearchBriefExcerptData(
    text: text,
    highlightRanges: [
      for (final range in ranges)
        SearchV2HighlightRange(
          start: range.start,
          length: range.end - range.start,
        ),
    ],
  );
  if (!maxWidth.isFinite ||
      ranges.isEmpty ||
      _searchBriefFits(context, excerpt: full, maxWidth: maxWidth)) {
    return full;
  }

  var lowerContextLength = 0;
  var upperContextLength = text.length;
  var best = _buildSearchBriefExcerpt(text, ranges, contextLength: 0);
  while (lowerContextLength <= upperContextLength) {
    final contextLength = (lowerContextLength + upperContextLength) ~/ 2;
    final candidate = _buildSearchBriefExcerpt(
      text,
      ranges,
      contextLength: contextLength,
    );
    if (_searchBriefFits(context, excerpt: candidate, maxWidth: maxWidth)) {
      best = candidate;
      lowerContextLength = contextLength + 1;
    } else {
      upperContextLength = contextLength - 1;
    }
  }
  return best;
}

bool _searchBriefFits(
  BuildContext context, {
  required _SearchBriefExcerptData excerpt,
  required double maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(
      style: _searchSummaryStyle,
      children: [_highlightedSearchSpan(excerpt.text, excerpt.highlightRanges)],
    ),
    maxLines: 2,
    ellipsis: '…',
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.localeOf(context),
  )..layout(maxWidth: maxWidth);
  return !painter.didExceedMaxLines;
}

_SearchBriefExcerptData _buildSearchBriefExcerpt(
  String text,
  List<_SearchHighlightRange> ranges, {
  required int contextLength,
}) {
  final windows = <_SearchHighlightRange>[];
  for (final range in ranges) {
    final expanded = _SearchHighlightRange(
      (range.start - contextLength).clamp(0, text.length).toInt(),
      (range.end + contextLength).clamp(0, text.length).toInt(),
    );
    if (windows.isEmpty || expanded.start > windows.last.end) {
      windows.add(expanded);
      continue;
    }
    final previous = windows.removeLast();
    windows.add(
      _SearchHighlightRange(
        previous.start,
        expanded.end > previous.end ? expanded.end : previous.end,
      ),
    );
  }

  final buffer = StringBuffer();
  final excerptRanges = <SearchV2HighlightRange>[];
  for (var index = 0; index < windows.length; index += 1) {
    final window = windows[index];
    if (index == 0 && window.start > 0) {
      final leadingEnd = _searchBriefLeadingContextEnd(text, window.start);
      buffer.write(text.substring(0, leadingEnd));
      if (leadingEnd < window.start) buffer.write('…');
    } else if (index > 0 && window.start > windows[index - 1].end) {
      buffer.write('…');
    }
    final outputStart = buffer.length;
    buffer.write(text.substring(window.start, window.end));
    for (final range in ranges) {
      final start = range.start > window.start ? range.start : window.start;
      final end = range.end < window.end ? range.end : window.end;
      if (end <= start) continue;
      excerptRanges.add(
        SearchV2HighlightRange(
          start: outputStart + start - window.start,
          length: end - start,
        ),
      );
    }
  }
  if (windows.last.end < text.length) buffer.write('…');
  return _SearchBriefExcerptData(
    text: buffer.toString(),
    highlightRanges: excerptRanges,
  );
}

int _searchBriefLeadingContextEnd(String text, int omittedEnd) {
  const preferredLength = 18;
  if (omittedEnd <= preferredLength) return omittedEnd;
  final boundary = text.lastIndexOf(' ', preferredLength);
  return boundary > 0 ? boundary : preferredLength;
}

class _SearchBriefExcerptData {
  const _SearchBriefExcerptData({
    required this.text,
    required this.highlightRanges,
  });

  final String text;
  final List<SearchV2HighlightRange> highlightRanges;
}

TextSpan _searchResultTitleSpan(_SearchResultItem item) {
  switch (item.tab) {
    case _SearchTab.origin:
      final origin = item.originV2!;
      final rawName = origin.originName;
      if (rawName.trim().isEmpty) {
        return TextSpan(text: item.displayTitle);
      }
      return TextSpan(
        children: [
          if (!rawName.startsWith('#')) const TextSpan(text: '#'),
          _highlightedSearchSpan(rawName, _originRanges(origin, 'origin_name')),
        ],
      );
    case _SearchTab.world:
      final world = item.worldV2!;
      final rawName = world.worldName;
      return _highlightedSearchSpan(
        rawName.trim().isEmpty ? item.displayTitle : rawName,
        world.matches
            .where((match) => match.field == 'world_name')
            .expand((match) => match.highlightRanges),
      );
    case _SearchTab.user:
      final user = item.userV2!;
      final rawName = user.name;
      return _highlightedSearchSpan(
        rawName.trim().isEmpty ? item.displayTitle : rawName,
        user.matches
            .where((match) => match.field == 'user_name')
            .expand((match) => match.highlightRanges),
      );
  }
}

Iterable<SearchV2HighlightRange> _originRanges(
  SearchV2OriginItem origin,
  String field,
) {
  return origin.matches
      .whereType<SearchV2TextMatch>()
      .where((match) => match.field == field)
      .expand((match) => match.highlightRanges);
}

Iterable<SearchV2HighlightRange> _originIdRanges(
  SearchV2OriginItem origin,
  String query,
) sync* {
  yield* origin.matches
      .whereType<SearchV2TextMatch>()
      .where((match) => const {'origin_id', 'oid'}.contains(match.field))
      .expand((match) => match.highlightRanges);
  yield* _localIdQueryRanges(origin.originId, query);
}

Iterable<SearchV2HighlightRange> _worldIdRanges(
  SearchV2WorldItem world,
  String query,
) sync* {
  yield* world.matches
      .where((match) => const {'world_id', 'wid'}.contains(match.field))
      .expand((match) => match.highlightRanges);
  yield* _localIdQueryRanges(world.worldId, query);
}

Iterable<SearchV2HighlightRange> _userIdRanges(
  SearchV2UserItem user,
  String query,
) sync* {
  yield* user.matches
      .where((match) => const {'uid', 'user_id'}.contains(match.field))
      .expand((match) => match.highlightRanges);
  yield* _localIdQueryRanges(user.uid, query);
}

Iterable<SearchV2HighlightRange> _localIdQueryRanges(
  String id,
  String rawQuery,
) sync* {
  final query = rawQuery.trim();
  if (id.isEmpty || query.isEmpty) return;
  final normalizedId = id.toLowerCase();
  final normalizedQuery = query.toLowerCase();
  var start = 0;
  while (start < normalizedId.length) {
    final matchStart = normalizedId.indexOf(normalizedQuery, start);
    if (matchStart < 0) return;
    yield SearchV2HighlightRange(
      start: matchStart,
      length: normalizedQuery.length,
    );
    start = matchStart + normalizedQuery.length;
  }
}

TextSpan _highlightedSearchSpan(
  String text,
  Iterable<SearchV2HighlightRange> ranges,
) {
  final merged = _mergedSearchHighlightRanges(text, ranges);
  if (merged.isEmpty) return TextSpan(text: text);

  final spans = <InlineSpan>[];
  var offset = 0;
  for (final range in merged) {
    if (range.start > offset) {
      spans.add(TextSpan(text: text.substring(offset, range.start)));
    }
    spans.add(
      TextSpan(
        text: text.substring(range.start, range.end),
        style: _searchMatchStyle,
      ),
    );
    offset = range.end;
  }
  if (offset < text.length) {
    spans.add(TextSpan(text: text.substring(offset)));
  }
  return TextSpan(children: spans);
}

List<_SearchHighlightRange> _mergedSearchHighlightRanges(
  String text,
  Iterable<SearchV2HighlightRange> ranges,
) {
  if (text.isEmpty) return const <_SearchHighlightRange>[];
  final normalized = <_SearchHighlightRange>[];
  for (final range in ranges) {
    if (range.length <= 0 || range.start >= text.length) continue;
    final start = range.start.clamp(0, text.length).toInt();
    final end = (range.start + range.length).clamp(0, text.length).toInt();
    if (end > start) normalized.add(_SearchHighlightRange(start, end));
  }
  normalized.sort((a, b) => a.start.compareTo(b.start));

  final merged = <_SearchHighlightRange>[];
  for (final range in normalized) {
    if (merged.isEmpty || range.start > merged.last.end) {
      merged.add(range);
      continue;
    }
    final previous = merged.removeLast();
    merged.add(
      _SearchHighlightRange(
        previous.start,
        range.end > previous.end ? range.end : previous.end,
      ),
    );
  }
  return merged;
}

class _SearchHighlightRange {
  const _SearchHighlightRange(this.start, this.end);

  final int start;
  final int end;
}

class _ResultThumb extends StatelessWidget {
  const _ResultThumb({required this.item});

  final _SearchResultItem item;

  @override
  Widget build(BuildContext context) {
    const userAvatarSize = 52.0;
    const resultCoverWidth = 60.0;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (item.tab == _SearchTab.user) {
      return GenesisAvatar(
        url: item.coverImage,
        name: item.title,
        size: userAvatarSize,
        maxDevicePixelRatio: devicePixelRatio,
      );
    }
    final imageHeight = item.tab == _SearchTab.origin
        ? resultCoverWidth / genesisOriginCoverAspectRatio
        : resultCoverWidth;
    return GenesisListImage(
      imageUrl: item.coverImage,
      placeholder: const ColoredBox(color: GenesisColors.darkFaintFill),
      width: resultCoverWidth,
      height: imageHeight,
      maxDevicePixelRatio: devicePixelRatio,
    );
  }
}

class _ResultStats extends StatelessWidget {
  const _ResultStats({required this.item});

  final _SearchResultItem item;

  @override
  Widget build(BuildContext context) {
    if (item.tab == _SearchTab.world) {
      return Text(
        formatWorldStatsLabel(
          tickNo: item.tickCount,
          subTickNo: item.subTickNo,
          messageCount: item.connectCount,
          playerCount: item.playerCount,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: GenesisColors.darkTextSecondary,
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w400,
        ),
      );
    }
    final stats = item.tab == _SearchTab.origin
        ? [
            _StatData(iconAsset: copyStatIconAsset, value: item.copyCount),
            _StatData(
              iconAsset: connectStatIconAsset,
              value: item.connectCount,
            ),
            _StatData(
              iconAsset: characterStatIconAsset,
              value: item.characterCount,
            ),
          ]
        : const <_StatData>[];

    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final stat in stats)
          StatItem(
            icon: stat.icon,
            iconAsset: stat.iconAsset,
            preserveIconAssetColor: stat.preserveIconAssetColor,
            iconSize: 12,
            iconColor: GenesisColors.darkTextSecondary,
            gap: 4,
            text: formatStatCount(stat.value),
            textStyle: const TextStyle(
              color: GenesisColors.darkTextSecondary,
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w400,
            ),
          ),
      ],
    );
  }
}

class _StatData {
  const _StatData({
    this.icon,
    this.iconAsset,
    this.preserveIconAssetColor = false,
    required this.value,
  }) : assert(icon != null || iconAsset != null);

  final IconData? icon;
  final String? iconAsset;
  final bool preserveIconAssetColor;
  final int value;
}

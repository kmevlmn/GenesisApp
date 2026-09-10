// ignore_for_file: use_key_in_widget_constructors

part of 'world_sections_library.dart';

class WorldStatusSection extends StatelessWidget {
  const WorldStatusSection({required this.world, required this.currentUid});

  final WorldDetail world;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    return WorldCharacterList(
      characters: world.characters,
      currentUid: currentUid,
      emptyText: 'No character status yet.',
      subtitleBuilder: (character) =>
          worldMetricStatusText(world.metric, character),
      subtitleColor: GenesisColors.darkTextSecondary,
      showCharacterDetails: false,
    );
  }
}

class WorldCharactersSection extends StatelessWidget {
  const WorldCharactersSection({required this.world, required this.currentUid});

  final WorldDetail world;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    return WorldCharacterList(
      characters: world.characters,
      currentUid: currentUid,
      emptyText: 'No characters yet.',
      subtitleBuilder: worldCharacterDescriptionText,
      subtitleColor: GenesisColors.darkTextSecondary,
      showCharacterDetails: true,
    );
  }
}

class WorldCharacterListView extends StatelessWidget {
  const WorldCharacterListView({
    required this.storageKey,
    required this.characters,
    required this.currentUid,
    required this.emptyText,
    required this.subtitleBuilder,
    required this.subtitleColor,
    required this.showCharacterDetails,
    this.controller,
  });

  final String storageKey;
  final List<Map<String, dynamic>> characters;
  final String currentUid;
  final String emptyText;
  final String Function(Map<String, dynamic> character) subtitleBuilder;
  final Color subtitleColor;
  final bool showCharacterDetails;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final sortedCharacters = worldSortedCharacters(characters, currentUid);
    return WorldSectionListView.builder(
      storageKey: storageKey,
      controller: controller,
      itemCount: math.max(sortedCharacters.length, 1),
      itemBuilder: (context, index) {
        if (sortedCharacters.isEmpty) {
          return WorldEmptySection(text: emptyText);
        }
        final character = sortedCharacters[index];
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 22),
          child: WorldCharacterRow(
            character: character,
            currentUid: currentUid,
            subtitle: subtitleBuilder(character),
            subtitleColor: subtitleColor,
            showCharacterDetails: showCharacterDetails,
          ),
        );
      },
    );
  }
}

class WorldCharacterList extends StatelessWidget {
  const WorldCharacterList({
    required this.characters,
    required this.currentUid,
    required this.emptyText,
    required this.subtitleBuilder,
    required this.subtitleColor,
    required this.showCharacterDetails,
  });

  final List<Map<String, dynamic>> characters;
  final String currentUid;
  final String emptyText;
  final String Function(Map<String, dynamic> character) subtitleBuilder;
  final Color subtitleColor;
  final bool showCharacterDetails;

  @override
  Widget build(BuildContext context) {
    if (characters.isEmpty) {
      return WorldEmptySection(text: emptyText);
    }
    final hasCharacterRole = characters.any(worldIsCharacterRole);
    final sortedCharacters = worldSortedCharacters(characters, currentUid);

    return Padding(
      padding: EdgeInsets.only(top: hasCharacterRole ? 5 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < sortedCharacters.length; i++) ...[
            WorldCharacterRow(
              character: sortedCharacters[i],
              currentUid: currentUid,
              subtitle: subtitleBuilder(sortedCharacters[i]),
              subtitleColor: subtitleColor,
              showCharacterDetails: showCharacterDetails,
            ),
            if (i != sortedCharacters.length - 1) const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}

class WorldCharacterRow extends StatelessWidget {
  const WorldCharacterRow({
    required this.character,
    required this.currentUid,
    required this.subtitle,
    required this.subtitleColor,
    required this.showCharacterDetails,
  });

  final Map<String, dynamic> character;
  final String currentUid;
  final String subtitle;
  final Color subtitleColor;
  final bool showCharacterDetails;

  @override
  Widget build(BuildContext context) {
    final name = worldMapString(character, const [
      'name',
    ], fallback: 'Character');
    final avatarUrl = worldResizedCharacterAvatarUrl(context, character);
    final playerUid = worldMapString(character, const ['player_uid']);
    final username = worldMapString(character, const ['player_username']);
    final playerDeleted = entityDeleted(character['player_deleted']);
    final suffix = worldCharacterNameSuffix(
      currentUid: currentUid,
      playerUid: playerUid,
      username: username,
      playerDeleted: playerDeleted,
    );
    final isCharacterRole = worldIsCharacterRole(character);
    final isNew = shouldMarkWorldContentAsNew(asBool(character['is_new']));
    final roleLabel = isCharacterRole ? 'Character' : 'Player';
    final identity = worldMapString(character, const ['identity']);
    final brief = worldMapString(character, const ['brief']);
    final goal = worldMapString(character, const ['goal']);
    final hasDisplayedDetails =
        identity.isNotEmpty ||
        brief.isNotEmpty ||
        (isCharacterRole && goal.isNotEmpty);
    const bodyStyle = TextStyle(
      fontSize: 13,
      height: 1.4,
      fontWeight: FontWeight.w400,
      color: GenesisColors.darkTextPrimary,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GenesisCharacterAvatar(
          url: avatarUrl,
          name: name,
          border: isCharacterRole
              ? null
              : Border.all(
                  color: kChatScenePlatePlayerRoleBorderColor,
                  width: 2,
                ),
          showFallbackWhileLoading: false,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                text: name,
                                children: [
                                  if (suffix.isNotEmpty)
                                    TextSpan(
                                      text: ' $suffix',
                                      style: const TextStyle(
                                        color: GenesisColors.darkTextTertiary,
                                      ),
                                    ),
                                ],
                              ),
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                                color: GenesisColors.darkTextPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isNew) ...[
                            const SizedBox(width: 6),
                            Align(
                              alignment: Alignment.center,
                              child: WorldNewBadge(
                                key: ValueKey<String>(
                                  'world-character-new-badge-'
                                  '${worldMapString(character, const ['character_id', 'char_id', 'id'], fallback: name)}',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      roleLabel,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.15,
                        fontWeight: FontWeight.w400,
                        color: GenesisColors.darkTextTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                if (showCharacterDetails) ...[
                  if (identity.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      identity,
                      style: bodyStyle,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (brief.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      brief,
                      style: bodyStyle.copyWith(
                        color: GenesisColors.redSecondary,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (isCharacterRole && goal.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Goal: $goal',
                      style: bodyStyle,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (isCharacterRole && !hasDisplayedDetails) ...[
                    const SizedBox(height: 5),
                    Text(
                      'No character details yet.',
                      style: bodyStyle.copyWith(color: subtitleColor),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w400,
                    ).copyWith(color: subtitleColor),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String worldResizedCharacterAvatarUrl(
  BuildContext context,
  Map<String, dynamic> character,
) {
  final rawUrl = worldMapString(character, const ['avatar']).trim();
  final resizedUrl = resizeGenesisImageUrl(
    rawUrl,
    logicalWidth: worldCharacterAvatarLogicalSize,
    devicePixelRatio: MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1,
  );
  return resizedUrl.isNotEmpty ? resizedUrl : rawUrl;
}

List<Map<String, dynamic>> worldSortedCharacters(
  List<Map<String, dynamic>> characters,
  String currentUid,
) {
  final indexed = characters.indexed.toList(growable: false);
  indexed.sort((a, b) {
    final rankCompare = worldCharacterSortRank(
      a.$2,
      currentUid,
    ).compareTo(worldCharacterSortRank(b.$2, currentUid));
    if (rankCompare != 0) return rankCompare;
    return a.$1.compareTo(b.$1);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

int worldCharacterSortRank(Map<String, dynamic> character, String currentUid) {
  if (worldIsCurrentUserCharacter(character, currentUid)) return 0;
  return worldIsCharacterRole(character) ? 2 : 1;
}

bool worldIsCurrentUserCharacter(
  Map<String, dynamic> character,
  String currentUid,
) {
  final playerUid = worldMapString(character, const ['player_uid']);
  return currentUid.isNotEmpty &&
      playerUid.isNotEmpty &&
      playerUid == currentUid;
}

bool worldIsCharacterRole(Map<String, dynamic> character) {
  return worldMapString(character, const ['player_uid']).isEmpty;
}

String worldCharacterNameSuffix({
  required String currentUid,
  required String playerUid,
  required String username,
  required bool playerDeleted,
}) {
  if (playerUid.isNotEmpty && playerDeleted) {
    return '($deletedEntityDisplayText)';
  }
  if (currentUid.isNotEmpty &&
      playerUid.isNotEmpty &&
      playerUid == currentUid) {
    return '';
  }
  if (playerUid.isNotEmpty && username.isNotEmpty) return '($username)';
  return '';
}

class WorldEmptySection extends StatelessWidget {
  const WorldEmptySection({required this.text, this.fontSize = 12});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: GenesisColors.darkTextTertiary,
          ),
        ),
      ),
    );
  }
}

String worldEventBody(WorldDetail world) {
  final candidates = [
    world.latestNarrator,
    world.origin.worldView,
    world.origin.description,
    world.name,
  ];
  for (final item in candidates) {
    final value = item.trim();
    if (value.isNotEmpty) return value;
  }
  return 'No world events yet.';
}

String worldCharacterDescriptionText(Map<String, dynamic> character) {
  final identity = worldMapString(character, const ['identity']);
  final brief = worldMapString(character, const ['brief']);
  if (!worldIsCharacterRole(character)) {
    final details = worldOrderedNonEmptyStrings([identity, brief]);
    return details.join('\n');
  }

  final goal = worldMapString(character, const ['goal']);
  final details = worldOrderedNonEmptyStrings([
    identity,
    brief,
    goal.isEmpty ? '' : 'Goal: $goal',
  ]);
  return details.isEmpty ? 'No character details yet.' : details.join('\n');
}

String worldMetricStatusText(
  Map<String, dynamic> metric,
  Map<String, dynamic> character,
) {
  final label = worldMapString(metric, const ['label']);
  final unit = worldMapString(metric, const ['unit']);
  final value = worldResolvedMetricValueText(
    character['metric_value'],
    metric['default'],
  );
  return '$label: $value$unit';
}

String worldResolvedMetricValueText(Object? metricValue, Object? defaultValue) {
  final parsedMetricValue = worldMetricNumber(metricValue);
  final resolved = parsedMetricValue == null || parsedMetricValue == 0
      ? defaultValue
      : metricValue;
  return worldMetricDisplayValue(resolved);
}

num? worldMetricNumber(Object? value) {
  if (value is num) return value;
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return null;
  return num.tryParse(text);
}

String worldMetricDisplayValue(Object? value) {
  if (value is num) {
    return value % 1 == 0 ? value.toInt().toString() : value.toString();
  }
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return '0';
  return text;
}

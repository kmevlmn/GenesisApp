import 'package:flutter/material.dart';
import '../../ui/tokens/genesis_colors.dart';

import '../../network/genesis_api.dart';
import '../../network/json_utils.dart';
import '../../components/common/genesis_timestamp_text.dart';
import '../../ui/components/genesis_character_avatar.dart';
import '../../ui/components/genesis_world_list_card_layout.dart';
import '../../ui/tokens/genesis_image_radii.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/entity_deleted.dart';
import '../../utils/genesis_timestamp_formatter.dart';
import '../../utils/stat_count_formatter.dart';

bool _isUsableWorldCardTimestamp(String value) {
  final text = value.trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return false;
  final numeric = num.tryParse(text);
  if (numeric != null) return numeric > 0;
  final parsed = parseFlexibleTimestamp(text);
  return parsed == null || parsed.year > 1970;
}

@immutable
class WorldListItem {
  const WorldListItem({
    required this.oid,
    required this.originVersionNum,
    required this.originVersionCreateAt,
    required this.wid,
    this.definitionVersion = 0,
    this.defaultMapLocationId = '',
    required this.status,
    required this.name,
    this.deleted = false,
    required this.cover,
    required this.displaySubtitle,
    required this.createdUid,
    required this.createdUserName,
    required this.ownerUid,
    required this.ownerName,
    required this.createdAt,
    required this.lastActiveAt,
    required this.updatedAt,
    required this.lastProgressAt,
    required this.lastProgressSummary,
    required this.lastProgressTickNo,
    required this.lastProgressSubTickNo,
    required this.lastProgressCurrentTime,
    required this.previewImages,
    required this.tags,
    required this.metric,
    this.myCharacter,
    required this.tickCnt,
    required this.connectCnt,
    required this.aiCharacterCnt,
    required this.playerCnt,
    required this.locationCnt,
    required this.coverHeight,
  });

  factory WorldListItem.fromJson(Map<String, dynamic> json) {
    final info = json['info'] is Map ? asJsonMap(json['info']) : json;
    final hasNestedStats = json['stats'] is Map;
    final stats = hasNestedStats ? asJsonMap(json['stats']) : json;
    final lastTick = json['last_tick'] is Map
        ? asJsonMap(json['last_tick'])
        : (info['last_tick'] is Map
              ? asJsonMap(info['last_tick'])
              : const <String, dynamic>{});
    final wid = asString(info['wid'], fallback: asString(info['world_id']));
    final name = asString(
      info['name'],
      fallback: asString(info['world_name'], fallback: wid),
    );
    return WorldListItem(
      oid: asString(info['oid'], fallback: asString(info['origin_id'])),
      originVersionNum: asInt(info['origin_version_num']),
      originVersionCreateAt: asString(
        info['origin_version_create_at'],
        fallback: asString(info['origin_version_time']),
      ),
      wid: wid,
      definitionVersion: asInt(info['definition_version']),
      defaultMapLocationId: asString(info['default_map_location_id']),
      status: asInt(info['status']),
      name: name.trim().isEmpty ? wid : name,
      deleted: entityDeleted(
        json['world_deleted'],
        fallback: entityDeleted(
          info['world_deleted'],
          fallback: info['deleted'],
        ),
      ),
      cover: resolveAssetUrl(
        asImageUrl(info['cover'], fallback: info['map_url']),
      ),
      displaySubtitle: asString(
        info['display_subtitle'],
        fallback: asString(info['brief']),
      ),
      createdUid: asString(info['created_uid']),
      createdUserName: asString(info['created_user_name']),
      ownerUid: asString(
        info['owner_uid'],
        fallback: asString(info['created_uid']),
      ),
      ownerName: asString(
        info['owner_name'],
        fallback: asString(info['created_user_name']),
      ),
      createdAt: asString(info['created_at']),
      lastActiveAt: asString(info['last_active_at']),
      updatedAt: asString(info['updated_at']),
      lastProgressAt: asString(lastTick['created_at']),
      lastProgressSummary: asString(lastTick['narrator']),
      lastProgressTickNo: hasNestedStats && stats.containsKey('tick_cnt')
          ? asInt(stats['tick_cnt'])
          : asInt(lastTick['tick_no'], fallback: asInt(lastTick['tick_index'])),
      lastProgressSubTickNo: hasNestedStats && stats.containsKey('sub_tick_no')
          ? asInt(stats['sub_tick_no'])
          : asInt(lastTick['sub_tick_no']),
      lastProgressCurrentTime: asString(
        lastTick['current_time'],
        fallback: asString(info['current_time']),
      ),
      previewImages: _previewImagesFromJson(info),
      tags: _tagsFromJson(info['tags']),
      metric: info['metric'] is Map
          ? asJsonMap(info['metric'])
          : const <String, dynamic>{},
      myCharacter: _myCharacterFromJson(json['my_character']),
      tickCnt: asInt(stats['tick_cnt']),
      connectCnt: asInt(stats['connect_cnt']),
      aiCharacterCnt: asInt(
        stats['ai_character_cnt'],
        fallback: asInt(stats['character_cnt']),
      ),
      playerCnt: asInt(stats['player_cnt']),
      locationCnt: asInt(stats['location_cnt']),
      coverHeight: _coverHeightFor(wid.isEmpty ? name : wid),
    );
  }

  final String oid;
  final int originVersionNum;
  final String originVersionCreateAt;
  final String wid;
  final int definitionVersion;
  final String defaultMapLocationId;
  final int status;
  final String name;
  final bool deleted;
  final String cover;
  final String displaySubtitle;
  final String createdUid;
  final String createdUserName;
  final String ownerUid;
  final String ownerName;
  final String createdAt;
  final String lastActiveAt;
  final String updatedAt;
  final String lastProgressAt;
  final String lastProgressSummary;
  final int lastProgressTickNo;
  final int lastProgressSubTickNo;
  final String lastProgressCurrentTime;
  final List<String> previewImages;
  final List<String> tags;
  final Map<String, dynamic> metric;
  final Map<String, dynamic>? myCharacter;
  final int tickCnt;
  final int connectCnt;
  final int aiCharacterCnt;
  final int playerCnt;
  final int locationCnt;
  final double coverHeight;

  String get title => name.trim().isEmpty ? wid : name.trim();

  String get ownerLabel {
    final owner = ownerName.trim();
    if (owner.isNotEmpty) return formatUidForDisplay(owner);
    final creator = createdUserName.trim();
    if (creator.isNotEmpty) return formatUidForDisplay(creator);
    return formatUidForDisplay(ownerUid, fallback: '-');
  }

  String get subtitle => displaySubtitle.trim().isEmpty
      ? 'Updated ${formatGenesisTimestamp(updatedAt)}'
      : displaySubtitle.trim();

  String get progressSummary => lastProgressSummary.trim();

  String get cardTimestamp {
    final activeTime = lastActiveAt.trim();
    if (_isUsableWorldCardTimestamp(activeTime)) return activeTime;
    final worldCreatedTime = createdAt.trim();
    return _isUsableWorldCardTimestamp(worldCreatedTime)
        ? worldCreatedTime
        : '';
  }

  String get cardTickLabel {
    final subTick = lastProgressSubTickNo > 0 ? '-$lastProgressSubTickNo' : '';
    return 'Tick $lastProgressTickNo$subTick';
  }

  String get progressTickTimeLabel {
    final parts = <String>[];
    if (lastProgressTickNo > 0) {
      parts.add(
        'Tick $lastProgressTickNo'
        '${lastProgressSubTickNo > 0 ? '-$lastProgressSubTickNo' : ''}',
      );
    }
    final currentTime = lastProgressCurrentTime.trim();
    if (currentTime.isNotEmpty) parts.add(currentTime);
    return parts.join(' · ');
  }

  List<String> get resolvedPreviewImages {
    if (previewImages.isNotEmpty) return previewImages;
    final image = cover.trim();
    if (image.isEmpty) return const <String>[];
    return <String>[image, image];
  }
}

class WorldItemCard extends StatelessWidget {
  const WorldItemCard({
    super.key,
    required this.item,
    this.thumbnailBorderRadius = GenesisImageRadii.contentValue,
  });

  final WorldListItem item;
  final double thumbnailBorderRadius;

  @override
  Widget build(BuildContext context) {
    return GenesisWorldListCardLayout(
      imageUrl: item.cover,
      placeholder: Theme.of(context).brightness == Brightness.dark
          ? const ColoredBox(
              color: GenesisColors.darkFaintFill,
              child: Center(
                child: Icon(
                  Icons.image_outlined,
                  color: GenesisColors.darkTextTertiary,
                  size: 22,
                ),
              ),
            )
          : null,
      thumbnailBorderRadius: thumbnailBorderRadius,
      content: _WorldSummary(item: item),
    );
  }
}

class _WorldSummary extends StatelessWidget {
  const _WorldSummary({required this.item});

  final WorldListItem item;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final timestamp = item.cardTimestamp;
    final character = item.myCharacter;
    final characterName = character == null
        ? ''
        : _mapString(character, const ['name'], fallback: 'Character');
    final otherPlayerCount = character == null || item.playerCnt <= 1
        ? 0
        : item.playerCnt - 1;
    final otherPlayerLabel = otherPlayerCount == 1
        ? '· 1 other Player'
        : '· $otherPlayerCount other Players';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          key: const ValueKey<String>('world-card-name'),
          style: TextStyle(
            color: dark
                ? GenesisColors.darkTextPrimary
                : const Color(0xFF4B6192),
            fontSize: 14,
            height: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '${item.cardTickLabel} · ${formatMessageCountLabel(item.connectCnt)}',
                key: const ValueKey<String>('world-card-tick-messages'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: dark
                      ? GenesisColors.darkTextSecondary
                      : const Color(0xFF666666),
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (formatGenesisTimestamp(timestamp).isNotEmpty) ...[
              const SizedBox(width: 10),
              GenesisTimestampText(
                key: const ValueKey<String>('world-card-time'),
                timestamp: timestamp,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: dark
                      ? GenesisColors.darkTextTertiary
                      : const Color(0xFF8B8B8B),
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
        if (item.progressSummary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            item.progressSummary,
            key: const ValueKey<String>('world-card-narrator'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: dark
                  ? GenesisColors.darkTextSecondary
                  : const Color(0xFF666666),
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
        if (character != null) ...[
          const SizedBox(height: 4),
          Row(
            key: const ValueKey<String>('world-card-character'),
            children: [
              GenesisCharacterAvatar(
                url: _mapImageUrl(character, const ['avatar']),
                name: characterName,
                size: 25,
                showFallbackWhileLoading: false,
                maxDevicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        characterName,
                        key: const ValueKey<String>(
                          'world-card-character-name',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: dark
                              ? GenesisColors.darkTextPrimary
                              : const Color(0xFF111111),
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    if (otherPlayerCount > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        otherPlayerLabel,
                        key: const ValueKey<String>('world-card-other-players'),
                        maxLines: 1,
                        style: TextStyle(
                          color: dark
                              ? GenesisColors.darkTextSecondary
                              : const Color(0xFF666666),
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _mapString(
  Map<String, dynamic> map,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = asString(map[key]).trim();
    if (value.isNotEmpty) return value;
  }
  return fallback;
}

String _mapImageUrl(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final imageUrl = resolveAssetUrl(asImageUrl(value));
    if (imageUrl.trim().isNotEmpty) return imageUrl;
  }
  return '';
}

Map<String, dynamic>? _myCharacterFromJson(Object? value) {
  if (value is! Map) return null;
  final character = asJsonMap(value);
  final hasContent = const [
    'char_id',
    'name',
    'player_uid',
  ].any((key) => asString(character[key]).trim().isNotEmpty);
  return hasContent ? character : null;
}

List<String> _tagsFromJson(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

List<String> _previewImagesFromJson(Map<String, dynamic> info) {
  for (final key in const [
    'last_progress_images',
    'progress_images',
    'preview_images',
    'images',
  ]) {
    final value = info[key];
    if (value is List) {
      return value
          .map((e) => resolveAssetUrl(asImageUrl(e)))
          .where((e) => e.trim().isNotEmpty)
          .toList(growable: false);
    }
  }
  return const <String>[];
}

double _coverHeightFor(String seed) {
  final hash = seed.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
  return (160 + (hash % 120)).clamp(140, 260).toDouble();
}

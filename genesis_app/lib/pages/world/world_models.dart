import 'package:flutter/material.dart';

import 'world_constants.dart';
import 'world_value_helpers.dart';

enum WorldBottomSheetKind { info, detail, locations, events, status, cast }

String worldBottomSheetPageName(WorldBottomSheetKind kind) {
  return switch (kind) {
    WorldBottomSheetKind.info => 'world_info',
    WorldBottomSheetKind.detail => 'world_detail_shell',
    WorldBottomSheetKind.locations => 'world_locations',
    WorldBottomSheetKind.events => 'world_events',
    WorldBottomSheetKind.status => 'world_status',
    WorldBottomSheetKind.cast => 'world_cast',
  };
}

class WorldBottomSheetSelection {
  const WorldBottomSheetSelection({
    required this.kind,
    required this.eventsLatestRevision,
    this.eventsTargetTickNumber,
  });

  final WorldBottomSheetKind kind;
  final int eventsLatestRevision;
  final int? eventsTargetTickNumber;
}

class WorldBottomTagItem {
  const WorldBottomTagItem({
    required this.label,
    required this.kind,
    this.asset,
    this.icon,
  });

  final String label;
  final WorldBottomSheetKind kind;
  final String? asset;
  final IconData? icon;
}

class WorldNewUserJoinNotice {
  const WorldNewUserJoinNotice({
    required this.characterId,
    required this.characterType,
    required this.characterName,
    required this.playerUid,
    required this.playerUsername,
    required this.ts,
  });

  final String characterId;
  final String characterType;
  final String characterName;
  final String playerUid;
  final String playerUsername;
  final DateTime? ts;

  factory WorldNewUserJoinNotice.fromCharacter(Map<String, dynamic> character) {
    return WorldNewUserJoinNotice(
      characterId: worldMapString(character, const ['char_id', 'id']),
      characterType: worldMapString(character, const ['type']),
      characterName: worldMapString(character, const ['name']),
      playerUid: worldMapString(character, const ['player_uid']),
      playerUsername: worldMapString(character, const ['player_username']),
      ts: null,
    );
  }

  String get displayPlayerUsername {
    final username = playerUsername.trim();
    if (username.isNotEmpty) return username;
    return 'Someone';
  }

  String get displayCharacterName {
    final name = characterName.trim();
    if (name.isNotEmpty) return name;
    return 'a character';
  }
}

WorldNewUserJoinNotice? worldLatestPlayerJoinNotice(
  List<Map<String, dynamic>> characters,
) {
  Map<String, dynamic>? latestCharacter;
  var latestJoinedAt = 0;
  for (final character in characters) {
    final playerUid = worldMapString(character, const ['player_uid']);
    if (playerUid.isEmpty) continue;
    final rawJoinedAt = character['player_joined_at'];
    final joinedAt = rawJoinedAt is num
        ? rawJoinedAt.toInt()
        : int.tryParse('$rawJoinedAt'.trim()) ?? 0;
    if (joinedAt <= 0 || joinedAt < latestJoinedAt) continue;
    latestJoinedAt = joinedAt;
    latestCharacter = character;
  }
  if (latestCharacter == null) return null;
  return WorldNewUserJoinNotice.fromCharacter(latestCharacter);
}

/// Info first, then the sections: the sheet's pages and the bubble's buttons
/// share this order.
const worldBottomTagItems = <WorldBottomTagItem>[
  WorldBottomTagItem(
    label: 'Info',
    kind: WorldBottomSheetKind.info,
    asset: worldInfoIconAsset,
  ),
  WorldBottomTagItem(
    label: 'Detail',
    kind: WorldBottomSheetKind.detail,
    asset: worldDetailIconAsset,
  ),
  WorldBottomTagItem(
    label: 'Locations',
    kind: WorldBottomSheetKind.locations,
    icon: Icons.place_outlined,
  ),
  WorldBottomTagItem(
    label: 'Events',
    kind: WorldBottomSheetKind.events,
    asset: worldSectionEventsIconAsset,
  ),
  WorldBottomTagItem(
    label: 'Status',
    kind: WorldBottomSheetKind.status,
    asset: worldSectionStatusIconAsset,
  ),
];

enum WorldHeaderActionKind { request, pending, launch, progress, unavailable }

class WorldHeaderAction {
  const WorldHeaderAction(this.kind, this.label, this.isClickable);

  final WorldHeaderActionKind kind;
  final String label;
  final bool isClickable;
}

WorldHeaderAction worldHeaderActionFor(String relationStatus) {
  switch (relationStatus.trim().toLowerCase()) {
    case 'anonymous':
    case 'reject':
    case 'rejected':
    case 'none':
      return const WorldHeaderAction(
        WorldHeaderActionKind.request,
        'Request',
        true,
      );
    case 'pending':
      return const WorldHeaderAction(
        WorldHeaderActionKind.pending,
        'Requested',
        false,
      );
    case 'approved':
      return const WorldHeaderAction(
        WorldHeaderActionKind.launch,
        'Launch',
        true,
      );
    case 'owner':
    case 'joined':
      return const WorldHeaderAction(
        WorldHeaderActionKind.progress,
        'Tick now',
        true,
      );
    default:
      return const WorldHeaderAction(
        WorldHeaderActionKind.unavailable,
        'Unavailable',
        false,
      );
  }
}

bool shouldConnectWorldChatroom(String relationStatus) {
  switch (relationStatus.trim().toLowerCase()) {
    case 'owner':
    case 'joined':
      return true;
    default:
      return false;
  }
}

String worldHeaderActionLabel(WorldHeaderActionKind action) {
  switch (action) {
    case WorldHeaderActionKind.request:
      return 'Request';
    case WorldHeaderActionKind.launch:
      return 'Launch';
    case WorldHeaderActionKind.progress:
      return 'Tick now';
    case WorldHeaderActionKind.pending:
      return 'Requested';
    case WorldHeaderActionKind.unavailable:
      return 'Unavailable';
  }
}

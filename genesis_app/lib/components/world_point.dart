import 'dart:typed_data';

import 'package:flutter/material.dart';

class WorldMapLocationNode {
  const WorldMapLocationNode({
    required this.id,
    required this.point,
    this.mapImageUrl = '',
    this.isRoot = false,
    this.chatTargetPoint,
    this.children = const <WorldMapLocationNode>[],
  });

  final String id;
  final WorldPoint point;
  final String mapImageUrl;
  final bool isRoot;
  final WorldPoint? chatTargetPoint;
  final List<WorldMapLocationNode> children;
}

class WorldPoint {
  const WorldPoint({
    required this.id,
    required this.name,
    required this.type,
    required this.position,
    required this.users,
    this.sceneId = '',
    this.pointId = '',
    this.iconUrl = '',
    this.iconBytes,
    this.mapImageUrl = '',
    this.description = '',
    this.locationDescription = '',
    this.depth = 0,
    this.isLeafLocation = true,
    this.isNew = false,
  });

  final String id;
  final String name;
  final WorldPointType type;
  final Offset position;
  final List<UserAvatar> users;
  final String sceneId;
  final String pointId;
  final String iconUrl;
  final Uint8List? iconBytes;
  final String mapImageUrl;
  final String description;
  final String locationDescription;
  final int depth;
  final bool isLeafLocation;
  final bool isNew;
}

class UserAvatar {
  const UserAvatar(
    this.initials, {
    this.id = '',
    this.name,
    this.avatarUrl = '',
    this.isPlayerControlledRole = false,
    this.isNew = false,
  });

  final String initials;
  final String id;
  final String? name;
  final String avatarUrl;
  final bool isPlayerControlledRole;
  final bool isNew;
}

enum WorldPointType { castle, shop, portal, tavern, camp }

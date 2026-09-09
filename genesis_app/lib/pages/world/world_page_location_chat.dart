part of 'world_page.dart';

extension _WorldPageLocationChat on _WorldPageState {
  void _handleCurrentTilemapLocationsChanged(
    String _,
    Set<String> locationIds,
  ) {
    _locationChatPageCache.preloadBackgroundsForTilemap(locationIds);
  }

  Future<void> _openCharactersMovedTargetLocation(
    ChatCharacterMovementVm movement,
  ) async {
    final targetLocationId = movement.toLocationId.trim();
    if (targetLocationId.isEmpty || targetLocationId == _activeChatLocationId) {
      return;
    }
    WorldLocationChatPanelDescriptor? descriptor =
        _locationChatDescriptors[targetLocationId];
    if (descriptor == null) {
      for (final candidate in _locationChatDescriptors.values) {
        if (candidate.localMessageLocationIds.contains(targetLocationId)) {
          descriptor = candidate;
          break;
        }
      }
    }
    if (descriptor == null || !mounted) {
      if (mounted) {
        showGenesisToast(
          context,
          'Location is unavailable',
          brightness: Brightness.dark,
        );
      }
      return;
    }
    if (descriptor.locationId == _activeChatLocationId) return;

    FocusManager.instance.primaryFocus?.unfocus();
    if (_world?.definitionVersion == 2) {
      _tilemapRestorationController.requestLocationNavigation(
        descriptor.locationId,
      );
      _showMapTab();
    }
    _recordWorldLocationChatDebug(
      action: 'charactersMovedLocationOpen',
      locationId: descriptor.locationId,
      details: <String, Object?>{
        'previousActiveId': _activeChatLocationId,
        'characterId': movement.characterId,
      },
    );
    await _showCachedLocationChat(descriptor);
  }

  Future<void> _openChatForPoint(WorldPoint point) async {
    final relationStatus = _world?.relationStatus.trim().toLowerCase() ?? '';
    if (!shouldConnectWorldChatroom(relationStatus)) {
      if (relationStatus == 'approved') {
        await _runWorldAction(WorldHeaderActionKind.launch);
      } else if (mounted) {
        showGenesisToast(
          context,
          'Request approval to launch',
          brightness: Brightness.dark,
        );
      }
      return;
    }
    final pointId = point.pointId.trim().isNotEmpty
        ? point.pointId.trim()
        : point.id.trim();
    final locationId = point.sceneId.trim().isNotEmpty
        ? point.sceneId.trim()
        : pointId;
    if (locationId.isEmpty) return;
    GenesisTelemetry.collectLog(
      actionType: 'pageview',
      action: 'world_map',
      object1: widget.wid,
      object2: locationId,
    );
    GenesisTelemetry.collectLog(
      actionType: 'pageview',
      action: 'world_location_chat',
      object1: widget.wid,
      object2: locationId,
    );

    final locationPathIds = _world == null
        ? <String>[locationId]
        : _locationPathIdsForLocationId(
            locationId,
            _world!.processedLocationTree,
          );
    final descriptor = WorldLocationChatPanelDescriptor(
      locationId: locationId,
      locationName: point.name,
      parentLocationName: locationPathIds.length < 2
          ? ''
          : _locationChatDescriptors[locationPathIds[locationPathIds.length -
                        2]]
                    ?.locationName ??
                '',
      backgroundImageUrl: point.iconUrl.trim().isNotEmpty
          ? point.iconUrl
          : point.mapImageUrl,
      backgroundPreviewImageUrl: '',
      isLeafLocation: point.isLeafLocation,
      localMessageLocationIds: worldOrderedNonEmptyStrings([
        pointId,
        locationId,
        point.id,
      ]),
      recentChatLocationPathIds: locationPathIds,
    );
    final syncedDescriptor =
        _locationChatDescriptors[locationId] ??
        _locationChatDescriptors[pointId] ??
        _locationChatDescriptors[point.id.trim()];
    await _showCachedLocationChat(
      syncedDescriptor?.copyWith(
            locationId: locationId,
            locationName: point.name,
            backgroundImageUrl:
                syncedDescriptor.backgroundImageUrl.trim().isNotEmpty
                ? syncedDescriptor.backgroundImageUrl
                : descriptor.backgroundImageUrl,
            backgroundPreviewImageUrl:
                syncedDescriptor.backgroundPreviewImageUrl.trim().isNotEmpty
                ? syncedDescriptor.backgroundPreviewImageUrl
                : descriptor.backgroundPreviewImageUrl,
            isLeafLocation: point.isLeafLocation,
            localMessageLocationIds: descriptor.localMessageLocationIds,
            recentChatLocationPathIds: descriptor.recentChatLocationPathIds,
          ) ??
          descriptor,
    );
  }

  void _recordWorldMapClick() {
    GenesisTelemetry.collectLog(
      actionType: 'event',
      action: 'world_map_click',
      object1: widget.wid,
    );
  }

  void _recordWorldTilemapClick() {
    GenesisTelemetry.collectLog(
      actionType: 'event',
      action: 'world_tilemap_click',
      object1: widget.wid,
    );
  }

  Future<void> _showCachedLocationChat(
    WorldLocationChatPanelDescriptor descriptor,
  ) async {
    final chatroom = _worldChatroom;
    final locationId = descriptor.locationId;
    if (locationId.isEmpty || chatroom == null || !mounted) return;
    final wasCached = _locationChatPageCache.hasPanel(locationId);
    final stopwatch = _locationChatMetricsEnabled
        ? (Stopwatch()..start())
        : null;
    final previousActiveId = _activeChatLocationId;
    _logLocationChatMetric(
      'open start location=$locationId cached=$wasCached '
      'previous=${previousActiveId.isEmpty ? 'none' : previousActiveId} '
      'aliases=${descriptor.localMessageLocationIds.join(',')}',
    );
    _recordWorldLocationChatDebug(
      action: 'openStart',
      locationId: locationId,
      details: {
        'cached': wasCached,
        'previousActiveId': previousActiveId,
        'descriptor': _debugDescriptor(descriptor),
      },
    );
    _pendingLocationChatLeaveId = '';
    if (previousActiveId.isNotEmpty && previousActiveId != locationId) {
      if (!descriptor.isLeafLocation) {
        unawaited(_leaveCachedLocationChat(previousActiveId));
      }
    }
    _setWorldPageState(() {
      _locationChatDescriptors[locationId] = descriptor;
      _locationChatPageCache.activate(descriptor);
      _activeChatLocationId = locationId;
    });
    WorldDetailsStatusBarOverride.setStyle(kChatDarkHeaderSystemUiOverlayStyle);
    unawaited(_hydrateActiveLocationChatMessages(descriptor));
    _logLocationChatMetric(
      'open location=$locationId cached=$wasCached '
      'previous=${previousActiveId.isEmpty ? 'none' : previousActiveId} '
      'active=$_activeChatLocationId elapsed=${stopwatch?.elapsedMilliseconds}ms',
    );
    _recordWorldLocationChatDebug(
      action: 'openDone',
      locationId: locationId,
      details: {
        'cached': wasCached,
        'previousActiveId': previousActiveId,
        'elapsedMs': stopwatch?.elapsedMilliseconds,
      },
    );
  }

  Future<void> _hydrateActiveLocationChatMessages(
    WorldLocationChatPanelDescriptor descriptor,
  ) async {
    final stopwatch = _locationChatMetricsEnabled
        ? (Stopwatch()..start())
        : null;
    final chatroom = _worldChatroom;
    final identity = chatroom?.identity;
    if (chatroom == null || identity == null) {
      _logLocationChatMetric(
        'active hydrate skipped location=${descriptor.locationId} '
        'hasChatroom=${chatroom != null} hasIdentity=${identity != null}',
      );
      _recordWorldLocationChatDebug(
        action: 'activeHydrateSkipped',
        locationId: descriptor.locationId,
        details: {
          'hasChatroom': chatroom != null,
          'hasIdentity': identity != null,
        },
      );
      return;
    }
    final ownerUid = worldFirstNonEmpty([identity.userId, identity.senderId]);
    if (ownerUid.isEmpty) {
      _logLocationChatMetric(
        'active hydrate skipped location=${descriptor.locationId} noOwner',
      );
      _recordWorldLocationChatDebug(
        action: 'activeHydrateSkipped',
        locationId: descriptor.locationId,
        details: {'reason': 'noOwner'},
      );
      return;
    }
    _logLocationChatMetric(
      'active hydrate start location=${descriptor.locationId} '
      'aliases=${descriptor.localMessageLocationIds.join(',')}',
    );
    unawaited(_preloadLocationChatMessages(descriptor));
    await chatroom.hydrateLocalMessages(
      worldId: widget.wid,
      locationId: descriptor.locationId,
      ownerUid: ownerUid,
      locationAliases: descriptor.localMessageLocationIds,
    );
    _logLocationChatMetric(
      'active hydrate done location=${descriptor.locationId} '
      'stateCount=${chatroom.state.messagesByLocation[descriptor.locationId]?.length ?? 0} '
      'elapsed=${stopwatch?.elapsedMilliseconds}ms',
    );
    _recordWorldLocationChatDebug(
      action: 'activeHydrateDone',
      locationId: descriptor.locationId,
      details: {
        'aliases': descriptor.localMessageLocationIds,
        'stateCount':
            chatroom.state.messagesByLocation[descriptor.locationId]?.length ??
            0,
        'elapsedMs': stopwatch?.elapsedMilliseconds,
      },
    );
  }

  void _closeCachedLocationChat() {
    final locationId = _activeChatLocationId;
    if (locationId.isEmpty) return;
    final closingInitialLocationChat = _initialLocationChatEntry;
    FocusManager.instance.primaryFocus?.unfocus();
    _pendingLocationChatLeaveId = locationId;
    _setWorldPageState(() {
      _activeChatLocationId = '';
      _locationChatPageCache.deactivate();
      if (closingInitialLocationChat) {
        _initialLocationChatEntry = false;
        _coverTilemapAfterInitialChat =
            _world?.definitionVersion == 2 &&
            !_tilemapDisplayReady &&
            _tilemapDisplayError == null;
      }
    });
    if (closingInitialLocationChat) {
      _scheduleLocationChatPrecache();
    }
    _recordWorldLocationChatDebug(
      action: 'close',
      locationId: locationId,
      details: {'cachedPanelCount': _locationChatPageCache.cachedPanelCount},
    );
    _syncWorldStatusBarForMainTab();
    if (closingInitialLocationChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _locationChatTransitionsEnabled) return;
        _setWorldPageState(() => _locationChatTransitionsEnabled = true);
      });
    }
  }

  void _completePendingLocationChatLeave() {
    final locationId = _pendingLocationChatLeaveId;
    _pendingLocationChatLeaveId = '';
    if (locationId.isEmpty || _activeChatLocationId.isNotEmpty) return;
    unawaited(_leaveCachedLocationChat(locationId));
  }

  void _handleWorldPopBlocked() {
    if (_activeChatLocationId.isEmpty) return;
    _closeCachedLocationChat();
  }

  Future<void> _leaveCachedLocationChat(String locationId) async {
    final descriptor = _locationChatDescriptors[locationId];
    final chatroom = _worldChatroom;
    if (descriptor?.isLeafLocation != true || chatroom == null) return;
    if (chatroom.state.joinedLocationId != locationId) return;
    try {
      await chatroom.leave();
    } catch (_) {
      // Closing or switching cached panels should not surface leave failures.
    }
  }

  void _syncLocationChatDescriptors(WorldDetail world) {
    final descriptors = _locationChatDescriptorsForWorld(world);
    final signature = _locationChatDescriptorsSignature(descriptors);
    if (signature == _locationChatDescriptorSignature) return;
    _locationChatDescriptorSignature = signature;
    _locationChatDescriptors = descriptors;
    _locationChatPageCache.syncDescriptors(descriptors);
    _recordWorldLocationChatDebug(
      action: 'syncDescriptors',
      details: {
        'count': descriptors.length,
        'leafCount': descriptors.values
            .where((descriptor) => descriptor.isLeafLocation)
            .length,
        'descriptors': descriptors.values
            .map(_debugDescriptor)
            .toList(growable: false),
      },
    );
    if (!_locationChatDescriptors.containsKey(_activeChatLocationId)) {
      _activeChatLocationId = '';
      _locationChatPageCache.deactivate();
      _syncWorldStatusBarForMainTab();
    }
    _preloadedLocationMessageIds.removeWhere(
      (locationId) => !descriptors.containsKey(locationId),
    );
    _preloadingLocationMessageFutures.removeWhere(
      (locationId, _) => !descriptors.containsKey(locationId),
    );
    _mapBubbleMessagesReady = false;
    _scheduleLocationChatPrecache();
  }

  bool _shouldApplyChatroomWorldSnapshot(WorldDetail nextWorld) {
    final currentWorld = _world;
    if (currentWorld == null) return true;
    if (identical(currentWorld, nextWorld)) return false;
    if (currentWorld.worldId != nextWorld.worldId) return true;
    if (currentWorld.relationStatus != nextWorld.relationStatus) return true;
    if (currentWorld.tickCount != nextWorld.tickCount) return true;
    if (currentWorld.subTickNo != nextWorld.subTickNo) return true;
    if (currentWorld.currentTime != nextWorld.currentTime) return true;
    if (currentWorld.lastChatLocationId != nextWorld.lastChatLocationId) {
      return true;
    }
    if (!setEquals(
      worldDetailEventLocationIds(currentWorld.locations),
      worldDetailEventLocationIds(nextWorld.locations),
    )) {
      return true;
    }
    if (currentWorld.isProgressing != nextWorld.isProgressing) return true;
    if (_worldNewContentStateSignature(currentWorld) !=
        _worldNewContentStateSignature(nextWorld)) {
      return true;
    }
    if (_worldPositionsSignature(currentWorld) !=
        _worldPositionsSignature(nextWorld)) {
      return true;
    }
    final nextSignature = _locationChatDescriptorsSignature(
      _locationChatDescriptorsForWorld(nextWorld),
    );
    return nextSignature != _locationChatDescriptorSignature;
  }

  String _worldPositionsSignature(WorldDetail world) {
    final parts = <String>[];
    for (final position in world.characterPositions) {
      final rawCharacter = position['character'];
      final character = rawCharacter is Map
          ? rawCharacter.map((key, value) => MapEntry('$key', value))
          : const <String, dynamic>{};
      parts.add(
        [
          'character',
          worldMapString(position, const [
            'location_id',
            'current_location_id',
          ]),
          worldMapString(character, const ['char_id', 'character_id', 'id']),
          worldMapString(character, const ['player_uid', 'user_id', 'uid']),
          worldMapString(character, const ['name']),
          worldMapString(character, const ['avatar', 'avatar_url']),
          '${character['type'] ?? ''}',
        ].join('\u001f'),
      );
    }
    for (final position in world.userPositions) {
      parts.add(
        [
          'user',
          worldMapString(position, const [
            'location_id',
            'current_location_id',
          ]),
          worldMapString(position, const ['uid', 'user_id', 'player_uid']),
          worldMapString(position, const ['name', 'user_name']),
          worldMapString(position, const ['avatar', 'avatar_url']),
        ].join('\u001f'),
      );
    }
    parts.sort();
    return parts.join('\u001e');
  }

  String _locationChatDescriptorsSignature(
    Map<String, WorldLocationChatPanelDescriptor> descriptors,
  ) {
    final parts =
        descriptors.values
            .map((descriptor) {
              return [
                descriptor.locationId,
                descriptor.locationName,
                descriptor.parentLocationName,
                descriptor.backgroundImageUrl,
                descriptor.backgroundPreviewImageUrl,
                descriptor.isLeafLocation ? '1' : '0',
                descriptor.localMessageLocationIds.join(','),
                descriptor.recentChatLocationPathIds.join(','),
              ].join('\u001f');
            })
            .toList(growable: false)
          ..sort();
    return parts.join('\u001e');
  }

  Map<String, WorldLocationChatPanelDescriptor>
  _locationChatDescriptorsForWorld(WorldDetail world) {
    final nodes = world.processedLocationTree.flattened;
    if (nodes.isNotEmpty) {
      final namesById = <String, String>{
        for (final node in nodes)
          if (node.id.trim().isNotEmpty)
            node.id.trim(): worldMapString(node.value, const [
              'location_name',
              'name',
            ], fallback: node.id.trim()),
      };
      final descriptors = <String, WorldLocationChatPanelDescriptor>{};
      for (final node in nodes) {
        final nodeId = node.id.trim();
        if (nodeId.isEmpty) continue;
        final pathIds = _locationPathIdsForLocationId(
          node.id,
          world.processedLocationTree,
        );
        descriptors[nodeId] = WorldLocationChatPanelDescriptor.fromNode(node)
            .copyWith(
              recentChatLocationPathIds: pathIds,
              parentLocationName: _parentNameFromPath(pathIds, namesById),
            );
      }
      return descriptors;
    }

    final locationIdsById = <String, Map<String, dynamic>>{
      for (final location in world.locations)
        if (worldMapString(location, const ['location_id', 'id']).isNotEmpty)
          worldMapString(location, const ['location_id', 'id']): location,
    };
    final parentIds = world.locations
        .map((location) => worldMapString(location, const ['location_pid']))
        .where((locationId) => locationId.isNotEmpty)
        .toSet();
    final namesById = <String, String>{
      for (final entry in locationIdsById.entries)
        entry.key: worldMapString(entry.value, const [
          'location_name',
          'name',
        ], fallback: entry.key),
    };
    final descriptors = <String, WorldLocationChatPanelDescriptor>{};
    for (final location in world.locations) {
      final locationId = worldMapString(location, const ['location_id', 'id']);
      if (locationId.isEmpty) continue;
      final pathIds = _locationPathIdsFromLocations(
        locationId,
        locationIdsById,
      );
      descriptors[locationId] =
          WorldLocationChatPanelDescriptor.fromLocation(
            location,
            isLeafLocation: !parentIds.contains(locationId),
          ).copyWith(
            recentChatLocationPathIds: pathIds,
            parentLocationName: _parentNameFromPath(pathIds, namesById),
          );
    }
    return descriptors;
  }

  static String _parentNameFromPath(
    List<String> pathIds,
    Map<String, String> namesById,
  ) {
    if (pathIds.length < 2) return '';
    return namesById[pathIds[pathIds.length - 2]] ?? '';
  }

  List<String> _locationPathIdsFromLocations(
    String locationId,
    Map<String, Map<String, dynamic>> locationsById,
  ) {
    final resolvedLocationId = locationId.trim();
    if (resolvedLocationId.isEmpty) return const <String>[];
    final path = <String>[];
    var currentId = resolvedLocationId;
    final seen = <String>{};
    while (currentId.isNotEmpty && seen.add(currentId)) {
      path.add(currentId);
      final current = locationsById[currentId];
      if (current == null) break;
      currentId = worldMapString(current, const ['location_pid']);
    }
    return worldOrderedNonEmptyStrings(path.reversed);
  }

  void _scheduleLocationChatPrecache() {
    final descriptors = _locationChatDescriptors.values
        .where((descriptor) => descriptor.isLeafLocation)
        .where((descriptor) => descriptor.locationId.trim().isNotEmpty)
        .toList(growable: false);
    _logLocationChatMetric(
      'panel precache scheduled count=${descriptors.length} '
      'cached=${_locationChatPageCache.cachedPanelCount} '
      'preloaded=${_preloadedLocationMessageIds.length}',
    );
    _recordWorldLocationChatDebug(
      action: 'precacheScheduled',
      details: {
        'count': descriptors.length,
        'cachedPanelCount': _locationChatPageCache.cachedPanelCount,
        'preloadedCount': _preloadedLocationMessageIds.length,
      },
    );
    if (descriptors.isEmpty) return;
    final chatroom = _worldChatroom;
    if (chatroom == null || chatroom.identity == null) return;
    final pendingDescriptors = descriptors
        .where(
          (descriptor) =>
              !_initialLocationChatEntry ||
              descriptor.locationId != _activeChatLocationId,
        )
        .where(
          (descriptor) =>
              !_preloadedLocationMessageIds.contains(descriptor.locationId) &&
              !_preloadingLocationMessageFutures.containsKey(
                descriptor.locationId,
              ),
        )
        .toList(growable: false);
    if (pendingDescriptors.isEmpty) {
      final expectedIds = descriptors
          .map((descriptor) => descriptor.locationId.trim())
          .where((locationId) => locationId.isNotEmpty)
          .toSet();
      if (expectedIds.every(_preloadedLocationMessageIds.contains)) {
        _mapBubbleMessagesReady = true;
        _replaceMapBubbleCandidates(
          _buildMapBubbleCandidates(chatroom.state, _world),
        );
      }
      return;
    }
    final pendingIds = pendingDescriptors
        .map((descriptor) => descriptor.locationId.trim())
        .where((locationId) => locationId.isNotEmpty)
        .toList(growable: false);
    final preloadFuture = chatroom
        .initializeLeafLocationQueues(locationIds: pendingIds)
        .then((_) {
          if (!identical(_worldChatroom, chatroom)) return;
          _preloadedLocationMessageIds.addAll(pendingIds);
        })
        .catchError((Object error) {
          _logLocationChatMetric('message preload failed error=$error');
          _recordWorldLocationChatDebug(
            action: 'preloadFailed',
            details: {'error': '$error'},
          );
        })
        .whenComplete(() {
          for (final locationId in pendingIds) {
            _preloadingLocationMessageFutures.remove(locationId);
          }
        });
    for (final locationId in pendingIds) {
      _preloadingLocationMessageFutures[locationId] = preloadFuture;
    }
    unawaited(
      preloadFuture.then((_) {
        if (!mounted || !identical(_worldChatroom, chatroom)) return;
        final expectedIds = descriptors
            .map((descriptor) => descriptor.locationId.trim())
            .where((locationId) => locationId.isNotEmpty)
            .toSet();
        if (!expectedIds.every(_preloadedLocationMessageIds.contains)) return;
        _setWorldPageState(() {
          _mapBubbleMessagesReady = true;
          _replaceMapBubbleCandidates(
            _buildMapBubbleCandidates(chatroom.state, _world),
          );
        });
        _logLocationChatMetric(
          'map bubble messages ready locations=${expectedIds.length}',
        );
        _recordWorldLocationChatDebug(
          action: 'mapBubbleMessagesReady',
          details: {
            'locations': expectedIds.toList(growable: false),
            'candidateCount': _mapBubbleCandidates.length,
          },
        );
      }),
    );
  }

  Future<void> _preloadLocationChatMessages(
    WorldLocationChatPanelDescriptor descriptor,
  ) {
    final locationId = descriptor.locationId.trim();
    if (locationId.isEmpty || !descriptor.isLeafLocation) {
      return Future<void>.value();
    }
    final chatroom = _worldChatroom;
    if (chatroom == null || chatroom.identity == null) {
      return Future<void>.value();
    }
    if (_preloadedLocationMessageIds.contains(locationId)) {
      return Future<void>.value();
    }
    final existing = _preloadingLocationMessageFutures[locationId];
    if (existing != null) return existing;
    _logLocationChatMetric(
      'message preload start location=$locationId '
      'aliases=${descriptor.localMessageLocationIds.join(',')}',
    );
    _recordWorldLocationChatDebug(
      action: 'preloadStart',
      locationId: locationId,
      details: {'aliases': descriptor.localMessageLocationIds},
    );
    final future = chatroom
        .initializeLeafLocationQueues(locationIds: [locationId])
        .then((messages) {
          if (!identical(_worldChatroom, chatroom) ||
              !_locationChatDescriptors.containsKey(locationId)) {
            return;
          }
          _preloadedLocationMessageIds.add(locationId);
          _logLocationChatMetric(
            'message preload done location=$locationId '
            'stateCount=${chatroom.state.messagesByLocation[locationId]?.length ?? 0}',
          );
          _recordWorldLocationChatDebug(
            action: 'preloadDone',
            locationId: locationId,
            details: {
              'stateCount':
                  chatroom.state.messagesByLocation[locationId]?.length ?? 0,
            },
          );
        })
        .catchError((Object error) {
          _logLocationChatMetric(
            'message preload failed location=$locationId error=$error',
          );
          _recordWorldLocationChatDebug(
            action: 'preloadFailed',
            locationId: locationId,
            details: {'error': '$error'},
          );
        })
        .whenComplete(() {
          _preloadingLocationMessageFutures.remove(locationId);
        });
    _preloadingLocationMessageFutures[locationId] = future;
    return future;
  }

  bool get _locationChatMetricsEnabled => kDebugMode || kProfileMode;

  void _logLocationChatMetric(String message) {
    if (!_locationChatMetricsEnabled) return;
    debugPrint('[World][LocationChatCache] $message');
  }

  void _recordWorldLocationChatDebug({
    required String action,
    String locationId = '',
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    if (!LocationChatDebugSlice.enabled) return;
    final activeLocationId = _activeChatLocationId.trim();
    LocationChatDebugSlice.recordEvent(
      source: 'world',
      action: action,
      worldId: widget.wid,
      locationId: locationId,
      details: <String, Object?>{
        ...details,
        'activeLocationId': activeLocationId,
        'cacheActiveLocationId': _locationChatPageCache.activeLocationId,
        'cachedPanelCount': _locationChatPageCache.cachedPanelCount,
        'preloadedLocationIds': _preloadedLocationMessageIds.toList(
          growable: false,
        ),
        'preloadingLocationIds': _preloadingLocationMessageFutures.keys.toList(
          growable: false,
        ),
        'mapBubbleMessagesReady': _mapBubbleMessagesReady,
      },
      snapshotKey: widget.wid,
      snapshot: <String, Object?>{
        'worldId': widget.wid,
        'activeLocationId': activeLocationId,
        'cacheActiveLocationId': _locationChatPageCache.activeLocationId,
        'cachedPanelCount': _locationChatPageCache.cachedPanelCount,
        'preloadedLocationIds': _preloadedLocationMessageIds.toList(
          growable: false,
        ),
        'preloadingLocationIds': _preloadingLocationMessageFutures.keys.toList(
          growable: false,
        ),
        'mapBubbleMessagesReady': _mapBubbleMessagesReady,
        'descriptorCount': _locationChatDescriptors.length,
        'descriptors': _locationChatDescriptors.values
            .map(_debugDescriptor)
            .toList(growable: false),
      },
    );
  }

  Map<String, Object?> _debugDescriptor(
    WorldLocationChatPanelDescriptor descriptor,
  ) {
    return <String, Object?>{
      'locationId': descriptor.locationId,
      'locationName': descriptor.locationName,
      'isLeafLocation': descriptor.isLeafLocation,
      'localMessageLocationIds': descriptor.localMessageLocationIds,
      'hasBackgroundImage': descriptor.backgroundImageUrl.trim().isNotEmpty,
      'ready': _locationChatPageCache.isReady(descriptor.locationId),
      'cached': _locationChatPageCache.hasPanel(descriptor.locationId),
    };
  }
}

String _worldNewContentStateSignature(WorldDetail world) {
  final parts = <String>[];
  for (final location in world.locations) {
    parts.add(
      [
        'location',
        worldMapString(location, const ['location_id', 'point_id', 'id']),
        _worldNewContentFlag(location['is_new']) ? '1' : '0',
      ].join('\u001f'),
    );
  }
  for (final character in world.characters) {
    parts.add(
      [
        'character',
        worldMapString(character, const [
          'character_id',
          'char_id',
          'id',
          'player_uid',
        ]),
        _worldNewContentFlag(character['is_new']) ? '1' : '0',
      ].join('\u001f'),
    );
  }
  for (final position in world.characterPositions) {
    final rawCharacter = position['character'];
    final character = rawCharacter is Map
        ? rawCharacter.map((key, value) => MapEntry('$key', value))
        : position;
    parts.add(
      [
        'character_position',
        worldMapString(character, const [
          'character_id',
          'char_id',
          'id',
          'player_uid',
        ]),
        _worldNewContentFlag(character['is_new']) ? '1' : '0',
      ].join('\u001f'),
    );
  }
  parts.sort();
  return parts.join('\u001e');
}

bool _worldNewContentFlag(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.trim().toLowerCase() == 'true';
  return false;
}

@visibleForTesting
bool worldNewContentStateChangedForTesting(
  WorldDetail currentWorld,
  WorldDetail nextWorld,
) {
  return _worldNewContentStateSignature(currentWorld) !=
      _worldNewContentStateSignature(nextWorld);
}

part of 'world_page.dart';

extension _WorldPageTabs on _WorldPageState {
  void _handleWorldMainTabChanged() {
    final nextIndex = _mainTabController.index
        .clamp(0, worldMainPageCount - 1)
        .toInt();
    if (nextIndex >= 2) {
      _sectionsWorldNotifier.value = _world;
    }
    _syncWorldStatusBarForMainTab(nextIndex);
    if (_worldMainTabIndex == nextIndex) return;
    _setWorldPageState(() => _worldMainTabIndex = nextIndex);
  }

  bool get _isDetailBottomSheetVisible {
    return _worldBottomSheetOpen &&
        _worldBottomSheetSelection.value.kind == WorldBottomSheetKind.detail;
  }

  void _handleWorldBottomSheetSelectionChanged() {
    if (_worldBottomSheetSelection.value.kind == WorldBottomSheetKind.events) {
      _clearEventsUnread();
    }
    if (!_isDetailBottomSheetVisible) return;
    if (!_hasUnreadNewUserJoin && _pendingNewUserJoinNotice == null) return;
    _setWorldPageState(_activateDetailNewUserJoinNotices);
  }

  void _syncWorldStatusBarForMainTab([int? index]) {
    if (_activeChatLocationId.isNotEmpty) {
      WorldDetailsStatusBarOverride.setStyle(
        kChatDarkHeaderSystemUiOverlayStyle,
      );
      return;
    }
    if ((index ?? _worldMainTabIndex) != 0) {
      WorldDetailsStatusBarOverride.setStyle(
        kChatDarkHeaderSystemUiOverlayStyle,
        backgroundColor: GenesisColors.darkBackground,
      );
      return;
    }
    WorldDetailsStatusBarOverride.clearStyle();
  }

  void _selectWorldMainTab(
    int index, {
    bool scrollEventsToLatest = false,
    int? eventsTargetTickNumber,
  }) {
    final nextIndex = index.clamp(0, worldMainPageCount - 1).toInt();
    if (scrollEventsToLatest) {
      _eventsLatestRevision += 1;
    }
    _eventsTargetTickNumber = eventsTargetTickNumber;
    if (nextIndex >= 2) {
      _sectionsWorldNotifier.value = _world;
    }
    _syncWorldStatusBarForMainTab(nextIndex);
    if (_mainTabController.index != nextIndex) {
      _mainTabController.animateTo(
        nextIndex,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    }
    if (_worldMainTabIndex == nextIndex) {
      _setWorldPageState(() {});
      return;
    }
    _setWorldPageState(() => _worldMainTabIndex = nextIndex);
  }

  void _handleWorldMainSwipePointerDown(PointerDownEvent event) {
    if (_activeChatLocationId.isNotEmpty || _world == null) return;
    if (_worldMainTabIndex != 0) return;
    if (_worldMainSwipePointer != null) return;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final localX = event.localPosition.dx;
    if (localX <= _WorldPageState._worldMainSwipeSystemGestureEdgeWidth ||
        localX >=
            screenWidth -
                _WorldPageState._worldMainSwipeSystemGestureEdgeWidth) {
      return;
    }

    _worldMainSwipePointer = event.pointer;
    _worldMainSwipeStartPosition = event.position;
    _worldMainSwipeStartCanMapScrollLeft = _worldMapCanScrollLeft;
    _worldMainSwipeStartCanMapScrollRight = _worldMapCanScrollRight;
  }

  void _handleWorldMainSwipePointerUp(PointerUpEvent event) {
    if (_worldMainSwipePointer != event.pointer) return;
    final startPosition = _worldMainSwipeStartPosition;
    if (startPosition != null && _worldMainTabIndex == 0) {
      _maybeSelectWorldMainTabBySwipe(event.position - startPosition);
    }
    _clearWorldMainSwipeTracking();
  }

  void _handleWorldMainSwipePointerCancel(PointerCancelEvent event) {
    if (_worldMainSwipePointer == event.pointer) {
      _clearWorldMainSwipeTracking();
    }
  }

  void _clearWorldMainSwipeTracking() {
    _worldMainSwipePointer = null;
    _worldMainSwipeStartPosition = null;
    _worldMainSwipeStartCanMapScrollLeft = false;
    _worldMainSwipeStartCanMapScrollRight = false;
  }

  void _maybeSelectWorldMainTabBySwipe(Offset delta) {
    final horizontalDistance = delta.dx.abs();
    final verticalDistance = delta.dy.abs();
    if (horizontalDistance < _WorldPageState._worldMainSwipeMinDistance ||
        horizontalDistance <
            verticalDistance * _WorldPageState._worldMainSwipeDirectionRatio) {
      return;
    }

    final nextIndex = delta.dx < 0
        ? _worldMainTabIndex + 1
        : _worldMainTabIndex - 1;
    if (nextIndex < 0 || nextIndex >= worldMainPageCount) return;
    if (!_canSelectWorldMainTabBySwipe(delta.dx)) return;
    _selectWorldMainTab(nextIndex);
  }

  bool _canSelectWorldMainTabBySwipe(double horizontalDelta) {
    if (_worldMainTabIndex != 0) return false;
    if (horizontalDelta < 0) {
      return !_worldMainSwipeStartCanMapScrollRight || !_worldMapCanScrollRight;
    }
    return !_worldMainSwipeStartCanMapScrollLeft || !_worldMapCanScrollLeft;
  }

  void _handleWorldMapHorizontalPanStateChanged(
    WorldMapHorizontalPanState state,
  ) {
    _worldMapCanScrollLeft = state.canScrollLeft;
    _worldMapCanScrollRight = state.canScrollRight;
  }

  Future<void> _loadCurrentUid() async {
    final uid =
        (await AppServicesScope.of(context).sessionStore.readUid())?.trim() ??
        '';
    if (!mounted) return;
    final uidChanged = uid != _currentUid;
    if (uidChanged) {
      if (_renderStage == _WorldPageRenderStage.content) {
        _setWorldPageState(() => _currentUid = uid);
      } else {
        _currentUid = uid;
      }
    }
    if (!mounted) return;
    _recentChatStoreUpdatesEnabled = true;
  }

  List<String> _locationPathIdsForLocationId(
    String locationId,
    ProcessedLocationTree<Map<String, dynamic>> tree,
  ) {
    final resolvedLocationId = locationId.trim();
    if (resolvedLocationId.isEmpty) return const <String>[];
    final nodesById = <String, LocationTreeNode<Map<String, dynamic>>>{
      for (final node in tree.flattened) node.id.trim(): node,
    };
    final path = <String>[];
    var current = nodesById[resolvedLocationId];
    while (current != null) {
      final id = current.id.trim();
      if (id.isNotEmpty && id != worldSyntheticRootLocationId) {
        path.add(id);
      }
      current = nodesById[current.parentId.trim()];
    }
    if (path.isEmpty) path.add(resolvedLocationId);
    return worldOrderedNonEmptyStrings(path.reversed);
  }
}

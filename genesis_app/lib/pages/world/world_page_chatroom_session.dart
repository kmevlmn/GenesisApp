part of 'world_page.dart';

extension _WorldPageChatroomSession on _WorldPageState {
  void _startWorldChatroom() {
    if (_worldChatroom != null) return;
    final services = AppServicesScope.read(context);
    final service = _createWorldChatroom(services);
    _attachWorldChatroom(service);
    unawaited(_connectWorldChatroom(service, services));
  }

  WorldChatroomService _createWorldChatroom(AppServices services) {
    _lastAppliedNewUserJoinRevision = 0;
    _lastAppliedMapUpdatedRevision = 0;
    _lastAppliedContentUpdateNoticeRevision = 0;
    _contentUpdateNotices = const <WorldContentUpdateNotice>[];
    final service = WorldChatroomService(
      api: services.api,
      client: services.chatroom,
      messageStorage: services.chatroomMessages,
      refreshInitialSnapshotOnConnect: false,
    );
    final world = _world;
    if (world != null) {
      service.applyWorldSnapshot(world);
    }
    return service;
  }

  void _attachWorldChatroom(WorldChatroomService service) {
    _deferredBottomSheetMapChatroomState = null;
    _worldChatroom = service;
    _worldChatroomSub = service.states.listen(_handleWorldChatroomState);
    _worldChatroomFailureSub = bindChatroomFailureToast(
      context,
      service.failures,
      shouldShow: (failure) => failure.code != 'snapshot_failed',
      onFailure: _handleWorldChatroomFailure,
    );
    _worldChatroomBalanceSub = bindGemBalancePrompt(
      context,
      service.balanceAlerts,
    );
  }

  void _handleWorldChatroomFailure(ChatroomFailureEvent failure) {
    if (!isChatroomUnauthorizedFailure(failure)) return;
    unawaited(_recoverWorldChatroomAuthentication());
  }

  Future<void> _recoverWorldChatroomAuthentication() {
    final existing = _worldChatroomAuthRecovery;
    if (existing != null) return existing;
    final recovery = _performWorldChatroomAuthenticationRecovery();
    _worldChatroomAuthRecovery = recovery;
    return recovery.whenComplete(() {
      if (identical(_worldChatroomAuthRecovery, recovery)) {
        _worldChatroomAuthRecovery = null;
      }
    });
  }

  Future<void> _performWorldChatroomAuthenticationRecovery() async {
    final oldService = _worldChatroom;
    try {
      await _detachWorldChatroomForAuthentication(oldService);
      if (!mounted) return;

      final services = AppServicesScope.read(context);
      await services.sessionStore.clearUid();
      services.notifySessionChanged();
      try {
        await services.identityAuth.signOutIdentity();
      } catch (error) {
        debugPrint(
          '[Auth][WorldChatroomUnauthorized] identity sign out failed: $error',
        );
      }
      if (!mounted) return;

      final loggedIn = await ensureGenesisLogin(
        context,
        continueAfterLogin: true,
      );
      if (!mounted) return;
      if (!loggedIn) {
        if (identical(_worldChatroom, oldService)) {
          _worldChatroom = null;
        }
        _exitWorldAfterAuthenticationCancelled();
        return;
      }

      await _loadCurrentUid();
      if (!mounted) return;
      final replacement = _createWorldChatroom(services);
      final identity = await _chatroomIdentity(services);
      try {
        await replacement.connect(worldId: widget.wid, identity: identity);
      } catch (error) {
        debugPrint(
          '[Auth][WorldChatroomUnauthorized] reconnect failed: $error',
        );
      }
      if (!mounted) {
        await replacement.dispose();
        return;
      }

      final activeLocationId = _activeChatLocationId.trim();
      final activeDescriptor = _locationChatDescriptors[activeLocationId];
      if (activeDescriptor?.isLeafLocation == true) {
        try {
          await replacement.join(locationId: activeLocationId);
        } catch (error) {
          debugPrint(
            '[Auth][WorldChatroomUnauthorized] location rejoin failed: $error',
          );
        }
      }
      if (!mounted) {
        await replacement.dispose();
        return;
      }
      _attachWorldChatroom(replacement);
      _setWorldPageState(() {
        _preloadedLocationMessageIds.clear();
        _preloadingLocationMessageFutures.clear();
        _mapBubbleMessagesReady = false;
        _replaceMapBubbleCandidates(const <WorldMapBubbleCandidate>[]);
      });
      _handleWorldChatroomState(replacement.state);
    } catch (error, stackTrace) {
      debugPrint(
        '[Auth][WorldChatroomUnauthorized] recovery failed: $error\n$stackTrace',
      );
      if (!mounted) return;
      if (identical(_worldChatroom, oldService)) {
        _worldChatroom = null;
      }
      _exitWorldAfterAuthenticationCancelled();
    }
  }

  Future<void> _detachWorldChatroomForAuthentication(
    WorldChatroomService? service,
  ) async {
    await _worldChatroomSub?.cancel();
    await _worldChatroomFailureSub?.cancel();
    await _worldChatroomBalanceSub?.cancel();
    _worldChatroomSub = null;
    _worldChatroomFailureSub = null;
    _worldChatroomBalanceSub = null;
    if (service != null) await service.dispose();
  }

  void _exitWorldAfterAuthenticationCancelled() {
    final navigator = Navigator.of(context);
    if (_activeChatLocationId.isEmpty) {
      unawaited(navigator.maybePop());
      return;
    }
    _setWorldPageState(() {
      _activeChatLocationId = '';
      _locationChatPageCache.deactivate();
    });
    _syncWorldStatusBarForMainTab();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(navigator.maybePop());
    });
  }

  void _handleWorldChatroomState(WorldChatroomState state) {
    if (!mounted) return;
    final world = state.world;
    final currentWorld = world ?? _world;
    final currentRelationStatus = currentWorld?.relationStatus ?? '';
    final canShowWorldTickProgress =
        _worldChatroom != null ||
        shouldConnectWorldChatroom(currentRelationStatus);
    final latestNewUserJoin = state.latestNewUserJoin;
    final hasNewUserJoin =
        latestNewUserJoin != null &&
        state.latestNewUserJoinRevision > _lastAppliedNewUserJoinRevision;
    final newUserJoinNotice = hasNewUserJoin
        ? _newUserJoinNoticeFromEvent(latestNewUserJoin)
        : null;
    final hasContentUpdateNotices =
        state.contentUpdateNoticeRevision >
        _lastAppliedContentUpdateNoticeRevision;
    final hasMapUpdate =
        state.mapUpdatedRevision > _lastAppliedMapUpdatedRevision;
    if (hasMapUpdate) {
      _lastAppliedMapUpdatedRevision = state.mapUpdatedRevision;
      _prefetchTilemapUpdateForLocationChat(currentWorld);
    }
    var shouldSyncRelationStatus = false;
    final previousInputBlocked = _lastChatroomInputBlocked;
    _lastChatroomInputBlocked = state.inputBlocked;
    final tickDoneFromPush =
        _worldTickInProgress &&
        previousInputBlocked == true &&
        !state.inputBlocked &&
        !_worldTickDoneHandling;
    final tickStartedFromPush =
        canShowWorldTickProgress &&
        state.inputBlocked &&
        previousInputBlocked != true &&
        !_worldTickInProgress;
    final socketCurrentTime = state.latestSocketCurrentTime.trim();
    final socketTickNo = state.latestSocketTickNo;
    final socketSubTickNo = state.latestSocketSubTickNo;
    final shouldApplySocketWorldProgress =
        (socketCurrentTime.isNotEmpty ||
            socketTickNo > 0 ||
            socketSubTickNo > 0) &&
        state.latestSocketCurrentTimeRevision >
            _lastAppliedChatroomWorldProgressRevision;
    final shouldApplyWorldSnapshot =
        world != null && _shouldApplyChatroomWorldSnapshot(world);
    final worldBeforeSocketProgress = currentWorld;
    final socketProgressChangesWorld =
        shouldApplySocketWorldProgress &&
        worldBeforeSocketProgress != null &&
        ((socketTickNo > 0 &&
                socketTickNo != worldBeforeSocketProgress.tickCount) ||
            (socketCurrentTime.isNotEmpty &&
                socketCurrentTime != worldBeforeSocketProgress.currentTime) ||
            (socketSubTickNo > 0 &&
                socketSubTickNo != worldBeforeSocketProgress.subTickNo));
    if (shouldApplySocketWorldProgress) {
      _lastAppliedChatroomWorldProgressRevision =
          state.latestSocketCurrentTimeRevision;
    }
    final deferMapVisuals = _worldBottomSheetOpen;
    List<WorldMapBubbleCandidate>? preparedMapBubbleCandidates;
    var mapVisualsChanged = false;
    if (deferMapVisuals) {
      _deferredBottomSheetMapChatroomState = state;
    } else if (!shouldApplyWorldSnapshot && !socketProgressChangesWorld) {
      preparedMapBubbleCandidates = _buildMapBubbleCandidates(
        state,
        currentWorld,
      );
      mapVisualsChanged = !_sameMapBubbleCandidates(
        _mapBubbleCandidates,
        preparedMapBubbleCandidates,
      );
    }
    final shouldMutatePageState =
        shouldApplyWorldSnapshot ||
        socketProgressChangesWorld ||
        mapVisualsChanged ||
        hasMapUpdate ||
        hasContentUpdateNotices ||
        newUserJoinNotice != null;
    void applyState() {
      var worldDetailChanged = false;
      if (world != null && shouldApplyWorldSnapshot) {
        _world = world;
        _syncLocationChatDescriptors(world);
        _applyWorldDetailEventLocations(world);
        shouldSyncRelationStatus = true;
        worldDetailChanged = true;
      }
      final currentWorldDetail = _world;
      if (socketProgressChangesWorld && currentWorldDetail != null) {
        _world = currentWorldDetail.copyWith(
          tickCount: socketTickNo > 0 ? socketTickNo : null,
          subTickNo: socketSubTickNo > 0 ? socketSubTickNo : null,
          currentTime: socketCurrentTime.isEmpty ? null : socketCurrentTime,
        );
        worldDetailChanged = true;
      }
      if (worldDetailChanged) {
        _sectionsWorldNotifier.value = _world;
      }
      if (!deferMapVisuals) {
        if (preparedMapBubbleCandidates != null) {
          _replaceMapBubbleCandidates(preparedMapBubbleCandidates);
        } else {
          final resolvedWorld = _world ?? currentWorld;
          _replaceMapBubbleCandidates(
            _buildMapBubbleCandidates(state, resolvedWorld),
          );
        }
      }
      if (newUserJoinNotice != null) {
        _applyNewUserJoinNotice(
          newUserJoinNotice,
          state.latestNewUserJoinRevision,
        );
      }
      if (hasContentUpdateNotices) {
        _lastAppliedContentUpdateNoticeRevision =
            state.contentUpdateNoticeRevision;
        _contentUpdateNotices = state.latestContentUpdateNotices;
      }
      if (hasMapUpdate) {
        _tilemapReloadRevision += 1;
      }
    }

    if (shouldMutatePageState) {
      if (deferMapVisuals && !hasMapUpdate) {
        applyState();
      } else {
        _setWorldPageState(applyState);
      }
    }
    if (shouldSyncRelationStatus) {
      _syncWorldChatroomForRelationStatus(world!.relationStatus);
    }
    _maybeOpenInitialLocationChat();
    if (tickStartedFromPush) {
      _setWorldTickInProgress(true);
      _startWorldTickTracking();
    }
    if (tickDoneFromPush) {
      unawaited(_handleWorldTickDone());
    }
  }

  void _prefetchTilemapUpdateForLocationChat(WorldDetail? world) {
    if (world == null ||
        world.definitionVersion != 2 ||
        _activeChatLocationId.isEmpty ||
        _initialLocationChatEntry) {
      return;
    }
    final initialLocationId = world.processedLocationTree
        .initialTilemapLocationId(syntheticRootId: worldSyntheticRootLocationId)
        .trim();
    if (initialLocationId.isEmpty) return;
    unawaited(
      _tilemapRestorationController.prefetchWorldMapUpdate(
        api: AppServicesScope.read(context).api,
        worldId: widget.wid,
        initialLocationId: initialLocationId,
        drillableLocationIds: world.processedLocationTree.flattened
            .where((location) => location.children.isNotEmpty)
            .map((location) => location.id),
      ),
    );
  }

  void _applyDeferredBottomSheetMapChatroomState() {
    final state = _deferredBottomSheetMapChatroomState;
    _deferredBottomSheetMapChatroomState = null;
    if (state == null) return;
    final world = _world;
    _replaceMapBubbleCandidates(_buildMapBubbleCandidates(state, world));
  }

  WorldNewUserJoinNotice _newUserJoinNoticeFromEvent(
    ChatroomNewUserJoinEvent event,
  ) {
    return WorldNewUserJoinNotice(
      characterId: event.characterId,
      characterType: event.characterType,
      characterName: event.characterName,
      playerUid: event.playerUid,
      playerUsername: event.playerUsername,
      ts: event.ts,
    );
  }

  void _applyNewUserJoinNotice(WorldNewUserJoinNotice notice, int revision) {
    _lastAppliedNewUserJoinRevision = revision;
    if (_isDetailBottomSheetVisible) {
      _pendingNewUserJoinNotice = null;
      _hasUnreadNewUserJoin = false;
      _newUserJoinNoticesNotifier.value = <WorldNewUserJoinNotice>[notice];
      return;
    }
    _pendingNewUserJoinNotice = notice;
    _hasUnreadNewUserJoin = true;
  }

  void _activateDetailNewUserJoinNotices() {
    final pending = _pendingNewUserJoinNotice;
    if (pending != null) {
      _newUserJoinNoticesNotifier.value = <WorldNewUserJoinNotice>[pending];
      _pendingNewUserJoinNotice = null;
    }
    _hasUnreadNewUserJoin = false;
  }

  void _syncWorldChatroomForRelationStatus(String relationStatus) {
    if (shouldConnectWorldChatroom(relationStatus)) {
      _startWorldChatroom();
      return;
    }
    _stopWorldChatroom();
  }

  void _maybeOpenInitialLocationChat() {
    final initialLocationId = _pendingInitialLocationId;
    final world = _world;
    if (initialLocationId.isEmpty || world == null) return;
    if (_worldChatroom == null) {
      if (!shouldConnectWorldChatroom(world.relationStatus)) {
        _pendingInitialLocationId = '';
        _initialLocationChatEntry = false;
        _locationChatTransitionsEnabled = true;
      }
      return;
    }
    final descriptor =
        _locationChatDescriptors[initialLocationId] ??
        _locationChatDescriptors.values
            .where(
              (item) =>
                  item.localMessageLocationIds.contains(initialLocationId),
            )
            .firstOrNull;
    if (descriptor == null) {
      _pendingInitialLocationId = '';
      _initialLocationChatEntry = false;
      _locationChatTransitionsEnabled = true;
      return;
    }
    if (_initialLocationChatEntry) {
      _pendingInitialLocationId = '';
      _setWorldPageState(() {
        _locationChatDescriptors[descriptor.locationId] = descriptor;
        _locationChatPageCache.activate(descriptor);
        _locationChatPageCache.markReady(descriptor.locationId);
        _activeChatLocationId = descriptor.locationId;
      });
      return;
    }
    _pendingInitialLocationId = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeChatLocationId.isNotEmpty) return;
      unawaited(_showCachedLocationChat(descriptor));
    });
  }

  void _stopWorldChatroom() {
    final chatroom = _worldChatroom;
    if (chatroom == null) return;
    unawaited(_worldChatroomSub?.cancel());
    unawaited(_worldChatroomFailureSub?.cancel());
    unawaited(_worldChatroomBalanceSub?.cancel());
    _worldChatroomSub = null;
    _worldChatroomFailureSub = null;
    _worldChatroomBalanceSub = null;
    _worldChatroom = null;
    _deferredBottomSheetMapChatroomState = null;
    _preloadedLocationMessageIds.clear();
    _preloadingLocationMessageFutures.clear();
    _mapBubbleMessagesReady = false;
    if (mounted) {
      _setWorldPageState(() {
        _activeChatLocationId = '';
        _locationChatPageCache.clear();
        _replaceMapBubbleCandidates(const <WorldMapBubbleCandidate>[]);
      });
    }
    unawaited(_disposeWorldChatroom(chatroom));
  }

  Future<void> _connectWorldChatroom(
    WorldChatroomService service,
    AppServices services,
  ) async {
    try {
      final identity = await _chatroomIdentity(services);
      if (!mounted || !identical(_worldChatroom, service)) return;
      await service.connect(worldId: widget.wid, identity: identity);
      if (!mounted || !identical(_worldChatroom, service)) return;
      _maybeOpenInitialLocationChat();
      _scheduleLocationChatPrecache();
    } catch (_) {
      // The service emits failures and keeps reconnecting while desired.
    }
  }

  Future<ChatroomConnectionIdentity> _chatroomIdentity(
    AppServices services,
  ) async {
    final uid = (await services.sessionStore.readUid())?.trim() ?? '';
    final userInfo = await services.sessionStore.readUserInfo();
    final cachedUid = userInfo == null
        ? ''
        : worldMapString(userInfo, const ['uid']);
    final senderId = worldFirstNonEmpty([uid, cachedUid, 'local-user']);
    final senderName = worldFirstNonEmpty([
      worldMapString(userInfo ?? const <String, dynamic>{}, const [
        'display_name',
        'nickname',
        'name',
      ]),
      formatUidForDisplay(uid),
      'Me',
    ]);
    return ChatroomConnectionIdentity(
      userId: senderId,
      senderId: senderId,
      senderName: senderName,
    );
  }

  Future<void> _disposeWorldChatroom(WorldChatroomService service) async {
    try {
      await service.disconnect();
    } catch (_) {
      // Leaving the page should not be blocked by socket shutdown errors.
    }
    await service.dispose();
  }
}

part of 'world_page.dart';

extension _WorldPageTickFlow on _WorldPageState {
  Future<void> _runWorldAction(WorldHeaderActionKind action) async {
    if (action == WorldHeaderActionKind.progress && _worldTickInProgress) {
      _openEventsAfterTickDone = true;
      _startWorldTickTracking();
      _setWorldTickWaitOverlayRequested(true);
      return;
    }
    if (_worldActionRunning) return;
    if (action == WorldHeaderActionKind.request) {
      if (!await ensureGenesisLogin(context)) return;
      if (!mounted) return;
      final confirmed = await _confirmWorldRequest();
      if (!mounted || !confirmed) return;
    }
    if (action == WorldHeaderActionKind.launch) {
      final world = _world;
      if (world == null) return;
      await _showLaunchRoleSheet(world);
      return;
    }
    _setWorldPageState(() => _worldActionRunning = true);
    if (action == WorldHeaderActionKind.progress) {
      _openEventsAfterTickDone = true;
      _setWorldTickWaitOverlayRequested(true);
      _setWorldTickInProgress(true);
      GenesisTelemetry.collectLog(
        actionType: 'event',
        action: 'world_progress_submit_start',
        object1: widget.wid,
      );
    }
    try {
      final api = AppServicesScope.of(context).api;
      var message = '';
      if (action == WorldHeaderActionKind.request) {
        message = await api.requestWorld(widget.wid);
        GenesisTelemetry.collectLog(
          actionType: 'event',
          action: 'request_submit',
          object1: widget.wid,
        );
      } else if (action == WorldHeaderActionKind.progress) {
        final result = await api.progressWorldResult(widget.wid);
        message = result.message;
        _pendingProgressTickCount = result.tickCount > 0
            ? result.tickCount
            : null;
        GenesisTelemetry.collectLog(
          actionType: 'event',
          action: 'world_progress_submit_success',
          object1: widget.wid,
          object2: _pendingProgressTickCount,
        );
      }
      if (!mounted) return;
      if (action != WorldHeaderActionKind.progress &&
          message.trim().isNotEmpty) {
        showGenesisToast(context, message, brightness: Brightness.dark);
      }
      if (action == WorldHeaderActionKind.progress) {
        _startWorldTickTracking(openEventsAfterDone: true);
      } else {
        await _fetchWorld();
      }
      if (!mounted) return;
    } catch (error) {
      if (!mounted) return;
      if (action == WorldHeaderActionKind.progress) {
        _openEventsAfterTickDone = false;
        _pendingProgressTickCount = null;
        _setWorldTickWaitOverlayRequested(false);
        _markWorldTickFailed();
        if (_isWorldProgressInsufficientGems(error)) {
          unawaited(
            showGemBalancePrompt(
              context,
              GemBalanceAlert(
                kind: GemBalanceAlertKind.insufficient,
                message: error is ApiException ? error.message : '',
              ),
              analyticsTrigger: gemPurchaseSheetTriggerTick,
            ),
          );
          return;
        }
      }
      showGenesisToast(
        context,
        '${worldHeaderActionLabel(action)} failed',
        brightness: Brightness.dark,
      );
    } finally {
      if (mounted && action != WorldHeaderActionKind.progress) {
        _setWorldPageState(() => _worldActionRunning = false);
      }
    }
  }

  bool _isWorldProgressInsufficientGems(Object error) {
    return error is ApiException && error.code == 21001;
  }

  void _startWorldTickTracking({bool openEventsAfterDone = false}) {
    if (openEventsAfterDone) _openEventsAfterTickDone = true;
    _startWorldTickLockPolling();
    _setWorldTickInProgress(true);
    if (!_worldActionRunning) {
      if (mounted) {
        _setWorldPageState(() => _worldActionRunning = true);
      } else {
        _worldActionRunning = true;
      }
    }
  }

  void _setWorldTickInProgress(bool inProgress) {
    if (!inProgress) {
      _stopWorldTickLockPolling();
    }
    final changed = _worldTickInProgress != inProgress;
    if (changed) {
      if (mounted) {
        _setWorldPageState(() => _worldTickInProgress = inProgress);
      } else {
        _worldTickInProgress = inProgress;
      }
    }
    final chatroom = _worldChatroom;
    if (chatroom != null) {
      try {
        chatroom.setInputBlocked(inProgress);
      } catch (_) {
        // Socket state is best-effort; page state still gates the visible button.
      }
    }
  }

  void _setWorldTickWaitOverlayRequested(bool requested) {
    if (_worldTickWaitOverlayRequested == requested) return;
    if (mounted) {
      _setWorldPageState(() => _worldTickWaitOverlayRequested = requested);
    } else {
      _worldTickWaitOverlayRequested = requested;
    }
  }

  void _startWorldTickLockPolling() {
    if (_worldTickLockPollingTimer?.isActive == true) return;
    _worldTickLockPollingTimer = Timer.periodic(
      _WorldPageState._worldTickLockPollInterval,
      (_) {
        unawaited(_pollWorldTickLockStatus(_worldTickLockPollingGeneration));
      },
    );
  }

  void _stopWorldTickLockPolling() {
    _worldTickLockPollingTimer?.cancel();
    _worldTickLockPollingTimer = null;
    _worldTickLockPollInFlight = false;
    _worldTickLockPollingGeneration += 1;
  }

  Future<void> _pollWorldTickLockStatus(int generation) async {
    if (!mounted ||
        !_worldTickInProgress ||
        _worldTickDoneHandling ||
        _worldTickLockPollInFlight ||
        generation != _worldTickLockPollingGeneration) {
      return;
    }
    _worldTickLockPollInFlight = true;
    try {
      final status = await AppServicesScope.read(
        context,
      ).api.chatroomHttp.tickLockStatus(worldId: widget.wid);
      if (!mounted ||
          !_worldTickInProgress ||
          _worldTickDoneHandling ||
          generation != _worldTickLockPollingGeneration) {
        return;
      }
      if (!status.isLocked) {
        unawaited(_handleWorldTickDone());
      }
    } catch (_) {
      // Polling is a fallback; keep waiting for tick_done or the next poll.
    } finally {
      if (generation == _worldTickLockPollingGeneration) {
        _worldTickLockPollInFlight = false;
      }
    }
  }

  Future<void> _handleWorldTickDone() async {
    if (_worldTickDoneHandling) return;
    _worldTickDoneHandling = true;
    _markWorldTickIdle();
    try {
      final chatroom = _worldChatroom;
      final refreshedWorld = chatroom == null
          ? null
          : await chatroom.refreshWorldSnapshot();
      if (chatroom == null) {
        await _fetchWorld();
      }
      if (!mounted) return;
      _markEventsUnread();
      final completedTickCount =
          refreshedWorld?.tickCount ??
          _world?.tickCount ??
          _pendingProgressTickCount;
      GenesisTelemetry.collectLog(
        actionType: 'event',
        action: 'world_progress_async_complete',
        object1: widget.wid,
        object2: completedTickCount,
      );
      _pendingProgressTickCount = null;
      if (_openEventsAfterTickDone) {
        _openEventsAfterTickDone = false;
        if (!_shouldSuppressAutoEventsAfterTick) {
          _showOrSelectEventsAfterTick();
        }
      }
    } finally {
      _worldTickDoneHandling = false;
    }
  }

  bool get _shouldSuppressAutoEventsAfterTick {
    if (_activeChatLocationId.isNotEmpty) {
      return true;
    }
    if (_locationChatPageCache.activeLocationId.isNotEmpty) {
      return true;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return true;
    }
    return false;
  }

  void _showOrSelectEventsAfterTick() {
    if (_worldBottomSheetOpen &&
        _worldBottomSheetSelection.value.kind != WorldBottomSheetKind.events) {
      final sheetContext = _worldBottomSheetContext;
      if (sheetContext != null) {
        _openEventsAfterCurrentBottomSheetClosed = true;
        _eventsAfterCurrentBottomSheetClosedTargetTickNumber =
            _world?.tickCount;
        unawaited(Navigator.of(sheetContext).maybePop());
        return;
      }
    }
    _openWorldBottomSheet(
      WorldBottomSheetKind.events,
      scrollEventsToLatest: true,
      eventsTargetTickNumber: _world?.tickCount,
    );
  }

  void _markWorldTickIdle() {
    _setWorldTickInProgress(false);
    _setWorldTickWaitOverlayRequested(false);
    if (!mounted) {
      _worldActionRunning = false;
      return;
    }
    _setWorldPageState(() => _worldActionRunning = false);
  }

  void _markWorldTickFailed() {
    if (mounted) {
      _setWorldPageState(() => _worldTickProgressFailureRevision += 1);
    } else {
      _worldTickProgressFailureRevision += 1;
    }
    _markWorldTickIdle();
  }

  void _markEventsUnread() {
    if (_eventsUnread) return;
    _setWorldPageState(() => _eventsUnread = true);
  }

  void _clearEventsUnread() {
    if (!_eventsUnread) return;
    _setWorldPageState(() => _eventsUnread = false);
  }

  Future<bool> _confirmWorldRequest() async {
    final result = await showGenesisActionBox<bool>(
      context: context,
      title: 'Request to join this World?',
      actions: const [
        GenesisActionBoxAction<bool>(label: 'Request', value: true),
      ],
    );
    return result ?? false;
  }

  Future<void> _showLaunchRoleSheet(WorldDetail world) async {
    if (_worldActionRunning) return;
    if (!await ensureGenesisLogin(context)) return;
    if (!mounted) return;
    final selection = await showOriginRoleLaunchSheet(
      context: context,
      characters: worldPresetRoleCharacters(world),
      resolveAvatarUrl: worldResolveAssetUrl,
      onFillFromProfile: _customRoleFromProfile,
    );
    if (!mounted || selection == null) return;
    await _joinApprovedWorld(world, selection);
  }

  Future<void> _joinApprovedWorld(
    WorldDetail world,
    OriginRoleLaunchSelection roleSelection,
  ) async {
    if (_worldActionRunning) return;
    _setWorldPageState(() => _worldActionRunning = true);
    try {
      final message = await AppServicesScope.of(context).api.joinApprovedWorld(
        world.worldId,
        presetCharacterId: roleSelection.presetCharacterId,
        customRole: roleSelection.customRole?.toPayload(),
      );
      if (!mounted) return;
      if (message.trim().isNotEmpty) {
        showGenesisToast(context, message, brightness: Brightness.dark);
      }
      await _fetchWorld();
    } catch (_) {
      if (!mounted) return;
      showGenesisToast(context, 'Launch failed', brightness: Brightness.dark);
    } finally {
      if (mounted) _setWorldPageState(() => _worldActionRunning = false);
    }
  }

  Future<OriginCustomRoleDraft?> _customRoleFromProfile() async {
    if (!await _ensureProfileFillLogin()) return null;
    if (!mounted) return null;
    final services = AppServicesScope.read(context);
    final userInfo = await services.sessionStore.readUserInfo();
    if (userInfo == null || userInfo.isEmpty) {
      if (mounted) {
        showGenesisToast(
          context,
          'No saved profile found',
          brightness: Brightness.dark,
        );
      }
      return null;
    }
    final cachedUser = userInfo;
    final cachedName = worldMapString(cachedUser, const [
      'name',
      'nickname',
      'user_name',
      'displayName',
      'display_name',
    ]);
    return OriginCustomRoleDraft(
      avatarUrl: worldResolvedProfileAvatar(cachedUser, ''),
      name: cachedName,
      identity: worldMapString(cachedUser, const ['identity']),
      bio: worldMapString(cachedUser, const ['bio', 'description']),
    );
  }

  Future<bool> _ensureProfileFillLogin() => ensureGenesisLogin(context);
}

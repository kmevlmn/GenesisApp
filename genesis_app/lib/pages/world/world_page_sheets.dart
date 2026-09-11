part of 'world_page.dart';

extension _WorldPageSheets on _WorldPageState {
  void _showMapTab() {
    if (_worldMainTabIndex == 0) return;
    _selectWorldMainTab(0);
  }

  void _handleBottomSheetLocationTap(WorldPoint point) {
    unawaited(_openChatForPoint(point));
  }

  void _openWorldBottomSheet(
    WorldBottomSheetKind kind, {
    bool scrollEventsToLatest = false,
    int? eventsTargetTickNumber,
  }) {
    final world = _world;
    if (world == null) return;
    GenesisTelemetry.collectLog(
      actionType: 'pageview',
      action: worldBottomSheetPageName(kind),
      object1: widget.wid,
    );
    if (kind == WorldBottomSheetKind.events) {
      _clearEventsUnread();
    }
    if (kind == WorldBottomSheetKind.detail &&
        (_hasUnreadNewUserJoin || _pendingNewUserJoinNotice != null)) {
      _setWorldPageState(_activateDetailNewUserJoinNotices);
    }
    if (scrollEventsToLatest) {
      _eventsLatestRevision += 1;
    }
    _eventsTargetTickNumber = eventsTargetTickNumber;
    _sectionsWorldNotifier.value = world;
    final services = AppServicesScope.read(context);
    _worldBottomSheetSelection.value = WorldBottomSheetSelection(
      kind: kind,
      eventsLatestRevision: _eventsLatestRevision,
      eventsTargetTickNumber: _eventsTargetTickNumber,
    );
    if (_worldBottomSheetOpen) return;
    _setWorldPageState(() => _worldBottomSheetOpen = true);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        // The sheet owns its drag extent so content scrolling and collapsing
        // use the same DraggableScrollableSheet gesture chain as Origin.
        enableDrag: false,
        backgroundColor: Colors.transparent,
        // The sheet rises in place from Info's resting card and draws its
        // own scrim, so the route itself neither slides nor dims.
        barrierColor: Colors.transparent,
        isDismissible: false,
        sheetAnimationStyle: const AnimationStyle(
          duration: Duration.zero,
          reverseDuration: Duration.zero,
        ),
        builder: (context) {
          _worldBottomSheetContext = context;
          final bottomSafeArea = worldBottomSafeAreaOf(context);
          return Stack(
            children: [
              Positioned.fill(
                child: WorldSingleSectionBottomSheet(
                  selectionListenable: _worldBottomSheetSelection,
                  services: services,
                  initialWorld: world,
                  worldListenable: _sectionsWorldNotifier,
                  newUserJoinNoticesListenable: _newUserJoinNoticesNotifier,
                  eventsCache: _sectionsEventsCache,
                  currentUid: _currentUid,
                  recentChatLocationIds: _recentChatLocationIds,
                  onLocationTap: _handleBottomSheetLocationTap,
                  onDeleteWorld: _confirmAndDeleteWorldFromDetail,
                  bottomReservedHeight:
                      worldBubbleReservedHeight + bottomSafeArea,
                  infoBuilder: (context, world) => WorldInfoHeader(
                    world: world,
                    currentUid: _currentUid,
                    worldActionRunning: _worldActionRunning,
                    onWorldAction: _runWorldAction,
                  ),
                ),
              ),
              // The bubble stays reachable over the sheet: sections switch in
              // place, Info included.
              Positioned(
                left: worldFloatingSideInset,
                right: worldFloatingSideInset,
                bottom: bottomSafeArea + worldFloatingBottomGap,
                child: ValueListenableBuilder<WorldBottomSheetSelection>(
                  valueListenable: _worldBottomSheetSelection,
                  builder: (context, selection, _) => WorldFloatingBubble(
                    key: const ValueKey<String>('world-sheet-bubble'),
                    selected: selection.kind,
                    eventsUnread: _eventsUnread,
                    showDetailUnreadDot: _hasUnreadNewUserJoin,
                    onSelected: (kind) => _openWorldBottomSheet(kind),
                  ),
                ),
              ),
            ],
          );
        },
      ).whenComplete(() {
        if (mounted) {
          _setWorldPageState(() {
            _worldBottomSheetOpen = false;
            _worldBottomSheetContext = null;
            _applyDeferredBottomSheetMapChatroomState();
          });
        } else {
          _worldBottomSheetOpen = false;
          _worldBottomSheetContext = null;
          _deferredBottomSheetMapChatroomState = null;
        }
        final openEvents = _openEventsAfterCurrentBottomSheetClosed;
        final targetTickNumber =
            _eventsAfterCurrentBottomSheetClosedTargetTickNumber;
        _openEventsAfterCurrentBottomSheetClosed = false;
        _eventsAfterCurrentBottomSheetClosedTargetTickNumber = null;
        if (openEvents && mounted && !_shouldSuppressAutoEventsAfterTick) {
          _openWorldBottomSheet(
            WorldBottomSheetKind.events,
            scrollEventsToLatest: true,
            eventsTargetTickNumber: targetTickNumber,
          );
        }
      }),
    );
  }

  Future<void> _confirmAndDeleteWorldFromDetail(
    BuildContext actionContext,
    WorldDetail world,
  ) async {
    final worldId = world.worldId.trim();
    if (worldId.isEmpty ||
        !worldCanDeleteLaunchedOnlyBySelf(world, _currentUid)) {
      showGenesisToast(
        actionContext,
        'Only worlds launched by you alone can be deleted.',
        duration: const Duration(seconds: 3),
        brightness: Brightness.dark,
      );
      return;
    }

    final confirmed = await showGenesisActionBox<bool>(
      context: actionContext,
      title: '',
      titleWidget: _DeleteWorldConfirmationTitle(name: world.name.trim()),
      titleHeight: null,
      actions: const [
        GenesisActionBoxAction<bool>(label: 'Delete', value: true),
      ],
      cancelLabel: 'Cancel',
    );
    if (confirmed != true || !mounted || !actionContext.mounted) return;
    final api = AppServicesScope.read(actionContext).api;

    try {
      await api.v1.world.deleteLaunched(worldId: worldId);
      if (!mounted) return;
      final bottomSheetContext = _worldBottomSheetContext;
      if (bottomSheetContext != null && bottomSheetContext.mounted) {
        await Navigator.of(bottomSheetContext).maybePop();
      }
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(WorldPageResult.deleted(deletedWorldId: worldId));
    } catch (error) {
      if (!actionContext.mounted) return;
      showGenesisToast(
        actionContext,
        apiErrorMessage(error),
        brightness: Brightness.dark,
      );
    }
  }
}

class _DeleteWorldConfirmationTitle extends StatelessWidget {
  const _DeleteWorldConfirmationTitle({required this.name});

  static const _baseStyle = TextStyle(
    color: GenesisColors.darkTextPrimary,
    fontSize: 15,
    height: 1.16,
    fontWeight: FontWeight.w600,
  );
  static const _nameStyle = TextStyle(color: GenesisColors.redSecondary);

  final String name;

  @override
  Widget build(BuildContext context) {
    final resolvedName = name.trim().isEmpty ? 'this World' : name.trim();
    return Center(
      child: Text.rich(
        TextSpan(
          style: _baseStyle,
          children: [
            const TextSpan(text: 'Delete world '),
            TextSpan(text: resolvedName, style: _nameStyle),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

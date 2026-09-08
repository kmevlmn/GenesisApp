import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../app/genesis_navigator.dart';
import '../../components/common/genesis_action_box.dart';
import '../../components/world_tick1_wait_dialog.dart';
import '../../network/models/world.dart';
import '../world/world_navigation.dart';
import 'origin_launch_pending_store.dart';

typedef OriginLaunchWorldLoader = Future<WorldDetail> Function(String worldId);

class OriginLaunchRuntimeState {
  const OriginLaunchRuntimeState({
    required this.originId,
    required this.worldId,
  });

  final String originId;
  final String worldId;
}

class OriginLaunchOutcome {
  const OriginLaunchOutcome({
    required this.originId,
    required this.worldId,
    required this.completed,
    this.world,
  });

  final String originId;
  final String worldId;
  final bool completed;
  final WorldDetail? world;
}

class OriginLaunchCoordinator {
  OriginLaunchCoordinator._()
    : state = ValueNotifier<OriginLaunchRuntimeState?>(null);

  static final OriginLaunchCoordinator instance = OriginLaunchCoordinator._();
  static const Duration _pollInterval = Duration(seconds: 10);

  final ValueNotifier<OriginLaunchRuntimeState?> state;
  final Set<ValueChanged<OriginLaunchOutcome>> _outcomeListeners =
      <ValueChanged<OriginLaunchOutcome>>{};

  Timer? _timer;
  String? _originId;
  String? _worldId;
  OriginLaunchWorldLoader? _loadWorld;
  bool _pollInFlight = false;
  bool _completionDialogShowing = false;

  VoidCallback addOutcomeListener(ValueChanged<OriginLaunchOutcome> listener) {
    _outcomeListeners.add(listener);
    return () => _outcomeListeners.remove(listener);
  }

  Future<void> start({
    required String originId,
    required String worldId,
    String initialLocationId = '',
    required OriginLaunchWorldLoader loadWorld,
    BuildContext? context,
  }) async {
    await OriginLaunchPendingStore.save(
      originId: originId,
      worldId: worldId,
      initialLocationId: initialLocationId,
    );
    final pending = await OriginLaunchPendingStore.load();
    if (pending == null) return;
    _begin(pending: pending, loadWorld: loadWorld);
  }

  Future<void> ensurePolling({
    required OriginLaunchWorldLoader loadWorld,
    String? originId,
    BuildContext? context,
  }) async {
    final pending = await OriginLaunchPendingStore.load();
    if (pending == null) {
      if (_originId == null) state.value = null;
      return;
    }
    final requestedOriginId = originId?.trim() ?? '';
    if (requestedOriginId.isNotEmpty && pending.originId != requestedOriginId) {
      return;
    }
    if (pending.isExpired) {
      await _handleCompleted(pending: pending);
      return;
    }
    _begin(pending: pending, loadWorld: loadWorld);
  }

  bool isLaunchingOrigin(String originId) {
    return state.value?.originId == originId.trim();
  }

  void resetForTesting() {
    cancel();
    state.value = null;
    _outcomeListeners.clear();
    _completionDialogShowing = false;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _originId = null;
    _worldId = null;
    _loadWorld = null;
    _pollInFlight = false;
  }

  void _begin({
    required OriginLaunchPending pending,
    required OriginLaunchWorldLoader loadWorld,
  }) {
    _loadWorld = loadWorld;
    if (_originId == pending.originId &&
        _worldId == pending.worldId &&
        (_pollInFlight || _timer?.isActive == true)) {
      return;
    }
    _timer?.cancel();
    _originId = pending.originId;
    _worldId = pending.worldId;
    state.value = OriginLaunchRuntimeState(
      originId: pending.originId,
      worldId: pending.worldId,
    );
    unawaited(_poll(pending));
  }

  Future<void> _poll(OriginLaunchPending pending) async {
    if (_originId != pending.originId ||
        _worldId != pending.worldId ||
        _pollInFlight) {
      return;
    }
    if (pending.isExpired) {
      await _handleCompleted(pending: pending);
      return;
    }

    _pollInFlight = true;
    try {
      final loadWorld = _loadWorld;
      if (loadWorld == null) return;
      final world = await loadWorld(pending.worldId);
      if (_originId != pending.originId || _worldId != pending.worldId) return;
      if (worldHasTick1(world)) {
        await _handleCompleted(pending: pending, world: world);
        return;
      }
    } catch (_) {
      if (_originId != pending.originId || _worldId != pending.worldId) return;
    } finally {
      _pollInFlight = false;
    }

    _scheduleNextPoll(pending);
  }

  void _scheduleNextPoll(OriginLaunchPending pending) {
    if (_originId != pending.originId || _worldId != pending.worldId) return;
    if (pending.isExpired) {
      unawaited(_handleCompleted(pending: pending));
      return;
    }
    state.value = OriginLaunchRuntimeState(
      originId: pending.originId,
      worldId: pending.worldId,
    );
    _timer?.cancel();
    _timer = Timer(_pollInterval, () => unawaited(_poll(pending)));
  }

  Future<void> _handleCompleted({
    required OriginLaunchPending pending,
    WorldDetail? world,
  }) async {
    cancel();
    await OriginLaunchPendingStore.clear();
    state.value = null;
    _notifyOutcome(
      OriginLaunchOutcome(
        originId: pending.originId,
        worldId: pending.worldId,
        completed: true,
        world: world,
      ),
    );
    GenesisTelemetry.collectLog(
      actionType: 'event',
      action: 'worldo_launch_async_complete',
      object1: pending.originId,
      object2: pending.worldId,
    );
    await _showCompletionDialog(
      world,
      fallbackWorldId: pending.worldId,
      initialLocationId: pending.initialLocationId,
    );
  }

  void _notifyOutcome(OriginLaunchOutcome outcome) {
    for (final listener in List.of(_outcomeListeners)) {
      listener(outcome);
    }
  }

  Future<void> _showCompletionDialog(
    WorldDetail? world, {
    required String fallbackWorldId,
    required String initialLocationId,
  }) async {
    if (_completionDialogShowing) return;
    final context = _globalDialogContext;
    if (context == null) return;
    _completionDialogShowing = true;
    try {
      final worldName = (world?.name.trim().isEmpty ?? true)
          ? fallbackWorldId
          : world!.name.trim();
      final title = 'Worldo #$worldName launched!';
      final shouldGo = await showGenesisActionBox<bool>(
        context: context,
        title: title,
        titleWidget: _successActionBoxTitle(
          leadingText: 'Worldo ',
          highlightedText: '#$worldName',
          trailingText: ' launched!',
        ),
        actions: const [
          GenesisActionBoxAction<bool>(label: 'Enter', value: true),
        ],
      );
      if (shouldGo == true) {
        _navigateToWorld(
          world,
          fallbackWorldId: fallbackWorldId,
          initialLocationId: initialLocationId,
        );
      }
    } finally {
      _completionDialogShowing = false;
    }
  }

  void _navigateToWorld(
    WorldDetail? world, {
    required String fallbackWorldId,
    required String initialLocationId,
  }) {
    final navigator = genesisNavigatorKey.currentState;
    if (navigator == null) return;
    final wid = (world?.worldId.trim().isEmpty ?? true)
        ? fallbackWorldId
        : world!.worldId.trim();
    openWorldFromMyWorldsRoot(
      navigator,
      arguments: {
        'wid': wid,
        if (world != null) 'initial_world_detail': world,
        if (initialLocationId.trim().isNotEmpty)
          'initial_location_id': initialLocationId.trim(),
      },
    );
  }

  BuildContext? get _globalDialogContext {
    final navigator = genesisNavigatorKey.currentState;
    final overlayContext = navigator?.overlay?.context;
    if (overlayContext != null && overlayContext.mounted) {
      return overlayContext;
    }
    final navigatorContext = navigator?.context;
    if (navigatorContext != null && navigatorContext.mounted) {
      return navigatorContext;
    }
    return null;
  }
}

Widget _successActionBoxTitle({
  required String leadingText,
  required String highlightedText,
  required String trailingText,
}) {
  const baseStyle = TextStyle(
    color: GenesisColors.darkTextPrimary,
    fontSize: 15,
    height: 1.16,
    fontWeight: FontWeight.w600,
  );
  return RichText(
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    text: TextSpan(
      style: baseStyle,
      children: [
        TextSpan(text: leadingText),
        TextSpan(
          text: highlightedText,
          style: baseStyle.copyWith(color: GenesisColors.redSecondary),
        ),
        TextSpan(text: trailingText),
      ],
    ),
  );
}

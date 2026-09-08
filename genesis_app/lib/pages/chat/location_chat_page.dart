import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/bootstrap/service_registry.dart';
import '../../app/config/genesis_image_config.dart';
import '../../app/debug/location_chat_bubble_layout_settings.dart';
import '../../app/debug/location_chat_debug_slice.dart';
import '../../app/debug/location_chat_header_effect_settings.dart';
import '../../app/debug/world_new_content_debug_settings.dart';
import '../../app/recent_chat/recent_world_chat_store.dart';
import '../../app/telemetry/firebase_analytics_monitoring.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/auth/login_guard.dart';
import '../../components/chat/chatroom_failure_toast.dart';
import '../../components/chat/shared/chat_ui.dart';
import '../../components/common/genesis_bottom_sheet_panel.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../components/common/genesis_modal_routes.dart';
import '../../components/common/genesis_report_actions.dart';
import '../../components/gems/gem_balance_prompt.dart';
import '../../components/gems/memory_model_entry_button.dart';
import '../../components/world_new_badge.dart';
import '../../network/chatroom/chatroom_connection_controller.dart';
import '../../network/chatroom/chatroom_message_type.dart';
import '../../network/chatroom/chatroom_models.dart';
import '../../network/chatroom/chatroom_timeline_payload.dart';
import '../../network/chatroom/world_chatroom_service.dart';
import '../../network/genesis_api.dart';
import '../../network/json_utils.dart';
import '../../network/models/gem_model.dart';
import '../../network/models/location_tree.dart';
import '../../network/models/world.dart';
import '../../platform/device/android_sdk_version.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_character_avatar.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../ui/components/genesis_static_network_image.dart';
import '../../ui/components/genesis_tab_bar.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/genesis_image_resource.dart';
import '../../utils/genesis_ugc_text.dart';
import 'location_chat_scroll_coordinator.dart';
import 'message_parsers/location_chat_message_parsers.dart';
import '../world/world_constants.dart' show worldCharacterAvatarLogicalSize;

part 'location_chat_panel_connection.dart';
part 'location_chat_message_reconciler.dart';
part 'location_chat_send_actions.dart';
part 'location_chat_message_window.dart';
part 'location_chat_mentions.dart';
part 'location_chat_composer_input.dart';
part 'location_chat_identity.dart';
part 'location_chat_panel_actions.dart';
part 'location_chat_layout.dart';
part 'location_chat_tick_progress.dart';
part 'location_chat_panel_widgets.dart';
part 'location_chat_shared.dart';

const double _locationChatAvatarLogicalSize = 40;
const double _locationChatComposerBottomExtension = 60;
const double _locationChatBackgroundPreviewLogicalWidth = 120;
const Duration _locationChatBackgroundFadeDuration = Duration(
  milliseconds: 150,
);
const int _locationChatKeyboardMotionTraceMaxSamples = 120;
const double _locationChatEdgeSwipeWidth = 24;
const double _locationChatEdgeSwipeTriggerDistance = 64;
const double _locationChatEdgeSwipeTriggerVelocity = 450;
const int _locationChatMessageGapMaxAttempts = 3;
const double _locationChatOlderMessagesTriggerExtent = 180;
const Duration _locationChatOlderMessagesIdleDelay = Duration(milliseconds: 80);
const String _locationChatDefaultBackgroundAsset =
    'assets/images/map_default/location_default.webp';

@visibleForTesting
Future<void> runLocationChatMetadataUpdateBestEffort(
  Future<void> Function() update,
) async {
  try {
    await update();
  } catch (error, stackTrace) {
    debugPrint('[LocationChat] metadata update failed: $error\n$stackTrace');
  }
}

@visibleForTesting
bool locationChatShouldShowAiContentDisclaimerForTesting({
  required bool initialContentReady,
  required bool hasMoreOlderMessages,
  required bool loadingOlderMessages,
}) {
  return initialContentReady && !hasMoreOlderMessages && !loadingOlderMessages;
}

@visibleForTesting
bool locationChatManagesKeyboardInsetForTesting({
  required TargetPlatform platform,
  required int? androidSdkInt,
}) {
  return platform == TargetPlatform.iOS ||
      platform == TargetPlatform.android && (androidSdkInt ?? 0) >= 30;
}

double locationChatEffectiveKeyboardInset({
  required double rawKeyboardInset,
  required double bottomSafeAreaInset,
}) {
  return math.max(0.0, rawKeyboardInset - bottomSafeAreaInset);
}

@visibleForTesting
double locationChatEffectiveKeyboardInsetForTesting({
  required double rawKeyboardInset,
  required double bottomSafeAreaInset,
}) => locationChatEffectiveKeyboardInset(
  rawKeyboardInset: rawKeyboardInset,
  bottomSafeAreaInset: bottomSafeAreaInset,
);

@visibleForTesting
ChatUiStyleConfig resolveLocationChatHeaderEffectStyle({
  required ChatUiStyleConfig baseStyle,
  required LocationChatHeaderEffectSettings settings,
}) {
  final surfaceOpacity = settings.transparencyStrength
      .clamp(0.0, 1.0)
      .toDouble();
  final blurSigma = settings.blurSigma
      .clamp(
        LocationChatHeaderEffectSettings.minBlurSigma,
        LocationChatHeaderEffectSettings.maxBlurSigma,
      )
      .toDouble();
  final surfaceBackground = baseStyle.conversationBackgroundColor.withValues(
    alpha: surfaceOpacity,
  );
  return baseStyle.copyWith(
    headerBackgroundColor: surfaceBackground,
    clearHeaderBackgroundGradient: true,
    headerBackdropBlurSigma: blurSigma,
    composerBackgroundColor: surfaceBackground,
    clearComposerBackgroundGradient: true,
    composerBackdropBlurSigma: blurSigma,
  );
}

class LocationChatPage extends StatefulWidget {
  const LocationChatPage({
    super.key,
    required this.worldId,
    required this.locationId,
    this.isLeafLocation = true,
    this.localMessageLocationIds = const <String>[],
    this.recentChatLocationPathIds = const <String>[],
    this.worldName,
    this.locationName,
    this.parentLocationName,
    this.backgroundImageUrl,
    this.backgroundPreviewImageUrl,
    this.renderBackgroundImage = true,
    this.service,
    this.connection,
    this.onCharactersMovedLocationTap,
  });

  final String worldId;
  final String locationId;
  final bool isLeafLocation;
  final List<String> localMessageLocationIds;
  final List<String> recentChatLocationPathIds;
  final String? worldName;
  final String? locationName;
  final String? parentLocationName;
  final String? backgroundImageUrl;
  final String? backgroundPreviewImageUrl;
  final bool renderBackgroundImage;
  final WorldChatroomService? service;
  final ChatroomConnectionController? connection;
  final ChatCharacterMovementTap? onCharactersMovedLocationTap;

  @override
  State<LocationChatPage> createState() => _LocationChatPageState();
}

class _LocationChatPageState extends State<LocationChatPage> {
  bool _openingCharactersMovedLocation = false;

  Future<void> _openCharactersMovedLocation(
    ChatCharacterMovementVm movement,
  ) async {
    final targetLocationId = movement.toLocationId.trim();
    if (targetLocationId.isEmpty ||
        targetLocationId == widget.locationId.trim()) {
      return;
    }
    if (_openingCharactersMovedLocation) return;
    _openingCharactersMovedLocation = true;
    final customHandler = widget.onCharactersMovedLocationTap;
    if (customHandler != null) {
      try {
        customHandler(movement);
      } catch (error) {
        GenesisTelemetry.collectLog(
          actionType: 'event',
          action: 'location_chat_movement_navigation_failed',
          object1: widget.worldId,
          object2: targetLocationId,
        );
        if (kDebugMode) {
          debugPrint('[LocationChat] movement callback failed: $error');
        }
      } finally {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openingCharactersMovedLocation = false;
        });
      }
      return;
    }
    try {
      await Navigator.of(context).pushReplacementNamed(
        RouteNames.locationChat,
        arguments: <String, Object?>{
          'world_id': widget.worldId,
          'location_id': targetLocationId,
          'world_name': widget.worldName ?? '',
          'location_name': movement.toLocationName,
          'is_leaf_location': true,
          'local_message_location_ids': <String>[targetLocationId],
          if (widget.service != null) 'world_chatroom_service': widget.service,
          if (widget.connection != null)
            'chatroom_connection': widget.connection,
        },
      );
    } catch (error) {
      GenesisTelemetry.collectLog(
        actionType: 'event',
        action: 'location_chat_movement_navigation_failed',
        object1: widget.worldId,
        object2: targetLocationId,
      );
      if (kDebugMode) {
        debugPrint('[LocationChat] movement navigation failed: $error');
      }
    } finally {
      if (mounted) _openingCharactersMovedLocation = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocationChatPanel(
      worldId: widget.worldId,
      modelWorldId: widget.worldId,
      locationId: widget.locationId,
      isLeafLocation: widget.isLeafLocation,
      localMessageLocationIds: widget.localMessageLocationIds,
      recentChatLocationPathIds: widget.recentChatLocationPathIds,
      worldName: widget.worldName,
      locationName: widget.locationName,
      parentLocationName: widget.parentLocationName,
      backgroundImageUrl: widget.backgroundImageUrl,
      backgroundPreviewImageUrl: widget.backgroundPreviewImageUrl,
      renderBackgroundImage: widget.renderBackgroundImage,
      service: widget.service,
      connection: widget.connection,
      active: true,
      leaveOnInactive: widget.service == null,
      showMoreButton: false,
      onBack: () => Navigator.of(context).maybePop(),
      onCharactersMovedLocationTap: (movement) {
        unawaited(_openCharactersMovedLocation(movement));
      },
    );
  }
}

class LocationChatPanel extends StatefulWidget {
  const LocationChatPanel({
    super.key,
    required this.worldId,
    this.modelWorldId,
    required this.locationId,
    this.isLeafLocation = true,
    this.localMessageLocationIds = const <String>[],
    this.recentChatLocationPathIds = const <String>[],
    this.worldName,
    this.locationName,
    this.parentLocationName,
    this.backgroundImageUrl,
    this.backgroundPreviewImageUrl,
    this.renderBackgroundImage = true,
    this.openingPreviewMessages = const <WorldChatroomMessage>[],
    this.openingPreviewEntities = const <WorldChatroomEntity>[],
    this.service,
    this.connection,
    this.worldTickInProgress = false,
    this.worldTickProgressFailureRevision = 0,
    this.active = true,
    this.leaveOnInactive = true,
    this.onBack,
    this.onInitialContentReady,
    this.showComposer = true,
    this.composerReplacement,
    this.composerTopOverlay,
    this.emptyState,
    this.showConnectionStatus = true,
    this.showMoreButton = false,
    this.systemUiOverlayStyle = kChatDarkHeaderSystemUiOverlayStyle,
    this.style,
    this.initialDraftText = '',
    this.initialMessageToSend = '',
    this.initialMentionCatalog,
    this.onDraftTextChanged,
    this.messageQueueInitializationCovered = false,
    this.unauthorizedHandledByOwner = false,
    this.onCharactersMovedLocationTap,
  });

  final String worldId;

  /// Set only when this panel belongs to a launched World. Worldo previews
  /// leave this null so model UI and model API requests stay disabled.
  final String? modelWorldId;
  final String locationId;
  final bool isLeafLocation;
  final List<String> localMessageLocationIds;
  final List<String> recentChatLocationPathIds;
  final String? worldName;
  final String? locationName;
  final String? parentLocationName;
  final String? backgroundImageUrl;
  final String? backgroundPreviewImageUrl;
  final bool renderBackgroundImage;
  final List<WorldChatroomMessage> openingPreviewMessages;
  final List<WorldChatroomEntity> openingPreviewEntities;
  final WorldChatroomService? service;
  final ChatroomConnectionController? connection;
  final bool worldTickInProgress;
  final int worldTickProgressFailureRevision;
  final bool active;
  final bool leaveOnInactive;
  final VoidCallback? onBack;
  final VoidCallback? onInitialContentReady;
  final bool showComposer;
  final Widget? composerReplacement;
  final Widget? composerTopOverlay;
  final Widget? emptyState;
  final bool showConnectionStatus;
  final bool showMoreButton;
  final SystemUiOverlayStyle systemUiOverlayStyle;
  final ChatUiStyleConfig? style;
  final String initialDraftText;
  final String initialMessageToSend;
  final ChatMentionCatalog? initialMentionCatalog;
  final ValueChanged<String>? onDraftTextChanged;
  final bool messageQueueInitializationCovered;
  final bool unauthorizedHandledByOwner;
  final ChatCharacterMovementTap? onCharactersMovedLocationTap;

  @override
  State<LocationChatPanel> createState() => _LocationChatPanelState();
}

class _LocationChatPanelState extends State<LocationChatPanel> {
  late final LocationChatScrollCoordinator _scrollCoordinator;
  ScrollController get _scrollController => _scrollCoordinator.controller;
  late final LocationChatMentionEditingController _textController;
  final _composerFocusNode = FocusNode();
  final Object _rosterTapRegionGroup = Object();
  final BackdropKey _surfaceBackdropKey = BackdropKey();
  final Stopwatch _panelStopwatch = Stopwatch()..start();
  final _messages = <ChatMessageVm>[];
  final Map<String, _LocationChatTimelineVmCacheEntry> _timelineVmCache =
      <String, _LocationChatTimelineVmCacheEntry>{};
  WorldChatroomService? _service;
  StreamSubscription<WorldChatroomState>? _stateSubscription;
  StreamSubscription<ChatroomFailureEvent>? _failuresSubscription;
  StreamSubscription<GemBalanceAlert>? _balanceAlertSubscription;
  WorldChatroomState _chatroomState = const WorldChatroomState();
  final Set<String> _myUserIdKeys = <String>{};
  final Set<String> _mySenderIdKeys = <String>{};
  String _myUserId = '';
  String _mySenderId = '';
  String _mySenderName = '';
  String _myAvatarUrl = '';
  String _selectedModelCode = '';
  String _selectedModelTitle = '';
  String _selectedModelTitleLookupCode = '';
  double _devicePixelRatio = 1;
  bool _ownsService = false;
  bool _joinedLocation = false;
  bool _joiningLocation = false;
  bool _optimisticSelfOccupancy = false;
  List<WorldChatroomEntity>? _lastActiveOccupants;
  List<WorldChatroomEntity>? _exitRetainedOccupants;
  bool _sending = false;
  bool _rosterOpen = false;
  bool _mentionSheetOpen = false;
  bool _mentionComposerPositionFrozen = false;
  double _mentionSheetKeyboardInset = 0;
  bool _mentionSheetSchedulePending = false;
  bool _handlingUnauthorizedFailure = false;
  bool _hasDraftText = false;
  bool _initialMessageSendPending = false;
  bool _initialMessageSendScheduled = false;
  bool _loadingOlderMessages = false;
  Timer? _olderMessagesLoadIdleTimer;
  bool _showOlderMessagesLoading = false;
  bool _hasMoreOlderMessages = true;
  bool _olderMessagesExhaustedByRemote = false;
  bool _olderMessagesExhaustedByCursorlessContent = false;
  bool _initialContentReadyNotified = false;
  Future<void>? _initialLatestMessagesRefresh;
  final Set<String> _unseenIncomingMessageLocalIds = <String>{};

  int get _unseenIncomingCount => _unseenIncomingMessageLocalIds.length;
  int _clientMsgCounter = 0;
  final Set<String> _messageGapFillKeys = <String>{};
  final Set<int> _messageGapFillBeforeLocationMessageIds = <int>{};
  final Map<String, int> _messageGapFillAttempts = <String, int>{};
  final Set<String> _releasedMessageGapKeys = <String>{};
  bool _deferredVisibleMessageGapFill = false;
  double _edgeSwipeBackDragDistance = 0;
  bool _edgeSwipeBackTriggered = false;
  bool _openingModelPage = false;
  late bool _retainModelEntryInHeader;
  int _serviceGeneration = 0;
  int _selectedModelLoadGeneration = 0;
  ValueListenable<int>? _userInfoRevisionListenable;
  int _tickProgressGeneration = 0;
  bool _tickProgressSessionActive = false;
  bool _awaitingTickProgressMessage = false;
  String _activeTickProgressSlotId = '';
  Set<String> _tickProgressBaselineLocalIds = const <String>{};
  int _tickProgressBaselineLocationMessageId = 0;
  int _tickProgressBaselineMessageId = 0;
  DateTime _tickProgressStartedAt = DateTime.fromMillisecondsSinceEpoch(0);

  String get _modelWorldId => widget.modelWorldId?.trim() ?? '';

  bool get _hasModelWorldId => _modelWorldId.isNotEmpty;
  final Map<String, String> _tickProgressLayoutIdByMessageLocalId =
      <String, String>{};
  final ChatMessageVm _aiContentDisclaimerMessage =
      ChatMessageVm.aiContentDisclaimer();
  int? _androidSdkInt;

  bool get _sendAwaitingResponse {
    final state = _service?.state ?? _chatroomState;
    return state.conversationRoundStatesByLocation.containsKey(
      widget.locationId,
    );
  }

  bool get _shouldShowAiContentDisclaimer =>
      locationChatShouldShowAiContentDisclaimerForTesting(
        initialContentReady: _initialContentReadyNotified,
        hasMoreOlderMessages: _hasMoreOlderMessages,
        loadingOlderMessages: _loadingOlderMessages,
      );

  void _setLocationChatState(VoidCallback callback) {
    setState(callback);
  }

  void _handleViewportCoordinatorChanged() {
    if (!mounted) return;
    _setLocationChatState(() {});
    _handleMessageListScroll();
  }

  @override
  void initState() {
    super.initState();
    _optimisticSelfOccupancy = widget.active && widget.isLeafLocation;
    locationChatHeaderEffectSettings.addListener(
      _handleHeaderEffectSettingsChanged,
    );
    locationChatBubbleLayoutSettings.addListener(
      _handleBubbleLayoutSettingsChanged,
    );
    unawaited(locationChatBubbleLayoutSettings.load());
    unawaited(locationChatHeaderEffectSettings.load());
    _androidSdkInt = cachedAndroidSdkInt;
    _retainModelEntryInHeader = widget.active && _hasModelWorldId;
    _scrollCoordinator = LocationChatScrollCoordinator()
      ..addListener(_handleViewportCoordinatorChanged);
    final initialService = widget.service;
    if (initialService != null) _syncSenderIdentity(initialService);
    final stateMentionCatalog = locationChatMentionCatalogForState(
      widget.service?.state ?? _chatroomState,
      currentUserIds: _myUserIdKeys,
      currentSenderIds: _mySenderIdKeys,
    );
    _textController = LocationChatMentionEditingController(
      catalog: mergeLocationChatMentionCatalogs(
        stateMentionCatalog,
        widget.initialMentionCatalog,
      ),
    );
    final initialMessageToSend = widget.initialMessageToSend;
    final initialDraftText = initialMessageToSend.trim().isNotEmpty
        ? initialMessageToSend
        : widget.initialDraftText;
    if (initialDraftText.isNotEmpty) {
      _textController.setSerializedText(initialDraftText);
      _hasDraftText = initialDraftText.trim().isNotEmpty;
    }
    _initialMessageSendPending = initialMessageToSend.trim().isNotEmpty;
    _logPanelMetric(
      'init active=${widget.active} leaf=${widget.isLeafLocation} '
      'aliases=${widget.localMessageLocationIds.join(',')}',
    );
    _composerFocusNode.addListener(_handleComposerFocusChanged);
    _textController.addListener(_handleDraftTextChanged);
    _scrollController.addListener(_handleMessageListScroll);
    _scrollCoordinator.enter();
    _prepareConnection();
    if (_hasModelWorldId) {
      unawaited(_loadSelectedModelCodeFromCache());
    }
    unawaited(_loadAndroidSdkIntForKeyboardInset());
  }

  Future<void> _loadAndroidSdkIntForKeyboardInset() async {
    final sdkInt = await loadAndroidSdkInt();
    if (!mounted || sdkInt == null || sdkInt == _androidSdkInt) return;
    _setLocationChatState(() => _androidSdkInt = sdkInt);
  }

  void _handleHeaderEffectSettingsChanged() {
    if (!mounted) return;
    _setLocationChatState(() {});
  }

  void _handleBubbleLayoutSettingsChanged() {
    if (!mounted) return;
    _setLocationChatState(() {});
  }

  @override
  void dispose() {
    locationChatHeaderEffectSettings.removeListener(
      _handleHeaderEffectSettingsChanged,
    );
    locationChatBubbleLayoutSettings.removeListener(
      _handleBubbleLayoutSettingsChanged,
    );
    _cancelOlderMessagesLoadSchedule();
    _selectedModelLoadGeneration++;
    _timelineVmCache.clear();
    _userInfoRevisionListenable?.removeListener(_handleCachedUserInfoChanged);
    _recordPanelDebug(action: 'dispose', activeOverride: false);
    final service = _service;
    if (_ownsService && service != null) {
      unawaited(service.disconnect().catchError((Object _) {}));
    }
    unawaited(_closeChatroom());
    widget.onDraftTextChanged?.call(_textController.serializedText);
    _scrollController.removeListener(_handleMessageListScroll);
    _scrollCoordinator.removeListener(_handleViewportCoordinatorChanged);
    _scrollCoordinator.dispose();
    _composerFocusNode.removeListener(_handleComposerFocusChanged);
    _composerFocusNode.dispose();
    _textController.removeListener(_handleDraftTextChanged);
    _textController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LocationChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final modelWorldIdChanged =
        (oldWidget.modelWorldId?.trim() ?? '') != _modelWorldId;
    if (modelWorldIdChanged) {
      _selectedModelLoadGeneration++;
      _selectedModelTitleLookupCode = '';
    }
    if (!_hasModelWorldId) {
      _retainModelEntryInHeader = false;
    } else if (widget.active) {
      _retainModelEntryInHeader = true;
    }
    if (_hasModelWorldId &&
        (modelWorldIdChanged || (!oldWidget.active && widget.active))) {
      unawaited(_loadSelectedModelCodeFromCache());
    }
    final changedChatTarget =
        oldWidget.service != widget.service ||
        oldWidget.worldId != widget.worldId ||
        oldWidget.locationId != widget.locationId;
    final becameActive = !oldWidget.active && widget.active;
    final becameInactive = oldWidget.active && !widget.active;
    if (becameActive) {
      _lastActiveOccupants = null;
      _exitRetainedOccupants = null;
      _optimisticSelfOccupancy = widget.isLeafLocation;
    } else if (becameInactive) {
      _exitRetainedOccupants =
          _lastActiveOccupants ??
          _roomOccupantsForCurrentLocation(_chatroomState);
      _optimisticSelfOccupancy = false;
    }
    if (changedChatTarget || becameInactive) {
      _rosterOpen = false;
    }
    final worldTickProgressChanged =
        oldWidget.worldTickInProgress != widget.worldTickInProgress;
    final worldTickProgressFailed =
        oldWidget.worldTickProgressFailureRevision !=
        widget.worldTickProgressFailureRevision;
    final changedOpeningPreview =
        !listEquals(
          oldWidget.openingPreviewMessages,
          widget.openingPreviewMessages,
        ) ||
        !listEquals(
          oldWidget.openingPreviewEntities,
          widget.openingPreviewEntities,
        );
    if (widget.active && (changedChatTarget || becameActive)) {
      _scrollCoordinator.enter();
    } else if (becameInactive || (!widget.active && changedChatTarget)) {
      _scrollCoordinator.deactivate();
    }
    if (worldTickProgressChanged) {
      final source =
          _chatroomState.messagesByLocation[widget.locationId] ??
          const <WorldChatroomMessage>[];
      _syncTickProgressState(
        progressing: widget.worldTickInProgress || _chatroomState.inputBlocked,
        nextSource: source,
      );
    }
    if (worldTickProgressFailed) {
      _cancelTickProgressMessage();
    }
    if (becameActive &&
        !widget.worldTickInProgress &&
        !(widget.service?.state.inputBlocked ?? _chatroomState.inputBlocked)) {
      _discardStaleTickProgressMessage();
    }
    if (changedChatTarget || changedOpeningPreview) {
      _cancelOlderMessagesLoadSchedule();
      _initialContentReadyNotified = false;
      unawaited(
        _closeChatroom().then((_) {
          if (!mounted) return;
          _hasMoreOlderMessages = true;
          if (changedChatTarget) {
            _olderMessagesExhaustedByRemote = false;
            _olderMessagesExhaustedByCursorlessContent = false;
          }
          _loadingOlderMessages = false;
          _showOlderMessagesLoading = false;
          _initialContentReadyNotified = false;
          _initialLatestMessagesRefresh = null;
          _messageGapFillKeys.clear();
          _messageGapFillBeforeLocationMessageIds.clear();
          _messageGapFillAttempts.clear();
          _releasedMessageGapKeys.clear();
          _deferredVisibleMessageGapFill = false;
          _prepareConnection();
        }),
      );
      return;
    }
    if (becameActive) {
      _activateConnection();
    } else if (becameInactive) {
      unawaited(_deactivateConnection());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userInfoRevision = AppServicesScope.of(
      context,
    ).sessionStore.userInfoRevision;
    if (!identical(_userInfoRevisionListenable, userInfoRevision)) {
      _userInfoRevisionListenable?.removeListener(_handleCachedUserInfoChanged);
      _userInfoRevisionListenable = userInfoRevision;
      userInfoRevision.addListener(_handleCachedUserInfoChanged);
    }
    final previousDevicePixelRatio = _devicePixelRatio;
    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    if ((previousDevicePixelRatio - _devicePixelRatio).abs() > 0.01 &&
        !widget.active &&
        widget.openingPreviewMessages.isNotEmpty) {
      final changedMessages = _syncOpeningPreviewMessages();
      _logPanelMetric(
        'opening preview dpr sync '
        '$previousDevicePixelRatio->$_devicePixelRatio '
        'changed=$changedMessages',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final occupants = !widget.active && _exitRetainedOccupants != null
        ? _exitRetainedOccupants!
        : _roomOccupantsForCurrentLocation(_chatroomState);
    final selfOccupantId = firstNonEmpty([_myUserId, _mySenderId]);
    final title = firstNonEmpty([widget.locationName, widget.locationId]);
    final joined = _chatroomState.joinedLocationId == widget.locationId;
    final connecting =
        _chatroomState.reconnecting ||
        _chatroomState.joining ||
        (_chatroomState.connected && !joined);
    final inputBlocked = _chatroomState.inputBlocked;
    final style = resolveLocationChatHeaderEffectStyle(
      baseStyle: widget.style ?? kLocationChatStyle,
      settings: locationChatHeaderEffectSettings.value,
    );
    final logicalWidth = MediaQuery.sizeOf(context).width;
    final ordinaryMessageBubbleMaxWidthCaps =
        locationChatOrdinaryMessageBubbleMaxWidthCapsForMetrics(
          logicalWidth: logicalWidth,
          textScaler: MediaQuery.textScalerOf(context),
          bubbleFontSize: style.bubbleTextStyle.fontSize ?? 14,
          crowdedEffectiveWidthThreshold: locationChatBubbleLayoutSettings
              .value
              .crowdedEffectiveWidthThreshold,
          avatarSize: style.avatarSize,
          avatarBubbleGap: style.avatarBubbleGap,
          avatarSideSpacerWidth: style.avatarSideSpacerWidth,
          messageListHorizontalPadding: style.messageListPadding.horizontal,
        );
    final Widget? composer;
    if (!widget.showComposer) {
      composer = null;
    } else {
      composer =
          widget.composerReplacement ??
          LocationChatComposerInput(
            controller: _textController,
            focusNode: _composerFocusNode,
            hintText: 'Text...',
            inputEnabled: widget.active,
            sendEnabled:
                widget.active &&
                joined &&
                _hasDraftText &&
                !_sending &&
                !_sendAwaitingResponse &&
                !inputBlocked,
            sending: false,
            onSend: _send,
            style: style,
            keepShortcutsVisible:
                widget.active && _mentionComposerPositionFrozen,
            backdropGroupKey: _surfaceBackdropKey,
          );
    }
    final headerForeground =
        style.headerTitleTextStyle.color ?? style.headerTitleIconColor;
    final occupantCountLabel = '${occupants.length}';
    final occupantPill = TapRegion(
      groupId: _rosterTapRegionGroup,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: occupants.isEmpty
            ? null
            : () => setState(() => _rosterOpen = !_rosterOpen),
        child: Container(
          key: const ValueKey<String>('location-chat-occupant-pill'),
          height: 18,
          padding: const EdgeInsets.fromLTRB(6, 0, 5, 0),
          decoration: BoxDecoration(
            color: headerForeground.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                occupantCountLabel,
                maxLines: 1,
                style: style.headerTitleTextStyle.copyWith(
                  color: headerForeground.withValues(alpha: 0.73),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
              const SizedBox(width: 3),
              _OccupantChevron(
                color: headerForeground.withValues(alpha: 0.8),
                pointUp: _rosterOpen,
              ),
            ],
          ),
        ),
      ),
    );
    final header = ChatHeader(
      title: title,
      titleOverline: widget.parentLocationName,
      titleSuffix: occupantPill,
      titleSuffixSemanticsLabel: occupantCountLabel,
      subtitle: '',
      connected: joined,
      connecting: connecting,
      alignContentLeft: true,
      onBack: widget.onBack ?? () => Navigator.of(context).maybePop(),
      showTitleIcon: true,
      showSubtitle: false,
      showMoreButton: widget.showMoreButton,
      trailingVerticallyCentered: true,
      trailing: _retainModelEntryInHeader && _hasModelWorldId
          ? Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ExcludeSemantics(
                excluding: !widget.active,
                child: IgnorePointer(
                  ignoring: !widget.active,
                  child: MemoryModelEntryButton(
                    modelLabel: _selectedModelLabel,
                    variant: MemoryModelEntryButtonVariant.roomHeader,
                    onTap: () => unawaited(_openMemoryModelPage()),
                  ),
                ),
              ),
            )
          : null,
      style: style,
      backdropGroupKey: _surfaceBackdropKey,
    );
    final headerHeight = _locationChatHeaderHeight(style);
    final displayMessages = _locationChatDisplayMessages();
    final managesKeyboardInset = locationChatManagesKeyboardInsetForTesting(
      platform: Theme.of(context).platform,
      androidSdkInt: _androidSdkInt,
    );
    final bottomSafeAreaInset = GenesisSafeAreaInsets.bottom(context);
    final messageList = ChatMentionScope(
      catalog: _textController.catalog,
      child: LocationChatAnchoredMessageList(
        key: const ValueKey<String>('location-chat-message-list'),
        coordinator: _scrollCoordinator,
        messages: displayMessages,
        messageLayoutId: _locationChatMessageLayoutId,
        topTitle: '',
        oldestEdgeLoading: _showOlderMessagesLoading,
        onOldestEdgeLoadingCollapsed: _handleOlderMessagesLoadingCollapsed,
        onMessageLongPressStart: _showMessageActionMenu,
        onFailedMessageTap: (message) =>
            unawaited(_retryFailedMessage(message)),
        onCharactersMovedLocationTap:
            widget.onCharactersMovedLocationTap == null
            ? null
            : (movement) {
                final targetLocationId = movement.toLocationId.trim();
                if (targetLocationId.isEmpty ||
                    targetLocationId == widget.locationId.trim()) {
                  return;
                }
                widget.onCharactersMovedLocationTap!(movement);
              },
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        showDateDividers: false,
        selfMessageBubbleMaxWidthCap:
            ordinaryMessageBubbleMaxWidthCaps.selfMessage,
        otherMessageBubbleMaxWidthCap:
            ordinaryMessageBubbleMaxWidthCaps.otherMessage,
        style: style,
      ),
    );

    return GenesisBottomSystemBarStyleScope(
      style: GenesisBottomSystemBarStyle(color: style.composerBackgroundColor),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: widget.systemUiOverlayStyle,
        child: Stack(
          children: [
            Positioned.fill(
              child: _LocationChatBackground(
                imageUrl: widget.backgroundImageUrl,
                previewImageUrl: widget.backgroundPreviewImageUrl,
                color: style.conversationBackgroundColor,
                enabled: widget.renderBackgroundImage,
              ),
            ),
            Positioned.fill(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                resizeToAvoidBottomInset:
                    !managesKeyboardInset &&
                    _composerFocusNode.hasFocus &&
                    !_mentionComposerPositionFrozen,
                body: _LocationChatKeyboardInsetLayout(
                  key: const ValueKey<String>(
                    'location-chat-ios-keyboard-inset',
                  ),
                  managesKeyboardInset: managesKeyboardInset,
                  freezeKeyboardInset: _mentionComposerPositionFrozen,
                  frozenKeyboardInset: _mentionSheetKeyboardInset,
                  onFrozenKeyboardInsetRestored:
                      _handleMentionKeyboardInsetRestored,
                  bottomSafeAreaInset: bottomSafeAreaInset,
                  onKeyboardMotionTraceSettled: kDebugMode
                      ? (samples) {
                          if (!LocationChatDebugSlice.enabled) return;
                          LocationChatDebugSlice.recordEvent(
                            source: 'panel',
                            action: 'keyboard_motion_settled',
                            worldId: widget.worldId,
                            locationId: widget.locationId,
                            details: <String, Object?>{
                              'sampleCount': samples.length,
                              'samples': samples,
                            },
                          );
                        }
                      : null,
                  messageViewport: Stack(
                    children: [
                      Positioned.fill(
                        child: NotificationListener<ScrollNotification>(
                          onNotification:
                              _scrollCoordinator.handleScrollNotification,
                          child: messageList,
                        ),
                      ),
                      if (widget.emptyState != null)
                        Positioned.fill(
                          child: IgnorePointer(child: widget.emptyState),
                        ),
                      if (_unseenIncomingCount > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 12,
                          child: Center(
                            child: _LocationChatNewMessageNotice(
                              count: _unseenIncomingCount,
                              onTap: _openUnseenIncomingMessages,
                            ),
                          ),
                        ),
                    ],
                  ),
                  header: header,
                  composerTopOverlay: widget.showComposer
                      ? widget.composerTopOverlay
                      : null,
                  composer: composer == null
                      ? null
                      : RepaintBoundary(
                          child: _LocationChatComposerExtension(
                            style: style,
                            child: composer,
                          ),
                        ),
                ),
              ),
            ),
            if (_supportsEdgeSwipeBack)
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: _edgeSwipeBackWidth(context),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: _handleEdgeSwipeBackStart,
                  onHorizontalDragUpdate: _handleEdgeSwipeBackUpdate,
                  onHorizontalDragEnd: _handleEdgeSwipeBackEnd,
                  onHorizontalDragCancel: _resetEdgeSwipeBack,
                ),
              ),
            if (_rosterOpen)
              Positioned(
                key: const ValueKey<String>('location-chat-roster-layer'),
                left: 16,
                right: 16,
                top: headerHeight + 4,
                child: TapRegion(
                  groupId: _rosterTapRegionGroup,
                  onTapOutside: (_) {
                    if (mounted && _rosterOpen) {
                      setState(() => _rosterOpen = false);
                    }
                  },
                  child: _LocationChatRoster(
                    key: const ValueKey<String>('location-chat-roster'),
                    occupants: occupants,
                    selfOccupantId: selfOccupantId,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool get _supportsEdgeSwipeBack {
    return widget.active &&
        widget.onBack != null &&
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}

class _LocationChatRoster extends StatelessWidget {
  const _LocationChatRoster({
    super.key,
    required this.occupants,
    required this.selfOccupantId,
  });

  static const double _blurSigma = 14;

  final List<WorldChatroomEntity> occupants;
  final String selfOccupantId;

  bool _isSelf(WorldChatroomEntity entity) {
    final id = selfOccupantId.trim();
    return id.isNotEmpty && entity.id.trim() == id;
  }

  @override
  Widget build(BuildContext context) {
    const accent = GenesisColors.redPrimary;
    const accentSoft = GenesisColors.redSecondary;
    const softWhite = Color(0xFFF4F3F6);
    const white = Colors.white;
    final radius = BorderRadius.circular(14);
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 38,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  blendMode: BlendMode.srcOver,
                  filterConfig: ImageFilterConfig.blur(
                    sigmaX: _blurSigma,
                    sigmaY: _blurSigma,
                    bounded: false,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: white.withValues(alpha: 0.12),
                  borderRadius: radius,
                  border: Border.all(color: white.withValues(alpha: 0.16)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entity in occupants)
                        Builder(
                          builder: (context) {
                            final isSelf = _isSelf(entity);
                            return Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelf
                                    ? white.withValues(alpha: 0.08)
                                    : null,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Row(
                                children: [
                                  GenesisCharacterAvatar(
                                    url: entity.avatarUrl,
                                    name: entity.name,
                                    size: 22,
                                    border: isSelf
                                        ? Border.all(color: accent, width: 1.5)
                                        : null,
                                    showFallbackWhileLoading: false,
                                    maxDevicePixelRatio:
                                        MediaQuery.devicePixelRatioOf(context),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      entity.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isSelf
                                            ? softWhite
                                            : white.withValues(alpha: 0.73),
                                        fontSize: 12,
                                        height: 1,
                                        fontWeight: isSelf
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  if (isSelf) ...[
                                    const SizedBox(width: 8),
                                    const Text(
                                      'YOU',
                                      style: TextStyle(
                                        color: accentSoft,
                                        fontSize: 9.5,
                                        height: 1,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.57,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OccupantChevron extends StatelessWidget {
  const _OccupantChevron({required this.color, required this.pointUp});

  final Color color;
  final bool pointUp;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 8,
      child: CustomPaint(
        painter: _OccupantChevronPainter(color: color, pointUp: pointUp),
      ),
    );
  }
}

class _OccupantChevronPainter extends CustomPainter {
  const _OccupantChevronPainter({required this.color, required this.pointUp});

  final Color color;
  final bool pointUp;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 12;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(2.2 * scale, 7.4 * scale)
      ..lineTo(6 * scale, 3.6 * scale)
      ..lineTo(9.8 * scale, 7.4 * scale);
    if (pointUp) {
      canvas.drawPath(path, paint);
      return;
    }
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(math.pi)
      ..translate(-size.width / 2, -size.height / 2)
      ..drawPath(path, paint)
      ..restore();
  }

  @override
  bool shouldRepaint(_OccupantChevronPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pointUp != pointUp;
  }
}

class _LocationChatKeyboardInsetLayout extends StatefulWidget {
  const _LocationChatKeyboardInsetLayout({
    super.key,
    required this.managesKeyboardInset,
    required this.freezeKeyboardInset,
    required this.frozenKeyboardInset,
    required this.onFrozenKeyboardInsetRestored,
    required this.bottomSafeAreaInset,
    this.onKeyboardMotionTraceSettled,
    required this.messageViewport,
    required this.header,
    this.composerTopOverlay,
    this.composer,
  });

  final bool managesKeyboardInset;
  final bool freezeKeyboardInset;
  final double frozenKeyboardInset;
  final VoidCallback onFrozenKeyboardInsetRestored;
  final double bottomSafeAreaInset;
  final ValueChanged<List<Map<String, Object?>>>? onKeyboardMotionTraceSettled;
  final Widget messageViewport;
  final Widget header;
  final Widget? composerTopOverlay;
  final Widget? composer;

  @override
  State<_LocationChatKeyboardInsetLayout> createState() =>
      _LocationChatKeyboardInsetLayoutState();
}

class _LocationChatKeyboardInsetLayoutState
    extends State<_LocationChatKeyboardInsetLayout>
    with WidgetsBindingObserver {
  int _keyboardMetricsGeneration = 0;
  double _liveKeyboardInset = 0;
  double _frozenKeyboardInset = 0;
  List<Map<String, Object?>>? _keyboardMotionSamples;
  Stopwatch? _keyboardMotionStopwatch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateLiveKeyboardInset(
      widget.managesKeyboardInset || widget.freezeKeyboardInset
          ? _viewKeyboardInset()
          : 0,
    );
    if (widget.freezeKeyboardInset) {
      _frozenKeyboardInset = math.max(
        widget.frozenKeyboardInset,
        math.max(_frozenKeyboardInset, _liveKeyboardInset),
      );
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted ||
        !widget.managesKeyboardInset && !widget.freezeKeyboardInset) {
      return;
    }
    final nextInset = _viewKeyboardInset();
    if ((_liveKeyboardInset - nextInset).abs() <= precisionErrorTolerance) {
      _scheduleFrozenKeyboardInsetRestored(nextInset);
      return;
    }
    setState(() => _updateLiveKeyboardInset(nextInset));
    _scheduleFrozenKeyboardInsetRestored(nextInset);
  }

  void _scheduleFrozenKeyboardInsetRestored(double keyboardInset) {
    if (!widget.freezeKeyboardInset || widget.frozenKeyboardInset <= 0) return;
    if (keyboardInset + 0.5 < widget.frozenKeyboardInset) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.freezeKeyboardInset) return;
      if (_viewKeyboardInset() + 0.5 < widget.frozenKeyboardInset) return;
      widget.onFrozenKeyboardInsetRestored();
    });
  }

  @override
  void didUpdateWidget(covariant _LocationChatKeyboardInsetLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onKeyboardMotionTraceSettled == null) {
      _clearKeyboardMotionTrace();
    }
    final wasTrackingInset =
        oldWidget.managesKeyboardInset || oldWidget.freezeKeyboardInset;
    final tracksInset =
        widget.managesKeyboardInset || widget.freezeKeyboardInset;
    if (tracksInset && !wasTrackingInset) {
      _updateLiveKeyboardInset(_viewKeyboardInset());
    }
    if (widget.freezeKeyboardInset && !oldWidget.freezeKeyboardInset) {
      _frozenKeyboardInset = math.max(
        widget.frozenKeyboardInset,
        math.max(_liveKeyboardInset, _viewKeyboardInset()),
      );
    } else if (widget.freezeKeyboardInset &&
        widget.frozenKeyboardInset != oldWidget.frozenKeyboardInset) {
      _frozenKeyboardInset = math.max(
        _frozenKeyboardInset,
        widget.frozenKeyboardInset,
      );
    } else if (!widget.freezeKeyboardInset && oldWidget.freezeKeyboardInset) {
      _frozenKeyboardInset = 0;
    }
    if (tracksInset) {
      return;
    }
    _keyboardMetricsGeneration += 1;
    _clearKeyboardMotionTrace();
    _liveKeyboardInset = 0;
  }

  void _updateLiveKeyboardInset(double nextInset) {
    if ((_liveKeyboardInset - nextInset).abs() <= precisionErrorTolerance) {
      return;
    }
    _liveKeyboardInset = nextInset;

    _recordKeyboardMotionSample(nextInset);
    final generation = ++_keyboardMetricsGeneration;
    _scheduleStableFrameCheck(generation, stableFrameCount: 0);
  }

  void _scheduleStableFrameCheck(
    int generation, {
    required int stableFrameCount,
  }) {
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (!mounted || generation != _keyboardMetricsGeneration) return;
      final nextStableFrameCount = stableFrameCount + 1;
      if (nextStableFrameCount < 2) {
        _scheduleStableFrameCheck(
          generation,
          stableFrameCount: nextStableFrameCount,
        );
        return;
      }

      _finishKeyboardMotionTrace();
    });
  }

  void _recordKeyboardMotionSample(double rawKeyboardInset) {
    if (widget.onKeyboardMotionTraceSettled == null) return;
    final stopwatch = _keyboardMotionStopwatch ??= Stopwatch()..start();
    final samples = _keyboardMotionSamples ??= <Map<String, Object?>>[];
    if (samples.length == _locationChatKeyboardMotionTraceMaxSamples) {
      samples.removeAt(0);
    }
    final layoutKeyboardInset = widget.freezeKeyboardInset
        ? _frozenKeyboardInset
        : rawKeyboardInset;
    final effectiveKeyboardInset = _effectiveKeyboardInset(layoutKeyboardInset);
    samples.add(<String, Object?>{
      'elapsedMicros': stopwatch.elapsedMicroseconds,
      'rawInset': rawKeyboardInset,
      'effectiveInset': effectiveKeyboardInset,
      'composerTranslationY': -effectiveKeyboardInset,
    });
  }

  void _finishKeyboardMotionTrace() {
    final samples = _keyboardMotionSamples;
    final callback = widget.onKeyboardMotionTraceSettled;
    if (samples != null && samples.isNotEmpty && callback != null) {
      callback(List<Map<String, Object?>>.unmodifiable(samples));
    }
    _clearKeyboardMotionTrace();
  }

  void _clearKeyboardMotionTrace() {
    _keyboardMotionSamples = null;
    _keyboardMotionStopwatch?.stop();
    _keyboardMotionStopwatch = null;
  }

  double _viewKeyboardInset() {
    final view = View.maybeOf(context);
    if (view == null || view.devicePixelRatio <= 0) return 0;
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  double _effectiveKeyboardInset(double rawKeyboardInset) {
    return locationChatEffectiveKeyboardInset(
      rawKeyboardInset: rawKeyboardInset,
      bottomSafeAreaInset: widget.bottomSafeAreaInset,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardMetricsGeneration += 1;
    _clearKeyboardMotionTrace();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layoutKeyboardInset = widget.freezeKeyboardInset
        ? _frozenKeyboardInset
        : _liveKeyboardInset;
    final liveKeyboardInset =
        widget.managesKeyboardInset || widget.freezeKeyboardInset
        ? _effectiveKeyboardInset(layoutKeyboardInset)
        : 0.0;
    return Padding(
      padding: EdgeInsets.only(bottom: liveKeyboardInset),
      child: Column(
        children: [
          widget.header,
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRect(
                    key: const ValueKey<String>(
                      'location-chat-message-viewport-clip',
                    ),
                    child: RepaintBoundary(child: widget.messageViewport),
                  ),
                ),
                if (widget.composerTopOverlay != null)
                  Positioned(
                    key: const ValueKey<String>(
                      'location-chat-composer-top-overlay',
                    ),
                    left: 0,
                    bottom: 0,
                    child: widget.composerTopOverlay!,
                  ),
              ],
            ),
          ),
          if (widget.composer != null) widget.composer!,
        ],
      ),
    );
  }
}

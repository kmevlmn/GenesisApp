import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        BoxParentData,
        ScrollCacheExtent,
        ScrollDirection,
        SliverMultiBoxAdaptorParentData;

import '../../components/chat/shared/chat_ui.dart';
import 'location_chat_reply_actions.dart';

enum LocationChatViewportMode { initializing, followingLatest, detached }

enum LocationChatBottomReason {
  sentMessage,
  unseenMessageNotice,
  composerFocus,
  inspirationExpanded,
  editPromptExpanded,
}

enum LocationChatBottomBehavior { jump, animate }

const locationChatOldestEdgeLoadingAnimationDuration = Duration(
  milliseconds: 220,
);
const _locationChatLayoutCorrectionExtentSignal = 0.001;
const _locationChatAnchorRestoreCacheExtent = 1000000000.0;

/// Owns every programmatic scroll-position change for location chat.
class LocationChatScrollCoordinator extends ChangeNotifier {
  LocationChatScrollCoordinator({ScrollController? controller})
    : controller = controller ?? ScrollController(),
      _ownsController = controller == null;

  static const double bottomTolerance = 24;
  static const double oldestMessageStopTolerance = 1;
  static const Duration bottomAnimationDuration = Duration(milliseconds: 220);

  final ScrollController controller;
  final bool _ownsController;

  LocationChatViewportMode _mode = LocationChatViewportMode.initializing;
  int _commandGeneration = 0;
  bool _entryRevealScheduled = false;
  double? _oldestMessageStopOffset;
  bool _userDragActive = false;
  bool _stopAtOldestMessageForCurrentDrag = false;
  bool _disposed = false;

  LocationChatViewportMode get mode => _mode;
  bool get isDetached => _mode == LocationChatViewportMode.detached;
  bool get shouldFollowLatest => !isDetached;
  int get commandGeneration => _commandGeneration;
  double? get oldestMessageStopOffset => _oldestMessageStopOffset;
  bool get shouldStopAtOldestMessage =>
      _userDragActive && _stopAtOldestMessageForCurrentDrag;

  bool get isAtBottom {
    if (!controller.hasClients) return true;
    final position = controller.position;
    return position.maxScrollExtent - position.pixels <= bottomTolerance;
  }

  void enter() {
    _cancelPendingCommands();
    _entryRevealScheduled = false;
    _setMode(LocationChatViewportMode.initializing);
    onViewportLaidOut();
  }

  void deactivate() {
    _cancelPendingCommands();
    _entryRevealScheduled = false;
    _setMode(LocationChatViewportMode.detached);
  }

  void onViewportLaidOut() {
    if (_disposed ||
        _mode != LocationChatViewportMode.initializing ||
        _entryRevealScheduled) {
      return;
    }
    _entryRevealScheduled = true;
    final generation = _commandGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entryRevealScheduled = false;
      if (!_commandIsCurrent(generation) || !controller.hasClients) return;
      _jumpTo(controller.position.maxScrollExtent);
      _setMode(LocationChatViewportMode.followingLatest);
    });
  }

  void requestBottom({
    required LocationChatBottomReason reason,
    required LocationChatBottomBehavior behavior,
  }) {
    if (_disposed) return;
    final generation = ++_commandGeneration;
    _entryRevealScheduled = false;
    _setMode(LocationChatViewportMode.followingLatest);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_commandIsCurrent(generation) || !controller.hasClients) return;
      final target = controller.position.maxScrollExtent;
      switch (behavior) {
        case LocationChatBottomBehavior.jump:
          _jumpTo(target);
        case LocationChatBottomBehavior.animate:
          _animateTo(target);
      }
    });
  }

  /// Reveal the entire edited row when it fits, otherwise keep its end visible.
  void revealEditedMessage({
    required BuildContext messageContext,
    required BuildContext viewportContext,
  }) {
    if (_disposed || !controller.hasClients) return;
    final messageBox = messageContext.findRenderObject();
    final viewportBox = viewportContext.findRenderObject();
    if (messageBox is! RenderBox ||
        viewportBox is! RenderBox ||
        !messageBox.hasSize ||
        !viewportBox.hasSize) {
      return;
    }
    final messageTop = messageBox.localToGlobal(Offset.zero).dy;
    final messageBottom = messageTop + messageBox.size.height;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy + 12;
    final viewportBottom = viewportTop + viewportBox.size.height - 24;
    double delta = 0;
    if (messageBottom - messageTop > viewportBottom - viewportTop ||
        messageBottom > viewportBottom) {
      delta = messageBottom - viewportBottom;
    } else if (messageTop < viewportTop) {
      delta = messageTop - viewportTop;
    }
    if (delta.abs() < 0.5) return;
    _cancelPendingCommands();
    _jumpTo(
      (controller.position.pixels + delta).clamp(
        controller.position.minScrollExtent,
        controller.position.maxScrollExtent,
      ),
    );
  }

  bool handleScrollNotification(ScrollNotification notification) {
    // Nested horizontal carousels must not change conversation anchoring.
    if (notification.metrics.axis != Axis.vertical || notification.depth != 0) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userDragActive = true;
      final stopOffset = _oldestMessageStopOffset;
      _stopAtOldestMessageForCurrentDrag =
          stopOffset != null &&
          notification.metrics.pixels > stopOffset + oldestMessageStopTolerance;
    } else if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _userDragActive = false;
      _stopAtOldestMessageForCurrentDrag = false;
    }

    final userDriven =
        notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle ||
        notification is ScrollUpdateNotification &&
            notification.dragDetails != null;
    if (!userDriven) return false;

    final atBottom =
        notification.metrics.maxScrollExtent - notification.metrics.pixels <=
        bottomTolerance;
    _cancelPendingCommands();
    _entryRevealScheduled = false;
    _setMode(
      atBottom
          ? LocationChatViewportMode.followingLatest
          : LocationChatViewportMode.detached,
    );
    return false;
  }

  void setOldestMessageStopOffset(double? value) {
    if (_disposed) return;
    final normalized = value?.clamp(0.0, double.infinity).toDouble();
    if (normalized == null && _oldestMessageStopOffset == null) return;
    if (normalized != null &&
        _oldestMessageStopOffset != null &&
        (normalized - _oldestMessageStopOffset!).abs() <
            precisionErrorTolerance) {
      return;
    }
    _oldestMessageStopOffset = normalized;
    if (normalized == null) {
      _userDragActive = false;
      _stopAtOldestMessageForCurrentDrag = false;
    }
  }

  void restoreAnchor({
    required double delta,
    required int expectedCommandGeneration,
  }) {
    if (_disposed ||
        !isDetached ||
        expectedCommandGeneration != _commandGeneration ||
        !controller.hasClients ||
        delta.abs() < precisionErrorTolerance) {
      return;
    }
    final position = controller.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < precisionErrorTolerance) return;
    _jumpTo(target);
  }

  void _cancelPendingCommands() {
    _commandGeneration += 1;
  }

  bool _commandIsCurrent(int generation) {
    return !_disposed && generation == _commandGeneration;
  }

  void _setMode(LocationChatViewportMode value) {
    if (_mode == value || _disposed) return;
    _mode = value;
    notifyListeners();
  }

  void _jumpTo(double target) {
    controller.jumpTo(target);
  }

  void _animateTo(double target) {
    controller.animateTo(
      target,
      duration: bottomAnimationDuration,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _commandGeneration += 1;
    if (_ownsController) controller.dispose();
    super.dispose();
  }
}

class LocationChatAnchoredMessageList extends StatefulWidget {
  const LocationChatAnchoredMessageList({
    super.key,
    required this.coordinator,
    required this.messages,
    required this.topTitle,
    this.active = true,
    this.onMessageLongPressStart,
    this.onFailedMessageTap,
    this.onCharactersMovedLocationTap,
    this.keyboardDismissBehavior,
    this.oldestEdgeNotice,
    this.oldestEdgeNoticeRequiresSecondScroll = false,
    this.oldestEdgeLoading = false,
    this.onOldestEdgeLoadingCollapsed,
    this.showDateDividers = true,
    this.messageLayoutId,
    this.replyActionsMessageId,
    this.replyActionsIdentity,
    this.replyActionsAnchorIndex,
    this.replyPresentationRevision = 0,
    this.replyStatus,
    this.isMember = true,
    this.onRegenerate,
    this.onGoOn,
    this.regenerateEnabled = true,
    this.goOnEnabled = true,
    this.editEnabled = true,
    this.regenerateBusy = false,
    this.goOnBusy = false,
    this.editBusy = false,
    this.replyCardIndex = 0,
    this.replyCardCount = 0,
    this.replyCardsConfirmed = false,
    this.onPreviousReplyCard,
    this.onNextReplyCard,
    this.onInspirationSend,
    this.onInspirationEdit,
    this.onEditReply,
    this.selfMessageBubbleMaxWidthCap,
    this.otherMessageBubbleMaxWidthCap,
    this.style,
  });

  final LocationChatScrollCoordinator coordinator;
  final List<ChatMessageVm> messages;
  final String topTitle;
  final bool active;
  final ChatMessageLongPressStart? onMessageLongPressStart;
  final ChatMessageTap? onFailedMessageTap;
  final ChatCharacterMovementTap? onCharactersMovedLocationTap;
  final ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior;
  final String? oldestEdgeNotice;
  final bool oldestEdgeNoticeRequiresSecondScroll;
  final bool oldestEdgeLoading;
  final VoidCallback? onOldestEdgeLoadingCollapsed;
  final bool showDateDividers;
  final String Function(ChatMessageVm message)? messageLayoutId;

  /// Presentation-only marker; does not determine round or action eligibility.
  final String? replyActionsMessageId;

  /// Stable world/location/round identity, independent of candidate message IDs.
  final String? replyActionsIdentity;

  /// Inserts the controls before this projected message index (length = tail).
  final int? replyActionsAnchorIndex;

  /// Change only for explicit card switches, never for streaming text updates.
  final int replyPresentationRevision;
  final Widget? replyStatus;
  final bool isMember;
  final VoidCallback? onRegenerate;
  final VoidCallback? onGoOn;
  final bool regenerateEnabled;
  final bool goOnEnabled;
  final bool editEnabled;
  final bool regenerateBusy;
  final bool goOnBusy;
  final bool editBusy;
  final int replyCardIndex;
  final int replyCardCount;
  final bool replyCardsConfirmed;
  final VoidCallback? onPreviousReplyCard;
  final VoidCallback? onNextReplyCard;
  final ValueChanged<String>? onInspirationSend;
  final ValueChanged<String>? onInspirationEdit;
  final VoidCallback? onEditReply;
  final double? selfMessageBubbleMaxWidthCap;
  final double? otherMessageBubbleMaxWidthCap;
  final ChatUiStyleConfig? style;

  @override
  State<LocationChatAnchoredMessageList> createState() =>
      _LocationChatAnchoredMessageListState();
}

class _LocationChatAnchoredMessageListState
    extends State<LocationChatAnchoredMessageList>
    with SingleTickerProviderStateMixin {
  final GlobalKey _messageContentKey = GlobalKey();
  final Map<String, GlobalKey> _messageLayoutKeys = <String, GlobalKey>{};
  final GlobalKey _scrollViewportKey = GlobalKey();
  final GlobalKey _replyControlLayoutKey = GlobalKey();
  ({double contentOffset, int commandGeneration})? _replySwitchAnchor;
  int _deferredHistoryPrefixCount = 0;

  String? get _replyIdentity =>
      widget.replyActionsIdentity ?? widget.replyActionsMessageId;

  int? get _replyInsertionIndex {
    if (_replyIdentity == null) return null;
    if (widget.replyActionsIdentity != null) {
      return ((widget.replyActionsAnchorIndex ?? widget.messages.length) -
              _deferredHistoryPrefixCount)
          .clamp(0, _renderedMessages.length);
    }
    final index = _renderedMessages.indexWhere(
      (message) => message.localId == widget.replyActionsMessageId,
    );
    return index < 0 ? null : index + 1;
  }

  final BackdropKey _messageBackdropKey = BackdropKey();
  late final AnimationController _oldestEdgeLoadingController;
  late final Animation<double> _oldestEdgeLoadingAnimation;
  late List<ChatMessageVm> _renderedMessages;
  bool _inspirationExpanded = false;
  bool _editPromptExpanded = false;
  int _inspirationPage = 0;
  List<ChatMessageVm>? _pendingMessages;
  late List<String> _messageLocalIds;
  int _historyCommitGeneration = 0;
  bool _loadingCollapsePending = false;
  bool _historyCommitScheduled = false;
  bool _oldestMessageStopLayoutScheduled = false;
  bool _detachedAnchorSnapshotScheduled = false;
  bool _anchorRestorePending = false;
  bool _anchorRestoreCleanupScheduled = false;
  int? _anchorRestoreMessageCount;
  double _layoutCorrectionExtentSignal = 0;
  ({String localId, double contentOffset})? _detachedLayoutAnchor;

  @override
  void initState() {
    super.initState();
    _renderedMessages = List<ChatMessageVm>.of(widget.messages);
    _messageLocalIds = _currentMessageLocalIds(_renderedMessages);
    _oldestEdgeLoadingController = AnimationController(
      vsync: this,
      duration: locationChatOldestEdgeLoadingAnimationDuration,
      value: widget.oldestEdgeLoading ? 1 : 0,
    )..addStatusListener(_handleOldestEdgeLoadingStatus);
    _oldestEdgeLoadingAnimation = CurvedAnimation(
      parent: _oldestEdgeLoadingController,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    widget.coordinator.addListener(_handleCoordinatorChanged);
    _scheduleInitialViewportLayout();
    _scheduleDetachedAnchorSnapshot();
  }

  @override
  void didUpdateWidget(LocationChatAnchoredMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldReplyIdentity =
        oldWidget.replyActionsIdentity ?? oldWidget.replyActionsMessageId;
    final presentationChanged =
        oldWidget.replyPresentationRevision != widget.replyPresentationRevision;
    if (presentationChanged &&
        oldReplyIdentity == _replyIdentity &&
        _replyIdentity != null &&
        oldWidget.coordinator == widget.coordinator) {
      final contentOffset = _contentOffset(
        _replyControlLayoutKey.currentContext,
      );
      _replySwitchAnchor = contentOffset == null
          ? null
          : (
              contentOffset: contentOffset,
              commandGeneration: widget.coordinator.commandGeneration,
            );
      _layoutCorrectionExtentSignal = _layoutCorrectionExtentSignal == 0
          ? _locationChatLayoutCorrectionExtentSignal
          : 0;
    } else if (oldReplyIdentity != _replyIdentity) {
      _replySwitchAnchor = null;
    }
    if (oldWidget.active != widget.active ||
        oldReplyIdentity != _replyIdentity) {
      _inspirationExpanded = false;
      _editPromptExpanded = false;
      _inspirationPage = 0;
    }
    if (oldWidget.coordinator != widget.coordinator) {
      oldWidget.coordinator.removeListener(_handleCoordinatorChanged);
      widget.coordinator.addListener(_handleCoordinatorChanged);
      _detachedLayoutAnchor = null;
      _scheduleDetachedAnchorSnapshot();
    }
    final loadingStarted =
        !oldWidget.oldestEdgeLoading && widget.oldestEdgeLoading;
    final loadingEnded =
        oldWidget.oldestEdgeLoading && !widget.oldestEdgeLoading;
    if (loadingEnded) _loadingCollapsePending = true;
    if (loadingStarted) {
      _historyCommitGeneration += 1;
      _historyCommitScheduled = false;
    }

    if (widget.oldestEdgeLoading || _loadingCollapsePending) {
      _pendingMessages = List<ChatMessageVm>.of(widget.messages);
      // Hold only prepended history for the loader collapse. The active round
      // must keep streaming and respond to card switches immediately.
      if (widget.replyActionsIdentity != null) {
        final firstId = _renderedMessages.isEmpty
            ? null
            : _messageLayoutId(_renderedMessages.first);
        final firstIndex = firstId == null
            ? 0
            : widget.messages.indexWhere(
                (message) => _messageLayoutId(message) == firstId,
              );
        _deferredHistoryPrefixCount = presentationChanged || firstIndex < 0
            ? 0
            : firstIndex;
        _replaceRenderedMessages(
          widget.messages.sublist(_deferredHistoryPrefixCount),
          rebuild: false,
        );
      }
    } else {
      _deferredHistoryPrefixCount = 0;
      _replaceRenderedMessages(widget.messages, rebuild: false);
    }

    if (widget.coordinator.mode == LocationChatViewportMode.initializing) {
      _scheduleInitialViewportLayout();
    }
    if (loadingStarted) {
      _oldestEdgeLoadingController.forward();
    }
    if (loadingEnded &&
        (_oldestEdgeLoadingController.status == AnimationStatus.completed ||
            _oldestEdgeLoadingController.value >= 1)) {
      _oldestEdgeLoadingController.reverse();
    }
  }

  void _handleOldestEdgeLoadingStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _loadingCollapsePending &&
        !widget.oldestEdgeLoading) {
      _oldestEdgeLoadingController.reverse();
      return;
    }
    if (status != AnimationStatus.dismissed || !_loadingCollapsePending) return;

    _scheduleHistoryCommitAfterCollapsedFrame();
  }

  void _scheduleHistoryCommitAfterCollapsedFrame() {
    if (_historyCommitScheduled) return;
    _historyCommitScheduled = true;
    final generation = ++_historyCommitGeneration;
    // Paint the fully collapsed loader once before capturing the old layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _historyCommitGeneration ||
          !_loadingCollapsePending ||
          widget.oldestEdgeLoading) {
        return;
      }

      final nextMessages = _pendingMessages ?? widget.messages;
      _pendingMessages = null;
      _deferredHistoryPrefixCount = 0;
      _loadingCollapsePending = false;
      _historyCommitScheduled = false;
      _replaceRenderedMessages(nextMessages, rebuild: true);
      widget.onOldestEdgeLoadingCollapsed?.call();
    });
  }

  void _replaceRenderedMessages(
    List<ChatMessageVm> nextMessages, {
    required bool rebuild,
  }) {
    final previousLocalIds = _messageLocalIds;
    final nextLocalIds = _currentMessageLocalIds(nextMessages);
    if (listEquals(previousLocalIds, nextLocalIds)) {
      void replace() {
        _renderedMessages = List<ChatMessageVm>.of(nextMessages);
      }

      if (rebuild) {
        setState(replace);
      } else {
        replace();
      }
      return;
    }

    final shouldPreserveAnchor =
        _replySwitchAnchor == null &&
        widget.coordinator.isDetached &&
        _requiresAnchorRestore(previousLocalIds, nextLocalIds);
    final visibleLayoutAnchor = shouldPreserveAnchor
        ? _visibleRetainedAnchor(previousLocalIds, nextLocalIds.toSet())
        : null;
    final previousContentOffset = visibleLayoutAnchor == null
        ? null
        : _messageContentOffset(visibleLayoutAnchor.localId);
    final layoutAnchor =
        visibleLayoutAnchor != null && previousContentOffset != null
        ? (
            localId: visibleLayoutAnchor.localId,
            contentOffset: previousContentOffset,
          )
        : null;
    if (shouldPreserveAnchor) {
      _detachedLayoutAnchor = layoutAnchor;
      _anchorRestorePending = layoutAnchor != null;
      _anchorRestoreMessageCount = layoutAnchor == null
          ? null
          : _anchorRestoreChildCount(
              previousLocalIds: previousLocalIds,
              nextLocalIds: nextLocalIds,
              anchorLocalId: layoutAnchor.localId,
            );
      // A rolling-window replacement can keep the exact same total extent.
      // Toggling a subpixel tail extent still makes ScrollPosition run the
      // layout-phase correction before this frame is painted.
      _layoutCorrectionExtentSignal = _layoutCorrectionExtentSignal == 0
          ? _locationChatLayoutCorrectionExtentSignal
          : 0;
    }

    void replace() {
      _renderedMessages = List<ChatMessageVm>.of(nextMessages);
      _messageLocalIds = nextLocalIds;
      _pruneMessageLayoutKeys();
    }

    if (rebuild) {
      setState(replace);
    } else {
      replace();
    }
    _scheduleDetachedAnchorSnapshot();
  }

  void _handleCoordinatorChanged() {
    if (!widget.coordinator.isDetached) {
      _detachedLayoutAnchor = null;
      _anchorRestorePending = false;
      _anchorRestoreMessageCount = null;
      return;
    }
    _scheduleDetachedAnchorSnapshot();
  }

  void _scheduleDetachedAnchorSnapshot() {
    if (_detachedAnchorSnapshotScheduled) return;
    _detachedAnchorSnapshotScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _detachedAnchorSnapshotScheduled = false;
      if (!mounted || !widget.coordinator.isDetached) return;
      final anchor = _visibleRetainedAnchor(
        _messageLocalIds,
        _messageLocalIds.toSet(),
      );
      if (anchor == null) return;
      final contentOffset = _messageContentOffset(anchor.localId);
      if (contentOffset == null) return;
      _detachedLayoutAnchor = (
        localId: anchor.localId,
        contentOffset: contentOffset,
      );
    });
  }

  void _scheduleInitialViewportLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.coordinator.onViewportLaidOut();
    });
  }

  List<String> _currentMessageLocalIds(List<ChatMessageVm> messages) {
    return messages.map(_messageLayoutId).toList(growable: false);
  }

  String _messageLayoutId(ChatMessageVm message) {
    return widget.messageLayoutId?.call(message) ?? message.localId;
  }

  bool _requiresAnchorRestore(List<String> previous, List<String> next) {
    if (listEquals(previous, next) || previous.isEmpty) return false;
    if (next.length >= previous.length) {
      var pureTailAppend = true;
      for (var index = 0; index < previous.length; index += 1) {
        if (previous[index] == next[index]) continue;
        pureTailAppend = false;
        break;
      }
      if (pureTailAppend) return false;
    }
    return true;
  }

  int _anchorRestoreChildCount({
    required List<String> previousLocalIds,
    required List<String> nextLocalIds,
    required String anchorLocalId,
  }) {
    final nextIndexByLocalId = <String, int>{
      for (var index = 0; index < nextLocalIds.length; index += 1)
        nextLocalIds[index]: index,
    };
    var lastRequiredIndex = nextIndexByLocalId[anchorLocalId] ?? 0;
    for (final localId in previousLocalIds) {
      final nextIndex = nextIndexByLocalId[localId];
      if (nextIndex == null ||
          !_isActive(_messageLayoutKeys[localId]?.currentContext)) {
        continue;
      }
      if (nextIndex > lastRequiredIndex) lastRequiredIndex = nextIndex;
    }
    return (lastRequiredIndex + 1).clamp(0, nextLocalIds.length);
  }

  ({String localId, double top})? _visibleRetainedAnchor(
    List<String> previousLocalIds,
    Set<String> retainedLocalIds,
  ) {
    final viewportBounds = _globalBounds(context.findRenderObject());
    ({String localId, double top})? closestAnchor;
    var closestDistance = double.infinity;
    var closestAnchorIsVisible = false;
    for (final localId in previousLocalIds) {
      if (!retainedLocalIds.contains(localId)) continue;
      final messageBounds = _messageBounds(localId);
      if (messageBounds == null) continue;
      if (viewportBounds == null) {
        return (localId: localId, top: messageBounds.top);
      }
      final isVisible =
          messageBounds.bottom >= viewportBounds.top &&
          messageBounds.top <= viewportBounds.bottom;
      if (closestAnchorIsVisible && !isVisible) continue;
      final distance = isVisible
          ? (messageBounds.center.dy - viewportBounds.center.dy).abs()
          : switch (messageBounds) {
              Rect(:final bottom) when bottom < viewportBounds.top =>
                viewportBounds.top - bottom,
              Rect(:final top) => top - viewportBounds.bottom,
            };
      if (isVisible && !closestAnchorIsVisible) {
        closestDistance = double.infinity;
      }
      if (distance >= closestDistance) continue;
      closestDistance = distance;
      closestAnchorIsVisible = isVisible;
      closestAnchor = (localId: localId, top: messageBounds.top);
    }
    return closestAnchor;
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_handleCoordinatorChanged);
    widget.coordinator.setOldestMessageStopOffset(null);
    _historyCommitGeneration += 1;
    _detachedLayoutAnchor = null;
    _oldestEdgeLoadingController
      ..removeStatusListener(_handleOldestEdgeLoadingStatus)
      ..dispose();
    _messageLayoutKeys.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? ChatUiStyleConfig.standard;
    final hasOldestEdgeContent =
        widget.topTitle.trim().isNotEmpty ||
        (widget.oldestEdgeNotice?.trim().isNotEmpty ?? false);
    final requiresSecondScroll =
        widget.oldestEdgeNoticeRequiresSecondScroll &&
        hasOldestEdgeContent &&
        _renderedMessages.isNotEmpty;
    _scheduleOldestMessageStopLayout(
      enabled: requiresSecondScroll,
      topPadding: style.messageListPadding.top,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 0.0;
        final messageViewportHeight =
            minHeight > style.messageListPadding.vertical
            ? minHeight - style.messageListPadding.vertical
            : 0.0;
        return ScrollConfiguration(
          key: const ValueKey<String>(
            'location-chat-message-scroll-configuration',
          ),
          behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: BackdropGroup(
            backdropKey: _messageBackdropKey,
            child: requiresSecondScroll
                ? _buildSecondScrollMessageView(
                    style: style,
                    minHeight: minHeight,
                    messageViewportHeight: messageViewportHeight,
                    hasOldestEdgeContent: hasOldestEdgeContent,
                  )
                : _buildLazyMessageView(
                    style: style,
                    hasOldestEdgeContent: hasOldestEdgeContent,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildLazyMessageView({
    required ChatUiStyleConfig style,
    required bool hasOldestEdgeContent,
  }) {
    final renderedMessageCount =
        _anchorRestorePending && _replySwitchAnchor == null
        ? (_anchorRestoreMessageCount ?? _renderedMessages.length).clamp(
            0,
            _renderedMessages.length,
          )
        : _renderedMessages.length;
    final messageIndexByLayoutId = <String, int>{
      for (var index = 0; index < renderedMessageCount; index += 1)
        _messageLayoutId(_renderedMessages[index]): index,
    };

    final replyIndex = _replyInsertionIndex;
    final hasReplyControls =
        replyIndex != null && replyIndex <= renderedMessageCount;
    final childCount = renderedMessageCount + (hasReplyControls ? 1 : 0);

    int? findChildIndex(Key key) {
      if (key case ValueKey<String>(:final value)) {
        if (value == 'location-chat-reply-control:$_replyIdentity') {
          return hasReplyControls ? replyIndex : null;
        }
        const prefix = 'location-chat-message-row:';
        if (!value.startsWith(prefix)) return null;
        final messageIndex =
            messageIndexByLayoutId[value.substring(prefix.length)];
        return messageIndex == null
            ? null
            : messageIndex +
                  (hasReplyControls && messageIndex >= replyIndex ? 1 : 0);
      }
      return null;
    }

    final padding = style.messageListPadding;
    final horizontalPadding = EdgeInsets.only(
      left: padding.left,
      right: padding.right,
    );

    return CustomScrollView(
      key: _scrollViewportKey,
      controller: widget.coordinator.controller,
      physics: _messageScrollPhysics(),
      // Keep the retained anchor in the same sliver layout transaction. Once
      // its exact variable-height offset has been applied, the next frame
      // returns to the normal lazy cache window.
      scrollCacheExtent: _anchorRestorePending || _replySwitchAnchor != null
          ? const ScrollCacheExtent.pixels(
              _locationChatAnchorRestoreCacheExtent,
            )
          : null,
      keyboardDismissBehavior:
          widget.keyboardDismissBehavior ??
          ScrollViewKeyboardDismissBehavior.manual,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top,
            padding.right,
            0,
          ),
          sliver: SliverToBoxAdapter(
            key: const ValueKey<String>('location-chat-oldest-edge-loading'),
            child: _buildOldestEdgeLoading(style),
          ),
        ),
        if (hasOldestEdgeContent)
          SliverPadding(
            padding: horizontalPadding,
            sliver: SliverToBoxAdapter(
              key: const ValueKey<String>('location-chat-oldest-edge-content'),
              child: ChatOldestEdgeContent(
                topTitle: widget.topTitle,
                notice: widget.oldestEdgeNotice,
                loading: false,
                style: style,
              ),
            ),
          ),
        SliverPadding(
          padding: horizontalPadding,
          sliver: SliverList.builder(
            itemCount: childCount,
            itemBuilder: (context, index) {
              if (hasReplyControls && index == replyIndex) {
                return _buildReplyControls(style);
              }
              final messageIndex =
                  index - (hasReplyControls && index > replyIndex ? 1 : 0);
              return _buildMessageRow(messageIndex, style);
            },
            findChildIndexCallback: findChildIndex,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            0,
            padding.right,
            padding.bottom,
          ),
          sliver: SliverToBoxAdapter(
            key: const ValueKey<String>('location-chat-layout-correction'),
            child: SizedBox(height: _layoutCorrectionExtentSignal),
          ),
        ),
      ],
    );
  }

  Widget _buildSecondScrollMessageView({
    required ChatUiStyleConfig style,
    required double minHeight,
    required double messageViewportHeight,
    required bool hasOldestEdgeContent,
  }) {
    return SingleChildScrollView(
      key: _scrollViewportKey,
      controller: widget.coordinator.controller,
      physics: _messageScrollPhysics(),
      keyboardDismissBehavior:
          widget.keyboardDismissBehavior ??
          ScrollViewKeyboardDismissBehavior.manual,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: style.messageListPadding,
          child: Column(
            key: _messageContentKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildOldestEdgeLoading(style),
              if (hasOldestEdgeContent)
                ChatOldestEdgeContent(
                  topTitle: widget.topTitle,
                  notice: widget.oldestEdgeNotice,
                  loading: false,
                  style: style,
                ),
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: messageViewportHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var index = 0;
                      index <= _renderedMessages.length;
                      index += 1
                    ) ...[
                      if (index == _replyInsertionIndex)
                        _buildReplyControls(style),
                      if (index < _renderedMessages.length)
                        _buildMessageRow(index, style, lazy: false),
                    ],
                  ],
                ),
              ),
              SizedBox(height: _layoutCorrectionExtentSignal),
            ],
          ),
        ),
      ),
    );
  }

  ScrollPhysics _messageScrollPhysics() {
    return LocationChatBottomAnchoringScrollPhysics(
      shouldFollowLatest: () => widget.coordinator.shouldFollowLatest,
      oldestMessageStopOffset: () => widget.coordinator.oldestMessageStopOffset,
      shouldStopAtOldestMessage: () =>
          widget.coordinator.shouldStopAtOldestMessage,
      takeDetachedLayoutCorrection: _takeDetachedLayoutCorrection,
      takePresentationLayoutCorrection: _takeReplySwitchLayoutCorrection,
    );
  }

  Widget _buildOldestEdgeLoading(ChatUiStyleConfig style) {
    return AnimatedBuilder(
      animation: _oldestEdgeLoadingAnimation,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SizedBox.square(
          dimension: style.sendingBadgeSize,
          child: Padding(
            padding: EdgeInsets.all(style.sendingBadgePadding),
            child: CircularProgressIndicator(
              strokeWidth: style.sendingBadgeStrokeWidth,
              color: style.sendingBadgeColor,
            ),
          ),
        ),
      ),
      builder: (context, child) {
        final factor = _oldestEdgeLoadingAnimation.value;
        if (factor <= 0 &&
            !widget.oldestEdgeLoading &&
            !_loadingCollapsePending) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: factor,
            child: Opacity(opacity: factor, child: child),
          ),
        );
      },
    );
  }

  void _scheduleOldestMessageStopLayout({
    required bool enabled,
    required double topPadding,
  }) {
    if (!enabled) {
      widget.coordinator.setOldestMessageStopOffset(null);
      return;
    }
    if (_oldestMessageStopLayoutScheduled) return;
    _oldestMessageStopLayoutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _oldestMessageStopLayoutScheduled = false;
      if (!mounted || _renderedMessages.isEmpty) return;
      final viewportBounds = _globalBounds(
        _scrollViewportKey.currentContext?.findRenderObject(),
      );
      final firstMessageBounds = _messageBounds(
        _messageLayoutId(_renderedMessages.first),
      );
      if (viewportBounds == null || firstMessageBounds == null) return;
      final controller = widget.coordinator.controller;
      if (!controller.hasClients) return;
      final stopOffset =
          controller.position.pixels +
          firstMessageBounds.top -
          viewportBounds.top -
          topPadding;
      widget.coordinator.setOldestMessageStopOffset(stopOffset);
    });
  }

  void _pruneMessageLayoutKeys() {
    final retainedLocalIds = _renderedMessages.map(_messageLayoutId).toSet();
    _messageLayoutKeys.removeWhere(
      (localId, _) => !retainedLocalIds.contains(localId),
    );
  }

  double? _takeReplySwitchLayoutCorrection() {
    final anchor = _replySwitchAnchor;
    if (anchor == null) return null;
    if (anchor.commandGeneration != widget.coordinator.commandGeneration) {
      _replySwitchAnchor = null;
      return null;
    }
    final nextOffset = _contentOffset(_replyControlLayoutKey.currentContext);
    if (nextOffset == null) return null;
    _replySwitchAnchor = null;
    _detachedLayoutAnchor = null;
    _anchorRestorePending = false;
    _anchorRestoreMessageCount = null;
    _scheduleDetachedAnchorSnapshot();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    return nextOffset - anchor.contentOffset;
  }

  double? _takeDetachedLayoutCorrection() {
    final anchor = _detachedLayoutAnchor;
    if (anchor == null) return null;
    final nextContentOffset = _messageContentOffset(anchor.localId);
    if (nextContentOffset == null) return null;
    _detachedLayoutAnchor = (
      localId: anchor.localId,
      contentOffset: nextContentOffset,
    );
    if (widget.oldestEdgeLoading || _loadingCollapsePending) return null;
    final correction = nextContentOffset - anchor.contentOffset;
    _finishAnchorRestoreAfterLayout();
    return correction.abs() > precisionErrorTolerance ? correction : null;
  }

  void _finishAnchorRestoreAfterLayout() {
    if (!_anchorRestorePending || _anchorRestoreCleanupScheduled) return;
    _anchorRestorePending = false;
    _anchorRestoreMessageCount = null;
    _anchorRestoreCleanupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorRestoreCleanupScheduled = false;
      if (!mounted || _anchorRestorePending) return;
      setState(() {});
    });
  }

  double? _messageContentOffset(String localId) {
    return _contentOffset(_messageLayoutKeys[localId]?.currentContext);
  }

  double? _contentOffset(BuildContext? messageContext) {
    if (!_isActive(messageContext)) return null;
    final messageRenderObject = messageContext!.findRenderObject();
    if (messageRenderObject == null || !messageRenderObject.attached) {
      return null;
    }

    // This runs from ScrollPhysics while the sliver is laying out. Reading a
    // RenderBox size (including through getOffsetToReveal) is not legal there.
    // The sliver child parent data already contains the exact variable-height
    // layout offset, so use it without forcing another geometry read.
    var boxOffset = 0.0;
    RenderObject? current = messageRenderObject;
    final contentContext = _messageContentKey.currentContext;
    final contentRenderObject = _isActive(contentContext)
        ? contentContext!.findRenderObject()
        : null;
    while (current != null) {
      if (current == contentRenderObject) {
        return boxOffset.isFinite ? boxOffset : null;
      }
      final parentData = current.parentData;
      if (parentData is SliverMultiBoxAdaptorParentData) {
        final layoutOffset = parentData.layoutOffset;
        if (layoutOffset == null) return null;
        final offset = layoutOffset + boxOffset;
        return offset.isFinite ? offset : null;
      }
      if (parentData is BoxParentData) {
        boxOffset += parentData.offset.dy;
      }
      current = current.parent;
    }
    return null;
  }

  Rect? _messageBounds(String localId) {
    if (localId.isEmpty) return null;
    final messageContext = _messageLayoutKeys[localId]?.currentContext;
    if (!_isActive(messageContext)) return null;
    final renderObject = messageContext!.findRenderObject();
    if (renderObject is! RenderBox || !_hasLaidOutRenderPath(renderObject)) {
      return null;
    }
    return _globalBounds(renderObject);
  }

  bool _isActive(BuildContext? context) {
    if (context == null || !context.mounted) return false;
    var active = true;
    assert(() {
      active = (context as Element).debugIsActive;
      return true;
    }());
    return active;
  }

  Rect? _globalBounds(RenderObject? renderObject) {
    if (renderObject is! RenderBox || !_hasLaidOutRenderPath(renderObject)) {
      return null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bounds = topLeft & renderObject.size;
    return topLeft.dx.isFinite &&
            topLeft.dy.isFinite &&
            bounds.width.isFinite &&
            bounds.height.isFinite
        ? bounds
        : null;
  }

  bool _hasLaidOutRenderPath(RenderObject renderObject) {
    RenderObject? current = renderObject;
    while (current != null) {
      if (!current.attached) return false;
      if (current is RenderBox && !current.hasSize) return false;
      current = current.parent;
    }
    return true;
  }

  Widget _buildMessageRow(
    int messageIndex,
    ChatUiStyleConfig style, {
    bool lazy = true,
  }) {
    final current = _renderedMessages[messageIndex];
    final previous = messageIndex == 0
        ? null
        : _renderedMessages[messageIndex - 1];
    final layoutId = _messageLayoutId(current);
    final layoutKey = _messageLayoutKeys.putIfAbsent(layoutId, GlobalKey.new);
    final showReplyActions = messageIndex + 1 == _replyInsertionIndex;
    final row = KeyedSubtree(
      key: layoutKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChatMessageRow(
            key: ValueKey(layoutId),
            message: current,
            imageViewerMessages: _renderedMessages,
            style: showReplyActions
                ? style.copyWith(
                    rowBottomPadding: LocationChatReplyActions.contentBottomGap,
                    systemMessageMargin: style.systemMessageMargin.copyWith(
                      bottom: LocationChatReplyActions.contentBottomGap,
                    ),
                  )
                : style,
            selfMessageBubbleMaxWidthCap: widget.selfMessageBubbleMaxWidthCap,
            otherMessageBubbleMaxWidthCap: widget.otherMessageBubbleMaxWidthCap,
            onMessageLongPressStart: widget.onMessageLongPressStart,
            onFailedMessageTap: widget.onFailedMessageTap,
            onCharactersMovedLocationTap: widget.onCharactersMovedLocationTap,
            showDateDivider:
                widget.showDateDividers &&
                shouldShowChatDateDivider(
                  previous?.createdAt,
                  current.createdAt,
                ),
          ),
        ],
      ),
    );
    if (!lazy) return row;
    return KeyedSubtree(
      key: ValueKey<String>('location-chat-message-row:$layoutId'),
      child: row,
    );
  }

  Widget _buildReplyControls(ChatUiStyleConfig style) => KeyedSubtree(
    key: ValueKey<String>('location-chat-reply-control:$_replyIdentity'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.replyStatus case final status?) status,
        Padding(
          key: _replyControlLayoutKey,
          padding: EdgeInsets.only(bottom: style.rowBottomPadding),
          child: LocationChatReplyActions(
            key: ValueKey('reply-actions-$_replyIdentity'),
            onInspirationSend: widget.onInspirationSend,
            onInspirationEdit: widget.onInspirationEdit,
            onEditReply: widget.onEditReply,
            isMember: widget.isMember,
            onRegenerate: widget.onRegenerate,
            onGoOn: widget.onGoOn,
            regenerateEnabled: widget.regenerateEnabled,
            goOnEnabled: widget.goOnEnabled,
            editEnabled: widget.editEnabled,
            regenerateBusy: widget.regenerateBusy,
            goOnBusy: widget.goOnBusy,
            editBusy: widget.editBusy,
            cardIndex: widget.replyCardIndex,
            cardCount: widget.replyCardCount,
            cardsConfirmed: widget.replyCardsConfirmed,
            onPreviousCard: widget.onPreviousReplyCard,
            onNextCard: widget.onNextReplyCard,
            editPromptExpanded: _editPromptExpanded,
            onEditPromptExpandedChanged: (expanded) {
              setState(() => _editPromptExpanded = expanded);
              if (expanded) {
                widget.coordinator.requestBottom(
                  reason: LocationChatBottomReason.editPromptExpanded,
                  behavior: LocationChatBottomBehavior.animate,
                );
              }
            },
            inspirationExpanded: _inspirationExpanded,
            inspirationPage: _inspirationPage,
            onInspirationPageChanged: (page) => _inspirationPage = page,
            onInspirationExpandedChanged: (expanded) {
              setState(() => _inspirationExpanded = expanded);
              if (expanded) {
                widget.coordinator.requestBottom(
                  reason: LocationChatBottomReason.inspirationExpanded,
                  behavior: LocationChatBottomBehavior.animate,
                );
              }
            },
            style: style,
            selfMessageBubbleMaxWidthCap: widget.selfMessageBubbleMaxWidthCap,
          ),
        ),
      ],
    ),
  );
}

class LocationChatBottomAnchoringScrollPhysics extends ClampingScrollPhysics {
  const LocationChatBottomAnchoringScrollPhysics({
    super.parent,
    required this.shouldFollowLatest,
    this.shouldPreservePrependAnchor,
    this.oldestMessageStopOffset,
    this.shouldStopAtOldestMessage,
    this.takeDetachedLayoutCorrection,
    this.takePresentationLayoutCorrection,
  });

  final ValueGetter<bool> shouldFollowLatest;
  final ValueGetter<bool>? shouldPreservePrependAnchor;
  final ValueGetter<double?>? oldestMessageStopOffset;
  final ValueGetter<bool>? shouldStopAtOldestMessage;
  final ValueGetter<double?>? takeDetachedLayoutCorrection;
  final ValueGetter<double?>? takePresentationLayoutCorrection;

  @override
  LocationChatBottomAnchoringScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return LocationChatBottomAnchoringScrollPhysics(
      parent: buildParent(ancestor),
      shouldFollowLatest: shouldFollowLatest,
      shouldPreservePrependAnchor: shouldPreservePrependAnchor,
      oldestMessageStopOffset: oldestMessageStopOffset,
      shouldStopAtOldestMessage: shouldStopAtOldestMessage,
      takeDetachedLayoutCorrection: takeDetachedLayoutCorrection,
      takePresentationLayoutCorrection: takePresentationLayoutCorrection,
    );
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => true;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (position.minScrollExtent == position.maxScrollExtent) return 0;
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final stopOffset = oldestMessageStopOffset?.call();
    if (stopOffset != null &&
        (shouldStopAtOldestMessage?.call() ?? false) &&
        value < stopOffset &&
        position.pixels >=
            stopOffset -
                LocationChatScrollCoordinator.oldestMessageStopTolerance) {
      return value - stopOffset;
    }
    return super.applyBoundaryConditions(position, value);
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final presentationCorrection = takePresentationLayoutCorrection?.call();
    if (presentationCorrection != null && presentationCorrection.isFinite) {
      return (newPosition.pixels + presentationCorrection).clamp(
        newPosition.minScrollExtent,
        newPosition.maxScrollExtent,
      );
    }
    if (!shouldFollowLatest()) {
      final currentPixels = newPosition.pixels.clamp(
        newPosition.minScrollExtent,
        newPosition.maxScrollExtent,
      );
      final layoutCorrection = takeDetachedLayoutCorrection?.call();
      if (layoutCorrection != null && layoutCorrection.isFinite) {
        return (currentPixels + layoutCorrection).clamp(
          newPosition.minScrollExtent,
          newPosition.maxScrollExtent,
        );
      }
      if (shouldPreservePrependAnchor?.call() ?? false) {
        final extentDelta =
            newPosition.maxScrollExtent - oldPosition.maxScrollExtent;
        return (oldPosition.pixels + extentDelta).clamp(
          newPosition.minScrollExtent,
          newPosition.maxScrollExtent,
        );
      }
      return currentPixels;
    }
    final wasNearBottom =
        oldPosition.maxScrollExtent - newPosition.pixels <=
        LocationChatScrollCoordinator.bottomTolerance;
    if (wasNearBottom) return newPosition.maxScrollExtent;
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

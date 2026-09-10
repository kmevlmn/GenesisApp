part of '../../../../pages/chat/location_chat_page.dart';

bool _isEditableRoundMessage(ChatMessageVm message) =>
    !message.isMe &&
    !message.isPlayerControlledRole &&
    message.senderType != 'user' &&
    (!message.isSystem || message.isNarrator) &&
    !message.isTimelineEvent &&
    message.status != 'streaming';

/// Select only the last AI reply round, including its narration and images.
List<ChatMessageVm> locationChatLatestEditableRound(
  List<ChatMessageVm> messages,
) {
  final end = messages.lastIndexWhere(_isEditableRoundMessage);
  if (end < 0) return const [];
  final roundId = messages[end].roundId.trim();
  if (roundId.isNotEmpty) {
    return messages
        .take(end + 1)
        .where(
          (message) =>
              message.roundId.trim() == roundId &&
              _isEditableRoundMessage(message),
        )
        .toList(growable: false);
  }
  // Without a server round identity there is no safe edit target.
  return const [];
}

ChatMessageVm _copyLocationChatMessageText(
  ChatMessageVm message,
  String text,
) => ChatMessageVm(
  localId: message.localId,
  clientMsgId: message.clientMsgId,
  globalMessageId: message.globalMessageId,
  messageId: message.messageId,
  locationMessageId: message.locationMessageId,
  roundId: message.roundId,
  tickNo: message.tickNo,
  subTickNo: message.subTickNo,
  senderId: message.senderId,
  senderName: message.senderName,
  avatarUrl: message.avatarUrl,
  imageUrl: message.imageUrl,
  timelinePayload: message.timelinePayload,
  isPlayerControlledRole: message.isPlayerControlledRole,
  text: text,
  currentTime: message.currentTime,
  isMe: message.isMe,
  status: message.status,
  senderType: message.senderType,
  createdAt: message.createdAt,
)..error = message.error;

class LocationChatEditResult {
  const LocationChatEditResult({
    required this.texts,
    required this.deletedMessageIds,
  });
  final Map<String, String> texts;
  final Set<String> deletedMessageIds;
}

/// Signals an external round transition without coupling the editor to networking.
class LocationChatEditExternalState {
  const LocationChatEditExternalState({
    this.frozen = false,
    this.saving = false,
    this.saved = false,
    this.error,
  });

  final bool frozen;
  final bool saving;
  final bool saved;
  final String? error;
}

class LocationChatEditPageArgs {
  const LocationChatEditPageArgs({
    required this.worldId,
    required this.locationId,
    required this.roundId,
    required this.messages,
    required this.style,
    required this.onSave,
    this.cardId,
    this.canEdit = true,
    this.canDelete = true,
    this.initialDraft,
    this.onDraftChanged,
    this.onCancel,
    this.externalState,
    this.backgroundImageUrl,
    this.backgroundPreviewImageUrl,
    this.selfMessageBubbleMaxWidthCap,
    this.otherMessageBubbleMaxWidthCap,
    this.mentionCatalog,
  });

  final String worldId;
  final String locationId;
  final int roundId;
  final int? cardId;
  final List<ChatMessageVm> messages;
  final bool canEdit;
  final bool canDelete;
  final LocationChatEditResult? initialDraft;

  /// Resolves only after authoritative persistence; throw to retain this draft.
  /// Errors are shown inline here, so the caller need not display another toast.
  final Future<void> Function(LocationChatEditResult result) onSave;
  final ValueChanged<LocationChatEditResult>? onDraftChanged;

  /// Called once when a normal edit is discarded, never for a frozen transition.
  final VoidCallback? onCancel;
  final ValueListenable<LocationChatEditExternalState>? externalState;
  final ChatUiStyleConfig style;
  final String? backgroundImageUrl;
  final String? backgroundPreviewImageUrl;
  final double? selfMessageBubbleMaxWidthCap;
  final double? otherMessageBubbleMaxWidthCap;
  final ChatMentionCatalog? mentionCatalog;
}

class LocationChatEditPage extends StatefulWidget {
  const LocationChatEditPage({super.key, required this.args});
  final LocationChatEditPageArgs args;

  @override
  State<LocationChatEditPage> createState() => _LocationChatEditPageState();
}

class _LocationChatEditPageState extends State<LocationChatEditPage>
    with WidgetsBindingObserver {
  late final List<ChatMessageVm> _messages;
  final _controllers = <String, LocationChatMentionEditingController>{};
  final _deletedMessageIds = <String>{};
  final _scrollCoordinator = LocationChatScrollCoordinator();
  final _viewportKey = GlobalKey();
  final _messageKeys = <String, GlobalKey>{};
  String? _activeMessageId;
  bool _revealScheduled = false;
  bool _saving = false;
  bool _completed = false;
  bool _cancelNotified = false;
  bool _completionScheduled = false;
  String? _saveError;
  LocationChatEditResult? _lastPublishedDraft;

  LocationChatEditExternalState get _external =>
      widget.args.externalState?.value ?? const LocationChatEditExternalState();
  bool get _busy => _saving || _external.saving;
  bool get _frozen => _external.frozen;
  bool get _inputEnabled => !_busy && !_frozen;
  bool get _canDelete =>
      _inputEnabled &&
      widget.args.canDelete &&
      (widget.args.cardId == null || _messages.length > 1);

  LocationChatEditResult _draft() => LocationChatEditResult(
    texts: Map.unmodifiable({
      for (final entry in _controllers.entries)
        if (!_deletedMessageIds.contains(entry.key))
          entry.key: entry.value.serializedText,
    }),
    deletedMessageIds: Set.unmodifiable(_deletedMessageIds),
  );

  void _draftChanged() {
    if (_completed) return;
    final draft = _draft();
    if (mapEquals(draft.texts, _lastPublishedDraft?.texts) &&
        setEquals(
          draft.deletedMessageIds,
          _lastPublishedDraft?.deletedMessageIds,
        )) {
      return;
    }
    _lastPublishedDraft = draft;
    widget.args.onDraftChanged?.call(draft);
  }

  void _externalChanged() {
    if (!mounted) return;
    if (!_inputEnabled) FocusManager.instance.primaryFocus?.unfocus();
    setState(() {});
    if (_external.saved && !_completionScheduled) {
      _completionScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _completionScheduled = false;
        if (mounted && _external.saved) _complete(_draft());
      });
    }
  }

  void _complete(LocationChatEditResult result) {
    if (!mounted || _completed) return;
    _completed = true;
    final route = ModalRoute.of<LocationChatEditResult>(context);
    final navigator = Navigator.of(context);
    if (route?.isCurrent ?? true) {
      navigator.pop(result);
    } else if (route != null && route.isActive) {
      // A later modal may be above this page; only close this editor.
      navigator.removeRoute(route, result);
    }
  }

  void _cancel() {
    if (_cancelNotified || _completed || _frozen) return;
    _cancelNotified = true;
    widget.args.onCancel?.call();
  }

  void _back() {
    if (_busy) return;
    _cancel();
    Navigator.of(context).pop();
  }

  @override
  void didChangeMetrics() => _scheduleActiveMessageReveal();

  void _activateEditor(String id) {
    _activeMessageId = id;
    _scheduleActiveMessageReveal();
  }

  void _scheduleActiveMessageReveal() {
    if (_revealScheduled || _activeMessageId == null) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted) return;
      final messageContext = _messageKeys[_activeMessageId]?.currentContext;
      final viewportContext = _viewportKey.currentContext;
      if (messageContext == null || viewportContext == null) return;
      _scrollCoordinator.revealEditedMessage(
        messageContext: messageContext,
        viewportContext: viewportContext,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final args = widget.args;
    if (args.worldId.trim().isEmpty ||
        args.locationId.trim().isEmpty ||
        args.roundId <= 0 ||
        (args.cardId != null && args.cardId! <= 0)) {
      throw ArgumentError(
        'The reply editor requires an explicit round target.',
      );
    }
    _messages = args.messages
        .where(
          (message) =>
              message.roundId == args.roundId.toString() &&
              _isEditableRoundMessage(message),
        )
        .map((message) => _copyLocationChatMessageText(message, message.text))
        .toList();
    final initialDeleted =
        args.initialDraft?.deletedMessageIds ?? const <String>{};
    _deletedMessageIds.addAll(
      initialDeleted.intersection(
        _messages.map((message) => message.localId).toSet(),
      ),
    );
    // Never restore a candidate draft that would remove every message.
    if (args.cardId != null && _deletedMessageIds.length == _messages.length) {
      _deletedMessageIds.clear();
    }
    for (final message in _messages) {
      _messageKeys[message.localId] = GlobalKey();
      if (message.isImage) continue;
      _controllers[message.localId] =
          LocationChatMentionEditingController(
            catalog: widget.args.mentionCatalog,
          )..setSerializedText(
            args.initialDraft?.texts[message.localId] ?? message.text,
          );
      _controllers[message.localId]!.addListener(_draftChanged);
    }
    _messages.removeWhere(
      (message) => _deletedMessageIds.contains(message.localId),
    );
    _lastPublishedDraft = _draft();
    args.externalState?.addListener(_externalChanged);
    if (_external.saved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _externalChanged();
      });
    }
  }

  @override
  void didUpdateWidget(LocationChatEditPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.args.externalState != widget.args.externalState) {
      oldWidget.args.externalState?.removeListener(_externalChanged);
      widget.args.externalState?.addListener(_externalChanged);
      _externalChanged();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.args.externalState?.removeListener(_externalChanged);
    _scrollCoordinator.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _deleteMessage(String id) {
    if (!_canDelete) return;
    if (_activeMessageId == id) {
      FocusManager.instance.primaryFocus?.unfocus();
      _activeMessageId = null;
    }
    setState(() {
      _deletedMessageIds.add(id);
      _messages.removeWhere((message) => message.localId == id);
    });
    _draftChanged();
  }

  Future<void> _done() async {
    if (!_inputEnabled) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final result = _draft();
    final hasChanges =
        result.deletedMessageIds.isNotEmpty ||
        widget.args.messages.any(
          (message) =>
              result.texts.containsKey(message.localId) &&
              result.texts[message.localId] != message.text,
        );
    if (!hasChanges) {
      _cancel();
      _complete(result);
      return;
    }
    if (widget.args.messages.any((message) {
      final text = result.texts[message.localId];
      return text != null && text != message.text && text.trim().isEmpty;
    })) {
      setState(() => _saveError = 'Message text cannot be empty.');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.args.onSave(result);
      if (mounted) _complete(result);
    } catch (error) {
      if (mounted && !_completed) {
        // Server errors are shown once by the global centered toast.
        setState(
          () => _saveError = isChatroomErrorPresentedGlobally(error)
              ? null
              : chatroomOperationErrorMessage(error),
        );
      }
    } finally {
      if (mounted && !_completed) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final style = args.style;
    return GenesisDarkTheme(
      child: PopScope<LocationChatEditResult>(
        canPop: !_busy || _completed,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop && !_completed) _cancel();
        },
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: kChatDarkHeaderSystemUiOverlayStyle,
          child: Scaffold(
            backgroundColor: GenesisColors.darkBackground,
            resizeToAvoidBottomInset: true,
            body: Column(
              children: [
                ChatHeader(
                  title: 'Edit Message',
                  subtitle: '',
                  connected: false,
                  connecting: false,
                  onBack: _back,
                  showTitleIcon: false,
                  showSubtitle: false,
                  showMoreButton: false,
                  alignContentLeft: true,
                  trailingVerticallyCentered: true,
                  style: style,
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: GenesisPrimaryButton(
                      key: const ValueKey('location-chat-edit-done'),
                      label: 'Save',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      backgroundColor: GenesisColors.redPrimary,
                      onPressed: _inputEnabled ? _done : null,
                      isLoading: _busy,
                      width: 64,
                      height: 32,
                      fullWidth: false,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      foregroundColor: GenesisColors.darkTextPrimary,
                    ),
                  ),
                ),
                if (_saveError != null || _external.error != null || _frozen)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      _saveError ??
                          _external.error ??
                          'This reply is being confirmed. Editing is paused.',
                      key: const ValueKey('location-chat-edit-status'),
                      style: style.bubbleTextStyle.copyWith(
                        color: GenesisColors.darkTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                Expanded(
                  child: ChatMentionScope(
                    catalog: args.mentionCatalog ?? ChatMentionCatalog.empty,
                    child: ChatMessageEditorScope(
                      controllers: args.canEdit ? _controllers : const {},
                      onEditorActivated: _activateEditor,
                      onEditorDeactivated: (id) {
                        if (_activeMessageId == id) _activeMessageId = null;
                      },
                      child: BackdropGroup(
                        child: SizedBox(
                          key: _viewportKey,
                          child: ListView.builder(
                            controller: _scrollCoordinator.controller,
                            key: const ValueKey('location-chat-edit-messages'),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: style.messageListPadding.copyWith(
                              bottom:
                                  style.messageListPadding.bottom +
                                  GenesisSafeAreaInsets.bottom(context),
                            ),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) => SizedBox(
                              key: _messageKeys[_messages[index].localId],
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: ExcludeFocus(
                                      excluding: !_inputEnabled,
                                      child: AbsorbPointer(
                                        absorbing: !_inputEnabled,
                                        child: ChatMessageRow(
                                          key: ValueKey(
                                            'location-chat-edit-row-${_messages[index].localId}',
                                          ),
                                          message: _messages[index],
                                          showDateDivider: false,
                                          style: style,
                                          selfMessageBubbleMaxWidthCap:
                                              args.selfMessageBubbleMaxWidthCap,
                                          otherMessageBubbleMaxWidthCap: args
                                              .otherMessageBubbleMaxWidthCap,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: _messages[index].isImage ? 4 : 0,
                                    top: _messages[index].isImage ? 12 : 0,
                                    child: GenesisDeleteButton(
                                      enabled: _canDelete,
                                      buttonKey: ValueKey(
                                        'location-chat-edit-delete-${_messages[index].localId}',
                                      ),
                                      decorationKey: ValueKey(
                                        'location-chat-edit-delete-decoration-${_messages[index].localId}',
                                      ),
                                      onPressed: () => _deleteMessage(
                                        _messages[index].localId,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension _LocationChatEditActions on _LocationChatPanelState {
  LocationChatEditFeature _editFeature(
    bool replyBlocked,
    ChatroomReplyRoundState? replyState,
    ChatUiStyleConfig style,
    double? selfCap,
    double? otherCap,
  ) => LocationChatEditFeature(
    enabled: !replyBlocked && (replyState?.canEdit ?? false),
    busy: _preparingReplyAction,
    onInvoke: () => unawaited(_editCurrentReply(style, selfCap, otherCap)),
  );

  Future<void> _openReplyEditor(LocationChatEditPageArgs args) async {
    if (_replyEditorOpen || !widget.active) return;
    _replyEditorOpen = true;
    _composerFocusNode.unfocus();
    try {
      await Navigator.of(
        context,
        rootNavigator: true,
      ).pushNamed<LocationChatEditResult>(
        RouteNames.locationChatEdit,
        arguments: args,
      );
    } finally {
      _replyEditorOpen = false;
    }
  }
}

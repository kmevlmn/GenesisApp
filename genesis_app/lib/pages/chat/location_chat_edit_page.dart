part of 'location_chat_page.dart';

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
  var start = end;
  while (start > 0) {
    final previous = messages[start - 1];
    if (!_isEditableRoundMessage(previous) ||
        previous.roundId.trim().isNotEmpty) {
      break;
    }
    start--;
  }
  return messages
      .sublist(start, end + 1)
      .where(_isEditableRoundMessage)
      .toList(growable: false);
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

/// Frontend-only changes; canonical messages and server caches remain separate.
class LocationChatLocalMessageEdits {
  final _edits = <String, ({String original, String text})>{};
  final _deletedIds = <String>{};

  bool isDeleted(ChatMessageVm message) =>
      _deletedIds.contains(message.localId);

  void clear() {
    _edits.clear();
    _deletedIds.clear();
  }

  void save(
    List<ChatMessageVm> source,
    Map<String, String> result, {
    Set<String> deletedMessageIds = const {},
  }) {
    final sourceIds = source.map((message) => message.localId).toSet();
    _deletedIds.addAll(deletedMessageIds.intersection(sourceIds));
    for (final id in _deletedIds) {
      _edits.remove(id);
    }
    for (final message in source) {
      if (_deletedIds.contains(message.localId)) continue;
      final text = result[message.localId];
      if (text == null) continue;
      if (text == message.text) {
        _edits.remove(message.localId);
      } else {
        _edits[message.localId] = (original: message.text, text: text);
      }
    }
  }

  ChatMessageVm apply(ChatMessageVm message) {
    final edit = _edits[message.localId];
    if (edit == null) return message;
    if (edit.original != message.text) {
      _edits.remove(message.localId);
      return message;
    }
    return _copyLocationChatMessageText(message, edit.text);
  }
}

class LocationChatEditResult {
  const LocationChatEditResult({
    required this.texts,
    required this.deletedMessageIds,
  });
  final Map<String, String> texts;
  final Set<String> deletedMessageIds;
}

class LocationChatEditPageArgs {
  const LocationChatEditPageArgs({
    required this.messages,
    required this.style,
    this.backgroundImageUrl,
    this.backgroundPreviewImageUrl,
    this.selfMessageBubbleMaxWidthCap,
    this.otherMessageBubbleMaxWidthCap,
    this.mentionCatalog,
  });

  final List<ChatMessageVm> messages;
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
    _messages = locationChatLatestEditableRound(widget.args.messages)
        .map((message) => _copyLocationChatMessageText(message, message.text))
        .toList();
    for (final message in _messages) {
      _messageKeys[message.localId] = GlobalKey();
      if (message.isImage) continue;
      _controllers[message.localId] = LocationChatMentionEditingController(
        catalog: widget.args.mentionCatalog,
      )..setSerializedText(message.text);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollCoordinator.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _deleteMessage(String id) {
    if (_activeMessageId == id) {
      FocusManager.instance.primaryFocus?.unfocus();
      _activeMessageId = null;
    }
    setState(() {
      _deletedMessageIds.add(id);
      _messages.removeWhere((message) => message.localId == id);
    });
  }

  void _done() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(
      LocationChatEditResult(
        texts: {
          for (final entry in _controllers.entries)
            if (!_deletedMessageIds.contains(entry.key))
              entry.key: entry.value.serializedText,
        },
        deletedMessageIds: Set.of(_deletedMessageIds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final style = args.style;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kChatDarkHeaderSystemUiOverlayStyle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _LocationChatBackground(
            imageUrl: args.backgroundImageUrl,
            previewImageUrl: args.backgroundPreviewImageUrl,
            color: style.conversationBackgroundColor,
            enabled: true,
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: true,
            body: Column(
              children: [
                ChatHeader(
                  title: 'Edit Message',
                  subtitle: '',
                  connected: false,
                  connecting: false,
                  onBack: () => Navigator.of(context).pop(),
                  showTitleIcon: false,
                  showSubtitle: false,
                  showMoreButton: false,
                  alignContentLeft: true,
                  trailingVerticallyCentered: true,
                  style: style,
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GenesisPrimaryButton(
                      key: const ValueKey('location-chat-edit-done'),
                      label: 'Save',
                      onPressed: _done,
                      width: 64,
                      height: 32,
                      fullWidth: false,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      foregroundColor: style.bubbleTextStyle.color,
                    ),
                  ),
                ),
                Expanded(
                  child: ChatMentionScope(
                    catalog: args.mentionCatalog ?? ChatMentionCatalog.empty,
                    child: ChatMessageEditorScope(
                      controllers: _controllers,
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
                                    child: ChatMessageRow(
                                      key: ValueKey(
                                        'location-chat-edit-row-${_messages[index].localId}',
                                      ),
                                      message: _messages[index],
                                      showDateDivider: false,
                                      style: style,
                                      selfMessageBubbleMaxWidthCap:
                                          args.selfMessageBubbleMaxWidthCap,
                                      otherMessageBubbleMaxWidthCap:
                                          args.otherMessageBubbleMaxWidthCap,
                                    ),
                                  ),
                                  Positioned(
                                    right: _messages[index].isImage ? 4 : 0,
                                    top: _messages[index].isImage ? 12 : 0,
                                    child: BackdropGroup(
                                      child: ChatStableBackdropSurface(
                                        sigma: style
                                            .composerSendButtonBackdropBlurSigma,
                                        borderRadius: BorderRadius.circular(
                                          style.composerSendButtonBorderRadius,
                                        ),
                                        child: CreateFormDeleteButton(
                                          backgroundColor: style
                                              .composerSendButtonDisabledColor,
                                          iconColor:
                                              style.bubbleTextStyle.color ??
                                              const Color(0xFFF4F3F6),
                                          borderSide: BorderSide.none,
                                          borderRadius: BorderRadius.circular(
                                            style
                                                .composerSendButtonBorderRadius,
                                          ),
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
        ],
      ),
    );
  }
}

extension _LocationChatEditActions on _LocationChatPanelState {
  Future<void> _openReplyEditor(LocationChatEditPageArgs args) async {
    if (_replyEditorOpen || !widget.active) return;
    final worldId = widget.worldId;
    final locationId = widget.locationId;
    _replyEditorOpen = true;
    _composerFocusNode.unfocus();
    try {
      final result = await Navigator.of(context, rootNavigator: true)
          .pushNamed<LocationChatEditResult>(
            RouteNames.locationChatEdit,
            arguments: args,
          );
      if (!mounted ||
          result == null ||
          widget.worldId != worldId ||
          widget.locationId != locationId) {
        return;
      }
      _setLocationChatState(
        () => _localMessageEdits.save(
          _messages,
          result.texts,
          deletedMessageIds: result.deletedMessageIds,
        ),
      );
    } finally {
      _replyEditorOpen = false;
    }
  }
}

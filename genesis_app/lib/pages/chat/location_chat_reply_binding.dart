part of 'location_chat_page.dart';

extension _LocationChatReplyBinding on _LocationChatPanelState {
  void _detachReplyActions() {
    _replyBindingGeneration++;
    _replyController?.removeListener(_onReplyActionsChanged);
    _replyController = null;
    _preparingReplyAction = false;
    _replyEditorState?.value = const LocationChatEditExternalState(
      frozen: true,
      error: 'This chat is no longer active.',
    );
    _restoredReplyLocations.clear();
  }

  void _bindReplyActions() {
    final service = _service;
    if (service == null || !widget.isLeafLocation) return;
    final next = service.replyActions;
    if (next == null) return;
    if (!identical(next, _replyController)) {
      _detachReplyActions();
      _replyController = next;
      next.addListener(_onReplyActionsChanged);
      service.setReplyWalletRefresher(
        AppServicesScope.read(context).gemWallet.refresh,
      );
    }
    if (_restoredReplyLocations.add(widget.locationId)) {
      unawaited(
        next.restore(widget.locationId).catchError((Object error) {
          debugPrint('[ReplyActions] restore failed: $error');
        }),
      );
    }
  }

  void _onReplyActionsChanged() {
    if (_replyRebuildScheduled) return;
    _replyRebuildScheduled = true;
    scheduleMicrotask(() {
      _replyRebuildScheduled = false;
      if (mounted && widget.active) _setLocationChatState(() {});
    });
  }

  Future<void> _runReplyAction(
    Future<void> Function(ChatroomReplyActionsController) action,
  ) async {
    final controller = _replyController;
    if (!widget.isMember || controller == null || _preparingReplyAction) return;
    final location = widget.locationId;
    final bindingGeneration = _replyBindingGeneration;
    _setLocationChatState(() => _preparingReplyAction = true);
    try {
      await action(controller);
    } catch (error) {
      if (mounted &&
          widget.active &&
          bindingGeneration == _replyBindingGeneration &&
          widget.locationId == location &&
          identical(controller, _replyController)) {
        // HTTP business errors already use the application's error presenter.
        if (error is! ApiException || error.kind != ApiExceptionKind.business) {
          showGenesisToast(context, '$error');
        }
      }
    } finally {
      if (mounted &&
          bindingGeneration == _replyBindingGeneration &&
          widget.locationId == location &&
          identical(controller, _replyController)) {
        _setLocationChatState(() => _preparingReplyAction = false);
      }
    }
  }

  void _browseReplyCard(int delta) {
    final controller = _replyController;
    if (controller == null) return;
    unawaited(
      controller.browse(widget.locationId, delta).catchError((Object error) {
        debugPrint('[ReplyActions] card position persistence failed: $error');
      }),
    );
  }

  ({List<ChatMessageVm> messages, int? anchorIndex}) _replyPresentation(
    ChatroomReplyRoundState? state,
  ) {
    final source = _locationChatDisplayMessages();
    if (state == null) return (messages: source, anchorIndex: null);
    final round = '${state.roundId}';
    final output = <ChatMessageVm>[];
    int? anchor;
    var inserted = false;
    final replacements = state.showCandidates
        ? _replyMessageVms(state.displayedMessages, cardId: state.viewedCardId)
        : const <ChatMessageVm>[];
    for (final message in source) {
      if (message.roundId == round && !message.isMe && !message.isSystem) {
        if (state.showCandidates) {
          if (!inserted) output.addAll(replacements);
          inserted = true;
        } else {
          output.add(message);
        }
        anchor = output.length;
      } else {
        output.add(message);
      }
    }
    if (state.showCandidates && !inserted) {
      output.addAll(replacements);
      anchor = output.length;
    }
    return (messages: output, anchorIndex: anchor ?? output.length);
  }

  List<ChatMessageVm> _replyMessageVms(
    List<WorldChatroomMessage> source, {
    int? cardId,
  }) {
    final identity = _LocationChatTimelineIdentityIndex.fromState(
      _chatroomState,
      currentUserIds: _myUserIdKeys,
      currentSenderIds: _mySenderIdKeys,
    );
    final parseContext = LocationChatMessageParseContext(
      currentLocationId: widget.locationId,
      isMine: (_) => false,
      senderName: _messageSenderDisplayName,
      avatarUrl: _messageAvatarUrl,
      isPlayerControlledRole: _messageSenderIsPlayerControlledRole,
      characterName: identity.characterName,
      locationName: identity.locationName,
      roleName: identity.roleName,
      roleIsAi: identity.roleIsAi,
      roleAvatarUrl: identity.roleAvatarUrl,
    );
    return [
      for (final message in source)
        if (_parserForMessage(message)?.parse(message, parseContext)
            case final parsed?)
          ChatMessageVm(
            localId:
                'reply:${widget.worldId}:${widget.locationId}:${parsed.roundId}:${cardId ?? 0}:${parsed.globalMessageId}',
            globalMessageId: parsed.globalMessageId,
            messageId: parsed.messageId,
            locationMessageId: parsed.locationMessageId,
            roundId: parsed.roundId,
            tickNo: parsed.tickNo,
            subTickNo: parsed.subTickNo,
            senderId: parsed.senderId,
            senderName: parsed.senderName,
            avatarUrl: parsed.avatarUrl,
            imageUrl: parsed.imageUrl,
            text: parsed.text,
            currentTime: parsed.currentTime,
            isMe: false,
            status: parsed.status,
            senderType: parsed.senderType,
            createdAt: parsed.createdAt,
          ),
    ];
  }

  Widget? _replyStatusWidget(ChatroomReplyRoundState? state) {
    if (state == null) return null;
    final pending = _replyController
        ?.statesFor(widget.locationId)
        .where(
          (source) =>
              source.goOnPending &&
              (source.roundId == state.roundId ||
                  source.goOnRoundId == state.roundId),
        )
        .firstOrNull;
    final awaitingRecovery = pending != null && !_sendAwaitingResponse;
    final message = pending?.goOnUnknown == true
        ? 'Result pending confirmation.'
        : state.error != null
        ? '${state.error}'
        : awaitingRecovery
        ? 'Reply is pending confirmation.'
        : pending != null && state.displayedMessages.isEmpty
        ? 'Waiting for the next reply…'
        : state.showCandidates &&
              state.displayedMessages.isEmpty &&
              state.generating
        ? 'Generating…'
        : null;
    if (message == null) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: Color(0xFFF4F3F6))),
          if (awaitingRecovery || state.error != null)
            TextButton(
              onPressed: () => unawaited(
                _runReplyAction((controller) => controller.reconnect()),
              ),
              child: const Text('Check status'),
            ),
        ],
      ),
    );
  }

  Future<void> _editCurrentReply(
    ChatUiStyleConfig style,
    double? selfCap,
    double? otherCap,
  ) async {
    final controller = _replyController;
    if (!widget.isMember ||
        controller == null ||
        _preparingReplyAction ||
        _replyEditorOpen) {
      return;
    }
    final location = widget.locationId;
    final bindingGeneration = _replyBindingGeneration;
    bool currentEditor() =>
        mounted &&
        widget.active &&
        bindingGeneration == _replyBindingGeneration &&
        identical(controller, _replyController) &&
        location == widget.locationId;
    _setLocationChatState(() => _preparingReplyAction = true);
    try {
      final target = await controller.prepareEditor(location);
      if (!currentEditor()) {
        return;
      }
      final messages = _replyMessageVms(target.messages, cardId: target.cardId);
      final byId = {for (final message in messages) message.localId: message};
      List<ChatroomLlmMessageOperation> operations(
        LocationChatEditResult result,
      ) => [
        for (final message in messages)
          if (result.deletedMessageIds.contains(message.localId))
            ChatroomLlmMessageOperation.delete(
              globalMessageId: message.globalMessageId,
            )
          else if (result.texts[message.localId] case final text?)
            if (text != message.text)
              ChatroomLlmMessageOperation.edit(
                globalMessageId: message.globalMessageId,
                content: text,
              ),
      ];
      final external = ValueNotifier(const LocationChatEditExternalState());
      final draft = target.draftOperations;
      final initialDraft = LocationChatEditResult(
        texts: {
          for (final message in messages)
            message.localId:
                draft
                    .where(
                      (op) =>
                          op.globalMessageId == message.globalMessageId &&
                          op.action == ChatroomLlmMessageAction.edit,
                    )
                    .firstOrNull
                    ?.content ??
                message.text,
        },
        deletedMessageIds: {
          for (final message in messages)
            if (draft.any(
              (op) =>
                  op.globalMessageId == message.globalMessageId &&
                  op.action == ChatroomLlmMessageAction.delete,
            ))
              message.localId,
        },
      );
      _replyEditorState = external;
      final initialRevision =
          controller
              .stateForRound(location, target.roundId)
              ?.completionRevision ??
          0;
      var externallyFrozen = false;
      void syncExternal() {
        if (!currentEditor()) return;
        final state = controller.stateForRound(location, target.roundId);
        if (state == null) return;
        externallyFrozen = externallyFrozen || state.frozen;
        external.value = LocationChatEditExternalState(
          frozen: state.frozen,
          saving: state.frozen && state.busy,
          saved:
              externallyFrozen &&
              !state.frozen &&
              !state.busy &&
              state.error == null &&
              state.completionRevision > initialRevision,
          error: state.error == null ? null : '${state.error}',
        );
      }

      controller.addListener(syncExternal);
      try {
        syncExternal();
        await _openReplyEditor(
          LocationChatEditPageArgs(
            worldId: widget.worldId,
            locationId: location,
            roundId: target.roundId,
            cardId: target.cardId,
            messages: messages,
            style: style,
            canEdit: target.canEdit,
            canDelete: target.canDelete,
            backgroundImageUrl: widget.backgroundImageUrl,
            backgroundPreviewImageUrl: widget.backgroundPreviewImageUrl,
            selfMessageBubbleMaxWidthCap: selfCap,
            otherMessageBubbleMaxWidthCap: otherCap,
            mentionCatalog: _textController.catalog,
            externalState: external,
            initialDraft: initialDraft,
            onSave: (result) async {
              if (!currentEditor()) {
                throw StateError('This chat is no longer active');
              }
              await controller.save(target, operations(result));
            },
            onDraftChanged: (result) {
              if (!currentEditor()) return;
              if (result.texts.keys.every(byId.containsKey)) {
                unawaited(
                  controller.setDraft(target, operations(result)).catchError((
                    Object error,
                  ) {
                    debugPrint(
                      '[ReplyActions] draft persistence failed: $error',
                    );
                  }),
                );
              }
            },
            onCancel: () {
              if (!currentEditor()) return;
              unawaited(
                controller.cancelDraft(target).catchError((Object error) {
                  debugPrint(
                    '[ReplyActions] draft cancellation failed: $error',
                  );
                }),
              );
            },
          ),
        );
      } finally {
        controller.removeListener(syncExternal);
        if (identical(_replyEditorState, external)) _replyEditorState = null;
        external.dispose();
      }
    } catch (error) {
      if (mounted && currentEditor()) {
        if (error is! ApiException || error.kind != ApiExceptionKind.business) {
          showGenesisToast(context, '$error');
        }
      }
    } finally {
      if (mounted &&
          bindingGeneration == _replyBindingGeneration &&
          widget.locationId == location &&
          identical(controller, _replyController)) {
        _setLocationChatState(() => _preparingReplyAction = false);
      }
    }
  }
}

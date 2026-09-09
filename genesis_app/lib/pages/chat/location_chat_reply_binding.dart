part of 'location_chat_page.dart';

extension _LocationChatReplyBinding on _LocationChatPanelState {
  void _detachReplyActions() {
    _replyBindingGeneration++;
    _replyController?.removeListener(_onReplyActionsChanged);
    _replyController = null;
    _preparingReplyAction = false;
    _replyRequestLoading = false;
    _replyStreamStarted = false;
    _replyLoadingSourceRound = null;
    _replyLoadingPreviousCardIds = const {};
    _lastReplyStatusError = null;
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
    _markReplyStreamStarted();
    if (_replyRebuildScheduled) return;
    _replyRebuildScheduled = true;
    scheduleMicrotask(() {
      _replyRebuildScheduled = false;
      if (mounted && widget.active) {
        final error = _replyController?.stateFor(widget.locationId)?.error;
        if (error != null &&
            !identical(error, _lastReplyStatusError) &&
            !_preparingReplyAction &&
            !isChatroomErrorPresentedGlobally(error)) {
          showGenesisToast(context, chatroomOperationErrorMessage(error));
        }
        _lastReplyStatusError = error;
        _setLocationChatState(() {});
      }
    });
  }

  Future<void> _runReplyAction(
    Future<void> Function(ChatroomReplyActionsController) action, {
    bool generating = false,
    bool regenerating = false,
  }) async {
    final controller = _replyController;
    if (!widget.isMember || controller == null || _preparingReplyAction) return;
    final location = widget.locationId;
    final bindingGeneration = _replyBindingGeneration;
    _setLocationChatState(() {
      _preparingReplyAction = true;
      _replyRequestLoading = generating;
      if (generating) {
        final source = controller.stateFor(location);
        _replyStreamStarted = false;
        _replyLoadingForRegeneration = regenerating;
        _replyLoadingSourceRound = source?.roundId;
        _replyLoadingPreviousCardIds = {
          for (final card in source?.cards ?? const []) card.cardId,
        };
      }
    });
    if (generating) {
      _scrollCoordinator.requestBottom(
        reason: LocationChatBottomReason.replyGeneration,
        behavior: LocationChatBottomBehavior.animate,
        duration: const Duration(milliseconds: 500),
      );
    }
    try {
      await action(controller);
    } catch (error) {
      if (mounted &&
          widget.active &&
          bindingGeneration == _replyBindingGeneration &&
          widget.locationId == location &&
          identical(controller, _replyController)) {
        // HTTP and WS business errors already use the global presenter.
        if (!isChatroomErrorPresentedGlobally(error)) {
          showGenesisToast(context, chatroomOperationErrorMessage(error));
        }
      }
    } finally {
      if (mounted &&
          bindingGeneration == _replyBindingGeneration &&
          widget.locationId == location &&
          identical(controller, _replyController)) {
        _setLocationChatState(() {
          _preparingReplyAction = false;
          _replyRequestLoading = false;
        });
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
    return buildLocationChatReplyPresentation(
      source: source,
      roundId: '${state.roundId}',
      replyMessageIds: state.formalReplyMessages
          .map((message) => message.globalMessageId)
          .where((id) => id > 0)
          .toSet(),
      candidates: state.showCandidates
          ? _replyMessageVms(
              state.displayedMessages,
              cardId: state.viewedCardId,
            )
          : null,
    );
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

  void _markReplyStreamStarted() {
    final round = _replyLoadingSourceRound;
    if (_replyStreamStarted || round == null) return;
    if (_replyLoadingForRegeneration) {
      _replyStreamStarted =
          _replyController
              ?.stateForRound(widget.locationId, round)
              ?.hasNewCandidateContent(_replyLoadingPreviousCardIds) ??
          false;
    } else {
      final messages =
          (_service?.state ?? _chatroomState).messagesByLocation[widget
              .locationId] ??
          const <WorldChatroomMessage>[];
      _replyStreamStarted = messages.any(
        (message) =>
            message.conversationRoundNumber > round &&
            const {
              'character',
              'narrator',
              'ai',
              'llm',
            }.contains(message.businessType) &&
            message.content.trim().isNotEmpty,
      );
    }
  }

  Widget? _replyStatusWidget(
    ChatroomReplyRoundState? state,
    ChatUiStyleConfig style,
  ) {
    final pending = _replyController
        ?.statesFor(widget.locationId)
        .where((source) => source.goOnPending)
        .firstOrNull;
    final loading =
        _replyRequestLoading ||
        (state?.generating == true && state?.error == null) ||
        (pending != null &&
            !pending.goOnUnknown &&
            pending.error == null &&
            _sendAwaitingResponse);
    _markReplyStreamStarted();
    return loading && !_replyStreamStarted
        ? LocationChatLoadingBubble(style: style)
        : null;
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
          error:
              state.error == null ||
                  isChatroomErrorPresentedGlobally(state.error)
              ? null
              : chatroomOperationErrorMessage(state.error!),
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
        if (!isChatroomErrorPresentedGlobally(error)) {
          showGenesisToast(context, chatroomOperationErrorMessage(error));
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

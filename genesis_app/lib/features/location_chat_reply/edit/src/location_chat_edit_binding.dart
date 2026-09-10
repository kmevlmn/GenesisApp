part of '../../../../pages/chat/location_chat_page.dart';

extension _LocationChatEditBinding on _LocationChatPanelState {
  Future<void> _editCurrentReply(
    ChatUiStyleConfig style,
    double? selfCap,
    double? otherCap,
  ) async {
    final controller = _replyController;
    if (controller == null ||
        _sending ||
        _replyCardTransitionBusy ||
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

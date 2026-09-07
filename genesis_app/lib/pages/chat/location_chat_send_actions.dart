part of 'location_chat_page.dart';

extension _LocationChatSendActions on _LocationChatPanelState {
  void _maybeSendInitialMessage() {
    if (!_initialMessageSendPending || _initialMessageSendScheduled) return;
    if (!widget.active ||
        _service == null ||
        _chatroomState.joinedLocationId != widget.locationId ||
        _chatroomState.inputBlocked ||
        _sendAwaitingResponse ||
        _sending ||
        isGenesisUgcTextBlank(_textController.serializedText)) {
      return;
    }
    _initialMessageSendScheduled = true;
    scheduleMicrotask(() async {
      _initialMessageSendScheduled = false;
      if (!mounted ||
          !_initialMessageSendPending ||
          !widget.active ||
          _service == null ||
          _chatroomState.joinedLocationId != widget.locationId ||
          _chatroomState.inputBlocked ||
          _sendAwaitingResponse ||
          _sending ||
          isGenesisUgcTextBlank(_textController.serializedText)) {
        return;
      }
      _initialMessageSendPending = false;
      await _send();
    });
  }

  void _editInspiration(String text) {
    _textController.setSerializedText(text);
    if (_composerFocusNode.hasFocus) {
      // The system back button can hide the keyboard without dropping focus.
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
    } else {
      _composerFocusNode.requestFocus();
    }
  }

  Future<void> _send({String? textOverride}) async {
    final service = _service;
    if (service == null ||
        _chatroomState.joinedLocationId != widget.locationId ||
        _chatroomState.inputBlocked ||
        _sendAwaitingResponse ||
        _sending) {
      return;
    }
    final text = normalizeGenesisUgcTextForDisplay(
      textOverride ?? _textController.serializedText,
    );
    if (isGenesisUgcTextBlank(text)) return;

    final clientMsgId = _nextClientMsgId();
    final localMessage = ChatMessageVm(
      localId: 'local-$clientMsgId',
      clientMsgId: clientMsgId,
      senderId: _mySenderId,
      senderName: _localSelfDisplayName(),
      avatarUrl: _resizedLocationChatAvatarUrl(_localSelfAvatarUrl()),
      isPlayerControlledRole: _identityCandidatesArePlayerControlledRole([
        _myUserId,
        _mySenderId,
      ]),
      text: text,
      isMe: true,
      status: 'sending',
    );

    _setLocationChatState(() {
      _sending = true;
      _messages.add(localMessage);
      _hasDraftText = false;
      _textController.clear();
    });
    _recordPanelDebug(
      action: 'optimisticSend',
      details: {
        'clientMsgId': clientMsgId,
        'vm': LocationChatDebugSlice.debugRenderMessage(localMessage),
      },
    );
    _scrollCoordinator.requestBottom(
      reason: LocationChatBottomReason.sentMessage,
      behavior: LocationChatBottomBehavior.jump,
    );

    await _submitLocalMessage(
      service: service,
      localMessage: localMessage,
      clientMsgId: clientMsgId,
      isInitialSend: true,
    );
  }

  Future<void> _retryFailedMessage(ChatMessageVm message) async {
    final service = _service;
    if (!message.isMe ||
        message.status != 'failed' ||
        service == null ||
        _chatroomState.joinedLocationId != widget.locationId ||
        _chatroomState.inputBlocked ||
        _sendAwaitingResponse ||
        _sending) {
      return;
    }

    final clientMsgId = _nextClientMsgId();
    _setLocationChatState(() {
      message.clientMsgId = clientMsgId;
      message.status = 'sending';
      message.error = null;
      _sending = true;
    });
    _recordPanelDebug(
      action: 'retrySend',
      details: {'clientMsgId': clientMsgId, 'localId': message.localId},
    );

    await _submitLocalMessage(
      service: service,
      localMessage: message,
      clientMsgId: clientMsgId,
      isInitialSend: false,
    );
  }

  Future<void> _submitLocalMessage({
    required WorldChatroomService service,
    required ChatMessageVm localMessage,
    required String clientMsgId,
    required bool isInitialSend,
  }) async {
    var receiptReceived = false;
    try {
      if (isInitialSend) {
        unawaited(
          FirebaseAnalyticsMonitoring.recordMessageSent(
            worldId: widget.worldId,
            locationId: widget.locationId,
          ),
        );
      }
      final handle = service.sendMessage(
        localMessage.text,
        clientMsgId: clientMsgId,
      );
      final receipt = await handle.receipt;
      receiptReceived = true;
      if (!mounted) {
        service.cancelCanonicalMessageWait(clientMsgId);
        return;
      }
      unawaited(
        runLocationChatMetadataUpdateBestEffort(_markRecentWorldChatLocation),
      );
      _setLocationChatState(() {
        localMessage.status = 'sent';
        _sending = false;
      });
      _recordPanelDebug(
        action: 'sendReceipt',
        details: {
          'clientMsgId': receipt.clientMsgId,
          'receivedAt': receipt.receivedAt?.toIso8601String(),
        },
      );

      WorldChatroomMessage canonicalMessage;
      try {
        canonicalMessage = await handle.canonicalMessage.timeout(
          const Duration(seconds: 5),
        );
      } on TimeoutException {
        await service.refreshLatestMessages(
          locationId: widget.locationId,
          limit: 20,
          emitLatestFetched: false,
        );
        canonicalMessage = await handle.canonicalMessage.timeout(
          const Duration(seconds: 2),
        );
      }
      if (!mounted) return;
      GenesisTelemetry.collectLog(
        actionType: 'event',
        action: 'location_chat_send_message',
        object1: widget.worldId,
        object2: widget.locationId,
        object3: canonicalMessage.messageId,
      );
      _setLocationChatState(() {
        ChatMessageVm target = localMessage;
        for (final message in _messages) {
          if (message.clientMsgId.trim() == clientMsgId) {
            target = message;
            break;
          }
        }
        target.globalMessageId = canonicalMessage.globalMessageId;
        target.messageId = canonicalMessage.messageId;
        target.locationMessageId = canonicalMessage.locationMessageId;
        target.roundId = canonicalMessage.conversationRoundId;
        target.status = 'sent';
        _sending = false;
      });
      _recordPanelDebug(
        action: 'sendCanonicalEcho',
        details: {
          'clientMsgId': clientMsgId,
          'globalMessageId': canonicalMessage.globalMessageId,
          'messageId': canonicalMessage.messageId,
          'locationMessageId': canonicalMessage.locationMessageId,
          'roundId': canonicalMessage.conversationRoundId,
        },
      );
    } catch (e) {
      if (receiptReceived) {
        service.cancelCanonicalMessageWait(clientMsgId, reason: e);
      }
      if (!mounted) return;
      final restoredDraft = receiptReceived
          ? null
          : recoverLocationChatDraftAfterRetriableAckFailure(
              failure: e,
              localMessage: localMessage,
              messages: _messages,
              activeSendFailure: true,
            );
      _setLocationChatState(() {
        if (restoredDraft != null) {
          _hasDraftText = restoredDraft.trim().isNotEmpty;
          _textController.setSerializedText(restoredDraft);
        } else if (!receiptReceived) {
          localMessage.status = 'failed';
          localMessage.error = e.toString();
        } else {
          // The command was accepted. Keep the optimistic message as sent so
          // a sync timeout cannot invite an accidental duplicate retry.
          localMessage.status = 'sent';
          localMessage.error = e.toString();
        }
        _sending = false;
      });
      if (restoredDraft != null && _shouldShowDraftRestoreToast(e)) {
        showGenesisToast(
          context,
          _locationChatDraftRestoreToastMessage(e),
          duration: const Duration(seconds: 4),
        );
      }
      if (receiptReceived) {
        showGenesisToast(
          context,
          'Message sent, but syncing the server message timed out.',
          duration: const Duration(seconds: 4),
        );
      }
      _recordPanelDebug(
        action: 'sendFailed',
        details: {'clientMsgId': clientMsgId, 'error': '$e'},
      );
    }
  }

  Future<void> _markRecentWorldChatLocation() async {
    final services = AppServicesScope.read(context);
    final worldId = widget.worldId;
    final locationId = widget.locationId;
    final locationPathIds = List<String>.of(widget.recentChatLocationPathIds);
    final uid = await resolveRecentWorldChatUid(services);
    await recentWorldChatStore.markRecentChat(
      uid: uid,
      worldId: worldId,
      locationId: locationId,
      locationPathIds: locationPathIds,
    );
  }

  String _nextClientMsgId() {
    _clientMsgCounter += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_clientMsgCounter';
  }

  String _latestMessageLocalId() {
    final unreadCandidates = _messages.where(
      (message) => message.status != 'system',
    );
    if (unreadCandidates.isEmpty) return '';
    return unreadCandidates.last.localId;
  }

  bool _syncHasMoreOlderMessagesForSource(List<WorldChatroomMessage> source) {
    final hasOlderCursor = _oldestLocationMessageId(source) > 0;
    if (!hasOlderCursor && source.isNotEmpty) {
      _olderMessagesExhaustedByCursorlessContent = true;
    }
    final nextHasMoreOlder =
        hasOlderCursor &&
        !_olderMessagesExhaustedByRemote &&
        !_olderMessagesExhaustedByCursorlessContent;
    if (_hasMoreOlderMessages == nextHasMoreOlder) return false;
    _hasMoreOlderMessages = nextHasMoreOlder;
    return true;
  }
}

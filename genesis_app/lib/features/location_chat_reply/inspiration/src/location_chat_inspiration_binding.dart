part of '../../../../pages/chat/location_chat_page.dart';

extension _LocationChatInspirationBinding on _LocationChatPanelState {
  void _editInspiration(String text) {
    if (_replyCardTransitionBusy) return;
    _textController.setSerializedText(text);
    if (_composerFocusNode.hasFocus) {
      // The system back button can hide the keyboard without dropping focus.
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
    } else {
      _composerFocusNode.requestFocus();
    }
  }

  LocationChatInspirationFeature _inspirationFeature() =>
      LocationChatInspirationFeature(
        messages: _inspirationMessages,
        loading: _inspirationLoading,
        enabled:
            _currentInspirationSource != null &&
            !_sending &&
            !_preparingReplyAction,
        onExpandedChanged: _onInspirationExpanded,
        onSend: _sendInspiration,
        onEdit: _editInspiration,
      );

  ChatroomInspirationSource? get _currentInspirationSource {
    if (!widget.active ||
        _chatroomState.inputBlocked ||
        widget.worldTickInProgress) {
      return null;
    }
    return _replyController?.stateFor(widget.locationId)?.inspirationSource;
  }

  void _bindInspirations() {
    final next = _service?.inspirations;
    if (identical(next, _inspirationController)) return;
    _detachInspirations();
    _inspirationController = next;
    next?.addListener(_onInspirationInvalidated);
  }

  void _detachInspirations() {
    _inspirationController?.removeListener(_onInspirationInvalidated);
    _resetInspiration();
    _inspirationController = null;
  }

  void _resetInspiration() {
    final location =
        _inspirationRequestSource?.locationId ??
        _inspirationDisplayedSource?.locationId;
    if (location != null) _inspirationController?.cancelView(location);
    _inspirationRequestGeneration++;
    _inspirationResetRevision++;
    _inspirationMessages = const [];
    _inspirationRequestSource = null;
    _inspirationDisplayedSource = null;
    _inspirationEpoch = null;
    _inspirationLoading = false;
  }

  void _onInspirationInvalidated() {
    final source = _inspirationDisplayedSource ?? _inspirationRequestSource;
    final epoch = _inspirationEpoch;
    if (source == null ||
        epoch == null ||
        (_inspirationController?.isCurrent(source, epoch) ?? false)) {
      return;
    }
    _resetInspiration();
    // Service notifications can arrive while a parent is rebuilding.
    scheduleMicrotask(() {
      if (mounted) _setLocationChatState(() {});
    });
  }

  void _syncInspirationView() {
    if (_sending) return;
    final source = _inspirationDisplayedSource ?? _inspirationRequestSource;
    if (source != null && !source.sameOrigin(_currentInspirationSource)) {
      _resetInspiration();
    }
  }

  void _onInspirationExpanded(bool expanded) {
    if (expanded) {
      unawaited(_loadInspirations());
    } else if (_inspirationLoading) {
      _setLocationChatState(_resetInspiration);
    }
  }

  Future<void> _loadInspirations() async {
    final service = _service;
    final controller = _inspirationController;
    final source = _currentInspirationSource;
    if (service == null ||
        controller == null ||
        source == null ||
        _inspirationLoading) {
      return;
    }
    final generation = ++_inspirationRequestGeneration;
    final binding = _replyBindingGeneration;
    bool current() =>
        mounted &&
        widget.active &&
        generation == _inspirationRequestGeneration &&
        binding == _replyBindingGeneration &&
        identical(service, _service) &&
        source.sameOrigin(_currentInspirationSource);
    _setLocationChatState(() {
      _inspirationRequestSource = source;
      _inspirationDisplayedSource = null;
      _inspirationMessages = const [];
      _inspirationLoading = true;
      _inspirationEpoch = null;
    });
    try {
      await service.ensureInspirationHistory(source.locationId);
      if (!current()) return;
      final verified = _currentInspirationSource!;
      _inspirationEpoch = controller.revision(source.locationId);
      final result = await controller.load(verified);
      if (!current() || result == null) return;
      final latest = _currentInspirationSource!;
      if (latest.cardId != null && latest.sourceCardId != result.sourceCardId) {
        return;
      }
      _setLocationChatState(() {
        _inspirationDisplayedSource = verified;
        _inspirationMessages = result.messages;
      });
    } catch (error) {
      if (mounted && current() && !isChatroomErrorPresentedGlobally(error)) {
        showGenesisToast(context, chatroomOperationErrorMessage(error));
      }
    } finally {
      if (mounted && generation == _inspirationRequestGeneration) {
        _setLocationChatState(() => _inspirationLoading = false);
      }
    }
  }

  void _sendInspiration(String text) {
    final source = _inspirationDisplayedSource;
    final epoch = _inspirationEpoch;
    if (source == null ||
        epoch == null ||
        _sending ||
        !source.sameOrigin(_currentInspirationSource) ||
        !_inspirationMessages.contains(text)) {
      return;
    }
    unawaited(
      _send(
        textOverride: text,
        inspirationSource: source,
        inspirationEpoch: epoch,
      ),
    );
  }
}

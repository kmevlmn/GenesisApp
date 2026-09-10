part of '../../../../network/chatroom/chatroom_reply_actions_controller.dart';

/// Internal implementation. Callers only see the regenerate feature contract.
extension ChatroomRegenerateFeatureImplementation
    on ChatroomReplyActionsController {
  Future<void> regenerate(String locationId) async {
    await restore(locationId);
    final state = await _target(locationId);
    if (!state.canRegenerate) {
      throw StateError('This round cannot be regenerated');
    }
    _invalidateCardsCache(state);
    state._regenerateDispatching = true;
    ++state._generation;
    state._error = null;
    final oldView = state._viewedCardId;
    final originalMessages = state.formalReplyMessages;
    _notify();
    var dispatched = false;
    var candidatePrepared = false;
    try {
      if (!state._canRegenerate ||
          state._cards.where((card) => card.cardId > 0).length >= 10 ||
          state._cards.any(
            (card) => card.cardId > 0 && !_terminal(card.generationState),
          )) {
        throw StateError('This round cannot be regenerated');
      }
      if (!state._eligible || state.frozen) {
        throw StateError('The source round changed');
      }
      final pendingIndex = state._cards.isEmpty
          ? 2
          : state._cards.fold<int>(
                  0,
                  (v, c) => c.cardIndex > v ? c.cardIndex : v,
                ) +
                1;
      if (state._cards.isEmpty) {
        // ID zero is a local preview only; it is never submitted as a card ID.
        state._cards.add(
          _placeholder(
            0,
            1,
            generationState: ChatroomCardGenerationState.succeeded,
          ),
        );
      }
      state._cards.add(_placeholder(-1, pendingIndex));
      state._viewedCardId = -1;
      state._presentationRevision++;
      candidatePrepared = true;
      state._generating = true;
      state._regenerationRequestId = _request('regenerate');
      await _persist(state);
      _notify();
      dispatched = true;
      final receipt = await _requireSession().regenerateLlmCard(
        locationId: locationId,
        conversationRoundId: state.roundId,
        clientMsgId: state._regenerationRequestId!,
      );
      _checkCurrent();
      final stillPendingView = state._viewedCardId == -1;
      state._cards.removeWhere((card) => card.cardId == -1);
      if (state._card(receipt.cardId) == null) {
        state._cards.add(
          _placeholder(
            receipt.cardId,
            pendingIndex,
            generationState: receipt.generationState,
          ),
        );
      }
      if (stillPendingView) state._viewedCardId = receipt.cardId;
      if (state._card(receipt.originalCardId) == null) {
        state._cards.removeWhere((card) => card.cardId == 0);
        state._cards.add(
          _assembledCard(
            state,
            receipt.originalCardId,
            1,
            originalMessages,
            billing: const ChatroomCardBilling(
              status: ChatroomCardBillingStatus.notRequired,
            ),
            isOriginal: true,
          ),
        );
        if (state._viewedCardId == 0) {
          state._viewedCardId = receipt.originalCardId;
        }
      }
      state._cards.sort((a, b) => a.cardIndex.compareTo(b.cardIndex));
      if (oldView == 0 && state._lastCompleteCardId == 0) {
        state._lastCompleteCardId = receipt.originalCardId;
      }
      state._canConfirm = true;
      state._generating = state._cards.any(
        (card) => !_terminal(card.generationState),
      );
      if (state._generating) {
        _watchRegeneration(state, receipt.cardId);
      } else {
        _cancelRegenerationWatchdog(state);
      }
      await _persist(state);
    } catch (error) {
      if (!_disposed) {
        state._error = error;
        // Unknown acceptance is checked with GET cards. Keep a server-visible
        // candidate, otherwise release the local placeholder; never resend.
        if (candidatePrepared) {
          if (!dispatched || _definiteRejection(error)) {
            state._cards.removeWhere((card) => card.cardId <= 0);
            state._regenerationRequestId = null;
            state._viewedCardId = state._lastCompleteCardId;
          } else {
            try {
              await _loadCards(state, force: true);
            } catch (_) {
              // The original WS error remains the useful user-facing cause.
            }
            if (state._regenerationRequestId != null &&
                state._card(-1) != null) {
              await _failRegenerationLocally(state, -1, error);
            }
          }
        }
        state._generating = state._cards.any(
          (card) => !_terminal(card.generationState),
        );
        if (!state._generating) _cancelRegenerationWatchdog(state);
        await _persist(state);
      }
      rethrow;
    } finally {
      state._regenerateDispatching = false;
      _notify();
      if (state.frozen && !_disposed) {
        if ((state._fixedCardId ?? 0) <= 0) {
          state._fixedCardId = state.lastCompleteCardId;
        }
        _background(state, () => finalizeBeforeSend(locationId));
      }
    }
  }
}

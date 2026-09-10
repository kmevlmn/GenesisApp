part of '../../../../network/chatroom/chatroom_reply_actions_controller.dart';

/// Internal implementation. Callers only see the edit feature contract.
extension ChatroomEditFeatureImplementation on ChatroomReplyActionsController {
  Future<ChatroomReplyEditorTarget> prepareEditor(String locationId) async {
    await restore(locationId);
    final state = await _target(locationId);
    if (!state.canEdit) throw StateError('This reply is not editable');
    _checkCurrent();
    if (state.frozen) throw StateError('This reply has been fixed');
    ++state._generation;
    final target = _editor(state);
    state._openEditors.add(target.cardId ?? 0);
    return target;
  }

  ChatroomReplyEditorTarget _editor(
    ChatroomReplyRoundState state, {
    int? cardId,
  }) {
    final targetCardId =
        cardId ?? (state.showCandidates ? state.viewedCardId : null);
    final card = targetCardId == null ? null : state._card(targetCardId);
    final messages = card == null
        ? state._formal.where(_isReply).toList()
        : card.messages.map(_candidateToWorld).toList();
    return ChatroomReplyEditorTarget(
      worldId: worldId,
      locationId: state.locationId,
      roundId: state.roundId,
      cardId: targetCardId,
      messages: List.unmodifiable(messages),
      canEdit: card?.canEdit ?? true,
      canDelete: card?.canDelete ?? true,
      state: state,
    );
  }

  Future<void> setDraft(
    ChatroomReplyEditorTarget target,
    List<ChatroomLlmMessageOperation> operations,
  ) async {
    final state = _validateTarget(target);
    if (state.frozen || state.busy) throw StateError('Reply editor is frozen');
    if (state._uncertainBatches.contains(target.cardId ?? 0)) {
      throw StateError('Resolve the previous save before changing its draft');
    }
    _validateOperations(target, operations, allowBlankDraft: true);
    _storeDraft(state, target, operations);
    await _persist(state);
    _notify();
  }

  void _storeDraft(
    ChatroomReplyRoundState state,
    ChatroomReplyEditorTarget target,
    List<ChatroomLlmMessageOperation> operations,
  ) {
    final key = target.cardId ?? 0;
    if (operations.isEmpty) {
      state._drafts.remove(key);
      state._draftBaselines.remove(key);
      return;
    }
    state._drafts[key] = List.of(operations);
    final baseline = state._draftBaselines.putIfAbsent(key, () => {});
    final changed = operations
        .map((operation) => operation.globalMessageId)
        .toSet();
    baseline.removeWhere((id, _) => !changed.contains(id));
    for (final message in target.messages) {
      if (changed.contains(message.globalMessageId)) {
        baseline.putIfAbsent(message.globalMessageId, () => message.content);
      }
    }
  }

  Future<void> cancelDraft(ChatroomReplyEditorTarget target) async {
    final state = _validateTarget(target);
    if (state.frozen || state.busy) return;
    state._openEditors.remove(target.cardId ?? 0);
    if (state._uncertainBatches.contains(target.cardId ?? 0)) return;
    state._drafts.remove(target.cardId ?? 0);
    state._draftBaselines.remove(target.cardId ?? 0);
    await _persist(state);
    _notify();
  }

  Future<void> save(
    ChatroomReplyEditorTarget target,
    List<ChatroomLlmMessageOperation> operations,
  ) async {
    final state = _validateTarget(target);
    if (state.frozen || state.busy) throw StateError('Reply editor is frozen');
    if (state._uncertainBatches.contains(target.cardId ?? 0) &&
        !_sameOperations(state._drafts[target.cardId ?? 0] ?? [], operations)) {
      throw StateError('Resolve the previous save before changing its draft');
    }
    _validateOperations(target, operations);
    _storeDraft(state, target, operations);
    state._busy = true;
    state._error = null;
    _notify();
    try {
      await _persist(state);
      await _saveDraft(state, target);
      state._openEditors.remove(target.cardId ?? 0);
      state._completionRevision++;
    } catch (error) {
      if (!_disposed) state._error = error;
      rethrow;
    } finally {
      state._busy = false;
      _notify();
      if (state.frozen && !_disposed && state.error == null) {
        _background(state, () => finalizeBeforeSend(state.locationId));
      }
    }
  }

  Future<void> _saveDraft(
    ChatroomReplyRoundState state,
    ChatroomReplyEditorTarget target,
  ) async {
    final key = target.cardId ?? 0;
    final operations = state._drafts[key] ?? const [];
    if (operations.isEmpty) return;
    if (state._uncertainBatches.contains(key)) {
      final current = target.cardId == null
          ? await _loadRound(state.locationId, state.roundId)
          : await _reloadCardMessages(state, target.cardId!);
      if (_operationsApplied(operations, current)) {
        state._drafts.remove(key);
        state._draftBaselines.remove(key);
        state._uncertainBatches.remove(key);
        if (target.cardId == null) {
          await _refreshFormalRange(
            state.locationId,
            state.roundId,
            state.roundId,
          );
        }
        await _persist(state);
        return;
      }
      // With deleted IDs absent or a changed baseline, replaying an atomic
      // batch is unsafe. Explicitly keep the draft for recovery instead.
      if (!_unchangedTargets(
        operations,
        state._draftBaselines[key] ?? {},
        current,
      )) {
        throw StateError(
          'The previous save result is uncertain; reload before editing again',
        );
      }
      state._uncertainBatches.remove(key);
    }
    _validateOperations(target, operations);
    _invalidateCardsCache(state);
    ++state._generation;
    // Persist ambiguity before dispatch so process death during POST also
    // requires a read before retrying (particularly for delete operations).
    state._uncertainBatches.add(key);
    await _persist(state);
    try {
      if (target.cardId != null) {
        final result = await _http.batchMutateLlmCardMessages(
          worldId: worldId,
          locationId: state.locationId,
          conversationRoundId: state.roundId,
          cardId: target.cardId!,
          operations: operations,
        );
        _checkCurrent();
        state._cards.removeWhere((card) => card.cardId == target.cardId);
        state._cards.add(result.card);
        state._cards.sort((a, b) => a.cardIndex.compareTo(b.cardIndex));
        state._authoritativeCards.add(target.cardId!);
        state._streamMessages.remove(target.cardId);
      } else {
        final result = await _http.batchMutateLlmMessages(
          worldId: worldId,
          locationId: state.locationId,
          conversationRoundId: state.roundId,
          operations: operations,
        );
        _checkCurrent();
        await _refreshFormalRange(
          state.locationId,
          result.startConversationRoundId,
          result.endConversationRoundId,
        );
        state._formal = await _loadRound(state.locationId, state.roundId);
      }
      _checkCurrent();
      ++state._generation;
      state._drafts.remove(key);
      state._draftBaselines.remove(key);
      state._uncertainBatches.remove(key);
      await _persist(state);
    } catch (error) {
      if (_definiteRejection(error)) state._uncertainBatches.remove(key);
      if (!_disposed) await _persist(state);
      rethrow;
    }
  }

  Future<List<WorldChatroomMessage>> _reloadCardMessages(
    ChatroomReplyRoundState state,
    int cardId,
  ) async {
    await _loadCards(state, force: true);
    final card = state._card(cardId);
    if (card == null) throw StateError('The candidate no longer exists');
    return card.messages.map(_candidateToWorld).toList();
  }

  ChatroomReplyRoundState _validateTarget(ChatroomReplyEditorTarget target) {
    _checkCurrent();
    if (target.worldId != worldId || target._state._controller != this) {
      throw StateError('Stale reply editor');
    }
    return target._state;
  }

  void _validateOperations(
    ChatroomReplyEditorTarget target,
    List<ChatroomLlmMessageOperation> operations, {
    bool allowBlankDraft = false,
  }) {
    if (operations.length > 100) {
      throw ArgumentError('A batch supports at most 100 changes');
    }
    final ids = <int>{};
    final messages = {
      for (final message in target.messages) message.globalMessageId: message,
    };
    var deletes = 0;
    for (final operation in operations) {
      if (!allowBlankDraft) operation.toJson();
      if (operation.globalMessageId <= 0) {
        throw ArgumentError('Missing stable message identity');
      }
      if (!ids.add(operation.globalMessageId) ||
          !messages.containsKey(operation.globalMessageId)) {
        throw ArgumentError('The edit target has changed');
      }
      if (operation.action == ChatroomLlmMessageAction.delete) {
        if (!target.canDelete) {
          throw StateError('Deleting this candidate is disabled');
        }
        deletes++;
      } else if (!target.canEdit ||
          messages[operation.globalMessageId]!.messageType == 'image') {
        throw StateError('This message cannot be edited');
      }
    }
    if (target.cardId != null &&
        deletes >= target.messages.length &&
        deletes > 0) {
      throw StateError('A candidate must retain at least one message');
    }
  }
}

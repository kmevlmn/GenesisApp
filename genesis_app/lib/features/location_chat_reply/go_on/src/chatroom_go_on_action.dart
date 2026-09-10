part of '../../../../network/chatroom/chatroom_reply_actions_controller.dart';

/// Internal implementation. Callers only see the Go On feature contract.
extension ChatroomGoOnFeatureImplementation on ChatroomReplyActionsController {
  Future<ChatroomGoOnReceipt> goOn(String locationId) async {
    await restore(locationId);
    final state = await _target(locationId);
    if (!state.canGoOn) throw StateError('This round cannot continue');
    // Block a second tap synchronously, before any save/select awaits.
    state._goOn = _PendingGoOn(_request('go-on'));
    state._error = null;
    _notify();
    var dispatched = false;
    try {
      await finalizeBeforeSend(locationId);
      if (!state._eligible || _isTickLocked()) {
        throw StateError('The source round changed');
      }
      state._busy = true;
      await _persist(state);
      dispatched = true;
      final receipt = await _requireSession().goOn(
        locationId: locationId,
        sourceConversationRoundId: state.roundId,
        clientMsgId: state._goOn!.clientMsgId,
      );
      _checkCurrent();
      state._goOn!.roundId = receipt.conversationRoundId;
      final next = _state(locationId, receipt.conversationRoundId);
      next._owner = ownerUid;
      if (!next._ended) {
        next._active = true;
        _onGoOnAccepted?.call(locationId, receipt.conversationRoundId);
      }
      state._goOn!.ended = next._ended;
      if (receipt.conversationRoundId > (_latest[locationId] ?? 0)) {
        _latest[locationId] = receipt.conversationRoundId;
      }
      await _persist(state);
      if (next._ended) {
        await _recoverGoOn(state);
      } else {
        _watchGoOn(
          state,
          streamStarted:
              next._formal.any((message) => message.streaming) ||
              next._formal.any(_isReply),
        );
      }
      return receipt;
    } catch (error) {
      if (!_disposed) {
        state._error = error;
        if (!dispatched || _goOnDefiniteRejection(error)) {
          state._goOn = null;
        } else {
          state._goOn!.uncertain = true;
        }
        await _persist(state);
        if (_errorCode(error) == 2015) {
          state._invalidated = true;
          await _persist(state);
          try {
            await _refreshLatestHistory?.call(locationId);
          } catch (_) {
            /* Preserve the original server rejection. */
          }
        }
        if (state._goOn case final pending?
            when pending.uncertain && !pending.finished) {
          try {
            await _refreshLatestHistory?.call(locationId);
          } catch (_) {
            // The original request error remains the useful user-facing cause.
          }
          if (!_disposed && identical(state._goOn, pending)) {
            pending.finished = true;
            await _persist(state);
          }
        }
      }
      rethrow;
    } finally {
      state._busy = false;
      _notify();
    }
  }
}

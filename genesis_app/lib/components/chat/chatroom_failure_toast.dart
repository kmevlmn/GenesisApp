import 'dart:async';

import 'package:flutter/material.dart';

import '../../network/api_exception.dart';
import '../../network/chatroom/chatroom_models.dart';
import '../common/genesis_center_toast.dart';

const Set<String> _userInitiatedChatroomRequestTypes = <String>{
  'join',
  'leave',
  'send_message',
};

const Set<String> _replyActionRequestTypes = <String>{
  'regenerate_llm_card',
  'go_on',
  'select_llm_card',
  'send_message', // Sending an inspiration uses the normal send request.
  'end_conversation_round',
  'llm_card_stream',
  'llm_card_generation_end',
};

bool _isReplyActionBusinessFailure(ChatroomFailureEvent failure) {
  final code = int.tryParse(failure.code.trim());
  return code != null &&
      code != 0 &&
      (_replyActionRequestTypes.contains(failure.requestType.trim()) ||
          _replyActionRequestTypes.contains(failure.sourceType.trim()) ||
          failure.sourceType == 'error');
}

/// These errors are already presented by the HTTP interceptor or WS listener.
/// Request futures and controller notifications must not present them again.
bool isChatroomErrorPresentedGlobally(Object? error) => switch (error) {
  ApiException e => e.kind == ApiExceptionKind.business,
  ChatroomFailureEvent() || ChatroomErrorEvent() => true,
  ChatroomPayloadEvent e => !e.ok,
  ChatroomLlmCardGenerationEnd e => e.errNo != 0,
  ChatroomLlmCardStream e => e.errNo != 0,
  _ => false,
};

String chatroomOperationErrorMessage(Object error) => switch (error) {
  TimeoutException() => 'Request timed out. Please try again.',
  ApiException e when e.kind == ApiExceptionKind.timeout =>
    'Request timed out. Please try again.',
  ApiException e when e.kind == ApiExceptionKind.transport =>
    'Network unavailable. Check your connection and try again.',
  ApiException e => e.message,
  ChatroomFailureEvent e => e.message,
  ChatroomErrorEvent e => e.message,
  ChatroomPayloadEvent e => e.codeMsg,
  ChatroomLlmCardGenerationEnd e => e.errMsg,
  ChatroomLlmCardStream e => e.errMsg,
  StateError e => e.message,
  _ => error.toString(),
};

const Set<String> _passiveChatroomFailureCodes = <String>{
  'connect_failed',
  'event_handle_failed',
  'heartbeat_failed',
  'message_cache_failed',
  'message_cache_load_failed',
  'message_history_load_failed',
  'protocol_error',
  'snapshot_failed',
  'socket_closed',
  'socket_error',
  'stream_missing',
};

const Set<String> _passiveChatroomFailureSourceTypes = <String>{
  'connect',
  'disconnect',
  'heartbeat',
  'socket',
  'socket_closed',
  'socket_error',
};

bool isChatroomUnauthorizedFailure(ChatroomFailureEvent failure) {
  return failure.code.trim() == '10001';
}

bool shouldShowChatroomFailureToast(ChatroomFailureEvent failure) {
  if (_isReplyActionBusinessFailure(failure)) return true;
  if (failure.code.trim() == '3001') return false;

  final requestType = failure.requestType.trim();
  if (_userInitiatedChatroomRequestTypes.contains(requestType)) return true;

  final code = failure.code.trim();
  if (_passiveChatroomFailureCodes.contains(code)) return false;

  final sourceType = failure.sourceType.trim();
  if (_passiveChatroomFailureSourceTypes.contains(sourceType)) return false;

  return true;
}

String chatroomFailureToastMessage(ChatroomFailureEvent failure) {
  final code = failure.code.trim();
  final requestType = failure.requestType.trim();
  if (code == 'ack_timeout' && requestType == 'go_on') {
    return 'Could not confirm Go on. Please try again.';
  }
  if (code != '10001' &&
      _isReplyActionBusinessFailure(failure) &&
      failure.message.trim().isNotEmpty) {
    return failure.message;
  }
  if (code == '1002' || code == '1008') {
    return 'Message format error. Please edit and send again.';
  }
  if (code == '2006') {
    return 'The World is progressing. Please try again shortly.';
  }
  if (code == '2010') {
    return 'Too little time between posts. Ease up and try again shortly.';
  }
  if (code == '10001') {
    return "You've been signed out unexpectedly. Please sign in again.";
  }
  if (code == '5000') {
    return 'Something went wrong. Please try again later.';
  }

  final message = failure.message.trim();
  if (!_isGenericChatroomFailureMessage(message) &&
      !_isInternalChatroomFailureMessage(message)) {
    if (message.isNotEmpty) return message;
  }
  return switch (requestType) {
    'join' => 'Join failed',
    'leave' => 'Leave failed',
    'send_message' => 'Send failed',
    _ => message.isEmpty ? 'Something went wrong' : message,
  };
}

Duration chatroomFailureToastDuration(ChatroomFailureEvent failure) {
  return const <String>{
        '1002',
        '1008',
        '2006',
        '2010',
        '5000',
        '10001',
      }.contains(failure.code.trim())
      ? const Duration(seconds: 4)
      : const Duration(seconds: 2);
}

bool _isGenericChatroomFailureMessage(String message) {
  return message.toLowerCase() == 'something went wrong';
}

bool _isInternalChatroomFailureMessage(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('chatroom ') ||
      normalized.contains(' ack') ||
      normalized.contains('llm') ||
      normalized.contains('stream');
}

StreamSubscription<ChatroomFailureEvent> bindChatroomFailureToast(
  BuildContext context,
  Stream<ChatroomFailureEvent> failures, {
  bool Function(ChatroomFailureEvent failure)? shouldShow,
  void Function(ChatroomFailureEvent failure)? onFailure,
}) {
  // A single WS event can reach the service through both events and failures.
  // Deduplicate by event identity, while allowing identical text on a new try.
  final seen = <Object>[];
  return failures.listen((failure) {
    final identity = failure.cause is ChatroomEvent ? failure.cause! : failure;
    if (seen.any((previous) => identical(previous, identity))) return;
    seen.add(identity);
    if (seen.length > 64) seen.removeAt(0);
    if (!shouldShowChatroomFailureToast(failure)) return;
    if (shouldShow != null && !shouldShow(failure)) return;
    if (context.mounted) {
      showGenesisToast(
        context,
        chatroomFailureToastMessage(failure),
        duration: chatroomFailureToastDuration(failure),
      );
      onFailure?.call(failure);
    }
  });
}

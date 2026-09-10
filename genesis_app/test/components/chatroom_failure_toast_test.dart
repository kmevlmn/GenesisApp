import 'dart:async';

import 'package:flutter/material.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/chat/chatroom_failure_toast.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_models.dart';

void main() {
  group('shouldShowChatroomFailureToast', () {
    test('hides passive websocket disconnect failures', () {
      expect(
        shouldShowChatroomFailureToast(
          const ChatroomFailureEvent(
            code: 'socket_closed',
            message: 'Something went wrong',
            sourceType: 'socket_closed',
          ),
        ),
        isFalse,
      );
      expect(
        shouldShowChatroomFailureToast(
          const ChatroomFailureEvent(
            code: 'socket_error',
            message: 'Something went wrong',
            sourceType: 'socket_error',
            requestType: 'socket',
          ),
        ),
        isFalse,
      );
    });

    test('hides automatic reconnect and heartbeat failures', () {
      expect(
        shouldShowChatroomFailureToast(
          const ChatroomFailureEvent(
            code: 'connect_failed',
            message: 'Failed to connect to chatroom',
            sourceType: 'connect',
            requestType: 'connect',
          ),
        ),
        isFalse,
      );
      expect(
        shouldShowChatroomFailureToast(
          const ChatroomFailureEvent(
            code: 'heartbeat_failed',
            message: 'Something went wrong',
            sourceType: 'heartbeat',
            requestType: 'heartbeat',
          ),
        ),
        isFalse,
      );
    });

    test('hides internal LLM stream ordering failures', () {
      expect(
        shouldShowChatroomFailureToast(
          const ChatroomFailureEvent(
            code: 'stream_missing',
            message: 'Missing LLM stream start for round-1',
            sourceType: 'llm_chunk',
          ),
        ),
        isFalse,
      );
      expect(
        shouldShowChatroomFailureToast(
          const ChatroomFailureEvent(
            code: 'stream_missing',
            message: 'Missing LLM stream start for round-1',
            sourceType: 'llm_stream_end',
          ),
        ),
        isFalse,
      );
    });

    test('hides internal chatroom maintenance failures', () {
      for (final code in <String>[
        'event_handle_failed',
        'message_cache_failed',
        'message_cache_load_failed',
        'message_history_load_failed',
        'protocol_error',
      ]) {
        expect(
          shouldShowChatroomFailureToast(
            ChatroomFailureEvent(
              code: code,
              message: 'Something went wrong',
              sourceType: code,
            ),
          ),
          isFalse,
        );
      }
    });

    test('keeps user initiated operation failures visible', () {
      expect(
        shouldShowChatroomFailureToast(
          const ChatroomFailureEvent(
            code: 'send_message_send_failed',
            message: 'Failed to send chatroom send_message',
            sourceType: 'send_message',
            requestType: 'send_message',
          ),
        ),
        isTrue,
      );
      expect(
        shouldShowChatroomFailureToast(
          const ChatroomFailureEvent(
            code: 'join_failed',
            message: 'Failed to join chatroom',
            sourceType: 'join',
            requestType: 'join',
          ),
        ),
        isTrue,
      );
    });

    test('shows server balance errors for user actions', () {
      expect(
        shouldShowChatroomFailureToast(
          const ChatroomFailureEvent(
            code: '3001',
            message: 'Insufficient balance',
            sourceType: 'ack',
            requestType: 'send_message',
          ),
        ),
        isTrue,
      );
    });
  });

  group('chatroomFailureToastMessage', () {
    test('maps internal protocol messages to user facing copy', () {
      expect(
        chatroomFailureToastMessage(
          const ChatroomFailureEvent(
            code: 'send_message_send_failed',
            message: 'Failed to send chatroom send_message',
            sourceType: 'send_message',
            requestType: 'send_message',
          ),
        ),
        'Send failed',
      );
      expect(
        chatroomFailureToastMessage(
          const ChatroomFailureEvent(
            code: 'ack_timeout',
            message: 'Timed out waiting for go_on ack',
            sourceType: 'ack',
            requestType: 'go_on',
          ),
        ),
        'Could not confirm Go on. Please try again.',
      );
      expect(
        chatroomFailureToastMessage(
          const ChatroomFailureEvent(
            code: 'ack_timeout',
            message: 'Timed out waiting for send_message ack',
            sourceType: 'ack',
            requestType: 'send_message',
          ),
        ),
        'Send failed',
      );
      expect(
        chatroomFailureToastMessage(
          const ChatroomFailureEvent(
            code: 'join_failed',
            message: 'Something went wrong',
            sourceType: 'join',
            requestType: 'join',
          ),
        ),
        'Join failed',
      );
    });

    test('keeps server provided user facing messages', () {
      expect(
        chatroomFailureToastMessage(
          const ChatroomFailureEvent(
            code: 'muted',
            message: 'You cannot send messages right now',
            sourceType: 'ack',
            requestType: 'send_message',
          ),
        ),
        'You cannot send messages right now',
      );
    });

    test('preserves rate limit err_msg', () {
      expect(
        chatroomFailureToastMessage(
          const ChatroomFailureEvent(
            code: '2010',
            message: 'Rate limit exceeded',
            sourceType: 'ack',
            requestType: 'send_message',
          ),
        ),
        'Rate limit exceeded',
      );
    });

    test('preserves world progress err_msg', () {
      expect(
        chatroomFailureToastMessage(
          const ChatroomFailureEvent(
            code: '2006',
            message: 'World is progressing',
            sourceType: 'ack',
            requestType: 'send_message',
          ),
        ),
        'World is progressing',
      );
    });

    test('preserves temporary server failure err_msg', () {
      expect(
        chatroomFailureToastMessage(
          const ChatroomFailureEvent(
            code: '5000',
            message: 'Service unavailable',
            sourceType: 'ack',
            requestType: 'send_message',
          ),
        ),
        'Service unavailable',
      );
    });

    test('maps unauthorized ack to sign-in copy', () {
      expect(
        chatroomFailureToastMessage(
          const ChatroomFailureEvent(
            code: '10001',
            message: 'Unauthorized',
            sourceType: 'ack',
            requestType: 'send_message',
          ),
        ),
        "You've been signed out unexpectedly. Please sign in again.",
      );
    });

    test('preserves message format err_msg', () {
      for (final code in <String>['1002', '1008']) {
        expect(
          chatroomFailureToastMessage(
            ChatroomFailureEvent(
              code: code,
              message: 'Message format error',
              sourceType: 'ack',
              requestType: 'send_message',
            ),
          ),
          'Message format error',
        );
      }
    });
  });

  test('all reply action business codes preserve server err_msg', () {
    for (final type in [
      'regenerate_llm_card',
      'go_on',
      'select_llm_card',
      'send_message',
      'end_conversation_round',
      'llm_card_generation_end',
      'llm_card_stream',
    ]) {
      for (final code in [
        '1002',
        '1008',
        '2006',
        '2010',
        '2012',
        '2023',
        '3001',
        '5000',
        '98765',
      ]) {
        final failure = ChatroomFailureEvent(
          code: code,
          message: '服务端 llm 错误 $code',
          requestType: type,
          sourceType: type,
        );
        expect(shouldShowChatroomFailureToast(failure), isTrue);
        expect(chatroomFailureToastMessage(failure), failure.message);
      }
    }
  });

  test('global errors are not presented again by reply futures or editors', () {
    for (final code in [2012, 3001, 10001]) {
      final http = ApiException(
        message: 'server $code',
        code: code,
        kind: ApiExceptionKind.business,
      );
      final ws = ChatroomFailureEvent(code: '$code', message: 'server $code');
      final event = ChatroomErrorEvent(code: '$code', message: 'server $code');
      for (final error in [http, ws, event]) {
        expect(isChatroomErrorPresentedGlobally(error), isTrue);
        expect(chatroomOperationErrorMessage(error), 'server $code');
      }
    }
    final local = ApiException(
      message: 'Request failed',
      kind: ApiExceptionKind.transport,
    );
    expect(isChatroomErrorPresentedGlobally(local), isFalse);
    expect(
      chatroomOperationErrorMessage(local),
      'Network unavailable. Check your connection and try again.',
    );
    expect(
      chatroomOperationErrorMessage(
        ApiException(message: 'Request failed', kind: ApiExceptionKind.timeout),
      ),
      'Request timed out. Please try again.',
    );
    expect(
      chatroomOperationErrorMessage(TimeoutException('late')),
      'Request timed out. Please try again.',
    );
  });

  testWidgets(
    'WS err_msg is centered once per event, with new retries visible',
    (tester) async {
      final failures = StreamController<ChatroomFailureEvent>();
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold();
            },
          ),
        ),
      );
      var shown = 0;
      final subscription = bindChatroomFailureToast(
        context,
        failures.stream,
        onFailure: (_) => shown++,
      );
      addTearDown(subscription.cancel);
      addTearDown(failures.close);
      final cause = ChatroomErrorEvent(code: '2010', message: '服务端原始提示');
      failures.add(ChatroomFailureEvent.fromError(cause, requestType: 'go_on'));
      failures.add(ChatroomFailureEvent.fromError(cause, requestType: 'go_on'));
      await tester.pump();
      expect(shown, 1);
      final toast = find.text('服务端原始提示');
      expect(toast, findsOneWidget);
      expect(tester.getCenter(toast), tester.getCenter(find.byType(Scaffold)));
      failures.add(
        ChatroomFailureEvent.fromError(
          ChatroomErrorEvent(code: '2010', message: '服务端原始提示'),
          requestType: 'go_on',
        ),
      );
      await tester.pump();
      expect(shown, 2);
      await tester.pump(const Duration(seconds: 4));
      expect(toast, findsNothing);
    },
  );

  group('chatroomFailureToastDuration', () {
    test('keeps rate limit toast visible for four seconds', () {
      expect(
        chatroomFailureToastDuration(
          const ChatroomFailureEvent(
            code: '2010',
            message: 'Rate limit exceeded',
            sourceType: 'ack',
            requestType: 'send_message',
          ),
        ),
        const Duration(seconds: 4),
      );
    });

    test('keeps world progress toast visible for four seconds', () {
      expect(
        chatroomFailureToastDuration(
          const ChatroomFailureEvent(
            code: '2006',
            message: 'World is progressing',
            sourceType: 'ack',
            requestType: 'send_message',
          ),
        ),
        const Duration(seconds: 4),
      );
    });

    test('keeps temporary server failure toast visible for four seconds', () {
      for (final code in <String>['5000', '10001']) {
        expect(
          chatroomFailureToastDuration(
            ChatroomFailureEvent(
              code: code,
              message: 'Service unavailable',
              sourceType: 'ack',
              requestType: 'send_message',
            ),
          ),
          const Duration(seconds: 4),
        );
      }
    });

    test('keeps message format toast visible for four seconds', () {
      for (final code in <String>['1002', '1008']) {
        expect(
          chatroomFailureToastDuration(
            ChatroomFailureEvent(
              code: code,
              message: 'Message format error',
              sourceType: 'ack',
              requestType: 'send_message',
            ),
          ),
          const Duration(seconds: 4),
        );
      }
    });

    test('keeps the default duration for other failures', () {
      expect(
        chatroomFailureToastDuration(
          const ChatroomFailureEvent(
            code: 'send_failed',
            message: 'Send failed',
            requestType: 'send_message',
          ),
        ),
        const Duration(seconds: 2),
      );
    });
  });
}

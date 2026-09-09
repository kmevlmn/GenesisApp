import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/websocket_capture.dart';
import 'package:genesis_flutter_android/network/devtools_websocket_profile.dart';
import 'package:genesis_flutter_android/network/websocket_transport.dart';
import 'package:http_profile/http_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'transport records SEND and RECV without changing socket messages',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final serverReceived = Completer<String>();
      final serverTask = server.first.then((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.add('{"type":"character","stream_type":"llm_chunk"}');
        final message = await socket.first;
        serverReceived.complete(message as String);
        await socket.close();
      });
      final controller = WebSocketCaptureController(
        notificationBatchDuration: Duration.zero,
      );
      await controller.setEnabled(true);
      final transport = IoWebSocketTransport(
        logFrames: false,
        captureController: controller,
      );
      final socket = await transport.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/chat?token=hidden'),
      );

      final received = await socket.messages.first;
      await socket.send('{"type":"send_message","client_message_id":"c_1"}');

      expect(received, contains('llm_chunk'));
      expect(await serverReceived.future, contains('send_message'));
      await serverTask;
      expect(controller.records, hasLength(2));
      expect(
        controller.records.map((record) => record.direction),
        containsAll(<WebSocketCaptureDirection>[
          WebSocketCaptureDirection.receive,
          WebSocketCaptureDirection.send,
        ]),
      );
      expect(
        controller.records.first.connectionId,
        controller.records.last.connectionId,
      );
      expect(controller.records.map((record) => record.sequence).toSet(), <int>{
        1,
        2,
      });
    },
  );

  for (final logFrames in [false, true]) {
    test(
      'DevTools groups regeneration frames with logFrames=$logFrames',
      () async {
        final previousProfiling = HttpClientRequestProfile.profilingEnabled;
        HttpClientRequestProfile.profilingEnabled = true;
        addTearDown(
          () => HttpClientRequestProfile.profilingEnabled = previousProfiling,
        );
        final profiles = <HttpClientRequestProfile>[];
        final recorded = Completer<void>();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        final requestBody = jsonEncode({
          'type': 'regenerate_llm_card',
          'client_msg_id': 'regen-1',
        });
        final frames = [
          for (final phase in ['start', 'chunk', 'end'])
            jsonEncode({
              'type': 'llm_card_stream',
              'stream_type': phase,
              'world_id': 'test',
              'location_id': 'loc-1',
              'conversation_round_id': 10,
              'global_message_id': 100,
              'sender_id': 'character-1',
              'payload': {
                'card_id': 20,
                'content': phase == 'start' ? '' : '新的分片',
              },
            }),
          jsonEncode({
            'type': 'llm_card_generation_end',
            'payload': {'content': '完成'},
          }),
        ];
        final serverTask = server.first.then((request) async {
          final socket = await WebSocketTransformer.upgrade(request);
          expect(await socket.first, requestBody);
          for (final frame in frames) {
            socket.add(frame);
          }
          await socket.close();
        });
        final transport = IoWebSocketTransport(
          logFrames: logFrames,
          frameLogSink: (_, _) => throw StateError('broken diagnostic sink'),
          frameProfileFactory: (uri) => DevToolsWebSocketProfile(
            uri,
            profileFactory:
                ({
                  required requestStartTime,
                  required requestMethod,
                  required requestUri,
                }) {
                  final profile = HttpClientRequestProfile.profile(
                    requestStartTime: requestStartTime,
                    requestMethod: requestMethod,
                    requestUri: requestUri,
                  )!;
                  profiles.add(profile);
                  unawaited(
                    profile.responseData.bodySink.done.then((_) {
                      if (profiles.length == 3 && !recorded.isCompleted) {
                        recorded.complete();
                      }
                    }),
                  );
                  return profile;
                },
          ),
        );
        final socket = await transport.connect(
          Uri.parse(
            'ws://127.0.0.1:${server.port}/aitown-chat/ws?world_id=test',
          ),
        );
        addTearDown(socket.close);
        final received = socket.messages.toList();
        await socket.send(requestBody);
        expect(await received, frames);
        await serverTask;
        await recorded.future.timeout(const Duration(seconds: 5));
        expect(profiles.map((profile) => profile.requestMethod), [
          'WS_SEND',
          'WS_RECV',
          'WS_RECV',
        ]);
        expect(utf8.decode(profiles.first.requestData.bodyBytes), requestBody);
        expect(
          const LineSplitter().convert(
            utf8.decode(profiles[1].responseData.bodyBytes),
          ),
          frames.take(3).toList(),
        );
        expect(profiles[1].responseData.endTime, isNotNull);
        expect(utf8.decode(profiles[2].responseData.bodyBytes), frames.last);
        expect(profiles[1].requestUri, contains('type=llm_card_stream'));
        expect(
          profiles[2].requestUri,
          contains('type=llm_card_generation_end'),
        );
      },
    );
  }
}

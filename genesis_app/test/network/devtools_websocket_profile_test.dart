import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/devtools_websocket_profile.dart';
import 'package:http_profile/http_profile.dart';

void main() {
  late bool previousProfilingState;

  setUp(() {
    previousProfilingState = HttpClientRequestProfile.profilingEnabled;
    HttpClientRequestProfile.profilingEnabled = true;
  });

  tearDown(() {
    HttpClientRequestProfile.profilingEnabled = previousProfilingState;
  });

  test('records outgoing JSON as a synthetic WS_SEND request', () async {
    late HttpClientRequestProfile capturedProfile;
    final recorder = DevToolsWebSocketProfile(
      Uri.parse(
        'wss://user:password@api.worldo.ai/aitown-chat/ws'
        '?world_id=world-1&token=secret-token',
      ),
      connectionId: 'ws-test',
      profileFactory:
          ({
            required requestStartTime,
            required requestMethod,
            required requestUri,
          }) {
            capturedProfile = HttpClientRequestProfile.profile(
              requestStartTime: requestStartTime,
              requestMethod: requestMethod,
              requestUri: requestUri,
            )!;
            return capturedProfile;
          },
    );

    await recorder.recordFrame(
      direction: '=>',
      message: jsonEncode({
        'type': 'send_message',
        'token': 'frame-secret',
        'payload': {
          'authorization': 'Bearer nested-secret',
          'content': 'hello',
        },
      }),
    );

    expect(capturedProfile.requestMethod, 'WS_SEND');
    final recordedUri = Uri.parse(capturedProfile.requestUri);
    expect(recordedUri.userInfo, isEmpty);
    expect(recordedUri.queryParameters['world_id'], 'world-1');
    expect(recordedUri.queryParameters['token'], '[REDACTED]');
    expect(Uri.splitQueryString(recordedUri.fragment), {
      'type': 'send_message',
      'connection': 'ws-test',
      'frame': '1',
    });
    expect(
      capturedProfile.requestData.headers,
      containsPair('x-genesis-devtools-synthetic', ['websocket-frame']),
    );
    expect(
      capturedProfile.requestData.headers,
      containsPair('x-genesis-websocket-direction', ['send']),
    );
    final requestJson =
        jsonDecode(utf8.decode(capturedProfile.requestData.bodyBytes))
            as Map<String, dynamic>;
    expect(requestJson['token'], '[REDACTED]');
    expect(
      (requestJson['payload'] as Map<String, dynamic>)['authorization'],
      '[REDACTED]',
    );
    expect(
      (requestJson['payload'] as Map<String, dynamic>)['content'],
      'hello',
    );
    expect(capturedProfile.responseData.statusCode, 200);
    expect(capturedProfile.responseData.bodyBytes, isEmpty);
    expect(capturedProfile.responseData.headers!['content-type'], [
      'application/json; charset=utf-8',
    ]);
    expect(capturedProfile.connectionInfo, {
      'transport': 'websocket',
      'connectionId': 'ws-test',
      'direction': 'send',
      'sequence': 1,
    });
  });

  test(
    'recording can resume on the same connection after being disabled',
    () async {
      final profiles = <HttpClientRequestProfile>[];
      final recorder = DevToolsWebSocketProfile(
        Uri.parse('wss://api.worldo.ai/aitown-chat/ws'),
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
              return profile;
            },
      );
      HttpClientRequestProfile.profilingEnabled = false;
      for (var i = 0; i < 1005; i++) {
        await recorder.recordFrame(
          direction: '<=',
          message: '{"type":"heartbeat"}',
        );
      }
      expect(profiles, isEmpty);
      HttpClientRequestProfile.profilingEnabled = true;
      await recorder.recordFrame(
        direction: '<=',
        message: '{"type":"llm_card_stream"}',
      );
      expect(profiles, hasLength(1));
      expect(profiles.single.requestUri, contains('type=llm_card_stream'));
    },
  );

  test('records incoming JSON in the synthetic response body', () async {
    late HttpClientRequestProfile capturedProfile;
    final recorder = DevToolsWebSocketProfile(
      Uri.parse('wss://api.worldo.ai/aitown-chat/ws?world_id=world-1'),
      connectionId: 'ws-test',
      profileFactory:
          ({
            required requestStartTime,
            required requestMethod,
            required requestUri,
          }) {
            capturedProfile = HttpClientRequestProfile.profile(
              requestStartTime: requestStartTime,
              requestMethod: requestMethod,
              requestUri: requestUri,
            )!;
            return capturedProfile;
          },
    );

    await recorder.recordFrame(
      direction: '<=',
      message:
          '{"type":"ack","global_msg_id":901,"msg_id":501,'
          '"location_msg_id":201,"err_no":0}',
    );

    expect(capturedProfile.requestMethod, 'WS_RECV');
    expect(
      Uri.splitQueryString(Uri.parse(capturedProfile.requestUri).fragment),
      {
        'type': 'ack',
        'global_msg_id': '901',
        'msg_id': '501',
        'location_msg_id': '201',
        'connection': 'ws-test',
        'frame': '1',
      },
    );
    expect(capturedProfile.requestData.bodyBytes, isEmpty);
    expect(
      utf8.decode(capturedProfile.responseData.bodyBytes),
      '{"type":"ack","global_msg_id":901,"msg_id":501,'
      '"location_msg_id":201,"err_no":0}',
    );
    expect(
      capturedProfile.responseData.headers,
      containsPair('x-genesis-websocket-global-msg-id', ['901']),
    );
    expect(
      capturedProfile.responseData.headers,
      containsPair('content-type', ['application/json; charset=utf-8']),
    );
    expect(capturedProfile.connectionInfo?['direction'], 'receive');
  });

  test('profiles V2 full message ids ahead of legacy aliases', () async {
    late HttpClientRequestProfile capturedProfile;
    final recorder = DevToolsWebSocketProfile(
      Uri.parse('wss://api.worldo.ai/aitown-chat/ws?world_id=world-1'),
      connectionId: 'ws-v2',
      profileFactory:
          ({
            required requestStartTime,
            required requestMethod,
            required requestUri,
          }) {
            capturedProfile = HttpClientRequestProfile.profile(
              requestStartTime: requestStartTime,
              requestMethod: requestMethod,
              requestUri: requestUri,
            )!;
            return capturedProfile;
          },
    );

    await recorder.recordFrame(
      direction: '<=',
      message: jsonEncode({
        'type': 'tick',
        'stream_type': '',
        'global_message_id': 90003,
        'message_id': 503,
        'location_message_id': 203,
        // Conflicting aliases must not override the canonical V2 fields.
        'global_msg_id': 1,
        'msg_id': 2,
        'location_msg_id': 3,
        'payload': {'content': 'Time advances'},
        'err_no': 0,
        'err_msg': '',
      }),
    );

    expect(
      Uri.splitQueryString(Uri.parse(capturedProfile.requestUri).fragment),
      {
        'type': 'tick',
        'global_msg_id': '90003',
        'msg_id': '503',
        'location_msg_id': '203',
        'connection': 'ws-v2',
        'frame': '1',
      },
    );
    expect(
      capturedProfile.responseData.headers,
      containsPair('x-genesis-websocket-global-msg-id', ['90003']),
    );
    expect(
      capturedProfile.responseData.headers,
      containsPair('x-genesis-websocket-msg-id', ['503']),
    );
    expect(
      capturedProfile.responseData.headers,
      containsPair('x-genesis-websocket-location-msg-id', ['203']),
    );
  });

  test('increments frame sequence and truncates oversized payloads', () async {
    final capturedProfiles = <HttpClientRequestProfile>[];
    final recorder = DevToolsWebSocketProfile(
      Uri.parse('wss://api.worldo.ai/aitown-chat/ws'),
      connectionId: 'ws-test',
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
            capturedProfiles.add(profile);
            return profile;
          },
    );

    await recorder.recordFrame(direction: '=>', message: 'first');
    await recorder.recordFrame(
      direction: '<=',
      message: 'x' * (kDevToolsWebSocketProfileMaxBodyBytes + 100),
    );

    expect(
      Uri.splitQueryString(Uri.parse(capturedProfiles[0].requestUri).fragment),
      {'connection': 'ws-test', 'frame': '1'},
    );
    expect(
      Uri.splitQueryString(Uri.parse(capturedProfiles[1].requestUri).fragment),
      {'connection': 'ws-test', 'frame': '2'},
    );
    final body = capturedProfiles[1].responseData.bodyBytes;
    expect(
      body.length,
      lessThanOrEqualTo(kDevToolsWebSocketProfileMaxBodyBytes),
    );
    expect(utf8.decode(body), contains('...[truncated'));
    expect(
      capturedProfiles[1].responseData.headers,
      containsPair('content-type', ['text/plain; charset=utf-8']),
    );
  });

  test(
    'retains stream metadata and redacts oversized JSON before truncation',
    () async {
      late HttpClientRequestProfile capturedProfile;
      final recorder = DevToolsWebSocketProfile(
        Uri.parse('wss://api.worldo.ai/aitown-chat/ws'),
        profileFactory:
            ({
              required requestStartTime,
              required requestMethod,
              required requestUri,
            }) {
              capturedProfile = HttpClientRequestProfile.profile(
                requestStartTime: requestStartTime,
                requestMethod: requestMethod,
                requestUri: requestUri,
              )!;
              return capturedProfile;
            },
      );

      await recorder.recordFrame(
        direction: '<=',
        message: jsonEncode({
          'token': 'secret-before-content',
          'payload': {'content': '你' * 22000},
          'type': 'llm_card_generation_end',
          'global_message_id': 9007199254740993,
        }),
      );

      expect(
        utf8.decode(capturedProfile.responseData.bodyBytes),
        contains('...[truncated'),
      );
      expect(
        Uri.parse(capturedProfile.requestUri).fragment,
        contains('type=llm_card_generation_end'),
      );
      expect(
        Uri.parse(capturedProfile.requestUri).fragment,
        contains('global_msg_id=9007199254740993'),
      );
      final body = utf8.decode(capturedProfile.responseData.bodyBytes);
      expect(body, contains('你'));
      expect(body, isNot(contains('secret-before-content')));
      expect(
        capturedProfile.responseData.bodyBytes.length,
        lessThanOrEqualTo(kDevToolsWebSocketProfileMaxBodyBytes),
      );
      expect(
        capturedProfile.responseData.headers,
        containsPair('content-type', ['text/plain; charset=utf-8']),
      );
    },
  );

  test('records regeneration after more than 1000 heartbeat frames', () async {
    final profiles = <HttpClientRequestProfile>[];
    final recorder = DevToolsWebSocketProfile(
      Uri.parse('wss://api.worldo.ai/aitown-chat/ws'),
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
            return profile;
          },
    );

    for (var index = 0; index < 1005; index += 1) {
      await recorder.recordFrame(
        direction: '=>',
        message: '{"type":"heartbeat"}',
      );
    }
    for (final type in [
      'regenerate_llm_card',
      'llm_card_stream',
      'llm_card_generation_end',
    ]) {
      await recorder.recordFrame(
        direction: type == 'regenerate_llm_card' ? '=>' : '<=',
        message: jsonEncode({
          'type': type,
          'payload': {'content': '新正文'},
        }),
      );
    }
    expect(profiles, hasLength(1008));
    expect(profiles.last.requestUri, contains('type=llm_card_generation_end'));
    expect(utf8.decode(profiles.last.responseData.bodyBytes), contains('新正文'));
  });
}

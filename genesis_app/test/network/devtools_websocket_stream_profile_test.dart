import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/devtools_websocket_profile.dart';
import 'package:http_profile/http_profile.dart';

void main() {
  late bool previousProfiling;
  late List<HttpClientRequestProfile> profiles;
  late DevToolsWebSocketProfile recorder;

  setUp(() {
    previousProfiling = HttpClientRequestProfile.profilingEnabled;
    HttpClientRequestProfile.profilingEnabled = true;
    profiles = [];
    recorder = DevToolsWebSocketProfile(
      Uri.parse('wss://api.worldo.ai/ws?token=secret'),
      streamIdleTimeout: const Duration(milliseconds: 100),
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
  });

  tearDown(() async {
    await recorder.close();
    HttpClientRequestProfile.profilingEnabled = previousProfiling;
  });

  Future<void> receive(Map<String, Object?> frame) =>
      recorder.recordFrame(direction: '<=', message: jsonEncode(frame));

  List<Map<String, dynamic>> body(HttpClientRequestProfile profile) =>
      const LineSplitter()
          .convert(utf8.decode(profile.responseData.bodyBytes))
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();

  for (final protocol in ['v2', 'legacy', 'card']) {
    test('$protocol streams use one live record through end', () async {
      await receive(_frame('start', protocol: protocol));
      expect(profiles, hasLength(1));
      final profile = profiles.single;
      expect(profile.responseData.endTime, isNull);
      await receive(_frame('chunk', protocol: protocol, content: 'Hello'));
      await Future<void>.delayed(Duration.zero);
      expect(profiles, hasLength(1));
      expect(body(profile).last['payload']['content'], 'Hello');
      expect(profile.responseData.endTime, isNull);
      await receive(_frame('end', protocol: protocol, content: 'Hello world'));
      expect(profiles, hasLength(1));
      expect(profile.responseData.endTime, isNotNull);
      expect(body(profile), hasLength(3));
      expect(body(profile).last['payload']['content'], 'Hello world');
      expect(profile.responseData.headers!['x-genesis-websocket-frame-count'], [
        '3',
      ]);
      expect(profile.responseData.headers!['content-type'], [
        'application/x-ndjson; charset=utf-8',
      ]);
      expect(profile.requestUri, isNot(contains('secret')));
      expect(profile.requestMethod, 'WS_RECV');
    });
  }

  test(
    'interleaved senders and rounds stay separate with missing message IDs',
    () async {
      await receive(_frame('start', sender: 'a', round: 1));
      await receive(_frame('start', sender: 'b', round: 1));
      await receive(_frame('start', sender: 'a', round: 2));
      await receive(_frame('chunk', sender: 'b', round: 1, content: 'B'));
      await receive(_frame('end', sender: 'a', round: 2, content: 'A2'));
      await receive(_frame('end', sender: 'b', round: 1, content: 'B'));
      await receive(_frame('end', sender: 'a', round: 1, content: 'A1'));
      expect(profiles, hasLength(3));
      expect(profiles.map((p) => body(p).last['payload']['content']), [
        'A1',
        'B',
        'A2',
      ]);
    },
  );

  test(
    'card and message IDs separate concurrent regenerated candidates',
    () async {
      await receive(_frame('start', protocol: 'card', card: 10, globalId: 100));
      await receive(_frame('start', protocol: 'card', card: 11, globalId: 101));
      await receive(
        _frame(
          'end',
          protocol: 'card',
          card: 11,
          globalId: 101,
          content: 'second',
        ),
      );
      await receive(
        _frame(
          'end',
          protocol: 'card',
          card: 10,
          globalId: 100,
          content: 'first',
        ),
      );
      expect(profiles, hasLength(2));
      expect(profiles.map((p) => body(p).last['payload']['content']), [
        'first',
        'second',
      ]);
    },
  );

  test(
    'ambiguous frames stay individual and do not contaminate active streams',
    () async {
      await receive(_frame('start', sender: 'a'));
      await receive(_frame('start', sender: 'b'));
      final ambiguous = _frame('chunk', content: 'unknown')
        ..remove('sender_id');
      await receive(ambiguous);
      await receive(_frame('end', sender: 'a', content: 'A'));
      await receive(_frame('end', sender: 'b', content: 'B'));
      expect(profiles, hasLength(3));
      expect(body(profiles.first), hasLength(2));
      expect(body(profiles[1]), hasLength(2));
      expect(
        jsonDecode(
          utf8.decode(profiles[2].responseData.bodyBytes),
        )['payload']['content'],
        'unknown',
      );
    },
  );

  test(
    'recording midway groups chunks and retains ordinary ACK records',
    () async {
      await receive(_frame('chunk', content: 'partial'));
      await receive({'type': 'ack', 'client_msg_id': 'business'});
      await receive(_frame('end', content: 'full'));
      expect(profiles, hasLength(2));
      expect(body(profiles.first), hasLength(2));
      expect(profiles.last.requestUri, contains('type=ack'));
    },
  );

  test('errors, disconnect and timeout finish partial records', () async {
    await receive(_frame('start', sender: 'error'));
    await receive(_frame('chunk', sender: 'error')..['err_no'] = 500);
    expect(profiles.first.responseData.error, 'WebSocket stream error');
    await receive(_frame('start', sender: 'timeout'));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(profiles[1].responseData.error, 'WebSocket stream timed out');
    await receive(_frame('start', sender: 'closed'));
    await recorder.close();
    expect(profiles.last.responseData.error, contains('closed'));
    expect(profiles.every((p) => p.responseData.endTime != null), isTrue);
  });

  test(
    'pause closes the old stream and resume starts a partial record',
    () async {
      await receive(_frame('start'));
      HttpClientRequestProfile.profilingEnabled = false;
      await receive({'type': 'heartbeat'});
      expect(profiles.single.responseData.error, 'DevTools recording paused');
      await receive(_frame('chunk', content: 'not recorded'));
      HttpClientRequestProfile.profilingEnabled = true;
      await receive(_frame('end', content: 'final'));
      expect(profiles, hasLength(2));
      expect(body(profiles.last).single['payload']['content'], 'final');
    },
  );

  test(
    'one bounded redacted body survives many chunks and oversized content',
    () async {
      await receive(_frame('start'));
      for (var i = 0; i < 100; i++) {
        await receive(
          _frame('chunk', content: '你' * 300)..['token'] = 'secret-value',
        );
      }
      await receive(_frame('end', content: '你' * 30000));
      expect(profiles, hasLength(1));
      final profile = profiles.single;
      final content = utf8.decode(profile.responseData.bodyBytes);
      expect(content, contains('stream body truncated'));
      expect(content, isNot(contains('secret-value')));
      expect(
        profile.responseData.bodyBytes.length,
        lessThanOrEqualTo(kDevToolsWebSocketProfileMaxBodyBytes),
      );
      expect(profile.responseData.headers!['x-genesis-websocket-frame-count'], [
        '102',
      ]);
      expect(profile.responseData.endTime, isNotNull);
    },
  );
}

Map<String, Object?> _frame(
  String phase, {
  String protocol = 'v2',
  String sender = 'alice',
  int round = 1,
  int card = 10,
  int globalId = 100,
  String content = '',
}) {
  final streamType = switch (phase) {
    'start' => 'llm_stream_start',
    'end' => 'llm_stream_end',
    _ => 'llm_chunk',
  };
  return {
    'type': switch (protocol) {
      'legacy' => streamType,
      'card' => 'llm_card_stream',
      _ => 'character',
    },
    if (protocol != 'legacy')
      'stream_type': protocol == 'card' ? phase : streamType,
    'world_id': 'world',
    'location_id': 'location',
    'conversation_round_id': round,
    if (protocol != 'legacy') 'sender_id': sender,
    if (protocol == 'card') 'global_message_id': globalId,
    'payload': {
      if (protocol == 'legacy') 'sender_id': sender,
      if (protocol == 'card') 'card_id': card,
      'content': content,
      if (phase == 'chunk') 'seq': 1,
    },
    'err_no': 0,
  };
}

part of 'devtools_websocket_profile.dart';

class _WebSocketStreamFrame {
  _WebSocketStreamFrame(this.json, this.family, this.phase, this.identity);

  final Map<dynamic, dynamic> json;
  final String family;
  final String phase;
  final Map<String, String> identity;

  bool get isEnd => phase == 'end';
  bool get hasError => json['err_no'] is num && (json['err_no'] as num) != 0;

  bool get hasStableIdentity =>
      identity.containsKey('global_message_id') ||
      (identity.containsKey('world_id') &&
          identity.containsKey('message_id')) ||
      (identity.containsKey('world_id') &&
          identity.containsKey('location_id') &&
          identity.containsKey('conversation_round_id') &&
          identity.containsKey('sender_id'));

  static _WebSocketStreamFrame? parse(Map<dynamic, dynamic> json) {
    final type = _profileField(json, 'type');
    final streamType = _profileField(json, 'stream_type');
    final family = type == 'llm_card_stream' ? 'card' : 'reply';
    final phase = family == 'card'
        ? switch (streamType) {
            'start' || 'chunk' || 'end' => streamType,
            _ => null,
          }
        : switch (streamType ?? type) {
            'llm_stream_start' => 'start',
            'llm_chunk' => 'chunk',
            'llm_stream_end' => 'end',
            _ => null,
          };
    if (phase == null) return null;
    final payload = json['payload'];
    String? field(String key) => json.containsKey(key)
        ? _profileField(json, key)
        : payload is Map
        ? _profileField(payload, key)
        : null;
    final identity = <String, String>{'family': family};
    for (final key in [
      'world_id',
      'location_id',
      'session_id',
      'conversation_round_id',
      'sender_id',
      'sender_type',
      if (family == 'card') ...['card_id', 'card_message_index'],
    ]) {
      final value = field(key);
      if (value != null && value != '0') identity[key] = value;
    }
    for (final (full, legacy) in [
      ('global_message_id', 'global_msg_id'),
      ('message_id', 'msg_id'),
      ('location_message_id', 'location_msg_id'),
    ]) {
      final value = _profileIdField(json, fullName: full, legacyName: legacy);
      if (value != null && (int.tryParse(value) ?? 0) > 0) {
        identity[full] = value;
      }
    }
    // V2 places the sender category in type; legacy frames use sender_type.
    if (family == 'reply' && (type == 'character' || type == 'narrator')) {
      identity.putIfAbsent('sender_type', () => type!);
    }
    return _WebSocketStreamFrame(json, family, phase, identity);
  }

  int matchScore(Map<String, String> other) {
    var score = 0;
    for (final entry in identity.entries) {
      final value = other[entry.key];
      if (value == null) continue;
      if (value != entry.value) return -1;
      score += switch (entry.key) {
        'global_message_id' => 128,
        'conversation_round_id' || 'card_id' => 64,
        'sender_id' => 32,
        'family' || 'sender_type' => 0,
        _ => 8,
      };
    }
    return score;
  }
}

class _WebSocketStreamProfile {
  _WebSocketStreamProfile(
    this.profile,
    Map<String, String> identity,
    this.headers,
  ) : identity = Map.of(identity) {
    final request = profile.requestData;
    request.followRedirects = false;
    request.persistentConnection = true;
    request.headersCommaValues = headers;
    request.contentLength = 0;
    _requestClosed = request.close().catchError((Object _) {});
    final response = profile.responseData;
    response.startTime = DateTime.now();
    response.statusCode = 200;
    response.persistentConnection = true;
    response.isRedirect = false;
    response.headersCommaValues = headers;
    profile.addEvent(
      HttpProfileRequestEvent(
        timestamp: DateTime.now(),
        name: 'WebSocket stream started',
      ),
    );
  }

  final HttpClientRequestProfile profile;
  final Map<String, String> identity;
  final Map<String, String> headers;
  late final Future<void> _requestClosed;
  Timer? idleTimer;
  int _frameCount = 0;
  int _byteCount = 0;
  bool _truncated = false;
  Future<void>? _closing;

  void append(_WebSocketStreamFrame frame) {
    identity.addAll(frame.identity);
    _frameCount++;
    if (!_truncated) {
      final line = '${jsonEncode(_redactJson(frame.json))}\n';
      final bytes = utf8.encode(line);
      final remaining = kDevToolsWebSocketProfileMaxBodyBytes - _byteCount;
      // Keep room for a truncation marker; never split a UTF-8 character.
      if (bytes.length > remaining - 128) {
        final preview = _truncateUtf8(line, maxBytes: remaining - 64);
        final marker = utf8.encode('\n...[stream body truncated]\n');
        profile.responseData.bodySink.add([...preview, ...marker]);
        _byteCount += preview.length + marker.length;
        _truncated = true;
        headers['content-type'] = 'text/plain; charset=utf-8';
      } else {
        profile.responseData.bodySink.add(bytes);
        _byteCount += bytes.length;
      }
    }
    profile.responseData.headersCommaValues = {
      ...headers,
      'x-genesis-websocket-frame-count': '$_frameCount',
      if (_truncated) 'x-genesis-websocket-body-truncated': 'true',
    };
  }

  Future<void> close([String? error]) => _closing ??= _finish(error);

  Future<void> _finish(String? error) async {
    idleTimer?.cancel();
    try {
      profile.responseData.contentLength = _byteCount;
      profile.addEvent(
        HttpProfileRequestEvent(
          timestamp: DateTime.now(),
          name: error ?? 'WebSocket stream ended',
        ),
      );
      await _requestClosed;
      if (error == null) {
        await profile.responseData.close();
      } else {
        await profile.responseData.closeWithError(error);
      }
    } catch (_) {
      // Diagnostics must not affect the socket or leak asynchronous errors.
    }
  }
}

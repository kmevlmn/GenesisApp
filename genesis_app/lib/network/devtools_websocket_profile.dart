import 'dart:convert';

import 'package:http_profile/http_profile.dart';

import 'devtools_http_profile.dart';

const kDevToolsWebSocketProfileMaxBodyBytes = 64 * 1024;

const _redactedValue = '[REDACTED]';
const _sensitiveFieldNames = <String>{
  'api_key',
  'apikey',
  'authorization',
  'cookie',
  'password',
  'refresh_token',
  'secret',
  'set-cookie',
  'signature',
  'token',
  'x-signature',
};

class DevToolsWebSocketProfile {
  DevToolsWebSocketProfile(
    this._uri, {
    GenesisHttpProfileFactory profileFactory = _createWebSocketProfile,
    String? connectionId,
  }) : _profileFactory = profileFactory,
       _connectionId = connectionId ?? 'ws-${_nextConnectionId++}';

  static int _nextConnectionId = 1;

  final Uri _uri;
  final GenesisHttpProfileFactory _profileFactory;
  final String _connectionId;
  // Bound diagnostic state on long-lived connections, including missing ACKs.
  final Set<String> _heartbeatClientMessageIds = <String>{};
  static const _maxHeartbeatClientMessageIds = 1024;
  int _nextSequence = 1;

  Future<void> recordFrame({
    required String direction,
    required String message,
  }) async {
    if (const bool.fromEnvironment('dart.vm.product')) return;
    final isOutgoing = direction == '=>';
    // Track heartbeats even while recording is paused so later ACKs stay hidden.
    if (_shouldSkipFrame(message, isOutgoing: isOutgoing)) return;
    // The Network recording toggle controls profiling. A lifetime frame quota
    // would permanently hide later business traffic on long-lived sockets.
    if (!HttpClientRequestProfile.profilingEnabled) return;

    HttpClientRequestProfile? profile;
    try {
      final recordedAt = DateTime.now();
      final payload = _profilePayload(message);
      final sequence = _nextSequence++;
      final requestUri = _profileUri(
        _uri,
        connectionId: _connectionId,
        sequence: sequence,
        messageType: payload.messageType,
        globalMessageId: payload.globalMessageId,
        messageId: payload.messageId,
        locationMessageId: payload.locationMessageId,
      );
      profile = _profileFactory(
        requestStartTime: recordedAt,
        requestMethod: isOutgoing ? 'WS_SEND' : 'WS_RECV',
        requestUri: requestUri.toString(),
      );
      if (profile == null) return;

      final metadataHeaders = <String, String>{
        'x-genesis-devtools-synthetic': 'websocket-frame',
        'x-genesis-websocket-connection-id': _connectionId,
        'x-genesis-websocket-direction': isOutgoing ? 'send' : 'receive',
        'x-genesis-websocket-sequence': '$sequence',
        if (payload.messageType != null)
          'x-genesis-websocket-message-type': payload.messageType!,
        if (payload.globalMessageId != null)
          'x-genesis-websocket-global-msg-id': payload.globalMessageId!,
        if (payload.messageId != null)
          'x-genesis-websocket-msg-id': payload.messageId!,
        if (payload.locationMessageId != null)
          'x-genesis-websocket-location-msg-id': payload.locationMessageId!,
      };
      final contentHeaders = <String, String>{
        ...metadataHeaders,
        'content-type': payload.contentType,
        'content-length': '${payload.bodyBytes.length}',
      };

      final requestData = profile.requestData;
      requestData.followRedirects = false;
      requestData.persistentConnection = true;
      requestData.headersCommaValues = isOutgoing
          ? contentHeaders
          : metadataHeaders;
      requestData.contentLength = isOutgoing ? payload.bodyBytes.length : 0;
      if (isOutgoing && payload.bodyBytes.isNotEmpty) {
        requestData.bodySink.add(payload.bodyBytes);
      }

      final responseData = profile.responseData;
      responseData.startTime = recordedAt;
      responseData.statusCode = 200;
      responseData.persistentConnection = true;
      responseData.isRedirect = false;
      responseData.headersCommaValues = <String, String>{
        ...metadataHeaders,
        'content-type': payload.contentType,
        'content-length': isOutgoing ? '0' : '${payload.bodyBytes.length}',
      };
      responseData.contentLength = isOutgoing ? 0 : payload.bodyBytes.length;
      if (!isOutgoing && payload.bodyBytes.isNotEmpty) {
        responseData.bodySink.add(payload.bodyBytes);
      }

      profile.connectionInfo = <String, dynamic>{
        'transport': 'websocket',
        'connectionId': _connectionId,
        'direction': isOutgoing ? 'send' : 'receive',
        'sequence': sequence,
      };
      profile.addEvent(
        HttpProfileRequestEvent(
          timestamp: recordedAt,
          name: isOutgoing
              ? 'WebSocket frame sent'
              : 'WebSocket frame received',
        ),
      );
    } catch (_) {
      // Profiling is diagnostic-only and must never affect WebSocket traffic.
    } finally {
      final capturedProfile = profile;
      if (capturedProfile != null) {
        try {
          await capturedProfile.requestData.close();
        } catch (_) {
          // Profiling is diagnostic-only and must never affect WebSocket traffic.
        }
        try {
          await capturedProfile.responseData.close();
        } catch (_) {
          // Profiling is diagnostic-only and must never affect WebSocket traffic.
        }
      }
    }
  }

  bool _shouldSkipFrame(String message, {required bool isOutgoing}) {
    Object? decoded;
    try {
      decoded = jsonDecode(message);
    } catch (_) {
      return false;
    }
    if (decoded is! Map) return false;
    final type = _profileField(decoded, 'type');
    final payload = decoded['payload'];
    final clientMessageId = decoded.containsKey('client_msg_id')
        ? _profileField(decoded, 'client_msg_id')
        : payload is Map
        ? _profileField(payload, 'client_msg_id')
        : null;
    if (type == 'heartbeat') {
      if (isOutgoing && clientMessageId != null) {
        _heartbeatClientMessageIds.add(clientMessageId);
        if (_heartbeatClientMessageIds.length > _maxHeartbeatClientMessageIds) {
          _heartbeatClientMessageIds.remove(_heartbeatClientMessageIds.first);
        }
      }
      return true;
    }
    // Retain recent IDs after an ACK to suppress duplicate acknowledgements too.
    return !isOutgoing &&
        type == 'ack' &&
        clientMessageId != null &&
        _heartbeatClientMessageIds.contains(clientMessageId);
  }
}

HttpClientRequestProfile? _createWebSocketProfile({
  required DateTime requestStartTime,
  required String requestMethod,
  required String requestUri,
}) {
  return HttpClientRequestProfile.profile(
    requestStartTime: requestStartTime,
    requestMethod: requestMethod,
    requestUri: requestUri,
  );
}

Uri _profileUri(
  Uri uri, {
  required String connectionId,
  required int sequence,
  required String? messageType,
  required String? globalMessageId,
  required String? messageId,
  required String? locationMessageId,
}) {
  final queryParameters = <String, dynamic>{};
  for (final entry in uri.queryParametersAll.entries) {
    queryParameters[entry.key] = _isSensitiveField(entry.key)
        ? const <String>[_redactedValue]
        : entry.value;
  }
  final fragment = Uri(
    queryParameters: <String, String>{
      if (messageType != null) 'type': messageType,
      if (globalMessageId != null) 'global_msg_id': globalMessageId,
      if (messageId != null) 'msg_id': messageId,
      if (locationMessageId != null) 'location_msg_id': locationMessageId,
      'connection': connectionId,
      'frame': '$sequence',
    },
  ).query;
  return uri.replace(
    userInfo: '',
    queryParameters: queryParameters.isEmpty ? null : queryParameters,
    fragment: fragment,
  );
}

_WebSocketProfilePayload _profilePayload(String message) {
  // Extract metadata and redact the complete JSON before limiting the stored
  // preview, so large stream/end frames still match the Network type filter.
  String sanitized;
  var contentType = 'text/plain; charset=utf-8';
  String? messageType;
  String? globalMessageId;
  String? messageId;
  String? locationMessageId;
  try {
    final decoded = jsonDecode(message);
    if (decoded is Map) {
      messageType = _profileField(decoded, 'type');
      globalMessageId = _profileIdField(
        decoded,
        fullName: 'global_message_id',
        legacyName: 'global_msg_id',
      );
      messageId = _profileIdField(
        decoded,
        fullName: 'message_id',
        legacyName: 'msg_id',
      );
      locationMessageId = _profileIdField(
        decoded,
        fullName: 'location_message_id',
        legacyName: 'location_msg_id',
      );
    }
    sanitized = jsonEncode(_redactJson(decoded));
    contentType = 'application/json; charset=utf-8';
  } catch (_) {
    sanitized = _redactRawSecrets(message);
  }
  return _WebSocketProfilePayload(
    contentType: devToolsWebSocketFrameExceedsBodyLimit(sanitized)
        ? 'text/plain; charset=utf-8'
        : contentType,
    bodyBytes: _truncateUtf8(sanitized),
    messageType: messageType,
    globalMessageId: globalMessageId,
    messageId: messageId,
    locationMessageId: locationMessageId,
  );
}

bool devToolsWebSocketFrameExceedsBodyLimit(String value) {
  var byteCount = 0;
  for (var index = 0; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit <= 0x7f) {
      byteCount += 1;
    } else if (codeUnit <= 0x7ff) {
      byteCount += 2;
    } else if (codeUnit >= 0xd800 &&
        codeUnit <= 0xdbff &&
        index + 1 < value.length) {
      final nextCodeUnit = value.codeUnitAt(index + 1);
      if (nextCodeUnit >= 0xdc00 && nextCodeUnit <= 0xdfff) {
        byteCount += 4;
        index += 1;
      } else {
        byteCount += 3;
      }
    } else {
      byteCount += 3;
    }
    if (byteCount > kDevToolsWebSocketProfileMaxBodyBytes) return true;
  }
  return false;
}

String? _profileField(Map<dynamic, dynamic> json, String key) {
  final value = json[key];
  if (value is! String && value is! num && value is! bool) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

String? _profileIdField(
  Map<dynamic, dynamic> json, {
  required String fullName,
  required String legacyName,
}) {
  // A present V2 field is authoritative, including an invalid/null value.
  // Only frames without that field may fall back to the legacy abbreviation.
  if (json.containsKey(fullName)) return _profileField(json, fullName);
  return _profileField(json, legacyName);
}

Object? _redactJson(Object? value) {
  if (value is Map) {
    return value.map((key, nestedValue) {
      final field = '$key';
      return MapEntry(
        field,
        _isSensitiveField(field) ? _redactedValue : _redactJson(nestedValue),
      );
    });
  }
  if (value is List) return value.map(_redactJson).toList(growable: false);
  if (value is String) return _redactRawSecrets(value);
  return value;
}

bool _isSensitiveField(String field) {
  return _sensitiveFieldNames.contains(field.trim().toLowerCase());
}

String _redactRawSecrets(String value) {
  return value.replaceAllMapped(
    RegExp(r'(Bearer\s+)[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    (match) => '${match.group(1)}$_redactedValue',
  );
}

List<int> _truncateUtf8(String value) {
  final encoded = utf8.encode(value);
  if (encoded.length <= kDevToolsWebSocketProfileMaxBodyBytes) return encoded;

  final suffix = '\n...[truncated ${encoded.length} byte payload]';
  final suffixBytes = utf8.encode(suffix);
  var prefixLength = kDevToolsWebSocketProfileMaxBodyBytes - suffixBytes.length;
  var result = <int>[];
  while (prefixLength >= 0) {
    final prefix = utf8.decode(
      encoded.sublist(0, prefixLength),
      allowMalformed: true,
    );
    result = utf8.encode('$prefix$suffix');
    if (result.length <= kDevToolsWebSocketProfileMaxBodyBytes) return result;
    prefixLength -= result.length - kDevToolsWebSocketProfileMaxBodyBytes;
  }
  return suffixBytes.take(kDevToolsWebSocketProfileMaxBodyBytes).toList();
}

class _WebSocketProfilePayload {
  const _WebSocketProfilePayload({
    required this.contentType,
    required this.bodyBytes,
    required this.messageType,
    required this.globalMessageId,
    required this.messageId,
    required this.locationMessageId,
  });

  final String contentType;
  final List<int> bodyBytes;
  final String? messageType;
  final String? globalMessageId;
  final String? messageId;
  final String? locationMessageId;
}

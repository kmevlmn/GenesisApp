import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'devtools_websocket_profile.dart';
import 'io_http_transport.dart';
import 'websocket_capture.dart';

const kLogWebSocketFrames = !bool.fromEnvironment('dart.vm.product');

typedef WebSocketFrameLogSink =
    void Function(String direction, String formatted);

abstract interface class NetworkWebSocket {
  Stream<String> get messages;

  Future<void> send(String message);

  Future<void> close([int? code, String? reason]);
}

abstract interface class NetworkWebSocketTransport {
  Future<NetworkWebSocket> connect(Uri uri, {Map<String, String>? headers});
}

class IoWebSocketTransport implements NetworkWebSocketTransport {
  IoWebSocketTransport({
    String? proxy,
    bool logFrames = kLogWebSocketFrames,
    String logName = 'NetworkWebSocket',
    String frameLogName = 'NetworkWebSocketFrame',
    WebSocketFrameLogSink? frameLogSink,
    WebSocketCaptureController? captureController,
    DevToolsWebSocketProfile Function(Uri)? frameProfileFactory,
  }) : _client = createProxyAwareHttpClient(proxy),
       _logFrames = logFrames,
       _logName = logName,
       _frameLogName = frameLogName,
       _frameLogSink = frameLogSink,
       _captureController = captureController ?? webSocketCaptureController,
       _frameProfileFactory =
           frameProfileFactory ?? DevToolsWebSocketProfile.new;

  final HttpClient _client;
  final bool _logFrames;
  final String _logName;
  final String _frameLogName;
  final WebSocketFrameLogSink? _frameLogSink;
  final WebSocketCaptureController _captureController;
  final DevToolsWebSocketProfile Function(Uri) _frameProfileFactory;

  @override
  Future<NetworkWebSocket> connect(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    developer.log('connecting $uri', name: _logName);
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: headers,
      compression: CompressionOptions.compressionOff,
      customClient: _client,
    );
    developer.log(
      'connected $uri protocol=${socket.protocol ?? ''}',
      name: _logName,
    );
    return _IoNetworkWebSocket(
      socket,
      logFrames: _logFrames,
      logName: _logName,
      frameLogName: _frameLogName,
      frameLogSink: _frameLogSink,
      captureConnection: _captureController.openConnection(uri),
      frameProfile: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _frameProfileFactory(uri),
    );
  }
}

class _IoNetworkWebSocket implements NetworkWebSocket {
  _IoNetworkWebSocket(
    this._socket, {
    required bool logFrames,
    required String logName,
    required String frameLogName,
    required WebSocketFrameLogSink? frameLogSink,
    required WebSocketCaptureConnection captureConnection,
    required DevToolsWebSocketProfile? frameProfile,
  }) : _logFrames = logFrames,
       _logName = logName,
       _frameLogName = frameLogName,
       _frameLogSink = frameLogSink,
       _captureConnection = captureConnection,
       _frameProfile = frameProfile;

  final WebSocket _socket;
  final bool _logFrames;
  final String _logName;
  final String _frameLogName;
  final WebSocketFrameLogSink? _frameLogSink;
  final WebSocketCaptureConnection _captureConnection;
  final DevToolsWebSocketProfile? _frameProfile;

  @override
  Stream<String> get messages {
    return _socket
        .where((event) => event is String)
        .cast<String>()
        .map((message) {
          _logFrame('<=', message);
          return message;
        })
        .handleError((Object error, StackTrace stackTrace) {
          unawaited(_frameProfile?.close(reason: 'WebSocket stream error'));
          developer.log(
            'socket stream error',
            name: _logName,
            error: error,
            stackTrace: stackTrace,
          );
        })
        .transform(
          StreamTransformer<String, String>.fromHandlers(
            handleDone: (sink) {
              unawaited(_frameProfile?.close());
              developer.log(
                'socket closed code=${_socket.closeCode} reason=${_socket.closeReason ?? ''}',
                name: _logName,
              );
              sink.close();
            },
          ),
        );
  }

  @override
  Future<void> send(String message) async {
    _logFrame('=>', message);
    _socket.add(message);
  }

  @override
  Future<void> close([int? code, String? reason]) {
    unawaited(_frameProfile?.close());
    developer.log(
      'closing socket code=${code ?? ''} reason=${reason ?? ''}',
      name: _logName,
    );
    return _socket.close(code, reason);
  }

  void _logFrame(String direction, String message) {
    if (const bool.fromEnvironment('dart.vm.product')) return;
    try {
      _captureConnection.recordFrame(
        direction == '=>'
            ? WebSocketCaptureDirection.send
            : WebSocketCaptureDirection.receive,
        message,
      );
    } catch (_) {
      // Diagnostics must never affect the real socket.
    }
    if (_logFrames) {
      try {
        final formatted = formatWebSocketFrameLog(
          direction: direction,
          message: message,
        );
        developer.log(formatted, name: _frameLogName);
        _frameLogSink?.call(direction, formatted);
      } catch (_) {
        // A failing log sink must not skip profiling or socket delivery.
      }
    }
    final frameProfile = _frameProfile;
    if (frameProfile != null) {
      unawaited(
        frameProfile.recordFrame(direction: direction, message: message),
      );
    }
  }
}

String formatWebSocketFrameLog({
  required String direction,
  required String message,
}) {
  if (devToolsWebSocketFrameExceedsBodyLimit(message)) {
    return 'WS $direction omitted oversized frame '
        'codeUnits=${message.length}';
  }
  Object? decoded;
  try {
    decoded = jsonDecode(message);
  } catch (_) {
    return 'WS $direction raw\n$message';
  }
  if (decoded is Map) {
    final map = decoded.map((key, value) => MapEntry('$key', value));
    final type = _stringField(map, 'type');
    final requestType = _stringField(map, 'request_type');
    final summary = [
      'WS $direction',
      if (type != null) 'type=$type',
      if (requestType != null) 'request=$requestType',
    ].join(' ');
    return '$summary\n$message';
  }
  return 'WS $direction json\n$message';
}

String? _stringField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

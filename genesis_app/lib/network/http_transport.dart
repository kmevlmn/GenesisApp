import 'dart:async';
import 'dart:typed_data';

abstract class HttpTransport {
  Future<TransportResponse> send(TransportRequest request);
}

abstract interface class OriginWarmableHttpTransport {
  Future<void> warmUp(Uri uri);
}

typedef NetworkProgressCallback = void Function(int sentBytes, int totalBytes);

class NetworkCancellationToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List<void Function()>.from(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void throwIfCancelled() {
    if (_cancelled) throw const NetworkRequestCancelledException();
  }

  void Function() addCancelListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }
}

class NetworkRequestCancelledException implements Exception {
  const NetworkRequestCancelledException();

  @override
  String toString() => 'NetworkRequestCancelledException';
}

class TransportRequest {
  const TransportRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.bodyBytes,
    required this.timeoutMs,
    this.decodeResponseBody = true,
    this.onSendProgress,
    this.onReceiveProgress,
    this.cancellationToken,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int>? bodyBytes;
  final int timeoutMs;
  final bool decodeResponseBody;
  final NetworkProgressCallback? onSendProgress;
  final NetworkProgressCallback? onReceiveProgress;
  final NetworkCancellationToken? cancellationToken;

  TransportRequest withCancellationToken(NetworkCancellationToken token) =>
      TransportRequest(
        method: method,
        uri: uri,
        headers: headers,
        bodyBytes: bodyBytes,
        timeoutMs: timeoutMs,
        decodeResponseBody: decodeResponseBody,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
        cancellationToken: token,
      );
}

/// One deadline covers preparation, sending, headers and the entire body.
/// The child token also prevents delayed preparation from sending after expiry.
Future<T> runWithNetworkDeadline<T>({
  required Duration timeout,
  required Future<T> Function(NetworkCancellationToken token) action,
  NetworkCancellationToken? cancellationToken,
}) async {
  cancellationToken?.throwIfCancelled();
  final token = NetworkCancellationToken();
  final result = Completer<T>();
  void cancel(Object error) {
    if (result.isCompleted) return;
    result.completeError(error);
    token.cancel();
  }

  final removeListener = cancellationToken?.addCancelListener(
    () => cancel(const NetworkRequestCancelledException()),
  );
  final timer = Timer(timeout, () {
    cancel(TimeoutException('HTTP request deadline exceeded.', timeout));
  });
  // Always observe late completion, including errors from aborted native tasks.
  unawaited(
    Future<T>.sync(() => action(token)).then<void>(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!result.isCompleted) result.completeError(error, stackTrace);
      },
    ),
  );
  try {
    return await result.future;
  } finally {
    timer.cancel();
    removeListener?.call();
  }
}

Future<Uint8List> readTransportResponseBytes(
  Stream<List<int>> stream, {
  required int totalBytes,
  NetworkProgressCallback? onReceiveProgress,
  NetworkCancellationToken? cancellationToken,
}) async {
  final output = BytesBuilder(copy: false);
  final iterator = StreamIterator<List<int>>(stream);
  final removeListener = cancellationToken?.addCancelListener(() {
    unawaited(iterator.cancel());
  });
  try {
    cancellationToken?.throwIfCancelled();
    while (await iterator.moveNext()) {
      cancellationToken?.throwIfCancelled();
      output.add(iterator.current);
      onReceiveProgress?.call(output.length, totalBytes);
    }
    cancellationToken?.throwIfCancelled();
    return output.takeBytes();
  } finally {
    removeListener?.call();
    await iterator.cancel();
  }
}

class TransportResponse {
  const TransportResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    this.bodyBytes = const <int>[],
    this.responsePayloadSizeBytes,
    this.httpProtocolVersion,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final List<int> bodyBytes;
  final int? responsePayloadSizeBytes;
  final String? httpProtocolVersion;
}

String? normalizeHttpProtocolVersion(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty || normalized == 'unknown') {
    return null;
  }
  if (normalized == 'h3' ||
      normalized.startsWith('h3-') ||
      normalized.startsWith('http/3') ||
      normalized.contains('quic')) {
    return 'h3';
  }
  if (normalized == 'h2' ||
      normalized == '2' ||
      normalized == '2.0' ||
      normalized.startsWith('http/2') ||
      normalized.contains('spdy')) {
    return 'h2';
  }
  if (normalized == 'http/1.1' ||
      normalized == 'http1.1' ||
      normalized == '1.1') {
    return 'http/1.1';
  }
  return normalized;
}

String? normalizeHttpProxyAddress(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;

  try {
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'http://$raw');
    if (uri == null ||
        uri.scheme.toLowerCase() != 'http' ||
        uri.host.trim().isEmpty ||
        !uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final port = uri.port;
    if (port < 1 || port > 65535) return null;
    final host = uri.host.toLowerCase();
    final authorityHost = host.contains(':') ? '[$host]' : host;
    return '$authorityHost:$port';
  } catch (_) {
    return null;
  }
}

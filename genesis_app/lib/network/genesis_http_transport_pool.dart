import 'dart:io';

import 'package:flutter/foundation.dart';

import 'dio_http_transport.dart';
import 'http_transport.dart';
import 'io_http_transport.dart';
import 'platform_http3_transport.dart';

const int genesisHttp3ConnectionCount = 1;
const int genesisHttp2ConnectionCount = 3;
const int genesisHttp1ConnectionCount = 1;
const int genesisHttpImageConcurrentFetches = 9;
const Duration genesisHttp2FallbackIdleTimeout = Duration(minutes: 5);

typedef Http3TransportBuilder = HttpTransport Function();

class GenesisHttpTransportPool implements HttpTransport {
  GenesisHttpTransportPool({required List<HttpTransport> transports})
    : _transports = List<HttpTransport>.unmodifiable(transports) {
    if (_transports.isEmpty) {
      throw ArgumentError.value(
        transports,
        'transports',
        'Must contain at least one transport.',
      );
    }
  }

  factory GenesisHttpTransportPool.platform({
    Http3TransportBuilder? transportBuilder,
    Http3TransportBuilder? fallbackBuilder,
  }) {
    final buildNative =
        transportBuilder ??
        () => PlatformHttp3Transport(client: createPlatformHttp3Client());
    final buildFallback =
        fallbackBuilder ??
        () =>
            DioHttpTransport(http2IdleTimeout: genesisHttp2FallbackIdleTimeout);
    final attemptNative =
        transportBuilder != null || Platform.isAndroid || Platform.isIOS;
    if (attemptNative) {
      try {
        return GenesisHttpTransportPool(
          transports: <HttpTransport>[buildNative()],
        );
      } catch (error, stackTrace) {
        _logHttp3Fallback(error, stackTrace);
      }
    }
    return GenesisHttpTransportPool(
      transports: <HttpTransport>[
        for (var index = 0; index < genesisHttp2ConnectionCount; index += 1)
          buildFallback(),
      ],
    );
  }

  factory GenesisHttpTransportPool.http2({
    String? proxy,
    Http3TransportBuilder? transportBuilder,
  }) {
    final buildTransport =
        transportBuilder ??
        () => DioHttpTransport(
          proxy: proxy,
          http2IdleTimeout: genesisHttp2FallbackIdleTimeout,
        );
    return GenesisHttpTransportPool(
      transports: <HttpTransport>[
        for (var index = 0; index < genesisHttp2ConnectionCount; index += 1)
          buildTransport(),
      ],
    );
  }

  factory GenesisHttpTransportPool.http1({required String proxy}) {
    return GenesisHttpTransportPool(
      transports: <HttpTransport>[IoHttpTransport(proxy: proxy)],
    );
  }

  final List<HttpTransport> _transports;
  final Map<String, Future<void>> _warmUpRequests = <String, Future<void>>{};
  int _nextTransportIndex = 0;

  int get connectionCount => _transports.length;

  @visibleForTesting
  bool get debugUsesHttp1 =>
      _transports.length == genesisHttp1ConnectionCount &&
      _transports.single is IoHttpTransport;

  Future<void> warmUp(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' || uri.host.trim().isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'Must be an HTTPS origin.');
    }
    final originKey =
        '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}'
        ':${uri.port}';
    final existing = _warmUpRequests[originKey];
    if (existing != null) return existing;

    final request = _warmUpOrigin(originKey: originKey, uri: uri);
    _warmUpRequests[originKey] = request;
    return request;
  }

  Future<void> _warmUpOrigin({
    required String originKey,
    required Uri uri,
  }) async {
    try {
      await Future.wait<void>([
        for (final transport in _transports)
          if (transport case final OriginWarmableHttpTransport warmable)
            warmable.warmUp(uri)
          else
            transport
                .send(
                  TransportRequest(
                    method: 'HEAD',
                    uri: uri,
                    headers: const <String, String>{'accept': '*/*'},
                    bodyBytes: null,
                    timeoutMs: 10000,
                  ),
                )
                .then((_) {}),
      ]);
    } catch (_) {
      _warmUpRequests.remove(originKey);
      rethrow;
    }
  }

  @override
  Future<TransportResponse> send(TransportRequest request) {
    final transport = _transports[_nextTransportIndex];
    _nextTransportIndex = (_nextTransportIndex + 1) % _transports.length;
    return transport.send(request);
  }
}

void _logHttp3Fallback(Object error, StackTrace stackTrace) {
  debugPrint(
    '[Network][HTTP3] native client initialization failed; '
    'falling back to the HTTP/2 pool: $error',
  );
  debugPrint('[Network][HTTP3] stacktrace:\n$stackTrace');
}

class GenesisHttpTransportRegistry {
  GenesisHttpTransportRegistry._();

  static HttpTransport? _transport;
  static String? _configurationKey;

  static HttpTransport configure({
    String httpEngine = 'http3',
    String? debugProxy,
  }) {
    final normalizedEngine = httpEngine.trim().toLowerCase();
    final normalizedProxy = normalizeHttpProxyAddress(debugProxy) ?? '';
    final configurationKey = '$normalizedEngine|$normalizedProxy';
    if (_transport != null && _configurationKey == configurationKey) {
      return _transport!;
    }

    final useProxyHttp1 = normalizedProxy.isNotEmpty;
    final useHttp3 =
        normalizedProxy.isEmpty &&
        (normalizedEngine == 'http3' ||
            normalizedEngine == 'quic' ||
            normalizedEngine == 'auto');
    final transport = useProxyHttp1
        ? GenesisHttpTransportPool.http1(proxy: normalizedProxy)
        : useHttp3
        ? GenesisHttpTransportPool.platform()
        : GenesisHttpTransportPool.http2();
    _configurationKey = configurationKey;
    _transport = transport;
    return transport;
  }

  static HttpTransport get current => _transport ?? configure();

  @visibleForTesting
  static void reset() {
    _configurationKey = null;
    _transport = null;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart' as http;

import '../app/telemetry/firebase_performance_monitoring.dart';
import 'dio_http_transport.dart';
import 'http_transport.dart';
import 'io_http_transport.dart';
import 'membership_request_privacy.dart';
import 'static_image_network_config.dart';

typedef HttpProtocolResolver = String? Function(http.StreamedResponse response);

class PlatformHttp3Transport implements HttpTransport {
  PlatformHttp3Transport({
    required http.Client client,
    HttpTransport? nonHttpsTransport,
    HttpProtocolResolver? protocolResolver,
    HttpRequestPerformanceMetricFactory? performanceMetricFactory,
    HttpRequestPerformanceMetricUrlFilter? performanceMetricUrlFilter,
    HttpRequestPerformanceMetricReady? performanceMetricReady,
  }) : _client = client,
       _nonHttpsTransport = nonHttpsTransport ?? DioHttpTransport(),
       _protocolResolver = protocolResolver ?? platformHttpProtocol,
       _performanceMetricFactory =
           performanceMetricFactory ?? createFirebasePerformanceMetric,
       _performanceMetricUrlFilter =
           performanceMetricUrlFilter ?? isFirebasePerformanceMetricUrl,
       _performanceMetricReady =
           performanceMetricReady ??
           (() => FirebasePerformanceMonitoring.isReady);

  final http.Client _client;
  final HttpTransport _nonHttpsTransport;
  final HttpProtocolResolver _protocolResolver;
  final HttpRequestPerformanceMetricFactory _performanceMetricFactory;
  final HttpRequestPerformanceMetricUrlFilter _performanceMetricUrlFilter;
  final HttpRequestPerformanceMetricReady _performanceMetricReady;

  @override
  Future<TransportResponse> send(TransportRequest request) {
    // Native http clients unconditionally profile bodies when DevTools is on.
    // The Dio path supports per-request exclusion for membership credentials.
    if (request.uri.scheme.toLowerCase() != 'https' ||
        isPrivateMembershipRequest(request.uri)) {
      return _nonHttpsTransport.send(request);
    }
    return runWithNetworkDeadline(
      timeout: Duration(milliseconds: request.timeoutMs),
      cancellationToken: request.cancellationToken,
      action: (token) => _send(request.withCancellationToken(token)),
    );
  }

  Future<TransportResponse> _send(TransportRequest request) async {
    request.cancellationToken?.throwIfCancelled();
    final metric = await startPerformanceMetric(
      request,
      factory: _performanceMetricFactory,
      urlFilter: _performanceMetricUrlFilter,
      ready: _performanceMetricReady,
    );
    final stopMetric = performanceMetricStopper(metric);
    final abortCompleter = Completer<void>();
    void abort() {
      stopMetric();
      if (!abortCompleter.isCompleted) abortCompleter.complete();
    }

    final removeCancelListener = request.cancellationToken?.addCancelListener(
      abort,
    );
    try {
      request.cancellationToken?.throwIfCancelled();
      final nativeRequest = http.AbortableRequest(
        request.method,
        request.uri,
        abortTrigger: abortCompleter.future,
      )..headers.addAll(request.headers);
      final requestBody = request.bodyBytes;
      if (requestBody != null) {
        nativeRequest.bodyBytes = requestBody;
        request.onSendProgress?.call(requestBody.length, requestBody.length);
      }

      final streamedResponse = await _client.send(nativeRequest);
      request.cancellationToken?.throwIfCancelled();

      final protocol = normalizeHttpProtocolVersion(
        _protocolResolver(streamedResponse),
      );
      recordPerformanceMetricProtocol(metric, protocol);

      final bodyBytes = await readTransportResponseBytes(
        streamedResponse.stream,
        totalBytes:
            nonNegativeContentLength(streamedResponse.contentLength) ?? -1,
        onReceiveProgress: request.onReceiveProgress,
        cancellationToken: request.cancellationToken,
      );
      final response = TransportResponse(
        statusCode: streamedResponse.statusCode,
        headers: Map<String, String>.from(streamedResponse.headers),
        body: request.decodeResponseBody
            ? utf8.decode(bodyBytes, allowMalformed: true)
            : '',
        bodyBytes: bodyBytes,
        responsePayloadSizeBytes:
            responsePayloadSizeFromHeaders(streamedResponse.headers) ??
            nonNegativeContentLength(streamedResponse.contentLength) ??
            bodyBytes.length,
        httpProtocolVersion: protocol,
      );
      recordPerformanceMetricResponse(metric, response);
      return response;
    } on http.RequestAbortedException {
      throw const NetworkRequestCancelledException();
    } on TimeoutException {
      abort();
      rethrow;
    } finally {
      removeCancelListener?.call();
      stopMetric();
    }
  }
}

http.Client createPlatformHttp3Client() {
  if (Platform.isAndroid) {
    final engine = CronetEngine.build(
      cacheMode: CacheMode.disabled,
      enableHttp2: true,
      enableQuic: true,
      quicHints: <(String, int, int)>[
        for (final host in genesisHttp3CapableHosts) (host, 443, 443),
      ],
    );
    return CronetClient.fromCronetEngine(engine, closeEngine: true);
  }
  if (Platform.isIOS) {
    final configuration =
        URLSessionConfiguration.ephemeralSessionConfiguration()
          ..cache = URLCache.withCapacity();
    return CupertinoClient.fromSessionConfiguration(configuration);
  }
  throw UnsupportedError(
    'HTTP/3 native transport is supported only on Android and iOS.',
  );
}

String? platformHttpProtocol(http.StreamedResponse response) {
  if (response is CronetStreamedResponse) {
    return response.negotiatedProtocol;
  }
  return null;
}

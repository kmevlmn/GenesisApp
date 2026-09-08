import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http2/http2.dart';

import '../app/telemetry/firebase_performance_monitoring.dart';
import 'devtools_http_profile.dart';
import 'http_transport.dart';
import 'io_http_transport.dart';

class DioHttpTransport implements HttpTransport {
  DioHttpTransport({
    Dio? dio,
    String? proxy,
    SecurityContext? securityContext,
    Duration http2IdleTimeout = const Duration(seconds: 15),
    HttpRequestPerformanceMetricFactory? performanceMetricFactory,
    HttpRequestPerformanceMetricUrlFilter? performanceMetricUrlFilter,
    HttpRequestPerformanceMetricReady? performanceMetricReady,
  }) : _dio = _prepareDio(
         dio ?? _createDio(proxy, http2IdleTimeout, securityContext),
       ),
       _performanceMetricFactory =
           performanceMetricFactory ?? createFirebasePerformanceMetric,
       _performanceMetricUrlFilter =
           performanceMetricUrlFilter ?? isFirebasePerformanceMetricUrl,
       _performanceMetricReady =
           performanceMetricReady ??
           (() => FirebasePerformanceMonitoring.isReady);

  final Dio _dio;
  final HttpRequestPerformanceMetricFactory _performanceMetricFactory;
  final HttpRequestPerformanceMetricUrlFilter _performanceMetricUrlFilter;
  final HttpRequestPerformanceMetricReady _performanceMetricReady;

  @override
  Future<TransportResponse> send(TransportRequest request) =>
      runWithNetworkDeadline(
        timeout: Duration(milliseconds: request.timeoutMs),
        cancellationToken: request.cancellationToken,
        action: (token) => _send(request.withCancellationToken(token)),
      );

  Future<TransportResponse> _send(TransportRequest request) async {
    request.cancellationToken?.throwIfCancelled();
    final metric = await startPerformanceMetric(
      request,
      factory: _performanceMetricFactory,
      urlFilter: _performanceMetricUrlFilter,
      ready: _performanceMetricReady,
    );
    final stopMetric = performanceMetricStopper(metric);
    final devToolsProfile = DevToolsHttpProfile.start(request);
    unawaited(devToolsProfile?.completeRequest(request));
    final dioCancelToken = CancelToken();
    final removeCancelListener = request.cancellationToken?.addCancelListener(
      () {
        stopMetric();
        if (!dioCancelToken.isCancelled) {
          dioCancelToken.cancel(const NetworkRequestCancelledException());
        }
      },
    );
    try {
      request.cancellationToken?.throwIfCancelled();
      final timeout = Duration(milliseconds: request.timeoutMs);
      final response = await _dio.request<Object?>(
        request.uri.toString(),
        data: _requestBodyData(request.bodyBytes),
        cancelToken: dioCancelToken,
        onSendProgress: request.onSendProgress,
        onReceiveProgress: request.onReceiveProgress,
        options: Options(
          method: request.method,
          headers: request.headers,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
          connectTimeout: timeout,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );

      final headers = <String, String>{
        for (final entry in response.headers.map.entries)
          entry.key: entry.value.join(','),
      };
      final httpProtocolVersion = response
          .extra[HttpClientAdapter.extraKeyHttpVersion]
          ?.toString();
      final bodyBytes = _responseBodyBytes(response.data);
      final normalizedProtocol = normalizeHttpProtocolVersion(
        httpProtocolVersion,
      );
      final transportResponse = TransportResponse(
        statusCode: response.statusCode ?? 0,
        headers: headers,
        body: request.decodeResponseBody
            ? utf8.decode(bodyBytes, allowMalformed: true)
            : '',
        bodyBytes: bodyBytes,
        responsePayloadSizeBytes:
            responsePayloadSizeFromHeaders(headers) ?? bodyBytes.length,
        httpProtocolVersion: normalizedProtocol,
      );
      recordPerformanceMetricProtocol(metric, normalizedProtocol);
      recordPerformanceMetricResponse(metric, transportResponse);
      unawaited(devToolsProfile?.completeResponse(transportResponse));
      return transportResponse;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        const cancellationError = NetworkRequestCancelledException();
        unawaited(devToolsProfile?.completeWithError(cancellationError));
        throw cancellationError;
      }
      unawaited(devToolsProfile?.completeWithError(error));
      rethrow;
    } catch (error) {
      unawaited(devToolsProfile?.completeWithError(error));
      rethrow;
    } finally {
      removeCancelListener?.call();
      stopMetric();
    }
  }
}

Object? _requestBodyData(List<int>? bodyBytes) {
  if (bodyBytes == null) return null;
  if (bodyBytes is Uint8List) return bodyBytes;
  return Uint8List.fromList(bodyBytes);
}

Dio _createDio(
  String? proxy,
  Duration http2IdleTimeout,
  SecurityContext? securityContext,
) {
  final normalizedProxy = normalizeHttpProxyAddress(proxy);
  final dio = Dio();
  final httpAdapter = IOHttpClientAdapter(
    createHttpClient: () => createProxyAwareHttpClient(
      normalizedProxy,
      securityContext: securityContext,
    ),
  );
  final proxyUri = _proxyUri(normalizedProxy);
  final httpsAdapter = Http2Adapter(
    CancellationAwareHttp2ConnectionManager(
      ConnectionManager(
        idleTimeout: http2IdleTimeout,
        onClientCreate: (_, setting) {
          setting.context = securityContext;
          setting.proxy = proxyUri;
          if (proxyUri != null &&
              !const bool.fromEnvironment('dart.vm.product')) {
            setting.onBadCertificate = (_) => true;
          }
        },
      ),
    ),
    fallbackAdapter: httpAdapter,
  );
  dio.httpClientAdapter = SchemeRoutingHttpClientAdapter(
    httpsAdapter: httpsAdapter,
    otherAdapter: httpAdapter,
  );
  return dio;
}

/// The adapter creates a request stream immediately after getConnection.
/// Check again here because establishing a shared connection can outlive the
/// request that asked for it. Do not close a connection used by other requests.
class CancellationAwareHttp2ConnectionManager implements ConnectionManager {
  CancellationAwareHttp2ConnectionManager(this.delegate);

  final ConnectionManager delegate;

  void _throwIfCancelled(RequestOptions options) {
    final error = options.cancelToken?.cancelError;
    if (error != null) throw error;
  }

  @override
  Future<ClientTransportConnection> getConnection(
    RequestOptions options,
    List<RedirectRecord> redirects,
  ) async {
    _throwIfCancelled(options);
    try {
      final connection = await delegate.getConnection(options, redirects);
      _throwIfCancelled(options);
      return connection;
    } catch (_) {
      // This also prevents late H2-not-supported from starting the fallback.
      _throwIfCancelled(options);
      rethrow;
    }
  }

  @override
  void removeConnection(ClientTransportConnection transport) =>
      delegate.removeConnection(transport);

  @override
  void close({bool force = false}) => delegate.close(force: force);

  @override
  @visibleForTesting
  // ConnectionManager requires this diagnostic getter on every implementation.
  // ignore: invalid_use_of_visible_for_testing_member
  int get cachedConnectionsCount => delegate.cachedConnectionsCount;
}

Dio _prepareDio(Dio dio) {
  // ApiClient serializes request bodies and sets their content type before
  // reaching this transport. Dio's implicit content-type interceptor is
  // therefore redundant, and keeping it also adds a response-handler stage
  // that was affected by Dio 5.10.0's interceptor error-zone regression.
  dio.interceptors.removeImplyContentTypeInterceptor();
  return dio;
}

class SchemeRoutingHttpClientAdapter implements HttpClientAdapter {
  SchemeRoutingHttpClientAdapter({
    required HttpClientAdapter httpsAdapter,
    required HttpClientAdapter otherAdapter,
  }) : _httpsAdapter = httpsAdapter,
       _otherAdapter = otherAdapter;

  final HttpClientAdapter _httpsAdapter;
  final HttpClientAdapter _otherAdapter;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final adapter = options.uri.scheme.toLowerCase() == 'https'
        ? _httpsAdapter
        : _otherAdapter;
    return adapter.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    _httpsAdapter.close(force: force);
    _otherAdapter.close(force: force);
  }
}

Uri? _proxyUri(String? proxy) {
  if (proxy == null) return null;
  return Uri.parse('http://$proxy');
}

Uint8List _responseBodyBytes(Object? data) {
  if (data == null) return Uint8List(0);
  if (data is Uint8List) return data;
  if (data is List<int>) return Uint8List.fromList(data);
  if (data is String) return Uint8List.fromList(utf8.encode(data));
  if (data is Iterable<int>) return Uint8List.fromList(data.toList());
  return Uint8List.fromList(utf8.encode(data.toString()));
}

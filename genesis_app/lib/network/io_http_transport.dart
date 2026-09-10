import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_performance/firebase_performance.dart';

import '../app/telemetry/firebase_performance_monitoring.dart';
import 'http_transport.dart';

typedef HttpRequestPerformanceMetricFactory =
    HttpRequestPerformanceMetric? Function(String url, HttpMethod method);
typedef HttpRequestPerformanceMetricUrlFilter = bool Function(Uri uri);
typedef HttpRequestPerformanceMetricReady = bool Function();

abstract class HttpRequestPerformanceMetric {
  set httpResponseCode(int? value);
  set requestPayloadSize(int? value);
  set responseContentType(String? value);
  set responsePayloadSize(int? value);

  void putAttribute(String name, String value);
  Future<void> start();
  Future<void> stop();
}

class IoHttpTransport implements HttpTransport {
  IoHttpTransport({
    HttpClient? client,
    String? proxy,
    HttpRequestPerformanceMetricFactory? performanceMetricFactory,
    HttpRequestPerformanceMetricUrlFilter? performanceMetricUrlFilter,
    HttpRequestPerformanceMetricReady? performanceMetricReady,
  }) : _client = client ?? createProxyAwareHttpClient(proxy),
       _performanceMetricFactory =
           performanceMetricFactory ?? createFirebasePerformanceMetric,
       _performanceMetricUrlFilter =
           performanceMetricUrlFilter ?? isFirebasePerformanceMetricUrl,
       _performanceMetricReady =
           performanceMetricReady ??
           (() => FirebasePerformanceMonitoring.isReady);

  final HttpClient _client;
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
    final removeMetricCancelListener = request.cancellationToken
        ?.addCancelListener(stopMetric);
    HttpClientRequest? httpRequest;
    void Function()? removeCancelListener;
    try {
      request.cancellationToken?.throwIfCancelled();
      // Keep observing openUrl after cancellation so a late connection is
      // aborted before any headers or body are sent.
      httpRequest = await _client.openUrl(request.method, request.uri);
      httpRequest.done.ignore();
      removeCancelListener = request.cancellationToken?.addCancelListener(() {
        httpRequest?.abort(const NetworkRequestCancelledException());
      });
      request.cancellationToken?.throwIfCancelled();
      final openedRequest = httpRequest;

      request.headers.forEach((key, value) {
        openedRequest.headers.set(key, value);
      });

      if (request.bodyBytes != null) {
        openedRequest.add(request.bodyBytes!);
        request.onSendProgress?.call(
          request.bodyBytes!.length,
          request.bodyBytes!.length,
        );
      }

      final httpResponse = await openedRequest.close();
      request.cancellationToken?.throwIfCancelled();

      final headers = <String, String>{};
      httpResponse.headers.forEach((name, values) {
        headers[name] = values.join(',');
      });

      final bodyBytes = await readTransportResponseBytes(
        httpResponse,
        totalBytes: nonNegativeContentLength(httpResponse.contentLength) ?? -1,
        onReceiveProgress: request.onReceiveProgress,
        cancellationToken: request.cancellationToken,
      );
      final body = request.decodeResponseBody
          ? utf8.decode(bodyBytes, allowMalformed: true)
          : '';

      final response = TransportResponse(
        statusCode: httpResponse.statusCode,
        headers: headers,
        body: body,
        bodyBytes: bodyBytes,
        responsePayloadSizeBytes:
            responsePayloadSizeFromHeaders(headers) ??
            nonNegativeContentLength(httpResponse.contentLength) ??
            bodyBytes.length,
      );
      recordPerformanceMetricResponse(metric, response);
      return response;
    } finally {
      removeCancelListener?.call();
      removeMetricCancelListener?.call();
      stopMetric();
    }
  }
}

class _FirebaseHttpRequestPerformanceMetric
    implements HttpRequestPerformanceMetric {
  _FirebaseHttpRequestPerformanceMetric(this._metric);

  final HttpMetric _metric;

  @override
  set httpResponseCode(int? value) {
    _metric.httpResponseCode = value;
  }

  @override
  set requestPayloadSize(int? value) {
    _metric.requestPayloadSize = value;
  }

  @override
  set responseContentType(String? value) {
    _metric.responseContentType = value;
  }

  @override
  set responsePayloadSize(int? value) {
    _metric.responsePayloadSize = value;
  }

  @override
  void putAttribute(String name, String value) {
    _metric.putAttribute(name, value);
  }

  @override
  Future<void> start() {
    return _metric.start();
  }

  @override
  Future<void> stop() {
    return _metric.stop();
  }
}

HttpRequestPerformanceMetric createFirebasePerformanceMetric(
  String url,
  HttpMethod method,
) {
  return _FirebaseHttpRequestPerformanceMetric(
    FirebasePerformance.instance.newHttpMetric(url, method),
  );
}

HttpClient createProxyAwareHttpClient(
  String? proxy, {
  SecurityContext? securityContext,
}) {
  final client = HttpClient(context: securityContext);
  final proxyAddress = normalizeHttpProxyAddress(proxy);
  if (proxyAddress != null) {
    client.findProxy = (_) => 'PROXY $proxyAddress; DIRECT';
    if (!const bool.fromEnvironment('dart.vm.product')) {
      client.badCertificateCallback = (_, __, ___) => true;
    }
  }
  return client;
}

HttpMethod? firebaseHttpMethodFor(String method) {
  switch (method.trim().toUpperCase()) {
    case 'CONNECT':
      return HttpMethod.Connect;
    case 'DELETE':
      return HttpMethod.Delete;
    case 'GET':
      return HttpMethod.Get;
    case 'HEAD':
      return HttpMethod.Head;
    case 'OPTIONS':
      return HttpMethod.Options;
    case 'PATCH':
      return HttpMethod.Patch;
    case 'POST':
      return HttpMethod.Post;
    case 'PUT':
      return HttpMethod.Put;
    case 'TRACE':
      return HttpMethod.Trace;
  }
  return null;
}

String firebaseMetricUrl(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  if (uri.hasPort) {
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.port,
      path: path,
    ).toString();
  }
  return Uri(scheme: uri.scheme, host: uri.host, path: path).toString();
}

bool isBusinessPerformanceMetricUrl(Uri uri) {
  switch (uri.host.toLowerCase()) {
    case 'api.worldo.ai':
    case 'dev.hushie.ai':
      return true;
  }
  return false;
}

bool isFirebasePerformanceMetricUrl(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  return (scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty;
}

void recordPerformanceMetricResponse(
  HttpRequestPerformanceMetric? metric,
  TransportResponse response,
) {
  if (metric == null) return;
  try {
    metric.httpResponseCode = response.statusCode;
    metric.responseContentType = headerValue(response.headers, 'content-type');
    metric.responsePayloadSize =
        response.responsePayloadSizeBytes ??
        (response.bodyBytes.isEmpty
            ? utf8.encode(response.body).length
            : response.bodyBytes.length);
  } catch (_) {}
}

void recordPerformanceMetricProtocol(
  HttpRequestPerformanceMetric? metric,
  String? protocol,
) {
  if (metric == null) return;
  final normalized = normalizeHttpProtocolVersion(protocol);
  if (normalized != 'h3' && normalized != 'h2' && normalized != 'http/1.1') {
    return;
  }
  try {
    metric.putAttribute('network_protocol', normalized!);
  } catch (_) {}
}

Future<HttpRequestPerformanceMetric?> startPerformanceMetric(
  TransportRequest request, {
  required HttpRequestPerformanceMetricFactory factory,
  required HttpRequestPerformanceMetricUrlFilter urlFilter,
  required HttpRequestPerformanceMetricReady ready,
}) async {
  HttpRequestPerformanceMetric? metric;
  try {
    final method = firebaseHttpMethodFor(request.method);
    if (method == null) return null;
    if (FirebasePerformanceMonitoring.isCircuitBroken || !ready()) return null;
    if (!urlFilter(request.uri)) return null;
    metric = factory(firebaseMetricUrl(request.uri), method);
    if (metric == null) return null;
    metric.requestPayloadSize = request.bodyBytes?.length ?? 0;
    final startFuture = metric.start();
    try {
      await startFuture.timeout(
        FirebasePerformanceMonitoring.instrumentationTimeout,
      );
    } on TimeoutException {
      FirebasePerformanceMonitoring.disableForCurrentProcess(
        'http_metric_start_timeout',
      );
      unawaited(_stopPerformanceMetricAfterStartCompletes(metric, startFuture));
      return null;
    }
    return metric;
  } catch (_) {
    unawaited(stopPerformanceMetric(metric));
    return null;
  }
}

Future<void> _stopPerformanceMetricAfterStartCompletes(
  HttpRequestPerformanceMetric metric,
  Future<void> startFuture,
) async {
  try {
    await startFuture;
  } catch (_) {
    return;
  }
  unawaited(stopPerformanceMetric(metric));
}

Future<void> stopPerformanceMetric(HttpRequestPerformanceMetric? metric) async {
  if (metric == null) return;
  try {
    await metric.stop().timeout(
      FirebasePerformanceMonitoring.instrumentationTimeout,
    );
  } on TimeoutException {
    FirebasePerformanceMonitoring.disableForCurrentProcess(
      'http_metric_stop_timeout',
    );
  } catch (_) {}
}

void Function() performanceMetricStopper(HttpRequestPerformanceMetric? metric) {
  var stopped = false;
  return () {
    if (stopped) return;
    stopped = true;
    unawaited(stopPerformanceMetric(metric));
  };
}

String? headerValue(Map<String, String> headers, String name) {
  final normalizedName = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == normalizedName) {
      return entry.value;
    }
  }
  return null;
}

int? responsePayloadSizeFromHeaders(Map<String, String> headers) {
  final raw = headerValue(headers, 'content-length')?.trim();
  if (raw == null || raw.isEmpty) return null;
  final value = int.tryParse(raw);
  return nonNegativeContentLength(value);
}

int? nonNegativeContentLength(int? value) {
  if (value == null || value < 0) return null;
  return value;
}

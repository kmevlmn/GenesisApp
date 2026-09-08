import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app/telemetry/genesis_telemetry.dart';
import 'api_request_trace_sampling.dart';
import 'api_exception.dart';
import 'genesis_http_transport_pool.dart';
import 'http_transport.dart';
import 'multipart_body.dart';

class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.bodyBytes,
    required this.data,
    required this.uri,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final List<int> bodyBytes;
  final Object? data;
  final Uri uri;
}

enum ApiResponseType { json, text, bytes }

enum ApiRequestTracePolicy { standard, always, excluded }

typedef ApiResponseProcessor = Object? Function(ApiResponse response);
typedef RequestHeaderProvider = Future<Map<String, String>> Function();
typedef ApiRequestSender =
    Future<TransportResponse> Function(TransportRequest request);
typedef ApiRequestInterceptor =
    Future<TransportResponse> Function(
      TransportRequest request,
      ApiRequestSender send,
    );

class ApiRetryPolicy {
  const ApiRetryPolicy({
    this.maxAttempts = 1,
    this.methods = const <String>{'GET', 'HEAD'},
    this.exceptionKinds = const <ApiExceptionKind>{
      ApiExceptionKind.transport,
      ApiExceptionKind.timeout,
    },
    this.transportErrorKinds = const <TransportErrorKind>{
      TransportErrorKind.timeout,
      TransportErrorKind.connection,
    },
  });

  static const ApiRetryPolicy none = ApiRetryPolicy(
    maxAttempts: 1,
    methods: <String>{},
    exceptionKinds: <ApiExceptionKind>{},
    transportErrorKinds: <TransportErrorKind>{},
  );

  static const ApiRetryPolicy safe = ApiRetryPolicy(maxAttempts: 2);

  final int maxAttempts;
  final Set<String> methods;
  final Set<ApiExceptionKind> exceptionKinds;
  final Set<TransportErrorKind> transportErrorKinds;

  bool shouldRetry({
    required TransportRequest request,
    required ApiException error,
    required int attempt,
  }) {
    if (attempt >= _effectiveMaxAttempts) return false;
    if (!methods.contains(request.method.trim().toUpperCase())) return false;
    if (!exceptionKinds.contains(error.kind)) return false;
    final transportKind = error.transportErrorKind;
    if (transportKind != null && !transportErrorKinds.contains(transportKind)) {
      return false;
    }
    return true;
  }

  int get _effectiveMaxAttempts => maxAttempts < 1 ? 1 : maxAttempts;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    Map<String, String>? defaultHeaders,
    ApiResponseProcessor? responseProcessor,
    RequestHeaderProvider? requestHeaderProvider,
    ApiRequestInterceptor? requestInterceptor,
    HttpTransport? transport,
    int timeoutMs = 15000,
    ApiRetryPolicy retryPolicy = ApiRetryPolicy.none,
  }) : _baseUri = Uri.parse(baseUrl),
       _defaultHeaders = Map<String, String>.from(defaultHeaders ?? const {}),
       _responseProcessor = responseProcessor ?? defaultResponseProcessor,
       _requestHeaderProvider = requestHeaderProvider,
       _requestInterceptor = requestInterceptor,
       _transport = transport ?? GenesisHttpTransportRegistry.current,
       _timeoutMs = timeoutMs,
       _retryPolicy = retryPolicy;

  final Uri _baseUri;
  final Map<String, String> _defaultHeaders;
  final ApiResponseProcessor _responseProcessor;
  final RequestHeaderProvider? _requestHeaderProvider;
  final ApiRequestInterceptor? _requestInterceptor;
  final HttpTransport _transport;
  final int _timeoutMs;
  final ApiRetryPolicy _retryPolicy;

  ApiClient copyWith({
    String? baseUrl,
    Map<String, String>? defaultHeaders,
    ApiResponseProcessor? responseProcessor,
    RequestHeaderProvider? requestHeaderProvider,
    ApiRequestInterceptor? requestInterceptor,
    HttpTransport? transport,
    int? timeoutMs,
    ApiRetryPolicy? retryPolicy,
  }) {
    return ApiClient(
      baseUrl: baseUrl ?? _baseUri.toString(),
      defaultHeaders: defaultHeaders ?? _defaultHeaders,
      responseProcessor: responseProcessor ?? _responseProcessor,
      requestHeaderProvider: requestHeaderProvider ?? _requestHeaderProvider,
      requestInterceptor: requestInterceptor ?? _requestInterceptor,
      transport: transport ?? _transport,
      timeoutMs: timeoutMs ?? _timeoutMs,
      retryPolicy: retryPolicy ?? _retryPolicy,
    );
  }

  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
    ApiResponseProcessor? responseProcessor,
    NetworkProgressCallback? onSendProgress,
    NetworkProgressCallback? onReceiveProgress,
    NetworkCancellationToken? cancellationToken,
    ApiRequestTracePolicy tracePolicy = ApiRequestTracePolicy.standard,
  }) {
    return request<T>(
      'GET',
      path,
      query: query,
      headers: headers,
      responseProcessor: responseProcessor,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      cancellationToken: cancellationToken,
      tracePolicy: tracePolicy,
    );
  }

  Future<List<int>> getBytes(
    String path, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
    NetworkProgressCallback? onReceiveProgress,
    NetworkCancellationToken? cancellationToken,
    ApiRequestTracePolicy tracePolicy = ApiRequestTracePolicy.standard,
  }) {
    return request<List<int>>(
      'GET',
      path,
      query: query,
      headers: headers,
      responseType: ApiResponseType.bytes,
      onReceiveProgress: onReceiveProgress,
      cancellationToken: cancellationToken,
      tracePolicy: tracePolicy,
    );
  }

  Future<String> getText(
    String path, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
    NetworkProgressCallback? onReceiveProgress,
    NetworkCancellationToken? cancellationToken,
    ApiRequestTracePolicy tracePolicy = ApiRequestTracePolicy.standard,
  }) {
    return request<String>(
      'GET',
      path,
      query: query,
      headers: headers,
      responseType: ApiResponseType.text,
      onReceiveProgress: onReceiveProgress,
      cancellationToken: cancellationToken,
      tracePolicy: tracePolicy,
    );
  }

  Future<List<int>> downloadBytes(
    String path, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
    NetworkProgressCallback? onReceiveProgress,
    NetworkCancellationToken? cancellationToken,
    ApiRequestTracePolicy tracePolicy = ApiRequestTracePolicy.standard,
  }) {
    return getBytes(
      path,
      query: query,
      headers: headers,
      onReceiveProgress: onReceiveProgress,
      cancellationToken: cancellationToken,
      tracePolicy: tracePolicy,
    );
  }

  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? body,
    Map<String, String>? headers,
    ApiResponseProcessor? responseProcessor,
    NetworkProgressCallback? onSendProgress,
    NetworkProgressCallback? onReceiveProgress,
    NetworkCancellationToken? cancellationToken,
    ApiRequestTracePolicy tracePolicy = ApiRequestTracePolicy.standard,
  }) {
    return request<T>(
      'POST',
      path,
      query: query,
      body: body,
      headers: headers,
      responseProcessor: responseProcessor,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      cancellationToken: cancellationToken,
      tracePolicy: tracePolicy,
    );
  }

  Future<T> put<T>(
    String path, {
    Map<String, Object?>? query,
    Object? body,
    Map<String, String>? headers,
    ApiResponseProcessor? responseProcessor,
    NetworkProgressCallback? onSendProgress,
    NetworkProgressCallback? onReceiveProgress,
    NetworkCancellationToken? cancellationToken,
    ApiRequestTracePolicy tracePolicy = ApiRequestTracePolicy.standard,
  }) {
    return request<T>(
      'PUT',
      path,
      query: query,
      body: body,
      headers: headers,
      responseProcessor: responseProcessor,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      cancellationToken: cancellationToken,
      tracePolicy: tracePolicy,
    );
  }

  Future<T> delete<T>(
    String path, {
    Map<String, Object?>? query,
    Object? body,
    Map<String, String>? headers,
    ApiResponseProcessor? responseProcessor,
    NetworkProgressCallback? onSendProgress,
    NetworkProgressCallback? onReceiveProgress,
    NetworkCancellationToken? cancellationToken,
    ApiRequestTracePolicy tracePolicy = ApiRequestTracePolicy.standard,
  }) {
    return request<T>(
      'DELETE',
      path,
      query: query,
      body: body,
      headers: headers,
      responseProcessor: responseProcessor,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      cancellationToken: cancellationToken,
      tracePolicy: tracePolicy,
    );
  }

  Future<T> request<T>(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
    Map<String, String>? headers,
    ApiResponseProcessor? responseProcessor,
    NetworkProgressCallback? onSendProgress,
    NetworkProgressCallback? onReceiveProgress,
    NetworkCancellationToken? cancellationToken,
    ApiResponseType responseType = ApiResponseType.json,
    ApiRequestTracePolicy tracePolicy = ApiRequestTracePolicy.standard,
  }) async {
    final stopwatch = Stopwatch()..start();
    final budget = Duration(milliseconds: _timeoutMs);
    Duration remainingBudget() {
      cancellationToken?.throwIfCancelled();
      final remaining = budget - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('HTTP request deadline exceeded.', budget);
      }
      return remaining;
    }

    late final Uri uri;
    try {
      uri = _resolveUri(path, query);
    } catch (error) {
      stopwatch.stop();
      final unresolvedRequest = _ApiCollectRequest.maybeCreateForPath(
        _tracePathForUnresolvedRequest(_baseUri, path),
        tracePolicy: tracePolicy,
      );
      unresolvedRequest?.failure(
        duration: stopwatch.elapsed,
        error: error,
        clientFailureCode: ApiClientFailureCode.invalidUri,
      );
      rethrow;
    }
    final collectRequest = _ApiCollectRequest.maybeCreate(
      uri,
      tracePolicy: tracePolicy,
    );

    late final TransportRequest request;
    var requestPreparationFailureCode = ApiClientFailureCode.requestHeaders;
    try {
      final runtimeHeaders = await runWithNetworkDeadline(
        timeout: remainingBudget(),
        cancellationToken: cancellationToken,
        action: (_) => _resolveRequestHeaders(),
      );
      final mergedHeaders = <String, String>{
        ..._defaultHeaders,
        ...runtimeHeaders,
        ...?headers,
      };
      requestPreparationFailureCode = body is MultipartBody
          ? ApiClientFailureCode.multipartFileRead
          : ApiClientFailureCode.requestBodySerialization;
      final prepared = _prepareBody(body, mergedHeaders);

      request = TransportRequest(
        method: method,
        uri: uri,
        headers: mergedHeaders,
        bodyBytes: prepared.bodyBytes,
        timeoutMs: _timeoutMs,
        decodeResponseBody: responseType != ApiResponseType.bytes,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
        cancellationToken: cancellationToken,
      );
    } on NetworkRequestCancelledException catch (error) {
      stopwatch.stop();
      collectRequest?.failure(
        duration: stopwatch.elapsed,
        error: error,
        clientFailureCode: ApiClientFailureCode.cancelled,
      );
      rethrow;
    } on TimeoutException catch (error) {
      stopwatch.stop();
      final apiError = _transportApiException(error, uri);
      collectRequest?.failure(duration: stopwatch.elapsed, error: apiError);
      throw apiError;
    } on ApiException catch (error) {
      stopwatch.stop();
      collectRequest?.failure(duration: stopwatch.elapsed, error: error);
      rethrow;
    } catch (error) {
      stopwatch.stop();
      collectRequest?.failure(
        duration: stopwatch.elapsed,
        error: error,
        clientFailureCode: requestPreparationFailureCode,
      );
      rethrow;
    }

    TransportResponse transportResponse;
    late Stopwatch attemptStopwatch;
    Duration? transportDuration;
    Stopwatch? activeTransportStopwatch;
    Duration attemptDuration() =>
        transportDuration ??
        activeTransportStopwatch?.elapsed ??
        attemptStopwatch.elapsed;
    var attempt = 1;
    var retryCount = 0;
    while (true) {
      attemptStopwatch = Stopwatch()..start();
      transportDuration = null;
      activeTransportStopwatch = null;
      Future<TransportResponse> sendWithTiming(
        TransportRequest outgoingRequest,
      ) async {
        final transportStopwatch = Stopwatch()..start();
        activeTransportStopwatch = transportStopwatch;
        transportDuration = null;
        try {
          return await _send(outgoingRequest);
        } finally {
          transportStopwatch.stop();
          transportDuration = transportStopwatch.elapsed;
        }
      }

      try {
        transportResponse = await runWithNetworkDeadline(
          timeout: remainingBudget(),
          cancellationToken: cancellationToken,
          action: (token) {
            final outgoing = request.withCancellationToken(token);
            Future<TransportResponse> send(TransportRequest signed) {
              // A shared initialization can finish after this request times out.
              // It may serve other callers, but this caller must never dispatch.
              token.throwIfCancelled();
              return sendWithTiming(signed.withCancellationToken(token));
            }

            final interceptor = _requestInterceptor;
            return interceptor == null
                ? send(outgoing)
                : interceptor(outgoing, send);
          },
        );
        break;
      } on NetworkRequestCancelledException catch (e) {
        attemptStopwatch.stop();
        stopwatch.stop();
        collectRequest?.failure(
          duration: attemptDuration(),
          error: e,
          clientFailureCode: ApiClientFailureCode.cancelled,
          retryCount: retryCount,
        );
        _recordHttpTelemetry(
          request: request,
          duration: stopwatch.elapsed,
          outcome: 'cancelled',
          errorType: e.runtimeType.toString(),
          errorKind: ApiExceptionKind.cancelled,
          attemptCount: attempt,
          retryCount: retryCount,
        );
        rethrow;
      } on ApiException catch (error) {
        if (stopwatch.elapsed < budget &&
            cancellationToken?.isCancelled != true &&
            _retryPolicy.shouldRetry(
              request: request,
              error: error,
              attempt: attempt,
            )) {
          attemptStopwatch.stop();
          retryCount += 1;
          _recordHttpRetryTelemetry(
            request: request,
            attempt: attempt,
            retryCount: retryCount,
            error: error,
          );
          attempt += 1;
          continue;
        }
        attemptStopwatch.stop();
        stopwatch.stop();
        collectRequest?.failure(
          duration: attemptDuration(),
          error: error,
          retryCount: retryCount,
        );
        _recordHttpTelemetry(
          request: request,
          duration: stopwatch.elapsed,
          outcome: 'api_exception',
          errorType: error.runtimeType.toString(),
          errorKind: error.kind,
          transportErrorKind: error.transportErrorKind,
          retryable: error.retryable,
          attemptCount: attempt,
          retryCount: retryCount,
        );
        rethrow;
      } catch (error) {
        final apiError = _transportApiException(error, uri);
        if (stopwatch.elapsed < budget &&
            cancellationToken?.isCancelled != true &&
            _retryPolicy.shouldRetry(
              request: request,
              error: apiError,
              attempt: attempt,
            )) {
          attemptStopwatch.stop();
          retryCount += 1;
          _recordHttpRetryTelemetry(
            request: request,
            attempt: attempt,
            retryCount: retryCount,
            error: apiError,
          );
          attempt += 1;
          continue;
        }
        attemptStopwatch.stop();
        stopwatch.stop();
        collectRequest?.failure(
          duration: attemptDuration(),
          error: apiError,
          retryCount: retryCount,
        );
        _recordHttpTelemetry(
          request: request,
          duration: stopwatch.elapsed,
          outcome: 'transport_exception',
          errorType: error.runtimeType.toString(),
          errorKind: apiError.kind,
          transportErrorKind: apiError.transportErrorKind,
          retryable: apiError.retryable,
          attemptCount: attempt,
          retryCount: retryCount,
        );
        throw apiError;
      }
    }
    attemptStopwatch.stop();

    final bodyBytes = transportResponse.bodyBytes.isEmpty
        ? utf8.encode(transportResponse.body)
        : transportResponse.bodyBytes;
    final isSuccessfulStatus =
        transportResponse.statusCode >= 200 &&
        transportResponse.statusCode < 300;
    final responseBody =
        responseType == ApiResponseType.bytes &&
            !isSuccessfulStatus &&
            transportResponse.body.isEmpty &&
            bodyBytes.isNotEmpty
        ? utf8.decode(bodyBytes, allowMalformed: true)
        : transportResponse.body;
    final decoded = _decodeResponseData(
      responseType: responseType,
      body: responseBody,
      bodyBytes: bodyBytes,
    );
    final apiResponse = ApiResponse(
      statusCode: transportResponse.statusCode,
      headers: transportResponse.headers,
      body: responseBody,
      bodyBytes: bodyBytes,
      data: decoded,
      uri: uri,
    );
    collectRequest?.inspectResponse(
      response: apiResponse,
      responseType: responseType,
      duration: attemptDuration(),
      retryCount: retryCount,
    );

    final processor = responseProcessor ?? _responseProcessor;
    try {
      final processed = processor(apiResponse);
      stopwatch.stop();
      collectRequest?.success(duration: attemptDuration());
      _recordHttpTelemetry(
        request: request,
        response: apiResponse,
        duration: stopwatch.elapsed,
        outcome: 'success',
        attemptCount: attempt,
        retryCount: retryCount,
      );
      return processed as T;
    } on Object catch (error) {
      attemptStopwatch.stop();
      stopwatch.stop();
      collectRequest?.failure(
        duration: attemptDuration(),
        error: error,
        response: apiResponse,
        retryCount: retryCount,
        responseFailureReason: 'response_processing',
      );
      _recordHttpTelemetry(
        request: request,
        response: apiResponse,
        duration: stopwatch.elapsed,
        outcome: 'response_exception',
        errorType: error.runtimeType.toString(),
        errorKind: error is ApiException
            ? error.kind
            : ApiExceptionKind.response,
        transportErrorKind: error is ApiException
            ? error.transportErrorKind
            : null,
        retryable: error is ApiException ? error.retryable : false,
        attemptCount: attempt,
        retryCount: retryCount,
      );
      rethrow;
    }
  }

  static Object? defaultResponseProcessor(ApiResponse response) {
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (ok) return response.data;
    throw ApiException(
      message: 'Something went wrong',
      statusCode: response.statusCode,
      responseBody: response.body,
      responseHeaders: response.headers,
      uri: response.uri,
      kind: ApiExceptionKind.httpStatus,
    );
  }

  Future<Map<String, String>> _resolveRequestHeaders() async {
    final provider = _requestHeaderProvider;
    if (provider == null) return const <String, String>{};
    final headers = await provider();
    return {
      for (final entry in headers.entries)
        if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
          entry.key: entry.value,
    };
  }

  Future<TransportResponse> _send(TransportRequest request) {
    return _transport.send(request);
  }

  Uri _resolveUri(String path, Map<String, Object?>? query) {
    final resolved = _baseUri.resolve(path);
    if (query == null || query.isEmpty) return resolved;

    final qp = <String, String>{
      ...resolved.queryParameters,
      for (final e in query.entries)
        if (e.value != null) e.key: e.value.toString(),
    };
    return resolved.replace(queryParameters: qp);
  }
}

void _recordHttpTelemetry({
  required TransportRequest request,
  required Duration duration,
  required String outcome,
  ApiResponse? response,
  String? errorType,
  ApiExceptionKind? errorKind,
  TransportErrorKind? transportErrorKind,
  bool retryable = false,
  int attemptCount = 1,
  int retryCount = 0,
}) {
  GenesisTelemetry.event(
    'http_request',
    category: 'network.http',
    data: <String, Object?>{
      'method': request.method.toUpperCase(),
      'host': request.uri.host,
      'path': request.uri.path,
      'status_code': response?.statusCode,
      'duration_ms': duration.inMilliseconds,
      'timeout_ms': request.timeoutMs,
      'outcome': outcome,
      'request_family': _requestFamily(request.uri),
      'api_err_no': _apiErrNo(response?.data),
      'error_type': errorType,
      'error_kind': errorKind?.name,
      'transport_error_kind': transportErrorKind?.name,
      'retryable': retryable,
      'attempt_count': attemptCount,
      'retry_count': retryCount,
    },
  );
}

void _recordHttpRetryTelemetry({
  required TransportRequest request,
  required int attempt,
  required int retryCount,
  required ApiException error,
}) {
  GenesisTelemetry.event(
    'http_request_retry',
    category: 'network.http',
    data: <String, Object?>{
      'method': request.method.toUpperCase(),
      'host': request.uri.host,
      'path': request.uri.path,
      'request_family': _requestFamily(request.uri),
      'attempt': attempt,
      'retry_count': retryCount,
      'error_kind': error.kind.name,
      'transport_error_kind': error.transportErrorKind?.name,
      'error_type': error.error?.runtimeType.toString(),
    },
    level: GenesisTelemetryLevel.warning,
  );
}

String _requestFamily(Uri uri) {
  final path = uri.path;
  if (path.startsWith('/aitown-chat/')) return 'chatroom';
  if (path.startsWith('/apix/')) return 'gateway_auth';
  if (path.startsWith('/api/')) return 'business_api';
  return 'other';
}

int? _apiErrNo(Object? data) {
  if (data is! Map) return null;
  final raw = data.containsKey('err_no') ? data['err_no'] : data['errNo'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '');
}

class _ApiCollectRequest {
  _ApiCollectRequest._({required this.path, required this.requestId}) {
    _record(action: 'api_req_start', object3: '', object4: '0');
  }

  static _ApiCollectRequest? maybeCreate(
    Uri uri, {
    required ApiRequestTracePolicy tracePolicy,
  }) {
    return maybeCreateForPath(uri.path, tracePolicy: tracePolicy);
  }

  static _ApiCollectRequest? maybeCreateForPath(
    String path, {
    required ApiRequestTracePolicy tracePolicy,
  }) {
    final normalizedPath = _normalizedApiPath(path);
    final isAlwaysMonitored = _alwaysMonitoredApiPaths.contains(normalizedPath);
    if (!normalizedPath.startsWith('/api/') && !isAlwaysMonitored) return null;
    if (normalizedPath == _businessApiCollectPath) return null;
    if (!isAlwaysMonitored) {
      if (tracePolicy == ApiRequestTracePolicy.excluded) return null;
      if (tracePolicy == ApiRequestTracePolicy.standard &&
          !ApiRequestTraceSampling.enabledForLaunch) {
        return null;
      }
    }
    try {
      return _ApiCollectRequest._(
        path: normalizedPath,
        requestId: newCollectEventId(),
      );
    } catch (_) {
      // Telemetry must never prevent the business request from running.
      return null;
    }
  }

  final String path;
  final String requestId;
  bool _terminalRecorded = false;

  void success({required Duration duration}) {
    if (_terminalRecorded) return;
    _terminalRecorded = true;
    _record(
      action: 'api_req_success',
      object3: '',
      object4: duration.inMilliseconds.toString(),
    );
  }

  void failure({
    required Duration duration,
    Object? error,
    ApiResponse? response,
    ApiClientFailureCode? clientFailureCode,
    String? responseFailureReason,
    int retryCount = 0,
  }) {
    if (_terminalRecorded) return;
    _terminalRecorded = true;
    final outcome = _apiRequestFailureOutcome(
      error: error,
      response: response,
      clientFailureCode: clientFailureCode,
      responseFailureReason: responseFailureReason,
      retryCount: retryCount,
    );
    _record(
      action: outcome.action,
      object3: outcome.object3,
      object4: duration.inMilliseconds.toString(),
      extData: outcome.extData,
    );
  }

  void inspectResponse({
    required ApiResponse response,
    required ApiResponseType responseType,
    required Duration duration,
    required int retryCount,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      failure(duration: duration, response: response, retryCount: retryCount);
      return;
    }
    if (_isMalformedJsonResponse(responseType, response.body)) {
      failure(
        duration: duration,
        response: response,
        responseFailureReason: 'json_decode',
        retryCount: retryCount,
      );
      return;
    }

    if (responseType != ApiResponseType.json) return;
    if (response.data is! Map) {
      failure(
        duration: duration,
        response: response,
        responseFailureReason: response.body.trim().isEmpty
            ? 'empty_body'
            : 'invalid_envelope',
        retryCount: retryCount,
      );
      return;
    }
    final envelope = response.data! as Map;
    final rawErrNo = envelope.containsKey('err_no')
        ? envelope['err_no']
        : envelope['errNo'];
    if (rawErrNo == null) {
      failure(
        duration: duration,
        response: response,
        responseFailureReason: 'missing_err_no',
        retryCount: retryCount,
      );
      return;
    }
    final errNo = _apiErrNo(response.data);
    if (errNo == null) {
      failure(
        duration: duration,
        response: response,
        responseFailureReason: 'invalid_err_no',
        retryCount: retryCount,
      );
      return;
    }
    if (errNo != 0) {
      failure(duration: duration, response: response, retryCount: retryCount);
    }
  }

  void _record({
    required String action,
    required String object3,
    required String object4,
    String extData = '',
  }) {
    try {
      GenesisTelemetry.collectLog(
        actionType: 'monitor',
        action: action,
        object1: path,
        object2: requestId,
        object3: object3,
        object4: object4,
        extData: extData,
      );
    } catch (_) {
      // Telemetry must never change the business request result.
    }
  }
}

const String _appGlobalConfigPath = '/api/v1/app/config';
const String _businessApiCollectPath = '/api/v1/collect';
const Set<String> _alwaysMonitoredApiPaths = <String>{
  _appGlobalConfigPath,
  '/apix/v1/time',
  '/apix/v1/app/device/challenge',
  '/apix/v1/app/device/register',
};

String _normalizedApiPath(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

String _tracePathForUnresolvedRequest(Uri baseUri, String path) {
  final rawPath = path.split(RegExp(r'[?#]')).first;
  if (rawPath.startsWith('/')) return rawPath;
  final basePath = baseUri.path.endsWith('/')
      ? baseUri.path
      : '${baseUri.path}/';
  return '$basePath$rawPath'.replaceAll(RegExp(r'/+'), '/');
}

bool _isMalformedJsonResponse(ApiResponseType responseType, String body) {
  if (responseType != ApiResponseType.json || body.trim().isEmpty) return false;
  try {
    jsonDecode(body);
    return false;
  } catch (_) {
    return true;
  }
}

class _ApiRequestFailureOutcome {
  const _ApiRequestFailureOutcome({
    required this.action,
    required this.object3,
    required this.extData,
  });

  final String action;
  final String object3;
  final String extData;
}

_ApiRequestFailureOutcome _apiRequestFailureOutcome({
  Object? error,
  ApiResponse? response,
  ApiClientFailureCode? clientFailureCode,
  String? responseFailureReason,
  required int retryCount,
}) {
  final apiError = error is ApiException ? error : null;
  final businessExceptionCode = apiError?.kind == ApiExceptionKind.business
      ? apiError?.code
      : null;
  final responseErrNo = _apiErrNo(response?.data);
  final errNo = businessExceptionCode ?? responseErrNo;
  final isSuccessfulHttpResponse =
      response != null &&
      response.statusCode >= 200 &&
      response.statusCode < 300;
  final isBusinessFailure =
      isSuccessfulHttpResponse &&
      errNo != null &&
      errNo != 0 &&
      (businessExceptionCode != null || responseFailureReason == null);
  if (isBusinessFailure) {
    return _ApiRequestFailureOutcome(
      action: 'api_req_fail_biz',
      object3: 'biz_$errNo',
      extData: _minimalFailureExtData(
        message: _responseErrorMessage(response.data),
        retryCount: retryCount,
      ),
    );
  }

  final responseStatus = response?.statusCode;
  final directErrorStatus = apiError?.kind == ApiExceptionKind.gatewayAuth
      ? null
      : apiError?.statusCode;
  final httpStatus = responseStatus ?? directErrorStatus;
  final code =
      clientFailureCode ??
      apiError?.clientFailureCode ??
      _clientFailureCodeFor(error);
  final hasResponseStatus =
      httpStatus != null && httpStatus >= 100 && httpStatus <= 599;
  final object3 = hasResponseStatus
      ? 'tech_http_$httpStatus'
      : 'tech_client_${code.value}';
  final nativeCode = _nativeErrorCode(apiError?.error ?? error);
  final upstreamStatus =
      !hasResponseStatus && apiError?.kind == ApiExceptionKind.gatewayAuth
      ? apiError?.statusCode
      : null;
  final upstreamPath =
      !hasResponseStatus && apiError?.kind == ApiExceptionKind.gatewayAuth
      ? apiError?.uri?.path
      : null;
  String? message;
  if (hasResponseStatus && (httpStatus < 200 || httpStatus >= 300)) {
    message = _responseErrorMessage(response?.data);
  } else if (code == ApiClientFailureCode.unknown) {
    final cause = apiError?.error;
    message = cause == null
        ? apiError?.message ?? (error == null ? null : _safeRawErrorText(error))
        : _safeRawErrorText(cause);
  } else if (code.value >= 1300 ||
      responseFailureReason == 'response_processing') {
    message =
        apiError?.message ?? (error == null ? null : _safeRawErrorText(error));
  }
  return _ApiRequestFailureOutcome(
    action: 'api_req_fail_tech',
    object3: object3,
    extData: _minimalFailureExtData(
      reason: responseFailureReason,
      message: message,
      nativeCode: nativeCode,
      upstreamStatus: upstreamStatus,
      upstreamPath: upstreamPath,
      retryCount: retryCount,
    ),
  );
}

String _minimalFailureExtData({
  String? reason,
  String? field,
  String? message,
  String? nativeCode,
  int? upstreamStatus,
  String? upstreamPath,
  required int retryCount,
}) {
  final details = <String, Object?>{
    if (reason?.trim().isNotEmpty == true) 'reason': reason,
    if (field?.trim().isNotEmpty == true) 'field': field,
    if (message?.trim().isNotEmpty == true)
      'message': _sanitizeErrorMessage(message!),
    if (nativeCode?.trim().isNotEmpty == true) 'native_code': nativeCode,
    if (upstreamStatus != null) 'upstream_status': upstreamStatus,
    if (upstreamPath?.trim().isNotEmpty == true) 'upstream_path': upstreamPath,
    if (retryCount > 0) 'retry_count': retryCount,
  };
  return details.isEmpty ? '' : jsonEncode(details);
}

String? _responseErrorMessage(Object? data) {
  if (data is! Map) return null;
  for (final key in <String>[
    'err_msg',
    'errMsg',
    'err_str',
    'errStr',
    'error',
    'message',
    'detail',
  ]) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) return value;
    if (value is num || value is bool) return value.toString();
  }
  return null;
}

String _sanitizeErrorMessage(String input) {
  var value = input.trim().replaceAll(RegExp(r'[\r\n\t]+'), ' ');
  value = value.replaceAll(
    RegExp(r'https?://[^\s,\])}]+', caseSensitive: false),
    '<url>',
  );
  value = value.replaceAll(
    RegExp(r'\bbearer\s+[^\s,;}]+', caseSensitive: false),
    'Bearer <redacted>',
  );
  value = value.replaceAllMapped(
    RegExp(
      r'\b(authorization|access[_-]?token|refresh[_-]?token|id[_-]?token|password|secret|cookie)\b\s*[:=]\s*[^\s,;}]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=<redacted>',
  );
  value = value.replaceAll(
    RegExp(r'\b[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\b'),
    '<redacted-jwt>',
  );
  const maxLength = 200;
  return value.length <= maxLength ? value : value.substring(0, maxLength);
}

String? _errorCode(String text, String field) {
  final match = RegExp(
    '${RegExp.escape(field)}=(-?\\d+)',
    caseSensitive: false,
  ).firstMatch(text);
  return match?.group(1);
}

String _safeErrorText(Object error) {
  return _safeRawErrorText(error).toLowerCase();
}

String _safeRawErrorText(Object error) {
  try {
    return error.toString();
  } catch (_) {
    return '';
  }
}

Object? _tryDecodeJson(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return input;
  try {
    return jsonDecode(trimmed);
  } catch (_) {
    return input;
  }
}

Object? _decodeResponseData({
  required ApiResponseType responseType,
  required String body,
  required List<int> bodyBytes,
}) {
  switch (responseType) {
    case ApiResponseType.json:
      return _tryDecodeJson(body);
    case ApiResponseType.text:
      return body;
    case ApiResponseType.bytes:
      return bodyBytes;
  }
}

ApiException _transportApiException(Object error, Uri uri) {
  final transportKind = _transportErrorKind(error);
  return ApiException(
    message: 'Request failed',
    error: error,
    uri: uri,
    kind: transportKind == TransportErrorKind.timeout
        ? ApiExceptionKind.timeout
        : ApiExceptionKind.transport,
    transportErrorKind: transportKind,
    clientFailureCode: _clientFailureCodeFor(error),
    retryable:
        transportKind == TransportErrorKind.timeout ||
        transportKind == TransportErrorKind.connection,
  );
}

ApiClientFailureCode _clientFailureCodeFor(Object? error) {
  if (error is NetworkRequestCancelledException) {
    return ApiClientFailureCode.cancelled;
  }
  if (error is ApiException) {
    final explicit = error.clientFailureCode;
    if (explicit != null) return explicit;
    if (error.kind == ApiExceptionKind.gatewayAuth) {
      return ApiClientFailureCode.gatewayOther;
    }
    if (error.kind == ApiExceptionKind.cancelled ||
        error.transportErrorKind == TransportErrorKind.cancelled) {
      return ApiClientFailureCode.cancelled;
    }
    if (error.kind == ApiExceptionKind.timeout ||
        error.transportErrorKind == TransportErrorKind.timeout) {
      return _timeoutFailureCode(error.error ?? error);
    }
    if (error.transportErrorKind == TransportErrorKind.badCertificate) {
      return _tlsFailureCode(error.error ?? error);
    }
    if (error.transportErrorKind == TransportErrorKind.connection) {
      return _connectionFailureCode(error.error ?? error);
    }
    return ApiClientFailureCode.unknown;
  }
  if (error is TimeoutException) return _timeoutFailureCode(error);
  if (error is CertificateException) {
    return ApiClientFailureCode.certificateInvalid;
  }
  if (error is HandshakeException) return ApiClientFailureCode.tlsHandshake;
  if (error is SocketException) return _socketFailureCode(error);

  final signature = _safeErrorText(error ?? '');
  if (signature.contains('cancel')) return ApiClientFailureCode.cancelled;
  if (signature.contains('timeout')) return _timeoutFailureCode(error);
  if (signature.contains('certificate')) {
    return ApiClientFailureCode.certificateInvalid;
  }
  if (signature.contains('tls') || signature.contains('handshake')) {
    return ApiClientFailureCode.tlsHandshake;
  }
  if (_isProtocolNegotiationFailure(signature)) {
    return ApiClientFailureCode.protocolNegotiation;
  }
  if (_looksLikeConnectionFailure(signature)) {
    return _connectionFailureCode(error);
  }
  return ApiClientFailureCode.unknown;
}

ApiClientFailureCode _timeoutFailureCode(Object? error) {
  final signature = _safeErrorText(error ?? '');
  if (signature.contains('connecttimeout') ||
      signature.contains('connection timeout') ||
      signature.contains('connect timeout')) {
    return ApiClientFailureCode.connectTimeout;
  }
  if (signature.contains('sendtimeout') || signature.contains('send timeout')) {
    return ApiClientFailureCode.sendTimeout;
  }
  if (signature.contains('receivetimeout') ||
      signature.contains('receive timeout') ||
      signature.contains('response timeout')) {
    return ApiClientFailureCode.receiveTimeout;
  }
  return ApiClientFailureCode.timeoutUnknownPhase;
}

ApiClientFailureCode _tlsFailureCode(Object error) {
  if (error is CertificateException ||
      _safeErrorText(error).contains('certificate')) {
    return ApiClientFailureCode.certificateInvalid;
  }
  return ApiClientFailureCode.tlsHandshake;
}

ApiClientFailureCode _socketFailureCode(SocketException error) {
  final signature = _safeErrorText(error);
  final nativeCode = error.osError?.errorCode;
  if (signature.contains('failed host lookup') ||
      signature.contains('name or service not known') ||
      signature.contains('nodename nor servname')) {
    return ApiClientFailureCode.dnsLookup;
  }
  if (<int>{51, 65, 101, 113}.contains(nativeCode) ||
      signature.contains('network is unreachable') ||
      signature.contains('no route to host') ||
      signature.contains('not connected to internet')) {
    return ApiClientFailureCode.networkUnavailable;
  }
  if (<int>{61, 111}.contains(nativeCode) ||
      signature.contains('connection refused')) {
    return ApiClientFailureCode.connectionRefused;
  }
  if (<int>{54, 104}.contains(nativeCode) ||
      signature.contains('connection reset') ||
      signature.contains('network connection was lost')) {
    return ApiClientFailureCode.connectionReset;
  }
  if (nativeCode == 32 ||
      signature.contains('broken pipe') ||
      signature.contains('connection closed') ||
      signature.contains('connection terminated')) {
    return ApiClientFailureCode.connectionClosed;
  }
  return ApiClientFailureCode.connectionOther;
}

ApiClientFailureCode _connectionFailureCode(Object? error) {
  if (error is SocketException) return _socketFailureCode(error);
  final signature = _safeErrorText(error ?? '');
  final nativeCode = _nativeErrorCode(error);
  if (signature.contains('failed host lookup') || nativeCode == '-1003') {
    return ApiClientFailureCode.dnsLookup;
  }
  if (signature.contains('network is unreachable') ||
      signature.contains('no route to host') ||
      signature.contains('not connected') ||
      nativeCode == '-1009') {
    return ApiClientFailureCode.networkUnavailable;
  }
  if (signature.contains('connection refused') || nativeCode == '-1004') {
    return ApiClientFailureCode.connectionRefused;
  }
  if (signature.contains('connection reset') || nativeCode == '-1005') {
    return ApiClientFailureCode.connectionReset;
  }
  if (signature.contains('broken pipe') ||
      signature.contains('connection closed') ||
      signature.contains('connection terminated')) {
    return ApiClientFailureCode.connectionClosed;
  }
  if (_isProtocolNegotiationFailure(signature)) {
    return ApiClientFailureCode.protocolNegotiation;
  }
  return ApiClientFailureCode.connectionOther;
}

bool _isProtocolNegotiationFailure(String signature) {
  final mentionsProtocol =
      signature.contains('http/2') ||
      signature.contains('http2') ||
      signature.contains('http/3') ||
      signature.contains('http3') ||
      signature.contains('quic');
  return mentionsProtocol &&
      (signature.contains('protocol') ||
          signature.contains('negotiat') ||
          signature.contains('requires http') ||
          signature.contains('not support'));
}

bool _looksLikeConnectionFailure(String signature) {
  return signature.contains('socketexception') ||
      signature.contains('clientexception') ||
      signature.contains('networkclientexception') ||
      signature.contains('cronet') ||
      signature.contains('dioexception') ||
      signature.contains('nserrorclientexception') ||
      signature.contains('connection') ||
      signature.contains('network');
}

String? _nativeErrorCode(Object? error) {
  if (error == null) return null;
  if (error is SocketException) return error.osError?.errorCode.toString();
  final text = _safeRawErrorText(error);
  return _errorCode(text, 'quicDetailedErrorCode') ??
      _errorCode(text, 'errorCode') ??
      _errorCode(text, 'code');
}

TransportErrorKind _transportErrorKind(Object error) {
  if (error is TimeoutException) return TransportErrorKind.timeout;
  final text = _safeErrorText(error);
  if (text.contains('timeout')) return TransportErrorKind.timeout;
  if (text.contains('cancel')) return TransportErrorKind.cancelled;
  if (text.contains('certificate') || text.contains('handshake')) {
    return TransportErrorKind.badCertificate;
  }
  if (text.contains('socketexception') ||
      text.contains('connection reset') ||
      text.contains('connection refused') ||
      text.contains('connection closed') ||
      text.contains('broken pipe') ||
      text.contains('network is unreachable') ||
      text.contains('failed host lookup')) {
    return TransportErrorKind.connection;
  }
  return TransportErrorKind.unknown;
}

class _PreparedBody {
  const _PreparedBody({required this.bodyBytes});

  final List<int>? bodyBytes;
}

_PreparedBody _prepareBody(Object? body, Map<String, String> headers) {
  if (body == null) return const _PreparedBody(bodyBytes: null);

  if (body is MultipartBody) {
    headers['content-type'] = body.contentType;
    return _PreparedBody(bodyBytes: body.toBytes());
  }

  if (body is List<int>) return _PreparedBody(bodyBytes: body);

  if (body is String) {
    return _PreparedBody(bodyBytes: utf8.encode(body));
  }

  if (body is Map || body is List) {
    headers.putIfAbsent('content-type', () => 'application/json');
    return _PreparedBody(bodyBytes: utf8.encode(jsonEncode(body)));
  }

  headers.putIfAbsent('content-type', () => 'text/plain; charset=utf-8');
  return _PreparedBody(bodyBytes: utf8.encode(body.toString()));
}

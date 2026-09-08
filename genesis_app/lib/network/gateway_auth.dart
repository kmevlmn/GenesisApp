import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/telemetry/genesis_telemetry.dart';
import '../platform/channels/genesis_method_channels.dart';
import '../platform/device/device_id_service.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'app_request_headers.dart';
import 'genesis_http_transport_pool.dart';
import 'http_transport.dart';
import 'json_utils.dart';
import 'v1/v1_api_resource.dart';

const String gatewaySignatureAlgorithm = 'ECDSA-P256-SHA256';

class GatewayRequestInterceptor {
  GatewayRequestInterceptor({
    required GatewayAuthCoordinator coordinator,
    GatewayRequestSigner? signer,
  }) : _coordinator = coordinator,
       _signer = signer ?? const GatewayRequestSigner();

  final GatewayAuthCoordinator _coordinator;
  final GatewayRequestSigner _signer;

  Future<TransportResponse> call(
    TransportRequest request,
    ApiRequestSender send,
  ) async {
    if (!isGatewaySignedRequest(request.uri)) {
      return send(_stripVerifiedHeaders(request));
    }

    var timeRetried = false;
    var nonceRetried = false;
    var registrationRetried = false;

    while (true) {
      final context = await _coordinator.signingContext();
      TransportRequest signed;
      final signStopwatch = Stopwatch()..start();
      try {
        signed = await _signer.sign(request, context);
        signStopwatch.stop();
        _gatewayTelemetry(
          'gateway.sign',
          phase: 'sign',
          data: <String, Object?>{
            'path': request.uri.path,
            'duration_ms': signStopwatch.elapsedMilliseconds,
            'outcome': 'success',
          },
        );
      } on ApiException catch (error) {
        signStopwatch.stop();
        _gatewayTelemetry(
          'gateway.sign',
          phase: 'sign',
          data: <String, Object?>{
            'path': request.uri.path,
            'duration_ms': signStopwatch.elapsedMilliseconds,
            'outcome': 'failure',
            'error_type': error.runtimeType.toString(),
            'error_message': error.message,
          },
          level: GenesisTelemetryLevel.warning,
        );
        if (!registrationRetried && isGatewayLocalSignatureError(error)) {
          registrationRetried = true;
          _gatewayTelemetry(
            'gateway.request.retry',
            phase: 'request_retry',
            data: <String, Object?>{
              'path': request.uri.path,
              'reason': 'local_signature_unavailable',
            },
            level: GenesisTelemetryLevel.warning,
          );
          await _coordinator.recoverRegistration(failedKeyId: context.keyId);
          continue;
        }
        rethrow;
      }
      final response = await send(signed);
      // These writes have no idempotency key. Preserve signing, but leave any
      // retry after a server response to the caller, including Gateway errors.
      if (request.method == 'POST' &&
          RegExp(
            r'^/aitown-chat/api/v1/worlds/[^/]+/locations/[^/]+/llm-messages/(batch|select)$',
          ).hasMatch(request.uri.path)) {
        return response;
      }
      final errNo = gatewayErrNo(response.body);
      if (errNo == 20502 && !timeRetried) {
        timeRetried = true;
        _gatewayTelemetry(
          'gateway.request.retry',
          phase: 'request_retry',
          data: <String, Object?>{
            'path': request.uri.path,
            'reason': 'time_20502',
            'err_no': errNo,
          },
          level: GenesisTelemetryLevel.warning,
        );
        await _coordinator.syncServerTime();
        continue;
      }
      if (errNo == 20503 && !nonceRetried) {
        nonceRetried = true;
        _gatewayTelemetry(
          'gateway.request.retry',
          phase: 'request_retry',
          data: <String, Object?>{
            'path': request.uri.path,
            'reason': 'nonce_20503',
            'err_no': errNo,
          },
          level: GenesisTelemetryLevel.warning,
        );
        continue;
      }
      if (isGatewayVerificationError(errNo) && !registrationRetried) {
        registrationRetried = true;
        _gatewayTelemetry(
          'gateway.request.retry',
          phase: 'request_retry',
          data: <String, Object?>{
            'path': request.uri.path,
            'reason': 'verification_20504_20509',
            'err_no': errNo,
          },
          level: GenesisTelemetryLevel.warning,
        );
        await _coordinator.recoverRegistration(failedKeyId: context.keyId);
        continue;
      }
      return response;
    }
  }

  TransportRequest _stripVerifiedHeaders(TransportRequest request) {
    final headers = Map<String, String>.from(request.headers)
      ..removeWhere((key, _) => key.toLowerCase().startsWith('x-verified-'));
    return TransportRequest(
      method: request.method,
      uri: request.uri,
      headers: headers,
      bodyBytes: request.bodyBytes,
      timeoutMs: request.timeoutMs,
      decodeResponseBody: request.decodeResponseBody,
      onSendProgress: request.onSendProgress,
      onReceiveProgress: request.onReceiveProgress,
      cancellationToken: request.cancellationToken,
    );
  }
}

bool isGatewaySignedRequest(Uri uri) {
  return uri.path.startsWith('/api/') || uri.path.startsWith('/aitown-chat/');
}

bool isGatewayLocalSignatureError(ApiException error) {
  return error.message == 'Gateway signature is unavailable' ||
      error.message == 'Gateway public key is unavailable';
}

bool isGatewayVerificationError(int? errNo) {
  return errNo == 20504 ||
      errNo == 20505 ||
      errNo == 20506 ||
      errNo == 20507 ||
      errNo == 20508 ||
      errNo == 20509;
}

int? gatewayErrNo(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final raw = decoded.containsKey('err_no')
        ? decoded['err_no']
        : decoded['errNo'];
    if (raw == null) return null;
    return asInt(raw);
  } catch (_) {
    return null;
  }
}

class GatewayRequestSigner {
  const GatewayRequestSigner();

  Future<TransportRequest> sign(
    TransportRequest request,
    GatewaySigningContext context,
  ) async {
    final bodyHash = gatewayBodySha256(request.bodyBytes);
    final timestamp =
        '${DateTime.now().millisecondsSinceEpoch + context.serverTimeOffsetMs}';
    final nonce = gatewayNonce();
    final canonical = gatewayCanonicalString(
      method: request.method,
      uri: request.uri,
      bodySha256Hex: bodyHash,
      appId: context.appId,
      platform: context.platform,
      deviceId: context.deviceId,
      appVersion: context.appVersion,
      keyId: context.keyId,
      timestampMs: timestamp,
      nonce: nonce,
    );
    final signature = await context.keyStore.signCanonical(canonical);
    final headers = Map<String, String>.from(request.headers)
      ..removeWhere((key, _) => key.toLowerCase().startsWith('x-verified-'))
      ..removeWhere(
        (key, _) => legacyAppPublicHeaderNames.contains(key.toLowerCase()),
      )
      ..addAll({
        'X-App-ID': context.appId,
        'X-Platform': context.platform,
        'X-Device-ID': context.deviceId,
        'X-App-Version': context.appVersion,
        'X-Key-ID': context.keyId,
        'X-Timestamp': timestamp,
        'X-Nonce': nonce,
        'X-Body-SHA256': bodyHash,
        'X-Signature-Alg': gatewaySignatureAlgorithm,
        'X-Signature': signature,
      });
    return TransportRequest(
      method: request.method,
      uri: request.uri,
      headers: headers,
      bodyBytes: request.bodyBytes,
      timeoutMs: request.timeoutMs,
      decodeResponseBody: request.decodeResponseBody,
      onSendProgress: request.onSendProgress,
      onReceiveProgress: request.onReceiveProgress,
      cancellationToken: request.cancellationToken,
    );
  }
}

typedef GatewayHandshakeHeaderSigner =
    Future<Map<String, String>> Function(Uri uri, Map<String, String> headers);
typedef GatewayIdentityProvider = Future<AppRequestIdentity> Function();

GatewayHandshakeHeaderSigner gatewayHandshakeHeaderSigner({
  required GatewayAuthCoordinator coordinator,
  GatewayRequestSigner signer = const GatewayRequestSigner(),
}) {
  return (uri, headers) async {
    var registrationRetried = false;
    while (true) {
      final context = await coordinator.signingContext();
      final request = TransportRequest(
        method: 'GET',
        uri: uri,
        headers: headers,
        bodyBytes: null,
        timeoutMs: 0,
      );
      final stopwatch = Stopwatch()..start();
      try {
        final signed = await signer.sign(request, context);
        stopwatch.stop();
        _gatewayTelemetry(
          'gateway.ws_handshake_sign',
          phase: 'ws_handshake_sign',
          data: <String, Object?>{
            'path': uri.path,
            'duration_ms': stopwatch.elapsedMilliseconds,
            'outcome': 'success',
          },
        );
        return signed.headers;
      } on ApiException catch (error) {
        stopwatch.stop();
        _gatewayTelemetry(
          'gateway.ws_handshake_sign',
          phase: 'ws_handshake_sign',
          data: <String, Object?>{
            'path': uri.path,
            'duration_ms': stopwatch.elapsedMilliseconds,
            'outcome': 'failure',
            'error_message': error.message,
          },
          level: GenesisTelemetryLevel.warning,
        );
        if (!registrationRetried && isGatewayLocalSignatureError(error)) {
          registrationRetried = true;
          _gatewayTelemetry(
            'gateway.request.retry',
            phase: 'request_retry',
            data: <String, Object?>{
              'path': uri.path,
              'reason': 'local_signature_unavailable',
            },
            level: GenesisTelemetryLevel.warning,
          );
          await coordinator.recoverRegistration(failedKeyId: context.keyId);
          continue;
        }
        rethrow;
      }
    }
  };
}

String gatewayBodySha256(List<int>? bodyBytes) {
  return sha256.convert(bodyBytes ?? const <int>[]).toString();
}

String gatewayCanonicalString({
  required String method,
  required Uri uri,
  required String bodySha256Hex,
  required String appId,
  required String platform,
  required String deviceId,
  required String appVersion,
  required String keyId,
  required String timestampMs,
  required String nonce,
}) {
  return [
    method.toUpperCase(),
    uri.path,
    gatewayCanonicalQuery(uri),
    bodySha256Hex,
    '',
    appId,
    platform,
    deviceId,
    appVersion,
    keyId,
    timestampMs,
    nonce,
  ].join('\n');
}

String gatewayCanonicalQuery(Uri uri) {
  final pairs = <MapEntry<String, String>>[];
  for (final entry in uri.queryParametersAll.entries) {
    final values = [...entry.value]..sort();
    for (final value in values) {
      pairs.add(MapEntry(entry.key, value));
    }
  }
  pairs.sort((a, b) {
    final keyCompare = a.key.compareTo(b.key);
    if (keyCompare != 0) return keyCompare;
    return a.value.compareTo(b.value);
  });
  return pairs
      .map((entry) {
        return '${Uri.encodeQueryComponent(entry.key)}='
            '${Uri.encodeQueryComponent(entry.value)}';
      })
      .join('&');
}

String gatewayNonce() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

class GatewayAuthCoordinator {
  GatewayAuthCoordinator({
    required String gatewayBaseUrl,
    required RequestHeaderProvider appHeaderProvider,
    GatewayIdentityProvider? identityProvider,
    required DeviceIdService deviceIdService,
    required GatewayDeviceKeyStore keyStore,
    GatewayRegistrationStore? registrationStore,
    HttpTransport? transport,
  }) : _appHeaderProvider = appHeaderProvider,
       _identityProvider = identityProvider,
       _deviceIdService = deviceIdService,
       _keyStore = keyStore,
       _registrationStore =
           registrationStore ??
           SharedPreferencesGatewayRegistrationStore(
             namespace: gatewayRegistrationNamespace(gatewayBaseUrl),
           ),
       _gatewayBaseUri = Uri.parse(gatewayBaseUrl),
       _transport = transport ?? GenesisHttpTransportRegistry.current {
    _client = ApiClient(
      baseUrl: gatewayBaseUrl,
      defaultHeaders: const {
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      responseProcessor: ApiClient.defaultResponseProcessor,
      transport: _transport,
    );
  }

  final RequestHeaderProvider _appHeaderProvider;
  final GatewayIdentityProvider? _identityProvider;
  final DeviceIdService _deviceIdService;
  final GatewayDeviceKeyStore _keyStore;
  final GatewayRegistrationStore _registrationStore;
  final Uri _gatewayBaseUri;
  final HttpTransport _transport;
  late final ApiClient _client;
  int? _serverTimeOffsetMs;
  Future<void>? _prepareFuture;
  Future<void>? _registrationRecoveryFuture;

  Future<void> prepare({bool forceRegister = false}) async {
    final stopwatch = Stopwatch()..start();
    if (forceRegister) {
      try {
        await _forceRegisterSingleFlight();
        stopwatch.stop();
        _gatewayTelemetry(
          'gateway.prepare',
          phase: 'prepare',
          data: <String, Object?>{
            'duration_ms': stopwatch.elapsedMilliseconds,
            'force_register': true,
            'outcome': 'success',
          },
        );
      } catch (error) {
        stopwatch.stop();
        _gatewayTelemetry(
          'gateway.prepare',
          phase: 'prepare',
          data: <String, Object?>{
            'duration_ms': stopwatch.elapsedMilliseconds,
            'force_register': true,
            'outcome': 'failure',
            'error_type': error.runtimeType.toString(),
          },
          level: GenesisTelemetryLevel.warning,
        );
        rethrow;
      }
      return;
    }
    final pending = _prepareFuture;
    if (pending != null) {
      await pending;
      return;
    }
    final future = _runPrepare();
    _prepareFuture = future;
    try {
      await future;
      stopwatch.stop();
      _gatewayTelemetry(
        'gateway.prepare',
        phase: 'prepare',
        data: <String, Object?>{
          'duration_ms': stopwatch.elapsedMilliseconds,
          'force_register': false,
          'outcome': 'success',
        },
      );
    } catch (_) {
      stopwatch.stop();
      _gatewayTelemetry(
        'gateway.prepare',
        phase: 'prepare',
        data: <String, Object?>{
          'duration_ms': stopwatch.elapsedMilliseconds,
          'force_register': false,
          'outcome': 'failure',
        },
        level: GenesisTelemetryLevel.warning,
      );
      if (identical(_prepareFuture, future)) {
        _prepareFuture = null;
      }
      rethrow;
    }
  }

  Future<GatewaySigningContext> signingContext({
    bool forceRegister = false,
  }) async {
    await prepare(forceRegister: forceRegister);
    final identity = await _identity();
    final keyId = await _registrationStore.readKeyId();
    var offset = _serverTimeOffsetMs;
    offset ??= await syncServerTime();
    if (keyId == null || keyId.trim().isEmpty) {
      throw ApiException(
        message: 'Gateway registration is unavailable',
        kind: ApiExceptionKind.gatewayAuth,
        clientFailureCode: ApiClientFailureCode.gatewayRegistration,
      );
    }
    return GatewaySigningContext(
      appId: identity.appId,
      platform: identity.platform,
      deviceId: identity.deviceId,
      appVersion: identity.appVersion,
      keyId: keyId,
      serverTimeOffsetMs: offset,
      keyStore: _keyStore,
    );
  }

  Future<void> recoverRegistration({required String failedKeyId}) async {
    final normalizedFailedKeyId = failedKeyId.trim();
    final inFlight = _registrationRecoveryFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final currentKeyId = (await _registrationStore.readKeyId())?.trim() ?? '';
    if (currentKeyId.isNotEmpty &&
        normalizedFailedKeyId.isNotEmpty &&
        currentKeyId != normalizedFailedKeyId) {
      return;
    }

    await _forceRegisterSingleFlight();
  }

  Future<void> _forceRegisterSingleFlight() async {
    final inFlight = _registrationRecoveryFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final future = _runPrepare(forceRegister: true);
    _registrationRecoveryFuture = future;
    try {
      await future;
    } finally {
      if (identical(_registrationRecoveryFuture, future)) {
        _registrationRecoveryFuture = null;
      }
    }
  }

  Future<void> _runPrepare({bool forceRegister = false}) async {
    final identity = await _identity();
    if (forceRegister) {
      await _registrationStore.clearKeyId();
      await _keyStore.reset();
    }
    var keyId = await _registrationStore.readKeyId();
    if (keyId == null || keyId.trim().isEmpty) {
      keyId = await _register(identity);
      await _registrationStore.saveKeyId(keyId);
    }
    if (_serverTimeOffsetMs == null) {
      await syncServerTime();
    }
  }

  Future<int> syncServerTime() async {
    final stopwatch = Stopwatch()..start();
    try {
      final serverTimeMs = await _client.get<int>(
        'v1/time',
        responseProcessor: _gatewayServerTimeResponse,
      );
      final offset = serverTimeMs - DateTime.now().millisecondsSinceEpoch;
      _serverTimeOffsetMs = offset;
      stopwatch.stop();
      _gatewayTelemetry(
        'gateway.time_sync',
        phase: 'time_sync',
        data: <String, Object?>{
          'duration_ms': stopwatch.elapsedMilliseconds,
          'offset_ms': offset,
          'outcome': 'success',
        },
      );
      return offset;
    } catch (error) {
      stopwatch.stop();
      _gatewayTelemetry(
        'gateway.time_sync',
        phase: 'time_sync',
        data: <String, Object?>{
          'duration_ms': stopwatch.elapsedMilliseconds,
          'outcome': 'failure',
          'error_type': error.runtimeType.toString(),
        },
        level: GenesisTelemetryLevel.warning,
      );
      throw _gatewayFailure(
        error,
        code: ApiClientFailureCode.gatewayTimeSync,
        message: 'Gateway time synchronization failed',
      );
    }
  }

  Future<void> clearRegistration() async {
    await _registrationStore.clearKeyId();
    _gatewayTelemetry(
      'gateway.clear_registration',
      phase: 'clear_registration',
      data: const <String, Object?>{'outcome': 'success'},
      level: GenesisTelemetryLevel.warning,
    );
  }

  Future<GatewaySignatureVerifyResponse> verifyLocalSignature({
    Object body = const <String, Object?>{},
  }) async {
    final bodyBytes = utf8.encode(jsonEncode(body));
    final context = await signingContext();
    final request = TransportRequest(
      method: 'POST',
      uri: _resolveGatewayUri('v1/app/device/signature/verify'),
      headers: const {
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      bodyBytes: bodyBytes,
      timeoutMs: 15000,
    );
    final signed = await const GatewayRequestSigner().sign(request, context);
    final response = await _transport.send(signed);
    return GatewaySignatureVerifyResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.body,
      data: _tryDecodeGatewayJson(response.body),
    );
  }

  Future<String> _register(GatewayIdentity identity) async {
    final challengeStopwatch = Stopwatch()..start();
    final String registerId;
    try {
      registerId = await _client.post<String>(
        'v1/app/device/challenge',
        body: {
          'app_id': identity.appId,
          'platform': identity.platform,
          'device_id': identity.deviceId,
          'app_version': identity.appVersion,
        },
        responseProcessor: _gatewayChallengeResponse,
      );
      challengeStopwatch.stop();
      _gatewayTelemetry(
        'gateway.challenge',
        phase: 'challenge',
        data: <String, Object?>{
          'duration_ms': challengeStopwatch.elapsedMilliseconds,
          'outcome': 'success',
        },
      );
    } catch (error) {
      challengeStopwatch.stop();
      _gatewayTelemetry(
        'gateway.challenge',
        phase: 'challenge',
        data: <String, Object?>{
          'duration_ms': challengeStopwatch.elapsedMilliseconds,
          'outcome': 'failure',
          'error_type': error.runtimeType.toString(),
        },
        level: GenesisTelemetryLevel.warning,
      );
      throw _gatewayFailure(
        error,
        code: ApiClientFailureCode.gatewayRegistration,
        message: 'Gateway challenge failed',
      );
    }
    final publicKey = await _keyStore.publicKeyBase64Url();
    final registerStopwatch = Stopwatch()..start();
    final String keyId;
    try {
      keyId = await _client.post<String>(
        'v1/app/device/register',
        body: {
          'register_id': registerId,
          'app_id': identity.appId,
          'platform': identity.platform,
          'device_id': identity.deviceId,
          'app_version': identity.appVersion,
          'public_key': publicKey,
          'public_key_hash': gatewayPublicKeyHash(publicKey),
          'attestation': const {'provider': 'dev', 'payload': ''},
        },
        responseProcessor: _gatewayRegistrationResponse,
      );
      registerStopwatch.stop();
      _gatewayTelemetry(
        'gateway.register',
        phase: 'register',
        data: <String, Object?>{
          'duration_ms': registerStopwatch.elapsedMilliseconds,
          'outcome': 'success',
        },
      );
    } catch (error) {
      registerStopwatch.stop();
      _gatewayTelemetry(
        'gateway.register',
        phase: 'register',
        data: <String, Object?>{
          'duration_ms': registerStopwatch.elapsedMilliseconds,
          'outcome': 'failure',
          'error_type': error.runtimeType.toString(),
        },
        level: GenesisTelemetryLevel.warning,
      );
      throw _gatewayFailure(
        error,
        code: ApiClientFailureCode.gatewayRegistration,
        message: 'Gateway registration failed',
      );
    }
    return keyId;
  }

  Future<GatewayIdentity> _identity() async {
    final provided = await _identityProvider?.call();
    final headers = provided == null
        ? await _appHeaderProvider()
        : const <String, String>{};
    final appId = (provided?.appId ?? headers['app-id'] ?? '').trim();
    final platform =
        (provided?.platform ??
                headers['app-platform'] ??
                AppRequestHeaderProvider.resolveCurrentPlatform() ??
                '')
            .trim();
    final appVersion = (provided?.appVersion ?? headers['app-version'] ?? '')
        .trim();
    final deviceId = (await _deviceIdService.getDeviceId()).trim();
    if (appId.isEmpty ||
        platform.isEmpty ||
        appVersion.isEmpty ||
        deviceId.isEmpty) {
      throw ApiException(
        message: 'Gateway identity headers are incomplete',
        kind: ApiExceptionKind.gatewayAuth,
        clientFailureCode: ApiClientFailureCode.gatewayIdentity,
      );
    }
    return GatewayIdentity(
      appId: appId,
      platform: platform,
      deviceId: deviceId,
      appVersion: appVersion,
    );
  }

  Uri _resolveGatewayUri(String path) => _gatewayBaseUri.resolve(path);
}

void _gatewayTelemetry(
  String name, {
  required String phase,
  Map<String, Object?> data = const <String, Object?>{},
  GenesisTelemetryLevel level = GenesisTelemetryLevel.info,
}) {
  GenesisTelemetry.event(
    name,
    category: 'network.gateway',
    data: <String, Object?>{'gateway_phase': phase, ...data},
    level: level,
  );
}

ApiException _gatewayFailure(
  Object error, {
  required ApiClientFailureCode code,
  required String message,
}) {
  final apiError = error is ApiException ? error : null;
  return ApiException(
    message: message,
    statusCode: apiError?.statusCode,
    error: error,
    uri: apiError?.uri,
    kind: ApiExceptionKind.gatewayAuth,
    clientFailureCode: code,
  );
}

Object? _unwrapGatewayData(Object? json) {
  return handleV1ResponseErrNo(json);
}

Object? _gatewayResponseData(ApiResponse response) {
  final json = ApiClient.defaultResponseProcessor(response);
  try {
    return _unwrapGatewayData(json);
  } on ApiException catch (error) {
    throw ApiException(
      message: error.message,
      code: error.code,
      statusCode: response.statusCode,
      error: error.error,
      responseBody: response.body,
      responseHeaders: response.headers,
      uri: response.uri,
      kind: error.kind,
      transportErrorKind: error.transportErrorKind,
      clientFailureCode: error.clientFailureCode,
      retryable: error.retryable,
    );
  }
}

String _gatewayChallengeResponse(ApiResponse response) {
  final registerId = asString(
    asJsonMap(_gatewayResponseData(response))['register_id'],
  ).trim();
  if (registerId.isEmpty) {
    throw ApiException(
      message: 'Gateway challenge response missing register_id',
      statusCode: response.statusCode,
      responseBody: response.body,
      responseHeaders: response.headers,
      uri: response.uri,
      kind: ApiExceptionKind.gatewayAuth,
      clientFailureCode: ApiClientFailureCode.gatewayRegistration,
    );
  }
  return registerId;
}

String _gatewayRegistrationResponse(ApiResponse response) {
  final keyId = asString(
    asJsonMap(_gatewayResponseData(response))['key_id'],
  ).trim();
  if (keyId.isEmpty) {
    throw ApiException(
      message: 'Gateway register response missing key_id',
      statusCode: response.statusCode,
      responseBody: response.body,
      responseHeaders: response.headers,
      uri: response.uri,
      kind: ApiExceptionKind.gatewayAuth,
      clientFailureCode: ApiClientFailureCode.gatewayRegistration,
    );
  }
  return keyId;
}

int _gatewayServerTimeResponse(ApiResponse response) {
  final serverTimeMs = asInt(
    asJsonMap(_gatewayResponseData(response))['server_time_ms'],
  );
  if (serverTimeMs <= 0) {
    throw ApiException(
      message: 'Gateway time response missing server_time_ms',
      statusCode: response.statusCode,
      responseBody: response.body,
      responseHeaders: response.headers,
      uri: response.uri,
      kind: ApiExceptionKind.gatewayAuth,
      clientFailureCode: ApiClientFailureCode.gatewayTimeSync,
    );
  }
  return serverTimeMs;
}

Object? _tryDecodeGatewayJson(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return input;
  try {
    return jsonDecode(trimmed);
  } catch (_) {
    return input;
  }
}

class GatewaySignatureVerifyResponse {
  const GatewaySignatureVerifyResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.data,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final Object? data;

  String prettyBody() {
    final decoded = data;
    if (decoded == null) return body;
    try {
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return body;
    }
  }
}

String gatewayPublicKeyHash(String publicKeyBase64Url) {
  final normalized = base64Url.normalize(publicKeyBase64Url);
  final bytes = base64Url.decode(normalized);
  return base64Url.encode(sha256.convert(bytes).bytes).replaceAll('=', '');
}

class GatewayIdentity {
  const GatewayIdentity({
    required this.appId,
    required this.platform,
    required this.deviceId,
    required this.appVersion,
  });

  final String appId;
  final String platform;
  final String deviceId;
  final String appVersion;
}

class GatewaySigningContext extends GatewayIdentity {
  const GatewaySigningContext({
    required super.appId,
    required super.platform,
    required super.deviceId,
    required super.appVersion,
    required this.keyId,
    required this.serverTimeOffsetMs,
    required this.keyStore,
  });

  final String keyId;
  final int serverTimeOffsetMs;
  final GatewayDeviceKeyStore keyStore;
}

abstract interface class GatewayDeviceKeyStore {
  Future<String> publicKeyBase64Url();
  Future<String> signCanonical(String canonical);
  Future<void> reset();
}

Future<void> clearGatewayAuthLocalState({
  GatewayDeviceKeyStore keyStore = const NativeGatewayDeviceKeyStore(),
  GatewayRegistrationStore? registrationStore,
}) async {
  if (registrationStore == null) {
    await SharedPreferencesGatewayRegistrationStore.clearAllKeyIds();
  } else {
    await registrationStore.clearKeyId();
  }
  await keyStore.reset();
}

class NativeGatewayDeviceKeyStore implements GatewayDeviceKeyStore {
  const NativeGatewayDeviceKeyStore();

  @override
  Future<String> publicKeyBase64Url() async {
    final value = await GenesisMethodChannels.device.invokeMethod<String>(
      GenesisMethodChannels.gatewayPublicKey,
    );
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      throw ApiException(
        message: 'Gateway public key is unavailable',
        kind: ApiExceptionKind.gatewayAuth,
        clientFailureCode: ApiClientFailureCode.gatewayLocalKey,
      );
    }
    return normalized;
  }

  @override
  Future<String> signCanonical(String canonical) async {
    final value = await GenesisMethodChannels.device.invokeMethod<String>(
      GenesisMethodChannels.signGatewayCanonical,
      {'canonical': canonical},
    );
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      throw ApiException(
        message: 'Gateway signature is unavailable',
        kind: ApiExceptionKind.gatewayAuth,
        clientFailureCode: ApiClientFailureCode.gatewaySigning,
      );
    }
    return normalized;
  }

  @override
  Future<void> reset() async {
    await GenesisMethodChannels.device.invokeMethod<void>(
      GenesisMethodChannels.resetGatewayKey,
    );
  }
}

abstract interface class GatewayRegistrationStore {
  Future<String?> readKeyId();
  Future<void> saveKeyId(String keyId);
  Future<void> clearKeyId();
}

String gatewayRegistrationNamespace(String gatewayBaseUrl) {
  final uri = Uri.tryParse(gatewayBaseUrl.trim());
  if (uri == null || uri.host.trim().isEmpty) {
    return gatewayBaseUrl.trim().toLowerCase();
  }
  final scheme = uri.scheme.trim().toLowerCase();
  final host = uri.host.trim().toLowerCase();
  final defaultPort =
      (scheme == 'https' && uri.port == 443) ||
      (scheme == 'http' && uri.port == 80);
  final port = defaultPort ? '' : ':${uri.port}';
  return '$scheme://$host$port';
}

class SharedPreferencesGatewayRegistrationStore
    implements GatewayRegistrationStore {
  const SharedPreferencesGatewayRegistrationStore({this.namespace = ''});

  static const _legacyKeyIdKey = 'gateway_key_id_v1';
  static const _scopedKeyIdPrefix = 'gateway_key_id_v2_';
  final String namespace;

  String get _keyIdKey {
    final normalized = namespace.trim().toLowerCase();
    if (normalized.isEmpty) return _legacyKeyIdKey;
    final digest = sha256.convert(utf8.encode(normalized)).toString();
    return '$_scopedKeyIdPrefix${digest.substring(0, 16)}';
  }

  @override
  Future<String?> readKeyId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyIdKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> saveKeyId(String keyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyIdKey, keyId.trim());
  }

  @override
  Future<void> clearKeyId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIdKey);
  }

  static Future<void> clearAllKeyIds() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where(
          (key) => key == _legacyKeyIdKey || key.startsWith(_scopedKeyIdPrefix),
        )
        .toList(growable: false);
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

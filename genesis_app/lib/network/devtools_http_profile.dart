import 'package:http_profile/http_profile.dart';

import 'http_transport.dart';
import 'membership_request_privacy.dart';

typedef GenesisHttpProfileFactory =
    HttpClientRequestProfile? Function({
      required DateTime requestStartTime,
      required String requestMethod,
      required String requestUri,
    });

void enableGenesisDevToolsHttpProfiling() {
  if (const bool.fromEnvironment('dart.vm.product')) return;
  HttpClientRequestProfile.profilingEnabled = true;
}

class DevToolsHttpProfile {
  DevToolsHttpProfile._(this._profile, {required bool redactMembershipReport})
    : _redactMembershipReport = redactMembershipReport;

  final HttpClientRequestProfile _profile;
  final bool _redactMembershipReport;
  bool _requestClosed = false;
  bool _responseClosed = false;

  static DevToolsHttpProfile? start(
    TransportRequest request, {
    GenesisHttpProfileFactory profileFactory = _createHttpProfile,
  }) {
    final redactMembershipReport = isMembershipPurchaseReportRequest(
      request.uri,
    );
    if (isPrivateMembershipRequest(request.uri) && !redactMembershipReport) {
      return null;
    }
    try {
      final profile = profileFactory(
        requestStartTime: DateTime.now(),
        requestMethod: request.method,
        requestUri: redactMembershipReport
            ? Uri(
                scheme: request.uri.scheme,
                host: request.uri.host,
                port: request.uri.hasPort ? request.uri.port : null,
                path: request.uri.path,
              ).toString()
            : request.uri.toString(),
      );
      return profile == null
          ? null
          : DevToolsHttpProfile._(
              profile,
              redactMembershipReport: redactMembershipReport,
            );
    } catch (_) {
      return null;
    }
  }

  Future<void> completeRequest(TransportRequest request) async {
    if (_requestClosed) return;
    _requestClosed = true;
    try {
      final requestData = _profile.requestData;
      requestData.headersCommaValues = _redactMembershipReport
          ? membershipReportProfileHeaders(request.headers)
          : request.headers;
      requestData.contentLength = request.bodyBytes?.length ?? 0;
      requestData.followRedirects = true;
      requestData.persistentConnection = true;
      final bodyBytes = request.bodyBytes;
      if (bodyBytes != null && bodyBytes.isNotEmpty) {
        requestData.bodySink.add(
          _redactMembershipReport
              ? membershipReportProfileBody(bodyBytes)
              : bodyBytes,
        );
      }
      _profile.addEvent(
        HttpProfileRequestEvent(
          timestamp: DateTime.now(),
          name: 'HTTP request dispatched',
        ),
      );
    } catch (_) {
      // Profiling is diagnostic-only and must never affect the request.
    }
    try {
      await _profile.requestData.close();
    } catch (_) {
      // Profiling is diagnostic-only and must never affect the request.
    }
  }

  Future<void> completeResponse(TransportResponse response) async {
    if (_responseClosed) return;
    _responseClosed = true;
    final receivedAt = DateTime.now();
    try {
      final responseData = _profile.responseData;
      responseData.startTime = receivedAt;
      responseData.statusCode = response.statusCode;
      responseData.headersCommaValues = _redactMembershipReport
          ? membershipReportProfileHeaders(response.headers)
          : response.headers;
      responseData.contentLength =
          response.responsePayloadSizeBytes ?? response.bodyBytes.length;
      responseData.isRedirect = _isRedirect(response.statusCode);
      responseData.persistentConnection = true;
      if (response.bodyBytes.isNotEmpty) {
        responseData.bodySink.add(
          _redactMembershipReport
              ? membershipReportProfileBody(response.bodyBytes)
              : response.bodyBytes,
        );
      }
      final protocol = response.httpProtocolVersion;
      _profile.connectionInfo = <String, dynamic>{
        'transport': 'dio',
        if (protocol != null) 'httpVersion': protocol,
      };
      _profile.addEvent(
        HttpProfileRequestEvent(
          timestamp: receivedAt,
          name: 'HTTP response received',
        ),
      );
    } catch (_) {
      // Profiling is diagnostic-only and must never affect the response.
    }
    try {
      await _profile.responseData.close();
    } catch (_) {
      // Profiling is diagnostic-only and must never affect the response.
    }
  }

  Future<void> completeWithError(Object error) async {
    if (_responseClosed) return;
    _responseClosed = true;
    try {
      await _profile.responseData.closeWithError(
        _redactMembershipReport
            ? error.runtimeType.toString()
            : error.toString(),
      );
    } catch (_) {
      // Profiling is diagnostic-only and must never mask the real error.
    }
  }
}

HttpClientRequestProfile? _createHttpProfile({
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

bool _isRedirect(int statusCode) {
  return statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}

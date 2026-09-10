import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'http_transport.dart';
import 'membership_request_privacy.dart';

const int defaultNetworkCaptureMaxRecords = 200;
const int defaultNetworkCaptureMaxBodyBytes = 40 * 1024 * 1024;

final NetworkCaptureController networkCaptureController =
    NetworkCaptureController();

enum NetworkCaptureStatus { pending, success, error }

class NetworkCaptureBody {
  const NetworkCaptureBody({
    required this.text,
    required this.byteCount,
    required this.contentType,
    required this.binary,
  });

  final String text;
  final int byteCount;
  final String contentType;
  final bool binary;

  bool get isEmpty => text.isEmpty && byteCount == 0;
  int get retainedBytes => utf8.encode(text).length;
}

class NetworkCaptureRecord {
  const NetworkCaptureRecord({
    required this.id,
    required this.method,
    required this.uri,
    required this.startedAt,
    required this.requestHeaders,
    required this.requestQuery,
    required this.requestBody,
    required this.status,
    this.finishedAt,
    this.statusCode,
    this.responseHeaders = const <String, String>{},
    this.responseBody,
    this.httpProtocolVersion,
    this.errorType,
    this.errorMessage,
  });

  final String id;
  final String method;
  final Uri uri;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final Map<String, String> requestHeaders;
  final Map<String, List<String>> requestQuery;
  final NetworkCaptureBody? requestBody;
  final NetworkCaptureStatus status;
  final int? statusCode;
  final Map<String, String> responseHeaders;
  final NetworkCaptureBody? responseBody;
  final String? httpProtocolVersion;
  final String? errorType;
  final String? errorMessage;

  Duration? get duration => finishedAt?.difference(startedAt);

  int get retainedBodyBytes =>
      (requestBody?.retainedBytes ?? 0) + (responseBody?.retainedBytes ?? 0);

  NetworkCaptureRecord copyWith({
    required DateTime finishedAt,
    required NetworkCaptureStatus status,
    int? statusCode,
    Map<String, String> responseHeaders = const <String, String>{},
    NetworkCaptureBody? responseBody,
    String? httpProtocolVersion,
    String? errorType,
    String? errorMessage,
  }) {
    return NetworkCaptureRecord(
      id: id,
      method: method,
      uri: uri,
      startedAt: startedAt,
      finishedAt: finishedAt,
      requestHeaders: requestHeaders,
      requestQuery: requestQuery,
      requestBody: requestBody,
      status: status,
      statusCode: statusCode,
      responseHeaders: responseHeaders,
      responseBody: responseBody,
      httpProtocolVersion: httpProtocolVersion,
      errorType: errorType,
      errorMessage: errorMessage,
    );
  }
}

class NetworkCaptureController extends ChangeNotifier {
  NetworkCaptureController({
    this.maxRecords = defaultNetworkCaptureMaxRecords,
    this.maxBodyBytes = defaultNetworkCaptureMaxBodyBytes,
    bool? available,
  }) : available = available ?? kDebugMode;

  static const String storageKey = 'developer_network_capture_enabled_v1';

  final int maxRecords;
  final int maxBodyBytes;
  final bool available;
  final List<NetworkCaptureRecord> _records = <NetworkCaptureRecord>[];
  bool _enabled = false;
  int _nextId = 1;
  int _revision = 0;
  Future<void>? _pendingSave;

  bool get enabled => _enabled;
  List<NetworkCaptureRecord> get records =>
      List<NetworkCaptureRecord>.unmodifiable(_records);

  Future<bool> loadEnabled() async {
    if (!available) {
      _disableUnavailableCapture();
      return false;
    }
    final revision = _revision;
    var storedValue = false;
    try {
      final preferences = await SharedPreferences.getInstance();
      storedValue = preferences.getBool(storageKey) ?? false;
    } catch (_) {
      storedValue = false;
    }
    if (revision == _revision && storedValue != _enabled) {
      _enabled = storedValue;
      notifyListeners();
    }
    return _enabled;
  }

  Future<void> setEnabled(bool enabled) async {
    if (!available) {
      _disableUnavailableCapture();
      return;
    }
    if (enabled == _enabled && _pendingSave == null) return;
    final previousValue = _enabled;
    final revision = ++_revision;
    _enabled = enabled;
    notifyListeners();
    final save = _saveEnabled(enabled);
    _pendingSave = save;
    try {
      await save;
    } catch (_) {
      if (revision == _revision) {
        _enabled = previousValue;
        notifyListeners();
      }
      rethrow;
    } finally {
      if (identical(_pendingSave, save)) _pendingSave = null;
    }
  }

  Future<void> _saveEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setBool(storageKey, enabled);
    if (!saved) throw StateError('Failed to save network capture setting.');
  }

  String? begin(TransportRequest request) {
    if (isPrivateMembershipRequest(request.uri)) return null;
    if (!available || !_enabled) return null;
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
    final record = NetworkCaptureRecord(
      id: id,
      method: request.method.toUpperCase(),
      uri: request.uri,
      startedAt: DateTime.now(),
      requestHeaders: _copyNetworkCaptureHeaders(request.headers),
      requestQuery: _copyNetworkCaptureQuery(request.uri.queryParametersAll),
      requestBody: captureNetworkRequestBody(request),
      status: NetworkCaptureStatus.pending,
    );
    _records.insert(0, record);
    _enforceLimits();
    notifyListeners();
    return id;
  }

  void complete(String id, TransportResponse response) {
    final index = _records.indexWhere((record) => record.id == id);
    if (index < 0) return;
    final status = response.statusCode >= 200 && response.statusCode < 300
        ? NetworkCaptureStatus.success
        : NetworkCaptureStatus.error;
    _records[index] = _records[index].copyWith(
      finishedAt: DateTime.now(),
      status: status,
      statusCode: response.statusCode,
      responseHeaders: _copyNetworkCaptureHeaders(response.headers),
      responseBody: captureNetworkResponseBody(response),
      httpProtocolVersion: response.httpProtocolVersion,
    );
    _enforceLimits();
    notifyListeners();
  }

  void fail(String id, Object error) {
    final index = _records.indexWhere((record) => record.id == id);
    if (index < 0) return;
    _records[index] = _records[index].copyWith(
      finishedAt: DateTime.now(),
      status: NetworkCaptureStatus.error,
      errorType: error.runtimeType.toString(),
      errorMessage: '$error',
    );
    _enforceLimits();
    notifyListeners();
  }

  void clear() {
    if (_records.isEmpty) return;
    _records.clear();
    notifyListeners();
  }

  void _disableUnavailableCapture() {
    if (!_enabled && _records.isEmpty) return;
    _revision += 1;
    _enabled = false;
    _records.clear();
    notifyListeners();
  }

  void _enforceLimits() {
    bool exceedsLimits() {
      final retainedBytes = _records.fold<int>(
        0,
        (total, record) => total + record.retainedBodyBytes,
      );
      return _records.length > maxRecords || retainedBytes > maxBodyBytes;
    }

    while (exceedsLimits()) {
      var removableIndex = -1;
      for (var index = _records.length - 1; index >= 0; index -= 1) {
        if (_records[index].status != NetworkCaptureStatus.pending) {
          removableIndex = index;
          break;
        }
      }
      if (removableIndex < 0) return;
      if (_records.length == 1) return;
      _records.removeAt(removableIndex);
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _revision += 1;
    _enabled = false;
    _records.clear();
    _nextId = 1;
    notifyListeners();
  }
}

HttpTransport debugNetworkCaptureTransport({
  required HttpTransport delegate,
  bool isDebugBuild = kDebugMode,
  NetworkCaptureController? controller,
}) {
  if (!isDebugBuild) return delegate;
  return RecordingHttpTransport(delegate: delegate, controller: controller);
}

class RecordingHttpTransport implements HttpTransport {
  RecordingHttpTransport({
    required HttpTransport delegate,
    NetworkCaptureController? controller,
  }) : _delegate = delegate,
       _controller = controller ?? networkCaptureController;

  final HttpTransport _delegate;
  final NetworkCaptureController _controller;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    String? captureId;
    try {
      captureId = _controller.begin(request);
    } catch (_) {
      captureId = null;
    }
    try {
      final response = await _delegate.send(request);
      if (captureId != null) {
        try {
          _controller.complete(captureId, response);
        } catch (_) {
          // Diagnostics must never affect the real request.
        }
      }
      return response;
    } catch (error) {
      if (captureId != null) {
        try {
          _controller.fail(captureId, error);
        } catch (_) {
          // Diagnostics must never affect the real request.
        }
      }
      rethrow;
    }
  }
}

Map<String, String> _copyNetworkCaptureHeaders(Map<String, String> input) {
  return Map<String, String>.unmodifiable(input);
}

Map<String, List<String>> _copyNetworkCaptureQuery(
  Map<String, List<String>> input,
) {
  return Map<String, List<String>>.unmodifiable(<String, List<String>>{
    for (final entry in input.entries)
      entry.key: List<String>.unmodifiable(entry.value),
  });
}

NetworkCaptureBody? captureNetworkRequestBody(TransportRequest request) {
  final bytes = request.bodyBytes;
  if (bytes == null || bytes.isEmpty) return null;
  final contentType = _networkContentType(request.headers);
  if (contentType.toLowerCase().startsWith('multipart/form-data')) {
    return _captureMultipartBody(bytes, contentType);
  }
  if (contentType.toLowerCase().contains('x-www-form-urlencoded')) {
    final raw = utf8.decode(bytes, allowMalformed: true);
    try {
      final values = Uri.splitQueryString(raw);
      return NetworkCaptureBody(
        text: Uri(queryParameters: values).query,
        byteCount: bytes.length,
        contentType: contentType,
        binary: false,
      );
    } catch (_) {
      return NetworkCaptureBody(
        text: raw,
        byteCount: bytes.length,
        contentType: contentType,
        binary: false,
      );
    }
  }
  if (_isTextNetworkContentType(contentType)) {
    return NetworkCaptureBody(
      text: utf8.decode(bytes, allowMalformed: true),
      byteCount: bytes.length,
      contentType: contentType,
      binary: false,
    );
  }
  return _binaryNetworkBody(bytes.length, contentType);
}

NetworkCaptureBody? captureNetworkResponseBody(TransportResponse response) {
  final bytes = response.bodyBytes;
  final contentType = _networkContentType(response.headers);
  if (response.body.isNotEmpty && _isTextNetworkContentType(contentType)) {
    return NetworkCaptureBody(
      text: response.body,
      byteCount:
          response.responsePayloadSizeBytes ??
          (bytes.isEmpty ? utf8.encode(response.body).length : bytes.length),
      contentType: contentType,
      binary: false,
    );
  }
  final byteCount = response.responsePayloadSizeBytes ?? bytes.length;
  if (byteCount <= 0) return null;
  return _binaryNetworkBody(byteCount, contentType);
}

NetworkCaptureBody _binaryNetworkBody(int byteCount, String contentType) {
  return NetworkCaptureBody(
    text: '[Binary body: $byteCount bytes]',
    byteCount: byteCount,
    contentType: contentType,
    binary: true,
  );
}

NetworkCaptureBody _captureMultipartBody(List<int> bytes, String contentType) {
  final boundaryMatch = RegExp(
    r'boundary=(?:"([^"]+)"|([^;]+))',
    caseSensitive: false,
  ).firstMatch(contentType);
  final boundary = boundaryMatch?.group(1) ?? boundaryMatch?.group(2)?.trim();
  if (boundary == null || boundary.isEmpty) {
    return NetworkCaptureBody(
      text: jsonEncode(<String, Object?>{
        'multipart': true,
        'payload_bytes': bytes.length,
      }),
      byteCount: bytes.length,
      contentType: contentType,
      binary: true,
    );
  }
  final boundaryBytes = latin1.encode('--$boundary');
  final separator = const <int>[13, 10, 13, 10];
  final fields = <String, String>{};
  final files = <Map<String, Object?>>[];
  var cursor = _indexOfBytes(bytes, boundaryBytes, 0);
  while (cursor >= 0) {
    final headerStart = cursor + boundaryBytes.length + 2;
    final headerEnd = _indexOfBytes(bytes, separator, headerStart);
    if (headerEnd < 0) break;
    final nextBoundary = _indexOfBytes(
      bytes,
      boundaryBytes,
      headerEnd + separator.length,
    );
    if (nextBoundary < 0) break;
    final headers = latin1.decode(bytes.sublist(headerStart, headerEnd));
    final name = RegExp(
      'name="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(headers)?.group(1);
    final filename = RegExp(
      'filename="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(headers)?.group(1);
    var contentLength = nextBoundary - (headerEnd + separator.length);
    if (contentLength >= 2) contentLength -= 2;
    final partContentType = RegExp(
      r'content-type:\s*([^\r\n]+)',
      caseSensitive: false,
    ).firstMatch(headers)?.group(1)?.trim();
    if (filename != null) {
      files.add(<String, Object?>{
        'field': name ?? '',
        'filename': filename,
        'content_type': partContentType ?? '',
        'bytes': contentLength,
      });
    } else if (name != null) {
      final valueStart = headerEnd + separator.length;
      final valueEnd = valueStart + contentLength.clamp(0, bytes.length);
      final value = utf8.decode(
        bytes.sublist(valueStart, valueEnd.clamp(valueStart, bytes.length)),
        allowMalformed: true,
      );
      fields[name] = value;
    }
    cursor = nextBoundary;
  }
  final text = jsonEncode(<String, Object?>{
    'fields': fields,
    'files': files,
    'payload_bytes': bytes.length,
  });
  return NetworkCaptureBody(
    text: text,
    byteCount: bytes.length,
    contentType: contentType,
    binary: true,
  );
}

int _indexOfBytes(List<int> source, List<int> pattern, int start) {
  if (pattern.isEmpty) return start;
  for (var index = start; index <= source.length - pattern.length; index += 1) {
    var matches = true;
    for (var offset = 0; offset < pattern.length; offset += 1) {
      if (source[index + offset] != pattern[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return index;
  }
  return -1;
}

String _networkContentType(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'content-type') return entry.value;
  }
  return '';
}

bool _isTextNetworkContentType(String contentType) {
  final normalized = contentType.toLowerCase();
  if (normalized.isEmpty) return true;
  return normalized.startsWith('text/') ||
      normalized.contains('json') ||
      normalized.contains('xml') ||
      normalized.contains('javascript') ||
      normalized.contains('x-www-form-urlencoded');
}

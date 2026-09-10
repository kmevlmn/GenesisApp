import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/devtools_http_profile.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/network_capture.dart';
import 'package:genesis_flutter_android/network/platform_http3_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PrivateTransport implements HttpTransport {
  TransportRequest? request;
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    this.request = request;
    return const TransportResponse(statusCode: 200, headers: {}, body: '{}');
  }
}

void main() {
  test(
    'membership requests stay out of capture and native body profiles',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = NetworkCaptureController(available: true);
      await controller.setEnabled(true);
      for (final path in [
        'membership/guest/prepare',
        'membership/guest/purchase/report',
        'membership/purchase/report',
        'membership/restore',
        'membership/claim',
      ]) {
        final request = TransportRequest(
          method: 'POST',
          uri: Uri.parse('https://test.invalid/api/v1/$path'),
          headers: {},
          bodyBytes: utf8.encode('{invalid sensitive body'),
          timeoutMs: 1000,
        );
        expect(controller.begin(request), isNull);
        var profileCreated = false;
        final profile = DevToolsHttpProfile.start(
          request,
          profileFactory:
              ({
                required requestStartTime,
                required requestMethod,
                required requestUri,
              }) {
                profileCreated = true;
                expect(requestUri, 'https://test.invalid/api/v1/$path');
                return null;
              },
        );
        expect(profile, isNull);
        expect(profileCreated, path.endsWith('/purchase/report'));
        final private = _PrivateTransport();
        final transport = PlatformHttp3Transport(
          client: MockClient(
            (_) async =>
                throw StateError('must not enter native body profiler'),
          ),
          nonHttpsTransport: private,
        );
        expect((await transport.send(request)).statusCode, 200);
        expect(private.request, same(request));
      }
      expect(controller.records, isEmpty);
    },
  );
  test(
    'ordinary Gems requests keep their native transport and capture',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = NetworkCaptureController(available: true);
      await controller.setEnabled(true);
      final request = TransportRequest(
        method: 'POST',
        uri: Uri.parse('https://test.invalid/api/v1/gem/purchase/report'),
        headers: {},
        bodyBytes: utf8.encode('{}'),
        timeoutMs: 1000,
      );
      expect(controller.begin(request), isNotNull);
      var nativeRequests = 0;
      final private = _PrivateTransport();
      final transport = PlatformHttp3Transport(
        client: MockClient((_) async {
          nativeRequests++;
          return http.Response('{}', 200);
        }),
        nonHttpsTransport: private,
        performanceMetricReady: () => false,
      );
      await transport.send(request);
      expect(nativeRequests, 1);
      expect(private.request, isNull);
    },
  );
}

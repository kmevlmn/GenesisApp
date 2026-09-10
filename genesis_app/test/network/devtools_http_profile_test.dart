import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/devtools_http_profile.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:http_profile/http_profile.dart';

void main() {
  late bool previousProfilingState;

  setUp(() {
    previousProfilingState = HttpClientRequestProfile.profilingEnabled;
    HttpClientRequestProfile.profilingEnabled = true;
  });

  tearDown(() {
    HttpClientRequestProfile.profilingEnabled = previousProfilingState;
  });

  for (final path in [
    'membership/products',
    'membership/guest/prepare',
    'membership/purchase/report',
    'membership/guest/purchase/report',
    'membership/guest/purchase/check',
    'membership/claim',
  ]) {
    test(
      'Debug $path preserves original request, response and errors',
      () async {
        late HttpClientRequestProfile profile;
        final body = jsonEncode({
          'account_uuid': 'debug-original-uuid',
          'purchase_token': 'debug-original-token',
          'signed_transaction': 'debug-original-jws',
        });
        final request = TransportRequest(
          method: 'POST',
          uri: Uri.parse(
            'https://test.invalid/api/v1/$path?account_uuid=debug-query',
          ),
          headers: const {'Authorization': 'Bearer debug-auth'},
          bodyBytes: utf8.encode(body),
          timeoutMs: 1000,
        );
        DevToolsHttpProfile recorder() => DevToolsHttpProfile.start(
          request,
          profileFactory:
              ({
                required requestStartTime,
                required requestMethod,
                required requestUri,
              }) => profile = HttpClientRequestProfile.profile(
                requestStartTime: requestStartTime,
                requestMethod: requestMethod,
                requestUri: requestUri,
              )!,
        )!;
        final recording = recorder();
        await recording.completeRequest(request);
        final responseBody = jsonEncode({
          'err_no': 0,
          'data': jsonDecode(body),
        });
        await recording.completeResponse(
          TransportResponse(
            statusCode: 200,
            headers: const {'set-cookie': 'debug-cookie'},
            body: responseBody,
            bodyBytes: utf8.encode(responseBody),
          ),
        );
        expect(profile.requestUri, request.uri.toString());
        expect(utf8.decode(profile.requestData.bodyBytes), body);
        expect(profile.requestData.headers?['Authorization'], [
          'Bearer debug-auth',
        ]);
        expect(utf8.decode(profile.responseData.bodyBytes), responseBody);
        expect(profile.responseData.headers?['set-cookie'], ['debug-cookie']);
        expect(utf8.decode(request.bodyBytes!), body);
        final failed = recorder();
        await failed.completeRequest(request);
        await failed.completeWithError(StateError('debug-original-error'));
        expect(profile.responseData.error, contains('debug-original-error'));
      },
    );
  }

  test(
    'non-Debug guest check profiles redact UUID, headers and response secrets',
    () async {
      late HttpClientRequestProfile profile;
      final request = TransportRequest(
        method: 'POST',
        uri: Uri.parse(
          'https://test.invalid/api/v1/membership/guest/purchase/check',
        ),
        headers: const {
          'Authorization': 'private-auth',
          'X-Device-ID': 'private-device',
        },
        bodyBytes: utf8.encode('{"account_uuid":"private-uuid"}'),
        timeoutMs: 1000,
      );
      final recorder = DevToolsHttpProfile.start(
        request,
        isDebugBuild: false,
        profileFactory:
            ({
              required requestStartTime,
              required requestMethod,
              required requestUri,
            }) => profile = HttpClientRequestProfile.profile(
              requestStartTime: requestStartTime,
              requestMethod: requestMethod,
              requestUri: requestUri,
            )!,
      )!;
      await recorder.completeRequest(request);
      await recorder.completeResponse(
        TransportResponse(
          statusCode: 200,
          headers: const {'set-cookie': 'private-cookie'},
          body:
              '{"err_no":0,"err_msg":"private-error","data":{"has_unbound_order":true,"account_uuid":"private-uuid"}}',
          bodyBytes: utf8.encode(
            '{"err_no":0,"err_msg":"private-error","data":{"has_unbound_order":true,"account_uuid":"private-uuid"}}',
          ),
        ),
      );
      expect(jsonDecode(utf8.decode(profile.requestData.bodyBytes)), {
        'account_uuid': '[REDACTED]',
      });
      expect(jsonDecode(utf8.decode(profile.responseData.bodyBytes)), {
        'err_no': 0,
        'data': {'has_unbound_order': true},
      });
      expect(
        profile.requestData.headers.toString(),
        isNot(contains('private-')),
      );
      expect(
        profile.responseData.headers.toString(),
        isNot(contains('private-')),
      );
      expect(utf8.decode(request.bodyBytes!), contains('private-uuid'));
    },
  );

  test(
    'non-Debug catalog profiles retain display data but redact nested upgrade credentials',
    () async {
      late HttpClientRequestProfile profile;
      final request = TransportRequest(
        method: 'GET',
        uri: Uri.parse(
          'https://test.invalid/api/v1/membership/products?provider=google',
        ),
        headers: const {
          'authorization': 'private-login',
          'X-Device-ID': 'private-device',
        },
        bodyBytes: null,
        timeoutMs: 1000,
      );
      final recorder = DevToolsHttpProfile.start(
        request,
        isDebugBuild: false,
        profileFactory:
            ({
              required requestStartTime,
              required requestMethod,
              required requestUri,
            }) => profile = HttpClientRequestProfile.profile(
              requestStartTime: requestStartTime,
              requestMethod: requestMethod,
              requestUri: requestUri,
            )!,
      )!;
      final product = {
        'provider': 'google',
        'plan_code': 'pro_yearly',
        'title': 'Server title',
        'account_uuid': 'private-uuid',
        'purchase_token': 'private-token',
        'price_amount': 9999,
        'can_purchase': true,
        'purchase_block_reason': '',
        'benefits': [
          {
            'title': 'Server benefit',
            'code': 'test',
            'icon_key': 'blue_gem',
            'display_type': 'included',
            'unexpected_credential': 'private-benefit',
          },
        ],
      };
      final body = jsonEncode({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {
          'list': [product],
        },
      });
      await recorder.completeRequest(request);
      await recorder.completeResponse(
        TransportResponse(
          statusCode: 200,
          headers: const {
            'cache-control': 'no-store',
            'set-cookie': 'private-cookie',
          },
          body: body,
          bodyBytes: utf8.encode(body),
        ),
      );
      final recordedBody = utf8.decode(profile.responseData.bodyBytes);
      final recorded = jsonDecode(recordedBody)['data']['list'][0];
      expect(recorded['title'], 'Server title');
      expect(recorded['price_amount'], 9999);
      expect(recorded['can_purchase'], isTrue);
      expect(recorded['benefits'][0]['title'], 'Server benefit');
      expect(recorded['account_uuid'], '[REDACTED]');
      expect(recorded['purchase_token'], '[REDACTED]');
      expect(recordedBody, isNot(contains('private-')));
      expect(
        profile.requestData.headers.toString(),
        isNot(contains('private-')),
      );
      expect(
        profile.responseData.headers.toString(),
        isNot(contains('private-')),
      );
      expect(product['purchase_token'], 'private-token');
    },
  );

  test('enables native HTTP profiling before bootstrap requests', () {
    HttpClientRequestProfile.profilingEnabled = false;

    enableGenesisDevToolsHttpProfiling();

    expect(HttpClientRequestProfile.profilingEnabled, true);
  });

  test('records transport-neutral request and response for DevTools', () async {
    late HttpClientRequestProfile capturedProfile;
    final request = TransportRequest(
      method: 'POST',
      uri: Uri.parse('https://api.worldo.ai/api/v1/search'),
      headers: const {
        'content-type': 'application/json',
        'x-request-id': 'request-1',
      },
      bodyBytes: const [1, 2, 3],
      timeoutMs: 5000,
    );
    final recorder = DevToolsHttpProfile.start(
      request,
      profileFactory:
          ({
            required requestStartTime,
            required requestMethod,
            required requestUri,
          }) {
            capturedProfile = HttpClientRequestProfile.profile(
              requestStartTime: requestStartTime,
              requestMethod: requestMethod,
              requestUri: requestUri,
            )!;
            return capturedProfile;
          },
    );

    expect(recorder, isNotNull);
    await recorder!.completeRequest(request);
    await recorder.completeResponse(
      const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json', 'content-length': '4'},
        body: 'done',
        bodyBytes: [100, 111, 110, 101],
        responsePayloadSizeBytes: 4,
        httpProtocolVersion: 'h2',
      ),
    );

    expect(capturedProfile.requestMethod, 'POST');
    expect(capturedProfile.requestUri, 'https://api.worldo.ai/api/v1/search');
    expect(capturedProfile.requestData.headers, {
      'content-type': ['application/json'],
      'x-request-id': ['request-1'],
    });
    expect(capturedProfile.requestData.bodyBytes, [1, 2, 3]);
    expect(capturedProfile.requestData.endTime, isNotNull);
    expect(capturedProfile.responseData.statusCode, 200);
    expect(capturedProfile.responseData.headers, {
      'content-type': ['application/json'],
      'content-length': ['4'],
    });
    expect(capturedProfile.responseData.bodyBytes, [100, 111, 110, 101]);
    expect(capturedProfile.responseData.endTime, isNotNull);
    expect(capturedProfile.connectionInfo, {
      'transport': 'dio',
      'httpVersion': 'h2',
    });
  });

  test('records transport errors without rethrowing from profiler', () async {
    late HttpClientRequestProfile capturedProfile;
    final request = TransportRequest(
      method: 'GET',
      uri: Uri.parse('https://api.worldo.ai/api/v1/health'),
      headers: const {},
      bodyBytes: null,
      timeoutMs: 5000,
    );
    final recorder = DevToolsHttpProfile.start(
      request,
      profileFactory:
          ({
            required requestStartTime,
            required requestMethod,
            required requestUri,
          }) {
            capturedProfile = HttpClientRequestProfile.profile(
              requestStartTime: requestStartTime,
              requestMethod: requestMethod,
              requestUri: requestUri,
            )!;
            return capturedProfile;
          },
    );

    await recorder!.completeRequest(request);
    await recorder.completeWithError(StateError('connection failed'));

    expect(capturedProfile.requestData.endTime, isNotNull);
    expect(capturedProfile.responseData.error, contains('connection failed'));
    expect(capturedProfile.responseData.endTime, isNotNull);
  });

  test(
    'non-Debug report failures stay visible without leaking non-JSON bodies or error text',
    () async {
      late HttpClientRequestProfile profile;
      final request = TransportRequest(
        method: 'POST',
        uri: Uri.parse(
          'https://test.invalid/api/v1/membership/purchase/report',
        ),
        headers: const {'content-type': 'application/json'},
        bodyBytes: utf8.encode('invalid private-request-token'),
        timeoutMs: 1000,
      );
      DevToolsHttpProfile recorder() => DevToolsHttpProfile.start(
        request,
        isDebugBuild: false,
        profileFactory:
            ({
              required requestStartTime,
              required requestMethod,
              required requestUri,
            }) {
              return profile = HttpClientRequestProfile.profile(
                requestStartTime: requestStartTime,
                requestMethod: requestMethod,
                requestUri: requestUri,
              )!;
            },
      )!;

      final failedResponse = recorder();
      await failedResponse.completeRequest(request);
      await failedResponse.completeResponse(
        TransportResponse(
          statusCode: 500,
          headers: const {'content-type': 'text/html'},
          body: 'invalid private-response-token',
          bodyBytes: utf8.encode('invalid private-response-token'),
        ),
      );
      expect(profile.responseData.statusCode, 500);
      expect(
        jsonDecode(utf8.decode(profile.requestData.bodyBytes)),
        '[REDACTED]',
      );
      expect(
        jsonDecode(utf8.decode(profile.responseData.bodyBytes)),
        '[REDACTED]',
      );

      final failedTransport = recorder();
      await failedTransport.completeRequest(request);
      await failedTransport.completeWithError(
        StateError('private-error-token'),
      );
      expect(profile.responseData.error, 'StateError');
      expect(profile.responseData.endTime, isNotNull);
    },
  );

  for (final path in [
    '/api/v1/membership/purchase/report',
    '/api/v1/membership/guest/purchase/report',
  ]) {
    test(
      'non-Debug $path is visible with redacted credentials and its business result',
      () async {
        late HttpClientRequestProfile profile;
        final body = {
          'provider': 'google',
          'store_product_id': 'premium',
          'purchase_token': 'private-purchase-token',
          'claim_token': 'private-claim-token',
          'transaction_id': 'private-transaction',
        };
        final request = TransportRequest(
          method: 'POST',
          uri: Uri.parse('https://test.invalid$path?token=private-query'),
          headers: const {
            'content-type': 'application/json',
            'Authorization': 'Bearer private-access-token',
            'X-Signature': 'private-signature',
          },
          bodyBytes: utf8.encode(jsonEncode(body)),
          timeoutMs: 1000,
        );
        final recorder = DevToolsHttpProfile.start(
          request,
          isDebugBuild: false,
          profileFactory:
              ({
                required requestStartTime,
                required requestMethod,
                required requestUri,
              }) {
                return profile = HttpClientRequestProfile.profile(
                  requestStartTime: requestStartTime,
                  requestMethod: requestMethod,
                  requestUri: requestUri,
                )!;
              },
        );
        expect(recorder, isNotNull);
        await recorder!.completeRequest(request);
        final response = {
          'err_no': 0,
          'err_msg': 'succ',
          'data': {
            'status': 'completed',
            'report_id': 'report-1',
            'membership_id': 'membership-1',
            'purchase_token': 'private-response-token',
          },
        };
        await recorder.completeResponse(
          TransportResponse(
            statusCode: 200,
            headers: const {
              'content-type': 'application/json',
              'set-cookie': 'private-cookie',
            },
            body: jsonEncode(response),
            bodyBytes: utf8.encode(jsonEncode(response)),
            httpProtocolVersion: 'h2',
          ),
        );
        expect(profile.requestUri, 'https://test.invalid$path');
        expect(profile.requestMethod, 'POST');
        expect(jsonDecode(utf8.decode(profile.requestData.bodyBytes)), {
          ...body,
          'purchase_token': '[REDACTED]',
          'claim_token': '[REDACTED]',
          'transaction_id': '[REDACTED]',
        });
        expect(
          profile.requestData.headers.toString(),
          isNot(contains('private-')),
        );
        expect(
          profile.responseData.headers.toString(),
          isNot(contains('private-')),
        );
        expect(profile.responseData.statusCode, 200);
        final recordedResponse = jsonDecode(
          utf8.decode(profile.responseData.bodyBytes),
        );
        expect(recordedResponse['data']['status'], 'completed');
        expect(recordedResponse['data']['report_id'], 'report-1');
        expect(recordedResponse['data']['purchase_token'], '[REDACTED]');
        expect(profile.requestData.endTime, isNotNull);
        expect(profile.responseData.endTime, isNotNull);
        // Profiling must never replace the actual request payload or headers.
        expect(jsonDecode(utf8.decode(request.bodyBytes!)), body);
        expect(request.headers['Authorization'], 'Bearer private-access-token');
      },
    );
  }
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/genesis_api.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/v1/membership_api.dart';

const _uuid = '4b74ec68-7abc-4cce-a223-e997e31dc811';

class _Transport implements HttpTransport {
  final requests = <TransportRequest>[];
  Object? response;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return TransportResponse(
      statusCode: 200,
      headers: const {'cache-control': 'no-store'},
      body: jsonEncode(response),
    );
  }
}

void main() {
  for (final unbound in [true, false]) {
    test(
      'check sends only original UUID and reads $unbound without caching',
      () async {
        final transport = _Transport()
          ..response = {
            'err_no': 0,
            'err_msg': 'succ',
            'data': {'has_unbound_order': unbound},
          };
        final api = MembershipV1Api(
          ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
        );
        final result = await api.checkGuestPurchase(
          accountUuid: _uuid.toUpperCase(),
        );
        expect(result.hasUnboundOrder, unbound);
        final request = transport.requests.single;
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v1/membership/guest/purchase/check');
        expect(request.uri.query, isEmpty);
        expect(jsonDecode(utf8.decode(request.bodyBytes!)), {
          'account_uuid': _uuid,
        });
        expect(request.headers['Cache-Control'], 'no-store');
        await api.checkGuestPurchase(accountUuid: _uuid);
        expect(transport.requests, hasLength(2));
      },
    );
  }

  for (final value in [null, 'true', 'false', 0, 1, <Object>[]]) {
    test(
      'missing or non-boolean status $value is unknown, never false',
      () async {
        final transport = _Transport()
          ..response = {
            'err_no': 0,
            'data': {if (value != null) 'has_unbound_order': value},
          };
        final api = MembershipV1Api(
          ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
        );
        await expectLater(
          api.checkGuestPurchase(accountUuid: _uuid),
          throwsFormatException,
        );
      },
    );
  }

  test('invalid UUID never reaches the backend', () async {
    final transport = _Transport();
    final api = MembershipV1Api(
      ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
    );
    for (final value in ['', 'device-id', ' $_uuid']) {
      await expectLater(
        api.checkGuestPurchase(accountUuid: value),
        throwsFormatException,
      );
    }
    expect(transport.requests, isEmpty);
  });

  test('business failure cannot be treated as no unbound order', () async {
    final transport = _Transport()
      ..response = {
        'err_no': 5000,
        'err_msg': 'system busy, please try again later',
        'data': {'has_unbound_order': false},
      };
    final api = MembershipV1Api(
      ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
    );
    await expectLater(
      api.checkGuestPurchase(accountUuid: _uuid),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 5000)),
    );
  });

  test('HTTP success without business envelope is not confirmation', () async {
    final transport = _Transport()..response = {'has_unbound_order': true};
    final api = MembershipV1Api(
      ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
    );
    await expectLater(
      api.checkGuestPurchase(accountUuid: _uuid),
      throwsFormatException,
    );
  });

  test('mock cannot invent guest ownership', () async {
    final api = GenesisApi(useMock: true);
    await expectLater(
      api.v1.membership.checkGuestPurchase(accountUuid: _uuid),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 5000)),
    );
  });
}

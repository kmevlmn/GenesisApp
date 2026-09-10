import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_order_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/network/v1/membership_api.dart';

import '../support/membership_fixtures.dart';

class _Transport implements HttpTransport {
  TransportRequest? last;
  Object? response = {
    'err_no': 0,
    'err_msg': 'succ',
    'data': {
      'status': 'completed',
      'report_id': 'report-test',
      'membership_id': 'membership-test',
      'current_grant': null,
    },
  };
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    last = request;
    return TransportResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(response),
    );
  }
}

void main() {
  test(
    'prepare accepts UUID only and rejects a missing or malformed UUID',
    () async {
      final transport = _Transport();
      final api = MembershipV1Api(
        ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
      );
      for (final value in [null, '', 'not-a-uuid']) {
        transport.response = {
          'err_no': 0,
          'data': {'account_uuid': value},
        };
        await expectLater(
          api.prepareGuest(
            provider: MembershipProvider.google,
            deviceId: 'test-device',
          ),
          throwsFormatException,
        );
      }
      transport.response = {
        'err_no': 0,
        'data': {'account_uuid': '4B74EC68-7ABC-4CCE-A223-E997E31DC811'},
      };
      final identity = await api.prepareGuest(
        provider: MembershipProvider.google,
        deviceId: 'test-device',
      );
      expect(identity.toJson(), {
        'account_uuid': '4b74ec68-7abc-4cce-a223-e997e31dc811',
      });
    },
  );

  test(
    'Apple guest report and claim share signed proof and the same request body',
    () async {
      final transport = _Transport();
      final api = MembershipV1Api(
        ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
      );
      final request = MembershipPurchaseRequest(
        product: membershipProduct(provider: MembershipProvider.apple),
        requestId: 'same-guest-operation',
        transactionId: '100',
        signedTransaction: 'header.payload.signature',
        guest: const MembershipGuestIdentity(
          accountUuid: '4b74ec68-7abc-4cce-a223-e997e31dc811',
        ),
      );
      await api.reportPurchase(request);
      expect(
        transport.last!.uri.path,
        '/api/v1/membership/guest/purchase/report',
      );
      final body = jsonDecode(utf8.decode(transport.last!.bodyBytes!));
      expect(body, {
        'provider': 'apple',
        'plan_code': request.product.planCode,
        'store_product_id': request.product.storeProductId,
        'request_id': request.requestId,
        'transaction_id': '100',
        'signed_transaction': 'header.payload.signature',
        'account_uuid': request.guest!.accountUuid,
      });
      await api.claimGuest(request);
      expect(transport.last!.uri.path, '/api/v1/membership/claim');
      expect(jsonDecode(utf8.decode(transport.last!.bodyBytes!)), body);
      transport.last = null;
      await expectLater(
        api.claimGuest(request.withSignedTransaction('')),
        throwsFormatException,
      );
      expect(transport.last, isNull);
    },
  );
  test(
    'eligibility uses the prepare device header and never puts identity in query',
    () async {
      final transport = _Transport()
        ..response = {
          'err_no': 0,
          'data': {'list': []},
        };
      final api = MembershipV1Api(
        ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
      );
      await api.products(
        provider: MembershipProvider.google,
        deviceId: 'device-test',
      );
      expect(transport.last!.uri.path, '/api/v1/membership/products');
      expect(transport.last!.uri.queryParameters, {'provider': 'google'});
      expect(transport.last!.headers['X-Device-ID'], 'device-test');
      expect(transport.last!.headers['Cache-Control'], 'no-store');
      expect(transport.last!.bodyBytes, isNull);
    },
  );

  test(
    'catalog parses original subscription credentials from the response',
    () async {
      const uuid = '8b74ec68-7abc-4cce-a223-e997e31dc811';
      final transport = _Transport()
        ..response = {
          'err_no': 0,
          'data': {
            'list': [
              {
                ...membershipProduct(yearly: true).toJson(),
                'account_uuid': uuid,
                'purchase_token': 'old-subscription-token',
              },
            ],
          },
        };
      final api = MembershipV1Api(
        ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
      );
      final result = await api.products(provider: MembershipProvider.google);
      expect(result.products.single.upgradeAccountUuid, uuid);
      expect(
        result.products.single.upgradePurchaseToken,
        'old-subscription-token',
      );
    },
  );

  test(
    'claim uses session and the original UUID, receipt and request ID',
    () async {
      final transport = _Transport();
      final api = MembershipV1Api(
        ApiClient(
          baseUrl: 'https://test.invalid/api/',
          transport: transport,
          defaultHeaders: {'authorization': 'Bearer test-session'},
        ),
      );
      const identity = MembershipGuestIdentity(
        accountUuid: '4b74ec68-7abc-4cce-a223-e997e31dc811',
      );
      final request = MembershipPurchaseRequest(
        product: membershipProduct(),
        requestId: 'guest-report-key',
        purchaseToken: 'google-token',
        guest: identity,
      );
      for (final status in ['completed', 'accepted', 'rejected']) {
        transport.response = {
          'err_no': 0,
          'data': {
            'account_uuid': identity.accountUuid,
            'status': status,
            'membership': status == 'completed'
                ? {
                    'is_active': false,
                    'has_overlap': false,
                    'subscriptions': [],
                  }
                : null,
            if (status == 'accepted') 'reason': 'processing',
            if (status == 'rejected') 'reason': 'invalid_purchase',
          },
        };
        final result = await api.claimGuest(request);
        expect(result.status.name, status);
        expect(transport.last!.uri.path, '/api/v1/membership/claim');
        expect(transport.last!.headers['authorization'], 'Bearer test-session');
        expect(jsonDecode(utf8.decode(transport.last!.bodyBytes!)), {
          'account_uuid': identity.accountUuid,
          'provider': 'google',
          'plan_code': 'pro_monthly',
          'store_product_id': membershipProduct().storeProductId,
          'request_id': 'guest-report-key',
          'purchase_token': 'google-token',
        });
      }
      for (final status in ['completed', 'accepted', 'rejected']) {
        transport.response = {
          'err_no': 0,
          'data': {'status': status},
        };
        expect((await api.claimGuest(request)).status.name, status);
        transport.response = {
          'err_no': 0,
          'data': {
            'status': status,
            'account_uuid': 123,
            'membership': 'ignored',
            'reason': [],
          },
        };
        expect((await api.claimGuest(request)).status.name, status);
      }
      for (final data in [
        {},
        {'status': null},
        {'status': 'unknown'},
        {'status': 1},
      ]) {
        transport.response = {'err_no': 0, 'data': data};
        await expectLater(api.claimGuest(request), throwsFormatException);
      }
      transport.response = {'err_no': 5000, 'err_msg': 'busy', 'data': null};
      await expectLater(api.claimGuest(request), throwsA(isA<ApiException>()));
    },
  );
  for (final provider in MembershipProvider.values) {
    test('$provider report uses only contracted platform fields', () async {
      final transport = _Transport();
      final api = MembershipV1Api(
        ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
      );
      final request = MembershipPurchaseRequest(
        product: membershipProduct(provider: provider, yearly: true),
        requestId: 'request-test',
        transactionId: 'apple-transaction',
        purchaseToken: 'google-token',
      );
      final result = await api.reportPurchase(request);
      expect(result.status, MembershipReportStatus.completed);
      expect(transport.last!.uri.path, '/api/v1/membership/purchase/report');
      final body = jsonDecode(utf8.decode(transport.last!.bodyBytes!)) as Map;
      expect(
        body.keys.toSet(),
        provider == MembershipProvider.google
            ? {
                'provider',
                'plan_code',
                'store_product_id',
                'purchase_token',
                'request_id',
              }
            : {
                'provider',
                'plan_code',
                'store_product_id',
                'transaction_id',
                'request_id',
              },
      );
      expect(body['plan_code'], 'pro_yearly');
      expect(body['request_id'], 'request-test');
    });
  }
  test('Google report accepts order identity without a base plan', () async {
    final transport = _Transport();
    final api = MembershipV1Api(
      ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
    );
    final request = MembershipPurchaseRequest(
      product: MembershipOrderProduct.fromJson({
        'provider': 'google',
        'plan_code': 'pro_yearly',
        'store_product_id': 'test_pro',
      }),
      requestId: 'request-without-base-plan',
      purchaseToken: 'verified-by-server-token',
    );
    await api.reportPurchase(request);
    final body = jsonDecode(utf8.decode(transport.last!.bodyBytes!));
    expect(body, {
      'provider': 'google',
      'plan_code': 'pro_yearly',
      'store_product_id': 'test_pro',
      'request_id': 'request-without-base-plan',
      'purchase_token': 'verified-by-server-token',
    });
  });

  test(
    'Google purchase proof remains required when the base plan is absent',
    () async {
      final transport = _Transport();
      final api = MembershipV1Api(
        ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
      );
      await expectLater(
        api.reportPurchase(
          const MembershipPurchaseRequest(
            product: MembershipOrderProduct(
              planCode: 'pro_yearly',
              provider: MembershipProvider.google,
              storeProductId: 'test_pro',
            ),
            requestId: 'missing-proof',
          ),
        ),
        throwsFormatException,
      );
      expect(transport.last, isNull);
    },
  );
  test(
    'guest prepare returns secure identity and guest report uses guest endpoint',
    () async {
      final transport = _Transport();
      final api = MembershipV1Api(
        ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
      );
      transport.response = {
        'err_no': 0,
        'data': {'account_uuid': '4b74ec68-7abc-4cce-a223-e997e31dc811'},
      };
      final identity = await api.prepareGuest(
        provider: MembershipProvider.google,
        deviceId: 'device-test',
      );
      expect(transport.last!.uri.path, '/api/v1/membership/guest/prepare');
      expect(jsonDecode(utf8.decode(transport.last!.bodyBytes!)), {
        'provider': 'google',
        'device_id': 'device-test',
      });
      transport.response = {
        'err_no': 0,
        'data': {'status': 'accepted', 'report_id': 'report-test'},
      };
      final result = await api.reportPurchase(
        MembershipPurchaseRequest(
          product: membershipProduct(),
          requestId: 'request-test',
          purchaseToken: 'token-test',
          guest: identity,
        ),
      );
      expect(result.status, MembershipReportStatus.accepted);
      expect(
        transport.last!.uri.path,
        '/api/v1/membership/guest/purchase/report',
      );
      final body = jsonDecode(utf8.decode(transport.last!.bodyBytes!)) as Map;
      expect(body['account_uuid'], identity.accountUuid);
      expect(body.containsKey('guest_id'), isFalse);
      expect(body.containsKey('claim_token'), isFalse);
      expect(body.containsKey('uid'), isFalse);
      expect(body.containsKey('payload'), isFalse);
      expect(body.containsKey('base_plan_id'), isFalse);
    },
  );
  test('missing envelope, status or report id is not acknowledged', () async {
    final transport = _Transport();
    final api = MembershipV1Api(
      ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
    );
    for (final response in [
      {'status': 'accepted', 'report_id': 'report-test'},
      {
        'err_no': 'invalid',
        'data': {'status': 'accepted', 'report_id': 'report-test'},
      },
      {'err_no': 0, 'data': <String, Object?>{}},
      {
        'err_no': 0,
        'data': {'status': 'accepted'},
      },
      {
        'err_no': 0,
        'data': {'status': 'completed', 'report_id': 'report-test'},
      },
    ]) {
      transport.response = response;
      await expectLater(
        api.reportPurchase(
          MembershipPurchaseRequest(
            product: membershipProduct(),
            requestId: 'request-test',
            purchaseToken: 'token-test',
          ),
        ),
        throwsFormatException,
      );
    }
  });
  test('business errors preserve existing ApiException behavior', () async {
    final transport = _Transport()
      ..response = {'err_no': 5000, 'err_msg': 'system busy', 'data': null};
    final api = MembershipV1Api(
      ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
    );
    await expectLater(
      api.reportPurchase(
        MembershipPurchaseRequest(
          product: membershipProduct(),
          requestId: 'request-test',
          purchaseToken: 'token-test',
        ),
      ),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 5000)),
    );
  });
}

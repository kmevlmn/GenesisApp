import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_order_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/network/models/membership_claim.dart';
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
  for (final provider in MembershipProvider.values) {
    for (final yearly in [false, true]) {
      test(
        '$provider yearly=$yearly guest report and claim keep identical plan-free bodies',
        () async {
          final transport = _Transport();
          final api = MembershipV1Api(
            ApiClient(
              baseUrl: 'https://test.invalid/api/',
              transport: transport,
            ),
          );
          final purchase = MembershipPurchaseRequest(
            product: membershipProduct(provider: provider, yearly: yearly),
            guest: const MembershipGuestIdentity(
              accountUuid: '4b74ec68-7abc-4cce-a223-e997e31dc811',
            ),
            purchaseToken: 'original-token',
            transactionId: 'original-transaction',
            signedTransaction: 'header.payload.signature',
          );
          await api.reportPurchase(purchase);
          final report =
              jsonDecode(utf8.decode(transport.last!.bodyBytes!))
                  as Map<String, dynamic>;
          expect(report, isNot(contains('plan_code')));
          expect(report, isNot(contains('request_id')));
          await api.claimGuest(MembershipClaimRequest.fromPurchase(purchase));
          final claim = jsonDecode(utf8.decode(transport.last!.bodyBytes!));
          expect(transport.last!.uri.path, '/api/v1/membership/claim');
          expect(claim, isNot(contains('plan_code')));
          expect(claim, isNot(contains('request_id')));
          expect(claim, report);
          await api.reportPurchase(purchase);
          expect(jsonDecode(utf8.decode(transport.last!.bodyBytes!)), report);
          await api.claimGuest(MembershipClaimRequest.fromPurchase(purchase));
          expect(jsonDecode(utf8.decode(transport.last!.bodyBytes!)), report);
        },
      );
    }
  }
  test(
    'reinstalled Google claim sends original proof without plan_code',
    () async {
      final transport = _Transport();
      final api = MembershipV1Api(
        ApiClient(
          baseUrl: 'https://test.invalid/api/',
          transport: transport,
          defaultHeaders: {'authorization': 'Bearer test-session'},
        ),
      );
      const request = MembershipClaimRequest(
        provider: MembershipProvider.google,
        storeProductId: 'test-shared-subscription',
        purchaseToken: 'original-google-token',
        guest: MembershipGuestIdentity(
          accountUuid: '4b74ec68-7abc-4cce-a223-e997e31dc811',
        ),
      );
      await api.claimGuest(request);
      expect(transport.last!.uri.path, '/api/v1/membership/claim');
      expect(transport.last!.headers['authorization'], 'Bearer test-session');
      expect(jsonDecode(utf8.decode(transport.last!.bodyBytes!)), {
        'provider': 'google',
        'store_product_id': 'test-shared-subscription',
        'account_uuid': request.guest.accountUuid,
        'purchase_token': 'original-google-token',
      });
    },
  );

  test('claim still requires complete original provider proof', () async {
    final transport = _Transport();
    final api = MembershipV1Api(
      ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
    );
    const guest = MembershipGuestIdentity(
      accountUuid: '4b74ec68-7abc-4cce-a223-e997e31dc811',
    );
    for (final request in [
      const MembershipClaimRequest(
        provider: MembershipProvider.google,
        storeProductId: 'test-pro',
        guest: guest,
      ),
      const MembershipClaimRequest(
        provider: MembershipProvider.google,
        storeProductId: '',
        guest: guest,
        purchaseToken: 'token',
      ),
      const MembershipClaimRequest(
        provider: MembershipProvider.apple,
        storeProductId: 'test-pro',
        guest: guest,
        transactionId: '100',
      ),
      const MembershipClaimRequest(
        provider: MembershipProvider.apple,
        storeProductId: 'test-pro',
        guest: guest,
        signedTransaction: 'header.payload.signature',
      ),
    ]) {
      await expectLater(api.claimGuest(request), throwsFormatException);
      expect(transport.last, isNull);
    }
  });
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
    'Apple guest report and claim share complete proof without plan_code',
    () async {
      final transport = _Transport();
      final api = MembershipV1Api(
        ApiClient(baseUrl: 'https://test.invalid/api/', transport: transport),
      );
      final request = MembershipPurchaseRequest(
        product: membershipProduct(provider: MembershipProvider.apple),
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
        'store_product_id': request.product.storeProductId,
        'transaction_id': '100',
        'signed_transaction': 'header.payload.signature',
        'account_uuid': request.guest!.accountUuid,
      });
      await api.claimGuest(MembershipClaimRequest.fromPurchase(request));
      expect(transport.last!.uri.path, '/api/v1/membership/claim');
      expect(jsonDecode(utf8.decode(transport.last!.bodyBytes!)), body);
      transport.last = null;
      await expectLater(
        api.claimGuest(
          MembershipClaimRequest.fromPurchase(
            request.withSignedTransaction(''),
          ),
        ),
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
    'claim uses session and the original UUID and receipt without a request ID',
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
        final result = await api.claimGuest(
          MembershipClaimRequest.fromPurchase(request),
        );
        expect(result.status.name, status);
        expect(transport.last!.uri.path, '/api/v1/membership/claim');
        expect(transport.last!.headers['authorization'], 'Bearer test-session');
        expect(jsonDecode(utf8.decode(transport.last!.bodyBytes!)), {
          'account_uuid': identity.accountUuid,
          'provider': 'google',
          'store_product_id': membershipProduct().storeProductId,
          'purchase_token': 'google-token',
        });
      }
      for (final status in ['completed', 'accepted', 'rejected']) {
        transport.response = {
          'err_no': 0,
          'data': {'status': status},
        };
        expect(
          (await api.claimGuest(
            MembershipClaimRequest.fromPurchase(request),
          )).status.name,
          status,
        );
        transport.response = {
          'err_no': 0,
          'data': {
            'status': status,
            'account_uuid': 123,
            'membership': 'ignored',
            'reason': [],
          },
        };
        expect(
          (await api.claimGuest(
            MembershipClaimRequest.fromPurchase(request),
          )).status.name,
          status,
        );
      }
      for (final data in [
        {},
        {'status': null},
        {'status': 'unknown'},
        {'status': 1},
      ]) {
        transport.response = {'err_no': 0, 'data': data};
        await expectLater(
          api.claimGuest(MembershipClaimRequest.fromPurchase(request)),
          throwsFormatException,
        );
      }
      transport.response = {'err_no': 5000, 'err_msg': 'busy', 'data': null};
      await expectLater(
        api.claimGuest(MembershipClaimRequest.fromPurchase(request)),
        throwsA(isA<ApiException>()),
      );
    },
  );
  for (final provider in MembershipProvider.values) {
    for (final yearly in [false, true]) {
      test(
        '$provider yearly=$yearly report uses only contracted platform fields',
        () async {
          final transport = _Transport();
          final api = MembershipV1Api(
            ApiClient(
              baseUrl: 'https://test.invalid/api/',
              transport: transport,
            ),
          );
          final request = MembershipPurchaseRequest(
            product: membershipProduct(provider: provider, yearly: yearly),
            transactionId: 'apple-transaction',
            purchaseToken: 'google-token',
          );
          final result = await api.reportPurchase(request);
          expect(result.status, MembershipReportStatus.completed);
          expect(
            transport.last!.uri.path,
            '/api/v1/membership/purchase/report',
          );
          final body =
              jsonDecode(utf8.decode(transport.last!.bodyBytes!)) as Map;
          expect(
            body.keys.toSet(),
            provider == MembershipProvider.google
                ? {'provider', 'store_product_id', 'purchase_token'}
                : {'provider', 'store_product_id', 'transaction_id'},
          );
          expect(body, isNot(contains('plan_code')));
          expect(body, isNot(contains('request_id')));
        },
      );
    }
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
      purchaseToken: 'verified-by-server-token',
    );
    await api.reportPurchase(request);
    final body = jsonDecode(utf8.decode(transport.last!.bodyBytes!));
    expect(body, {
      'provider': 'google',
      'store_product_id': 'test_pro',
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
      expect(body.containsKey('plan_code'), isFalse);
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
          purchaseToken: 'token-test',
        ),
      ),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 5000)),
    );
  });
}

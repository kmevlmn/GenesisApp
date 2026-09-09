import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/genesis_api.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/models/membership_manual_set.dart';
import 'package:genesis_flutter_android/platform/session/memory_user_session_store.dart';

class _Transport implements HttpTransport {
  final requests = <TransportRequest>[];
  Object? response = {
    'err_no': 0,
    'err_msg': 'succ',
    'data': {
      'uid': 'u_test',
      'membership_id': 'manual-test',
      'plan_code': 'pro_yearly',
      'expires_at': 2000000000,
      'auto_renew': false,
      'membership_status': 1,
      'current_grant': null,
      'next_grant_at': null,
    },
  };

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return TransportResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(response),
    );
  }
}

void main() {
  const request = MembershipManualSetRequest(
    uid: ' u_test ',
    planCode: 'pro_yearly',
    expiresAt: 2000000000,
    reason: ' debug membership ',
  );
  late _Transport transport;
  late GenesisApi api;

  setUp(() {
    transport = _Transport();
    api = GenesisApi(
      apiClient: ApiClient(
        baseUrl: 'https://configured.invalid/api/',
        transport: transport,
      ),
    );
  });

  test(
    'facade sends only documented fields to the configured internal route',
    () async {
      final result = await api.v1.membership.setManual(request);
      final sent = transport.requests.single;
      expect(
        sent.uri.toString(),
        'https://configured.invalid/api_internal/v1/membership/set',
      );
      expect(sent.method, 'POST');
      expect(jsonDecode(utf8.decode(sent.bodyBytes!)), {
        'uid': 'u_test',
        'plan_code': 'pro_yearly',
        'expires_at': 2000000000,
        'reason': 'debug membership',
      });
      expect(result.uid, 'u_test');
      expect(result.planCode, 'pro_yearly');
      expect(result.expiresAt, 2000000000);
      expect(result.membershipStatus, 1);
    },
  );

  test(
    'optional reason is omitted and past positive timestamps reach the server',
    () async {
      await api.v1.membership.setManual(
        const MembershipManualSetRequest(
          uid: 'u_test',
          planCode: 'pro_monthly',
          expiresAt: 1,
        ),
      );
      expect(jsonDecode(utf8.decode(transport.requests.single.bodyBytes!)), {
        'uid': 'u_test',
        'plan_code': 'pro_monthly',
        'expires_at': 1,
      });
    },
  );

  test('invalid input never sends an internal mutation', () async {
    for (final invalid in [
      const MembershipManualSetRequest(
        uid: '',
        planCode: 'pro_monthly',
        expiresAt: 1,
      ),
      const MembershipManualSetRequest(
        uid: 'u_test',
        planCode: 'invalid',
        expiresAt: 1,
      ),
      const MembershipManualSetRequest(
        uid: 'u_test',
        planCode: 'pro_yearly',
        expiresAt: 0,
      ),
      MembershipManualSetRequest(
        uid: 'u_test',
        planCode: 'pro_yearly',
        expiresAt: 1,
        reason: 'x' * 513,
      ),
    ]) {
      await expectLater(
        api.v1.membership.setManual(invalid),
        throwsFormatException,
      );
    }
    expect(transport.requests, isEmpty);
  });

  test(
    'business failure is not treated as success or automatically retried',
    () async {
      transport.response = {
        'err_no': 1404,
        'err_msg': 'user not found',
        'data': null,
      };
      await expectLater(
        api.v1.membership.setManual(request),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 1404)),
      );
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'unknown target UID is reported inline without global page navigation',
    () async {
      var pageNotFound = false;
      transport.response = {
        'err_no': 1404,
        'err_msg': 'user not found',
        'data': null,
      };
      final livePipelineApi = GenesisApi(
        transport: transport,
        useMock: false,
        sessionStore: MemoryUserSessionStore(),
        appHeaderProvider: () async => {},
        onPageNotFound: (_) async => pageNotFound = true,
      );
      await expectLater(
        livePipelineApi.v1.membership.setManual(request),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'user not found',
          ),
        ),
      );
      expect(pageNotFound, isFalse);
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'missing envelope and invalid success data cannot show success',
    () async {
      for (final response in [
        {'uid': 'u_test'},
        {'err_no': 0, 'data': null},
        {
          'err_no': 0,
          'data': {
            'uid': 'u_other',
            'plan_code': 'pro_yearly',
            'expires_at': 1,
            'membership_status': 1,
          },
        },
      ]) {
        transport.response = response;
        await expectLater(
          api.v1.membership.setManual(request),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'local mock refuses to pretend a server membership was changed',
    () async {
      final mockApi = GenesisApi(useMock: true);
      await expectLater(
        mockApi.v1.membership.setManual(request),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 5000)),
      );
    },
  );
}

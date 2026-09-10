import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/platform/billing/purchase_toast_diagnostics.dart';

void main() {
  test('long purchase block reasons and guest report paths stay readable', () {
    final info = purchaseDebugInfo(
      'vip.report',
      status: 'rejected',
      reason: 'cross_platform_upgrade_not_allowed',
      error: ApiException(
        message: 'Unavailable',
        uri: Uri.parse(
          'https://example.com/api/v1/membership/guest/purchase/report',
        ),
      ),
    );
    expect(info, contains('reason=cross_platform_upgrade_not_allowed'));
    expect(info, contains('path=/api/v1/membership/guest/purchase/report'));
  });
  test('API diagnostics include failure metadata without request credentials', () {
    final info = purchaseDebugInfo(
      'vip.report',
      error: ApiException(
        message:
            'verification failed\naccount_uuid=4b74ec68-7abc-4cce-a223-e997e31dc811 purchase_token=private-token',
        kind: ApiExceptionKind.business,
        code: 4001,
        statusCode: 400,
        uri: Uri.parse(
          'https://example.com/api/v1/membership/purchase/report?token=private-query',
        ),
        responseBody: 'private-body',
        error: StateError('private-cause'),
      ),
    );
    final text = purchaseToastMessage('VIP purchase failed.', debugInfo: info);
    expect(text.split('\n'), hasLength(2));
    expect(
      text,
      startsWith(
        'debug：vip.report; ApiException; kind=business; code=4001; http=400;',
      ),
    );
    expect(text, contains('path=/api/v1/membership/purchase/report'));
    expect(text, contains('message=verification failed'));
    expect(text, isNot(contains('private-')));
    expect(text, isNot(contains('4b74ec68-7abc')));
    expect(text, endsWith('\nVIP purchase failed.'));
  });

  test('platform errors preserve code and message but omit native details', () {
    final info = purchaseDebugInfo(
      'vip.launch_store',
      error: PlatformException(
        code: 'billing_unavailable',
        message: 'Store disconnected',
        details: {'purchase_token': 'private-token'},
      ),
    );
    expect(
      info,
      contains('code=billing_unavailable; message=Store disconnected'),
    );
    expect(info, isNot(contains('private-token')));
  });
}

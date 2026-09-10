import '../models/membership_product.dart';
import '../models/membership_purchase.dart';
import '../models/membership_claim.dart';
import '../models/membership_manual_set.dart';
import '../models/membership_guest_purchase_check.dart';
import '../api_client.dart';
import '../json_utils.dart';
import 'v1_api_resource.dart';

class MembershipV1Api extends V1ApiResource {
  const MembershipV1Api(super.client);

  /// Debug editor for manual membership; this is a root-level internal route.
  Future<MembershipManualSetResult> setManual(
    MembershipManualSetRequest request,
  ) async {
    final response = await client.post<Object?>(
      '/api_internal/v1/membership/set',
      body: request.toJson(),
      // Here 1404 means the entered UID does not exist, not a missing page.
      responseProcessor: ApiClient.defaultResponseProcessor,
    );
    if (response is! Map || response['err_no'] is! int) {
      throw const FormatException(
        'Missing manual membership response envelope',
      );
    }
    final data = handleV1ResponseErrNo(response);
    if (data is! Map) {
      throw const FormatException('Missing manual membership response data');
    }
    final result = MembershipManualSetResult.fromJson(asJsonMap(data));
    if (result.uid != request.uid.trim()) {
      throw const FormatException('Manual membership response uid mismatch');
    }
    return result;
  }

  /// GET /api/v1/membership/products; each product has its title and benefits.
  Future<MembershipProductList> products({
    required MembershipProvider provider,
    String? deviceId,
  }) async {
    final response = await client.get<Object?>(
      'v1/membership/products',
      query: v1Query({'provider': provider.name}),
      headers: {
        if (deviceId != null) 'X-Device-ID': deviceId,
        'Cache-Control': 'no-store',
      },
      tracePolicy: ApiRequestTracePolicy.excluded,
    );
    return MembershipProductList.fromJson(
      asJsonMap(handleV1ResponseErrNo(response)),
    );
  }

  Future<MembershipGuestIdentity> prepareGuest({
    required MembershipProvider provider,
    required String deviceId,
  }) async {
    return MembershipGuestIdentity.fromJson(
      await _postPrivate('membership/guest/prepare', {
        'provider': provider.name,
        'device_id': deviceId,
      }),
    );
  }

  Future<MembershipPurchaseReport> reportPurchase(
    MembershipPurchaseRequest request,
  ) async {
    return MembershipPurchaseReport.fromJson(
      await _postPrivate(
        request.guest == null
            ? 'membership/purchase/report'
            : 'membership/guest/purchase/report',
        request.toJson(),
      ),
    );
  }

  /// Read-only ownership check. A true result does not mean VIP is active.
  Future<MembershipGuestPurchaseCheck> checkGuestPurchase({
    required String accountUuid,
  }) async {
    if (!isMembershipAccountUuid(accountUuid)) {
      throw const FormatException('Invalid membership guest account UUID');
    }
    return MembershipGuestPurchaseCheck.fromJson(
      await _postPrivate(
        'membership/guest/purchase/check',
        {'account_uuid': accountUuid.toLowerCase()},
        headers: const {'Cache-Control': 'no-store'},
      ),
    );
  }

  Future<MembershipClaimResult> claimGuest(
    MembershipClaimRequest request,
  ) async {
    return MembershipClaimResult.fromJson(
      await _postPrivate('membership/claim', request.toJson()),
    );
  }

  Future<Map<String, dynamic>> _postPrivate(
    String path,
    Map<String, Object?> body, {
    Map<String, String>? headers,
  }) async {
    final response = await client.post<Object?>(
      'v1/$path',
      body: body,
      headers: headers,
      tracePolicy: ApiRequestTracePolicy.excluded,
    );
    // A receipt is acknowledged only by a valid business envelope and status.
    if (response is! Map || response['err_no'] is! int) {
      throw const FormatException('Missing membership response envelope');
    }
    return asJsonMap(handleV1ResponseErrNo(response));
  }
}

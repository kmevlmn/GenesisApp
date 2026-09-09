import 'dart:convert';

/// These bodies contain purchase credentials or one-time guest claim secrets.
bool isPrivateMembershipRequest(Uri uri) => const [
  '/membership/purchase/report',
  '/membership/restore',
  '/membership/guest/prepare',
  '/membership/guest/purchase/report',
  '/membership/claim',
].any(uri.path.endsWith);

/// Purchase reports can be inspected in DevTools using a sanitized copy.
/// Keep their real payloads out of native profiling and persistent capture.
bool isMembershipPurchaseReportRequest(Uri uri) => const [
  '/membership/purchase/report',
  '/membership/guest/purchase/report',
].any(uri.path.endsWith);

Map<String, String> membershipReportProfileHeaders(
  Map<String, String> headers,
) => {
  for (final entry in headers.entries)
    entry.key:
        const {
          'content-type',
          'content-length',
          'content-encoding',
          'accept',
          'date',
          'cache-control',
        }.contains(entry.key.toLowerCase())
        ? entry.value
        : '[REDACTED]',
};

List<int> membershipReportProfileBody(List<int> bytes) {
  if (bytes.isEmpty) return bytes;
  try {
    return utf8.encode(
      jsonEncode(_membershipReportProfileJson(jsonDecode(utf8.decode(bytes)))),
    );
  } catch (_) {
    // An unexpected/non-JSON response must not fall back to raw credentials.
    return utf8.encode(jsonEncode('[REDACTED]'));
  }
}

Object? _membershipReportProfileJson(Object? value) {
  if (value is! Map) return '[REDACTED]';
  return {
    for (final entry in value.entries)
      entry.key:
          const {
            'provider',
            'plan_code',
            'store_product_id',
            'base_plan_id',
            'request_id',
            'err_no',
            'err_msg',
            'data',
            'status',
            'report_id',
            'membership_id',
            'reason',
          }.contains(entry.key)
          ? entry.value is Map || entry.value is List
                ? _membershipReportProfileJson(entry.value)
                : entry.value
          : '[REDACTED]',
  };
}

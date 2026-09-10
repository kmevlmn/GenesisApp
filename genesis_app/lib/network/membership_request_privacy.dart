import 'dart:convert';

/// These requests or responses contain private purchase credentials.
bool isPrivateMembershipRequest(Uri uri) => const [
  '/membership/products',
  '/membership/purchase/report',
  '/membership/guest/prepare',
  '/membership/guest/purchase/report',
  '/membership/guest/purchase/check',
  '/membership/claim',
].any(uri.path.endsWith);

bool isMembershipProductRequest(Uri uri) =>
    uri.path.endsWith('/membership/products');

bool isMembershipGuestCheckRequest(Uri uri) =>
    uri.path.endsWith('/membership/guest/purchase/check');

List<int> membershipGuestCheckProfileBody(List<int> bytes) {
  if (bytes.isEmpty) return bytes;
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map) throw const FormatException('Invalid check envelope');
    final data = value['data'];
    return utf8.encode(
      jsonEncode({
        if (value.containsKey('account_uuid')) 'account_uuid': '[REDACTED]',
        if (value['err_no'] is int) 'err_no': value['err_no'],
        if (data is Map && data['has_unbound_order'] is bool)
          'data': {'has_unbound_order': data['has_unbound_order']},
      }),
    );
  } catch (_) {
    return utf8.encode(jsonEncode('[REDACTED]'));
  }
}

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
            'store_product_id',
            'base_plan_id',
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

/// Keep catalog display data inspectable without exposing upgrade credentials.
List<int> membershipProductProfileBody(List<int> bytes) {
  if (bytes.isEmpty) return bytes;
  try {
    return utf8.encode(
      jsonEncode(_membershipProductProfileJson(jsonDecode(utf8.decode(bytes)))),
    );
  } catch (_) {
    return utf8.encode(jsonEncode('[REDACTED]'));
  }
}

Object? _membershipProductProfileJson(Object? value) {
  if (value is List) {
    return value.map(_membershipProductProfileJson).toList();
  }
  if (value is! Map) return '[REDACTED]';
  return {
    for (final entry in value.entries)
      entry.key:
          const {
            'err_no',
            'err_msg',
            'data',
            'list',
            'title',
            'benefits',
            'code',
            'icon_key',
            'display_type',
            'provider',
            'plan_code',
            'store_product_id',
            'base_plan_id',
            'offer_id',
            'billing_months',
            'monthly_gems_cent',
            'price_currency_code',
            'price_amount',
            'can_purchase',
            'purchase_block_reason',
          }.contains(entry.key)
          ? entry.value is Map || entry.value is List
                ? _membershipProductProfileJson(entry.value)
                : entry.value
          : '[REDACTED]',
  };
}

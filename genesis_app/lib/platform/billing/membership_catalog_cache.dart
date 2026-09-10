import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../network/models/membership_product.dart';

/// Display snapshots only. Purchase identities are excluded by product.toJson.
class MembershipCatalogCache {
  MembershipCatalogCache({required this.namespace});

  final String namespace;
  Future<void> _writes = Future.value();

  String _key(MembershipProvider provider, String? ownerUid) =>
      'membership_catalog_v1.${Uri.encodeComponent(jsonEncode([namespace, provider.name, ownerUid]))}';

  Future<MembershipProductList?> load(
    MembershipProvider provider,
    String? ownerUid,
  ) async {
    await _writes;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(provider, ownerUid));
    if (raw == null) return null;
    try {
      return MembershipProductList.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    MembershipProvider provider,
    String? ownerUid,
    List<MembershipProduct> products,
  ) {
    final body = jsonEncode({
      'list': [for (final product in products) product.toJson()],
    });
    final operation = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(provider, ownerUid), body);
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }
}

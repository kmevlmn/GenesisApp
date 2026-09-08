import '../models/membership_product.dart';
import 'v1_api_resource.dart';

class MembershipV1Api extends V1ApiResource {
  const MembershipV1Api(super.client);

  /// GET /api/v1/membership/products; prices come from the platform store.
  Future<MembershipProductList> products({
    required MembershipProvider provider,
  }) async {
    return MembershipProductList.fromJson(
      await getMap('membership/products', v1Query({'provider': provider.name})),
    );
  }
}

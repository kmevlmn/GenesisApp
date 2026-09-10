import '../../network/models/membership_order_product.dart';
import '../../network/models/membership_purchase.dart';
import 'billing_models.dart';

/// A legacy restore record or a store receipt awaiting an exact plan.
/// Resolved receipts move into the normal purchase/report queue.
class MembershipRestoreRecord {
  const MembershipRestoreRecord({
    required this.requestId,
    required this.ownerUid,
    required this.purchase,
    this.product,
    this.reportStatus,
    this.reportId,
    this.reportReason,
    this.finished = false,
  });

  final String requestId;
  final String ownerUid;
  final BillingPurchase purchase;
  final MembershipOrderProduct? product;
  final String? reportStatus;
  final String? reportId;
  final String? reportReason;
  final bool finished;

  bool get paid =>
      // Official confirmation can arrive before a second native callback.
      reportStatus == 'completed' ||
      purchase.status == BillingPurchaseStatus.purchased ||
      purchase.status == BillingPurchaseStatus.restored;
  String get receiptKey => membershipReceiptKey(purchase);
  bool get needsRetry =>
      reportStatus == null ||
      reportStatus == 'accepted' ||
      purchase.provider == BillingProvider.appStore && paid && !finished;

  MembershipPurchaseRequest get request => MembershipPurchaseRequest(
    product:
        product ?? (throw StateError('membership_restore_plan_unresolved')),
    purchaseToken: purchase.purchaseToken,
    transactionId: purchase.transactionId,
  );

  MembershipRestoreRecord copyWith({
    MembershipOrderProduct? product,
    BillingPurchase? purchase,
    String? reportStatus,
    String? reportId,
    String? reportReason,
    bool? finished,
  }) => MembershipRestoreRecord(
    requestId: requestId,
    ownerUid: ownerUid,
    purchase: purchase ?? this.purchase,
    product: product ?? this.product,
    reportStatus: reportStatus ?? this.reportStatus,
    reportId: reportId ?? this.reportId,
    reportReason: reportStatus != null ? reportReason : this.reportReason,
    finished: finished ?? this.finished,
  );

  Map<String, Object?> toJson() => {
    'request_id': requestId,
    'owner_uid': ownerUid,
    'provider': purchase.provider.apiValue,
    'store_product_id': purchase.productId,
    'purchase_token': purchase.purchaseToken,
    'transaction_id': purchase.transactionId,
    'original_transaction_id': purchase.originalTransactionId,
    'purchase_time': purchase.purchaseTime,
    'account_uuid': purchase.obfuscatedAccountId,
    'state': purchase.status.name,
    'product': product?.toOrderJson(),
    'report_status': reportStatus,
    'report_id': reportId,
    'report_reason': reportReason,
    'finished': finished,
  };

  factory MembershipRestoreRecord.fromJson(Map<String, dynamic> json) =>
      MembershipRestoreRecord(
        requestId: json['request_id'] as String,
        ownerUid: json['owner_uid'] as String,
        purchase: BillingPurchase(
          provider: switch (json['provider']) {
            'google' => BillingProvider.googlePlay,
            'apple' => BillingProvider.appStore,
            _ => throw const FormatException('Invalid restore provider'),
          },
          productId: json['store_product_id'] as String,
          purchaseToken: json['purchase_token'] as String,
          transactionId: json['transaction_id'] as String,
          originalTransactionId: json['original_transaction_id'] as String,
          originalJson: '',
          purchaseTime: json['purchase_time'] as String,
          obfuscatedAccountId: json['account_uuid'] as String?,
          status: BillingPurchaseStatus.values.byName(json['state'] as String),
        ),
        product: json['product'] == null
            ? null
            : MembershipOrderProduct.fromJson(
                Map<String, dynamic>.from(json['product'] as Map),
              ),
        reportStatus: json['report_status'] as String?,
        reportId: json['report_id'] as String?,
        reportReason: json['report_reason'] as String?,
        finished: json['finished'] as bool,
      );
}

String membershipReceiptKey(BillingPurchase purchase) =>
    '${purchase.provider.name}:${purchase.productId}:'
    '${purchase.provider == BillingProvider.googlePlay ? purchase.purchaseToken : purchase.transactionId}';

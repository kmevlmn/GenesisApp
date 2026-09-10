import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../network/models/membership_order_product.dart';
import '../../network/models/membership_purchase.dart';
import 'membership_restore_record.dart';
import 'membership_guest_claim_record.dart';

class MembershipPurchaseRecord {
  const MembershipPurchaseRecord({
    required this.requestId,
    required this.product,
    required this.accountUuid,
    required this.ownerUid,
    this.guest,
    this.transactionId = '',
    this.originalTransactionId = '',
    this.purchaseToken = '',
    this.state = 'prepared',
    this.reportStatus,
    this.reportId,
    this.reportReason,
    this.finished = false,
  });

  final String requestId;
  final MembershipOrderProduct product;
  final String accountUuid;
  final String? ownerUid;
  final MembershipGuestIdentity? guest;
  final String transactionId;
  final String originalTransactionId;
  final String purchaseToken;
  final String state;
  final String? reportStatus;
  final String? reportId;
  final String? reportReason;
  final bool finished;

  bool get hasReceipt => product.provider == MembershipProvider.google
      ? purchaseToken.isNotEmpty
      : transactionId.isNotEmpty;
  bool get paid => state == 'purchased' || state == 'restored';
  // A purchase status without any receipt cannot be reported or treated as
  // proof of payment. Keep its identity so a later store callback can recover it.
  bool get needsReceiptRecovery =>
      reportStatus == null &&
      !hasReceipt &&
      (paid || state == 'receipt_missing');
  MembershipPurchaseRequest get request => MembershipPurchaseRequest(
    product: product,
    requestId: requestId,
    transactionId: transactionId,
    purchaseToken: purchaseToken,
    guest: guest,
  );

  MembershipPurchaseRecord copyWith({
    String? requestId,
    String? transactionId,
    String? originalTransactionId,
    String? purchaseToken,
    String? state,
    String? reportStatus,
    String? reportId,
    String? reportReason,
    bool? finished,
    bool newReport = false,
    bool retryReport = false,
  }) => MembershipPurchaseRecord(
    requestId: requestId ?? this.requestId,
    product: product,
    accountUuid: accountUuid,
    ownerUid: ownerUid,
    guest: guest,
    transactionId: transactionId ?? this.transactionId,
    originalTransactionId: originalTransactionId ?? this.originalTransactionId,
    purchaseToken: purchaseToken ?? this.purchaseToken,
    state: state ?? this.state,
    reportStatus: newReport || retryReport
        ? null
        : reportStatus ?? this.reportStatus,
    reportId: newReport || retryReport ? null : reportId ?? this.reportId,
    reportReason: newReport || retryReport
        ? null
        : reportStatus != null
        ? reportReason
        : this.reportReason,
    finished: newReport ? false : finished ?? this.finished,
  );

  /// Keep store receipt identity for restore after removing the guest secret.
  MembershipPurchaseRecord bindGuestToAccount(String uid) =>
      MembershipPurchaseRecord(
        requestId: requestId,
        product: product,
        accountUuid: accountUuid,
        ownerUid: uid,
        transactionId: transactionId,
        originalTransactionId: originalTransactionId,
        purchaseToken: purchaseToken,
        state: state,
        reportStatus: reportStatus,
        reportId: reportId,
        reportReason: reportReason,
        finished: finished,
      );

  Map<String, Object?> toJson() => {
    'request_id': requestId,
    'product': product.toOrderJson(),
    'account_uuid': accountUuid,
    'owner_uid': ownerUid,
    'guest': guest?.toJson(),
    'transaction_id': transactionId,
    'original_transaction_id': originalTransactionId,
    'purchase_token': purchaseToken,
    'state': state,
    'report_status': reportStatus,
    'report_id': reportId,
    'report_reason': reportReason,
    'finished': finished,
  };

  factory MembershipPurchaseRecord.fromJson(Map<String, dynamic> json) =>
      MembershipPurchaseRecord(
        requestId: json['request_id'] as String,
        product: MembershipOrderProduct.fromJson(
          Map<String, dynamic>.from(json['product'] as Map),
        ),
        accountUuid: json['account_uuid'] as String,
        ownerUid: json['owner_uid'] as String?,
        guest: json['guest'] == null
            ? null
            : MembershipGuestIdentity.fromJson(
                Map<String, dynamic>.from(json['guest'] as Map),
              ),
        transactionId: json['transaction_id'] as String,
        originalTransactionId: json['original_transaction_id'] as String,
        purchaseToken: json['purchase_token'] as String,
        state: json['state'] as String,
        reportStatus: json['report_status'] as String?,
        reportId: json['report_id'] as String?,
        reportReason: json['report_reason'] as String?,
        finished: json['finished'] as bool,
      );
}

abstract interface class MembershipPendingStore {
  Future<List<MembershipPurchaseRecord>> loadAll();
  Future<void> save(MembershipPurchaseRecord record);
  Future<List<MembershipPurchaseRecord>> loadConfirmedReceipts();
  Future<void> complete(MembershipPurchaseRecord record);
  Future<List<MembershipRestoreRecord>> loadRestores();
  Future<void> saveRestore(MembershipRestoreRecord record);
  Future<void> removeRestore(String requestId);
  Future<List<MembershipGuestClaimRecord>> loadGuestClaims();
  Future<void> saveGuestClaim(MembershipGuestClaimRecord record);
  Future<void> completeGuestClaim(MembershipGuestClaimRecord record);
}

/// Kept separate from the Gems queue, including guest secrets after reporting.
class SecureMembershipPendingStore implements MembershipPendingStore {
  SecureMembershipPendingStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
            aOptions: AndroidOptions(resetOnError: false),
          );
  final FlutterSecureStorage _storage;
  static const _key = 'membership_purchase_records_v1';
  static const _restoreKey = 'membership_restore_records_v1';
  static const _confirmedKey = 'membership_confirmed_receipts_v1';
  static const _guestClaimsKey = 'membership_guest_claims_v1';
  Future<void> _writes = Future.value();

  @override
  Future<List<MembershipPurchaseRecord>> loadAll() async {
    await _writes;
    return _read();
  }

  Future<List<MembershipPurchaseRecord>> _read([String key = _key]) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return [];
    final rows = jsonDecode(raw) as List;
    return rows
        .map(
          (row) => MembershipPurchaseRecord.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<MembershipPurchaseRecord>> loadConfirmedReceipts() async {
    await _writes;
    return _read(_confirmedKey);
  }

  @override
  Future<void> complete(MembershipPurchaseRecord record) {
    final operation = _writes.then((_) async {
      // Keep exact plan/account/receipt identity for restore and deduplication.
      // Guest claim secrets must survive removal from the pending queue.
      final receipts = await _read(_confirmedKey);
      receipts.removeWhere((r) => r.requestId == record.requestId);
      receipts.add(record);
      await _storage.write(
        key: _confirmedKey,
        value: jsonEncode(receipts.map((r) => r.toJson()).toList()),
      );
      await _removePurchase(record.requestId);
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _removePurchase(String requestId) async {
    final records = await _read();
    records.removeWhere((r) => r.requestId == requestId);
    await _storage.write(
      key: _key,
      value: jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }

  @override
  Future<void> save(MembershipPurchaseRecord record) {
    final operation = _writes.then((_) async {
      final records = await _read();
      final index = records.indexWhere(
        (item) => item.requestId == record.requestId,
      );
      if (index < 0) {
        records.add(record);
      } else {
        records[index] = record;
      }
      await _storage.write(
        key: _key,
        value: jsonEncode(records.map((item) => item.toJson()).toList()),
      );
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<List<MembershipRestoreRecord>> loadRestores() async {
    await _writes;
    return _readRestores();
  }

  Future<List<MembershipRestoreRecord>> _readRestores() async {
    final raw = await _storage.read(key: _restoreKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map(
          (row) => MembershipRestoreRecord.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> saveRestore(MembershipRestoreRecord record) {
    final operation = _writes.then((_) async {
      final records = await _readRestores();
      final index = records.indexWhere((r) => r.requestId == record.requestId);
      if (index < 0) {
        records.add(record);
      } else {
        records[index] = record;
      }
      await _storage.write(
        key: _restoreKey,
        value: jsonEncode(records.map((r) => r.toJson()).toList()),
      );
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<void> removeRestore(String requestId) {
    final operation = _writes.then((_) async {
      final records = await _readRestores();
      records.removeWhere((r) => r.requestId == requestId);
      await _storage.write(
        key: _restoreKey,
        value: jsonEncode(records.map((r) => r.toJson()).toList()),
      );
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<List<MembershipGuestClaimRecord>> _readGuestClaims() async {
    final raw = await _storage.read(key: _guestClaimsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map(
          (row) => MembershipGuestClaimRecord.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<MembershipGuestClaimRecord>> loadGuestClaims() async {
    await _writes;
    return _readGuestClaims();
  }

  @override
  Future<void> saveGuestClaim(MembershipGuestClaimRecord record) {
    final operation = _writes.then((_) async {
      final records = await _readGuestClaims();
      records.removeWhere((r) => r.guest.guestId == record.guest.guestId);
      records.add(record);
      await _storage.write(
        key: _guestClaimsKey,
        value: jsonEncode(records.map((r) => r.toJson()).toList()),
      );
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<void> completeGuestClaim(MembershipGuestClaimRecord record) {
    final operation = _writes.then((_) async {
      final uid = record.ownerUid;
      if (record.status != 'completed' || uid == null || uid.isEmpty) {
        throw StateError('Guest claim is not completed');
      }
      final claims = await _readGuestClaims();
      final saved = claims.where(
        (r) => r.guest.guestId == record.guest.guestId,
      );
      if (saved.isEmpty) return;
      if (saved.single.status != 'completed' || saved.single.ownerUid != uid) {
        throw StateError('Guest claim completion must be durable');
      }
      // Remove the claim last: an interrupted cleanup can resume from its
      // durable completed status, without sending another binding request.
      for (final key in [_confirmedKey, _key]) {
        final purchases = await _read(key);
        if (!purchases.any((r) => r.guest?.guestId == record.guest.guestId)) {
          continue;
        }
        await _storage.write(
          key: key,
          value: jsonEncode([
            for (final purchase in purchases)
              (purchase.guest?.guestId == record.guest.guestId
                      ? purchase.bindGuestToAccount(uid)
                      : purchase)
                  .toJson(),
          ]),
        );
      }
      claims.removeWhere((r) => r.guest.guestId == record.guest.guestId);
      if (claims.isEmpty) {
        await _storage.delete(key: _guestClaimsKey);
      } else {
        await _storage.write(
          key: _guestClaimsKey,
          value: jsonEncode(claims.map((r) => r.toJson()).toList()),
        );
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/models/gem_wallet.dart';

Map<String, Object?> membership({int status = 1}) => {
  'membership_status': status,
  'plan_code': 'pro_yearly',
  'expires_at': 1820354400,
  'auto_renew': false,
  'blue_gems_cent': 0,
  'has_overlap': false,
};

void main() {
  test(
    'server status is authoritative even with zero Gems and auto-renew off',
    () {
      for (final status in [0, 1, 2]) {
        final wallet = GemWallet.fromJson({
          'wallet': {'balance_cent': 518240},
          'membership': membership(status: status),
        });
        expect(wallet.membership!.isActive, status == 1);
        expect(wallet.balanceCent, 518240);
        expect(
          wallet.membership!.expiresAt!.millisecondsSinceEpoch,
          1820354400000,
        );
        expect(wallet.membership!.expiresAt!.isUtc, isTrue);
      }
    },
  );
  test(
    'missing membership remains compatible with existing Gems responses',
    () {
      expect(
        GemWallet.fromJson({
          'wallet': {'balance_cent': 100},
        }).membership,
        isNull,
      );
    },
  );
  test('invalid status or amount is not silently treated as a membership', () {
    for (final change in [
      {'membership_status': '1'},
      {'membership_status': 3},
      {'blue_gems_cent': 300.0},
      {'blue_gems_cent': -1},
      {'expires_at': '1820354400'},
      {'auto_renew': null},
    ]) {
      expect(
        () => GemWalletMembership.fromJson({...membership(), ...change}),
        throwsFormatException,
      );
      final wallet = GemWallet.fromJson({
        'wallet': {'balance_cent': 12345},
        'membership': {...membership(), ...change},
      });
      expect(wallet.balanceCent, 12345);
      expect(wallet.membership, isNull);
    }
  });
}

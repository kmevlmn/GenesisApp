import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/debug/membership_guest_login_debug_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to mandatory login', () async {
    final settings = MembershipGuestLoginDebugSettingsController();
    expect(settings.forceLogin, isTrue);
    expect(await settings.load(), isTrue);
  });

  test(
    'debug override survives a new controller and can be enabled again',
    () async {
      final settings = MembershipGuestLoginDebugSettingsController();
      await settings.setForceLogin(false);
      final restarted = MembershipGuestLoginDebugSettingsController();
      expect(await restarted.load(), isFalse);
      await restarted.setForceLogin(true);
      expect(await settings.load(), isTrue);
    },
  );

  test(
    'non-debug builds ignore a saved false value and cannot disable login',
    () async {
      SharedPreferences.setMockInitialValues({
        MembershipGuestLoginDebugSettingsController.storageKey: false,
      });
      final settings = MembershipGuestLoginDebugSettingsController(
        isDebugBuild: false,
      );
      expect(await settings.load(), isTrue);
      await settings.setForceLogin(false);
      expect(settings.forceLogin, isTrue);
      expect(settings.listenable.value, isTrue);
    },
  );

  test('invalid stored setting falls back to mandatory login', () async {
    SharedPreferences.setMockInitialValues({
      MembershipGuestLoginDebugSettingsController.storageKey: 'invalid',
    });
    expect(await MembershipGuestLoginDebugSettingsController().load(), isTrue);
  });
}

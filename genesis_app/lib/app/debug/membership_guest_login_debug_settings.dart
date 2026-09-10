import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final membershipGuestLoginDebugSettings =
    MembershipGuestLoginDebugSettingsController();

class MembershipGuestLoginDebugSettingsController {
  MembershipGuestLoginDebugSettingsController({this.isDebugBuild = kDebugMode});

  static const storageKey = 'developer_membership_guest_force_login_v1';
  final bool isDebugBuild;
  final ValueNotifier<bool> _forceLogin = ValueNotifier(true);
  int _revision = 0;
  Future<void>? _pendingSave;

  ValueListenable<bool> get listenable => _forceLogin;
  bool get forceLogin => !isDebugBuild || _forceLogin.value;

  Future<bool> load() async {
    if (!isDebugBuild) return true;
    final pendingSave = _pendingSave;
    if (pendingSave != null) {
      try {
        await pendingSave;
      } catch (_) {
        // A failed save restores the previous setting.
      }
    }
    final revision = _revision;
    var enabled = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      enabled = preferences.getBool(storageKey) ?? true;
    } catch (_) {
      // An unavailable debug preference must not disable mandatory login.
    }
    if (revision == _revision) _forceLogin.value = enabled;
    return forceLogin;
  }

  Future<void> setForceLogin(bool enabled) async {
    if (!isDebugBuild) return;
    final previous = _forceLogin.value;
    final revision = ++_revision;
    _forceLogin.value = enabled;
    final save = _save(enabled);
    _pendingSave = save;
    try {
      await save;
    } catch (_) {
      if (revision == _revision) _forceLogin.value = previous;
      rethrow;
    } finally {
      if (identical(_pendingSave, save)) _pendingSave = null;
    }
  }

  Future<void> _save(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setBool(storageKey, enabled)) {
      throw StateError('Failed to save the guest VIP login debug setting.');
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _revision++;
    _pendingSave = null;
    _forceLogin.value = true;
  }
}

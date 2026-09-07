import 'package:flutter/material.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/gems/daily_check_in_coordinator.dart';
import '../../platform/auth/auth_session.dart';
import '../../platform/session/user_session_store.dart';
import '../login_sheet.dart';

/// Whether the caller may continue its current operation.
///
/// User actions must be repeated after an interactive login. Only automatic
/// authentication recovery should opt in to [continueAfterLogin].
Future<bool> ensureGenesisLogin(
  BuildContext context, {
  bool continueAfterLogin = false,
}) async {
  if (await hasGenesisLoginSession(context)) return true;
  if (!context.mounted) return false;
  final loginContext = context;

  final loggedIn = await showLoginSheet(
    context: loginContext,
    onLogin: (provider) {
      return _loginWithProvider(loginContext, provider);
    },
  );
  if (!loginContext.mounted || !loggedIn) return false;
  await scheduleDailyCheckInAfterLogin(loginContext);
  if (!loginContext.mounted) return false;
  if (!continueAfterLogin) return false;
  return hasGenesisLoginSession(loginContext);
}

Future<bool> hasGenesisLoginSession(BuildContext context) async {
  final services = AppServicesScope.read(context);
  return await services.sessionStore.readLoginUid() != null;
}

Future<bool> _loginWithProvider(
  BuildContext context,
  IdentityProvider provider,
) async {
  final services = AppServicesScope.read(context);
  final session = await services.identityAuth.signIn(provider);
  final user = await services.backendAuth.loginWithIdentity(session);
  if (user.uid.trim().isNotEmpty) {
    await services.sessionStore.saveUid(user.uid);
  }
  final cachedUserInfo = await services.sessionStore.readUserInfo();
  final loginUserInfo = <String, dynamic>{
    if (cachedUserInfo != null) ...cachedUserInfo,
    'uid': user.uid,
    'login_provider': provider.name,
  };
  if (user.nickname.trim().isNotEmpty) {
    loginUserInfo['name'] = user.nickname;
  }
  if (user.avatar.trim().isNotEmpty) {
    loginUserInfo['avatar'] = user.avatar;
  }
  await services.sessionStore.saveUserInfo(loginUserInfo);
  services.notifySessionChanged();
  return true;
}
